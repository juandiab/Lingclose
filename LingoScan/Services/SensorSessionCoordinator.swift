import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Máquina de estados del sensor (`ARQUITECTURA.md` §3) sobre el fork de RoundWhiteDiscKit.
///
/// Reglas que este actor hace cumplir:
/// - NFC: `identify()` solo lee (`0xA1`); `activate(ticket:)` solo envía `0xA0` con un
///   `ActivationTicket`. Nunca hay activación como fallback ni cambio de receptor.
/// - Registro durable: `prepared` antes de mostrar el ticket, `sent` antes de escribir NFC,
///   `response_saved` al recibir los 19 B (antes de BLE), `authenticated` tras Phase 6.
/// - Un fallo del handshake completo es terminal (`authenticationFailed`), con evidencia en
///   `event_log` y sin reintento automático de credenciales. Un corte se informa como
///   `interrupted`, nunca como credenciales equivocadas.
/// - `sensorCertSigningKeys` nunca vacío: se comprueba antes de conectar.
/// - PIN, kAuth y claves solo pasan por `Redactor.secret` en los logs.
actor SensorSessionCoordinator {
    static let appID = "com.otalvaro.lingoscan"
    private static let historyLimit = 200

    private(set) var state: SessionState = .noSensor
    /// Transiciones recientes (diagnóstico y tests).
    private(set) var history: [SessionState] = []
    private var observers: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    private let link: any SensorLink
    private let nfc: any SensorNFC
    private let pairingStore: any PairingStatePersisting
    private let credentials: any PairingCredentialsProviding
    private let store: SQLiteStore
    private let clock: any SessionClock
    private let timeouts: SessionTimeouts
    private let receiverIDGenerator: @Sendable () -> UInt32

    private var sessionID: String?
    private var profile: SensorProfile?
    private var sessionTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    /// Fin, fallo de autenticación o pausa: no se reconecta hasta una acción explícita.
    private var terminal = false

    // Plano de datos de la conexión actual (se rehace en cada Phase 6).
    private var crypto: DataPlaneCrypto?
    private var decoder: DataPlaneDecoder?
    private var assembler: DataPlaneNotificationAssembler?
    private var dataPlane: Libre3DataPlaneState?
    private var mapper: LingoReadingMapper?
    private var outSequence: UInt16 = 0
    private var dataPlaneStartedAt: Date?
    private var lastValidFrameAt: Date?
    private var backfillRequestedAt: Date?
    private var persistedHistoricLifeCount: Int?
    private var hasStreamed = false
    private var retiredRawCount = 0

    init(
        link: any SensorLink,
        nfc: any SensorNFC,
        pairingStore: any PairingStatePersisting,
        credentials: any PairingCredentialsProviding,
        store: SQLiteStore,
        clock: any SessionClock = SystemSessionClock(),
        timeouts: SessionTimeouts = .standard,
        receiverIDGenerator: @escaping @Sendable () -> UInt32 = SensorSessionCoordinator.randomReceiverID
    ) {
        self.link = link
        self.nfc = nfc
        self.pairingStore = pairingStore
        self.credentials = credentials
        self.store = store
        self.clock = clock
        self.timeouts = timeouts
        self.receiverIDGenerator = receiverIDGenerator
    }

    /// Receiver ID aleatorio distinto de 0 y de 1001 (`RECUPERACION_V1.md` §4.1).
    static func randomReceiverID() -> UInt32 {
        while true {
            let value = UInt32.random(in: 1...UInt32.max)
            if value != 1001 { return value }
        }
    }

    /// Tramas descifradas en canales con parser que acabaron como `.raw` (todas las conexiones).
    var unexpectedRawCount: Int { retiredRawCount + (decoder?.unexpectedRawCount ?? 0) }

    func states() -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionState.self, bufferingPolicy: .bufferingNewest(32))
        let id = UUID()
        observers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    // MARK: - Arranque y NFC

    /// Restaura el estado al arrancar (también cuando iOS relanza la app por BLE).
    func start() async {
        do {
            guard let id = try await pairingStore.currentSessionID(),
                  let saved = try await pairingStore.loadState(sessionID: id) else {
                await set(.noSensor)
                return
            }
            let secrets = try await pairingStore.loadSecrets(sessionID: id)
            sessionID = id
            let restoredProfile = saved.profile(serial: secrets.serial ?? "")
            profile = restoredProfile
            if saved.collectorPaused {
                terminal = true
                await set(.paused)
                return
            }
            if let phase = saved.authFailurePhase {
                terminal = true
                await set(.authenticationFailed(phase, reason: .other(saved.authFailureSummary ?? "fallo de autenticación previo")))
                return
            }
            switch saved.activation.state {
            case .prepared:
                await set(.readyToActivate(restoredProfile))
            case .sent:
                terminal = true
                await log(.warning, "arranque con intento \(public: saved.activation.attemptID) en sent: no se reenvía 0xA0 ni 0xA8; diagnóstico solo con 0xA1")
                await set(.authenticationFailed(.activation, reason: .incompleteActivation(.sent)))
            case .responseSaved:
                terminal = true
                await set(.authenticationFailed(.connecting, reason: .other("emparejamiento sin terminar; requiere confirmación")))
            case .authenticated:
                let restored = await link.restoredPeripheralIDs()
                if let peripheral = saved.peripheralUUID, restored.contains(peripheral) {
                    await log(.info, "CoreBluetooth restauró el periférico de la sesión")
                }
                await set(.reconnecting(attempt: 1))
                beginSession(mode: .reconnect)
            case .failed:
                terminal = true
                await set(.authenticationFailed(.activation, reason: .other(saved.activation.failureReason ?? "activación fallida")))
            }
        } catch {
            await log(.error, "no se pudo leer el estado de pairing: \(public: Self.typeName(error))")
            await set(.noSensor)
        }
    }

    /// Lectura NFC solo `0xA1`. Nunca activa ni cambia de receptor.
    @discardableResult
    func identify() async throws -> SensorProfile {
        let read = try await nfc.readPatchInfo()
        await log(.info, "NFC 0xA1: \(public: read.family.rawValue) pt \(read.productType) sv \(read.securityVersion) state \(read.stateByte) serial \(serial: read.serialNumber)")

        if let id = sessionID,
           let saved = try await pairingStore.loadState(sessionID: id),
           saved.activation.state == .authenticated,
           try await pairingStore.loadSecrets(sessionID: id).serial == read.serialNumber {
            // Sensor ya emparejado por esta app (`identified → paired → reconnecting`).
            if sessionTask == nil, !terminal {
                await set(.reconnecting(attempt: 1))
                beginSession(mode: .reconnect)
            }
            return read
        }

        if let id = sessionID,
           let saved = try await pairingStore.loadState(sessionID: id),
           saved.activation.state == .sent,
           try await pairingStore.loadSecrets(sessionID: id).serial == read.serialNumber {
            // Diagnóstico de un intento incompleto: solo se informa el `state` leído; el estado
            // de la sesión no cambia y nunca se ofrece reactivar desde aquí.
            await log(.warning, "diagnóstico 0xA1 del intento incompleto: state del sensor \(read.stateByte)")
            return read
        }

        await set(.identified(read))
        if !read.isSupportedLingo {
            await set(.incompatible(read, reason: .unsupportedVariant(productType: read.productType, securityVersion: read.securityVersion)))
        } else if read.isTerminated {
            await set(.incompatible(read, reason: .sensorEnded(stateByte: read.stateByte)))
        } else if read.isFresh {
            profile = read
            await set(.readyToActivate(read))
        }
        // Lingo ya activado por otro receptor: queda `identified`; nunca se envía 0xA8.
        return read
    }

    /// Paso 1 de `RECUPERACION_V1.md` §4: genera y guarda el Receiver ID, crea la sesión en
    /// `prepared` e invoca el hook de recuperación. Debe ocurrir antes de mostrar el ticket.
    func prepareActivation(for candidate: SensorProfile) async throws -> PreparedActivation {
        guard case .readyToActivate(let ready) = state, ready == candidate,
              candidate.isSupportedLingo, candidate.isFresh else {
            throw SensorSessionCoordinatorError.invalidState(state.logLabel)
        }
        let id = UUID().uuidString.lowercased()
        let attempt = UUID().uuidString.lowercased()
        let receiverID = receiverIDGenerator()
        let now = clock.now

        try await pairingStore.saveSecrets(PairingSecrets(receiverID: receiverID, serial: candidate.serialNumber), sessionID: id)
        let saved = PairingState(activation: .prepared(sessionID: id, attemptID: attempt, now: now), profile: candidate)
        try await store.upsertSession(makeSessionRecord(
            saved, profile: candidate, state: .prepared, epoch: Int64(now.timeIntervalSince1970), source: .command
        ))
        try await pairingStore.begin(saved)
        sessionID = id
        profile = candidate
        terminal = false
        hasStreamed = false
        await log(.info, "activación preparada: sesión \(public: id), intento \(public: attempt), serial \(serial: candidate.serialNumber)")
        return PreparedActivation(sessionID: id, attemptID: attempt, receiverID: receiverID, profile: candidate)
    }

    /// `0xA0` con un ticket emitido tras la confirmación escrita. Persiste `sent` antes de
    /// escribir NFC y `response_saved` al recibir los 19 B, antes de cualquier operación BLE.
    func activate(ticket: ActivationTicket) async throws {
        guard case .readyToActivate = state else {
            throw SensorSessionCoordinatorError.invalidState(state.logLabel)
        }
        guard ticket.sessionID == sessionID else { throw SensorSessionCoordinatorError.ticketDoesNotMatchSession }
        let id = ticket.sessionID
        await set(.activating)

        try await pairingStore.transition(sessionID: id, to: .sent, now: clock.now)
        await updateSessionRecord { $0.activationState = .sent }
        await log(.info, "0xA0: sent persistido (confirmación \(public: ticket.confirmationID.uuidString.lowercased())); escribiendo NFC")

        let response: ActivationResponse
        do {
            response = try await nfc.activate(ticket: ticket)
        } catch {
            let reason = NFCServiceError(error, patchStateByte: ticket.profile.stateByte).description
            await failActivation(sessionID: id, reason: reason)
            return
        }

        try await pairingStore.saveSecrets(
            PairingSecrets(pin: response.pin, bleAddress: response.bleAddress, activationResponse: response.raw),
            sessionID: id
        )
        await log(.info, "0xA0: respuesta \(hex: response.raw), PIN \(secret: response.pin), MAC \(secret: Data(response.bleAddress.utf8))")
        guard response.scannedSerial == ticket.profile.serialNumber else {
            await failActivation(sessionID: id, reason: "el lector NFC activó un sensor con otro serial")
            return
        }
        guard var saved = try await pairingStore.loadState(sessionID: id) else {
            throw ActivationTransitionError.unknownSession
        }
        let epoch = response.activationTimeEpochS ?? Int64(clock.now.timeIntervalSince1970)
        saved.activationTimeEpochS = epoch
        try await pairingStore.saveState(saved)
        try await pairingStore.transition(sessionID: id, to: .responseSaved, now: clock.now)
        await updateSessionRecord {
            $0.activationState = .responseSaved
            $0.activationTimeEpochS = epoch
            $0.activationTimeSource = response.activationTimeEpochS == nil ? .command : .nfcResponse
        }
        await set(.pairing(.connecting))
        beginSession(mode: .firstPair)
    }

    /// Acción explícita (Fase 3b) tras `authenticationFailed` con PIN guardado. Nunca automática.
    func retryPairing() async throws {
        guard case .authenticationFailed = state, let id = sessionID,
              var saved = try await pairingStore.loadState(sessionID: id),
              saved.activation.state == .responseSaved || saved.activation.state == .authenticated else {
            throw SensorSessionCoordinatorError.invalidState(state.logLabel)
        }
        saved.authFailurePhase = nil
        saved.authFailureSummary = nil
        try await pairingStore.saveState(saved)
        let hasKAuth = try await pairingStore.loadSecrets(sessionID: id).kAuth != nil
        await log(.info, "reintento de emparejamiento solicitado por el usuario")
        terminal = false
        await set(hasKAuth ? .reconnecting(attempt: 1) : .pairing(.connecting))
        beginSession(mode: hasKAuth ? .reconnect : .firstPair)
    }

    // MARK: - Pausa (transferencia de rol)

    /// Desconecta y desactiva reconexión, restauración y Health hasta `resume()`.
    func pause() async {
        terminal = true
        sessionTask?.cancel()
        sessionTask = nil
        stopWatchdog()
        await link.disconnect()
        retireDataPlane()
        if let id = sessionID, var saved = try? await pairingStore.loadState(sessionID: id) {
            saved.collectorPaused = true
            try? await pairingStore.saveState(saved)
        }
        await set(.paused)
    }

    func resume() async {
        guard case .paused = state, let id = sessionID,
              var saved = try? await pairingStore.loadState(sessionID: id) else { return }
        saved.collectorPaused = false
        try? await pairingStore.saveState(saved)
        terminal = false
        await start()
    }

    // MARK: - Vigilante de `stale`

    /// > `timeouts.stale` sin trama de tiempo real válida → `stale` y se fuerza la reconexión.
    func evaluateStaleness() async {
        switch state {
        case .streaming, .warmingUp, .pairing(.subscribing): break
        default: return
        }
        guard let reference = lastValidFrameAt ?? dataPlaneStartedAt,
              clock.now.timeIntervalSince(reference) >= timeouts.stale.timeInterval else { return }
        await set(.stale(since: reference))
        await log(.warning, "sin trama válida desde \(UTCInstant(reference)); se fuerza reconexión")
        await link.disconnect()
    }

    // MARK: - Sesión BLE

    private func beginSession(mode: SessionMode) {
        sessionTask?.cancel()
        terminal = false
        sessionTask = Task { [weak self] in
            await self?.runSession(initialMode: mode)
        }
    }

    private func runSession(initialMode: SessionMode) async {
        var mode = initialMode
        var attempt = 1
        var backoff = timeouts.reconnectBackoff

        while isLive {
            guard let id = sessionID else { return }
            let saved: PairingState
            let secrets: PairingSecrets
            do {
                guard let loaded = try await pairingStore.loadState(sessionID: id) else { return }
                saved = loaded
                secrets = try await pairingStore.loadSecrets(sessionID: id)
            } catch {
                await log(.error, "estado de pairing ilegible: \(public: Self.typeName(error))")
                return
            }
            guard let pin = secrets.pin, pin.count == 4 else {
                await failAuthentication(phase: .connecting, reason: .other("sin PIN BLE guardado"))
                return
            }

            // Credenciales antes de conectar: nunca con lista de claves vacía.
            let needsFull = mode != .reconnect || secrets.kAuth == nil
            var fullCredentials: (identity: AppIdentity, keys: [Data])?
            if needsFull {
                do {
                    fullCredentials = try await resolveCredentials()
                } catch {
                    let (phase, reason) = Self.classify(error)
                    await failAuthentication(phase: phase, reason: reason)
                    return
                }
            }

            await setIfLive(mode == .firstPair ? .pairing(.connecting) : .reconnecting(attempt: attempt))
            let peripheralID: UUID
            do {
                peripheralID = try await link.connect(
                    peripheralID: saved.peripheralUUID, timeout: timeouts.connect, scanWindow: timeouts.scanWindow
                )
            } catch {
                guard isLive else { return }
                await log(.warning, "conexión BLE fallida (intento \(attempt)): \(public: Self.typeName(error))")
                attempt += 1
                try? await clock.sleep(for: backoff)
                backoff = min(backoff * 2, timeouts.maxReconnectBackoff)
                continue
            }
            guard isLive else { await link.disconnect(); return }
            if saved.peripheralUUID != peripheralID {
                await mutateSaved { $0.peripheralUUID = peripheralID }
            }

            let material: Phase6SessionMaterial
            if let fullCredentials {
                if mode == .firstPair { await setIfLive(.pairing(.certificateLoad)) }
                do {
                    let (phase6, kAuth) = try await fullHandshake(
                        pin: pin, identity: fullCredentials.identity, keys: fullCredentials.keys
                    )
                    material = phase6
                    try await persistAuthenticated(kAuth: kAuth, identityLabel: fullCredentials.identity.label)
                } catch {
                    await link.disconnect()
                    guard isLive else { return }
                    let (phase, reason) = Self.classify(error)
                    await failAuthentication(phase: phase, reason: reason)
                    return
                }
            } else if let kAuth = secrets.kAuth {
                do {
                    material = try await cachedHandshake(pin: pin, kAuth: kAuth)
                    await log(.info, "handshake corto OK con kAuth \(secret: kAuth)")
                } catch {
                    let alive = await link.isConnected()
                    await link.disconnect()
                    guard isLive else { return }
                    let (phase, reason) = Self.classify(error)
                    if alive {
                        await log(.warning, "handshake corto rechazado en \(public: phase.rawValue) (\(public: reason.summary)); se intenta el completo")
                        mode = .fullFallback
                    } else {
                        await log(.warning, "enlace perdido durante el handshake corto (\(public: phase.rawValue)); se reintenta la conexión")
                        attempt += 1
                        try? await clock.sleep(for: backoff)
                        backoff = min(backoff * 2, timeouts.maxReconnectBackoff)
                    }
                    continue
                }
            } else {
                return
            }

            do {
                try await startDataPlane(material: material)
            } catch {
                await link.disconnect()
                await failAuthentication(phase: .phase6, reason: .other("material de sesión inválido: \(Self.typeName(error))"))
                return
            }
            if mode == .firstPair { await setIfLive(.pairing(.subscribing)) }
            do {
                try await link.enableDataPlaneNotifications(timeout: timeouts.cccd)
            } catch {
                await link.disconnect()
                guard isLive else { return }
                await log(.warning, "suscripción del plano de datos fallida: \(public: Self.typeName(error))")
                mode = .reconnect
                attempt += 1
                try? await clock.sleep(for: backoff)
                continue
            }
            mode = .reconnect
            attempt = 1
            backoff = timeouts.reconnectBackoff
            startWatchdog()

            for await event in await link.events() {
                guard isLive else { break }
                await handle(event)
            }

            stopWatchdog()
            retireDataPlane()
            guard isLive else { return }
            await log(.info, "enlace BLE cerrado; reconectando")
        }
    }

    private var isLive: Bool { !terminal && !Task.isCancelled }

    private func resolveCredentials() async throws -> (identity: AppIdentity, keys: [Data]) {
        let identity = try await credentials.identity(for: .lingo)
        let keys = try await credentials.signingKeys(for: .lingo)
        guard !keys.isEmpty else { throw PairingFlowError.noTrustedSigningKeys }
        return (identity, keys)
    }

    private func fullHandshake(pin: Data, identity: AppIdentity, keys: [Data]) async throws -> (Phase6SessionMaterial, Data) {
        let transport = try await link.pairingTransport()
        let flow = try PairingFlow(transport: transport, phoneCert: identity.certificate, sensorCertSigningKeys: keys)
        let commandTimeout = timeouts.command.timeInterval
        let result = try await flow.runCommandGatedFirstPairHandshake(
            blePIN: pin,
            phase5RawKeyProvider: { preamble in try Self.authKey(identity: identity, preamble: preamble) },
            commandTimeout: commandTimeout
        )
        let kAuth = try Self.authKey(identity: identity, preamble: result.preamble)
        return (result.sessionMaterial, kAuth)
    }

    private func cachedHandshake(pin: Data, kAuth: Data) async throws -> Phase6SessionMaterial {
        let transport = try await link.pairingTransport()
        // El camino corto no verifica certificados; el init solo exige una lista no vacía.
        let keys = (try? await credentials.signingKeys(for: .lingo)) ?? Libre3PatchSigningKey.known
        let flow = try PairingFlow(transport: transport, sensorCertSigningKeys: keys)
        let commandTimeout = timeouts.command.timeInterval
        let result = try await flow.runCachedReconnectHandshake(tail4: pin, phase5RawKey: kAuth, commandTimeout: commandTimeout)
        return result.sessionMaterial
    }

    /// kAuth = `AppIdentity.authKey` con la efímera del teléfono, la efímera del sensor y la
    /// clave estática de su certificado (`docs/PROTOCOLO_LINGO.md` §5.2).
    static func authKey(identity: AppIdentity, preamble: FirstPairPreambleResult) throws -> Data {
        let handshake = preamble.phaseHandshake
        let sensorStatic = try EphemeralExchange.parsePeerPubkey(handshake.sensorCert.staticPub)
        return try identity.authKey(
            phoneEphemeral: handshake.phoneEph.privateKey,
            sensorEphemeral: handshake.sensorEphPub,
            sensorStatic: sensorStatic
        )
    }

    private func persistAuthenticated(kAuth: Data, identityLabel: String) async throws {
        guard let id = sessionID else { return }
        try await pairingStore.saveSecrets(PairingSecrets(kAuth: kAuth), sessionID: id)
        guard var saved = try await pairingStore.loadState(sessionID: id) else { throw ActivationTransitionError.unknownSession }
        saved.identityLabel = identityLabel
        saved.authFailurePhase = nil
        saved.authFailureSummary = nil
        try await pairingStore.saveState(saved)
        try await pairingStore.transition(sessionID: id, to: .authenticated, now: clock.now)
        await updateSessionRecord { $0.activationState = .authenticated }
        await log(.info, "Phase 6 OK: kAuth \(secret: kAuth) guardada; identidad \(public: identityLabel)")
    }

    // MARK: - Plano de datos

    private func startDataPlane(material: Phase6SessionMaterial) async throws {
        guard let id = sessionID, let saved = try await pairingStore.loadState(sessionID: id) else {
            throw ActivationTransitionError.unknownSession
        }
        retireDataPlane()
        let newCrypto = try DataPlaneCrypto(sessionMaterial: material)
        crypto = newCrypto
        decoder = DataPlaneDecoder(crypto: newCrypto, family: .lingo)
        assembler = DataPlaneNotificationAssembler(targetLength: DataPlaneNotificationAssembler.lingoGlucoseFrameLength)
        dataPlane = Libre3DataPlaneState(
            warmupDurationMinutes: saved.warmupMinutes,
            wearDurationMinutes: saved.wearMinutes,
            lastAcceptedGlucoseLifeCount: saved.lastLifeCount.flatMap { UInt16(exactly: $0) }
        )
        outSequence = 0
        dataPlaneStartedAt = clock.now
        lastValidFrameAt = nil
        backfillRequestedAt = nil
        persistedHistoricLifeCount = saved.lastHistoricLifeCount
        if let last = saved.lastLifeCount, last >= saved.warmupMinutes { hasStreamed = true }
        mapper = LingoReadingMapper(session: try await sessionRecordForReadings(saved), tzAtCapture: TimeZone.current.identifier)
    }

    private func retireDataPlane() {
        retiredRawCount += decoder?.unexpectedRawCount ?? 0
        crypto = nil
        decoder = nil
        assembler = nil
        dataPlane = nil
        mapper = nil
    }

    private func handle(_ event: SensorLinkEvent) async {
        guard case .fragment(let channel, let bytes) = event, let assembler, let decoder else { return }
        switch assembler.ingest(fragment: bytes, channel: channel) {
        case .pending:
            return
        case .overflow(let accumulated, let fragmentLength):
            await log(.warning, "ensamblador: \(accumulated) + \(fragmentLength) B excede 57 B; trama descartada")
        case .emptyFragment:
            await log(.warning, "ensamblador: fragmento vacío; trama descartada")
        case .complete(let frameBytes):
            let packet: DataPlaneDecodedPacket
            do {
                packet = try decoder.decrypt(frame: try DataFrame.parse(frameBytes), channel: channel)
            } catch {
                await log(.warning, "descifrado fallido en \(public: channel.rawValue) (\(frameBytes.count) B): \(public: Self.typeName(error))")
                return
            }
            await process(packet)
        }
    }

    private func process(_ packet: DataPlaneDecodedPacket) async {
        _ = dataPlane?.record(packet)
        switch packet.payload {
        case .patchStatus(let status):
            await handlePatchStatus(status)
        case .lingoRealtime:
            lastValidFrameAt = clock.now
            await storeReadings(from: packet.payload)
        case .lingoHistoricalPage, .lingoFastData:
            await storeReadings(from: packet.payload)
        case .raw(let plaintext):
            switch packet.channel {
            case .patchControl:
                backfillRequestedAt = nil
                await log(.debug, "patchControl: \(hex: plaintext)")
            case .glucoseData, .patchStatus, .historicData, .clinicalData:
                let reason = decoder?.lastDecodeError?.reason ?? "?"
                await log(.warning, "raw inesperado en \(public: packet.channel.rawValue) (\(plaintext.count) B, \(public: String(reason.prefix(120)))); total \(unexpectedRawCount)")
            case .eventLog, .factoryData:
                await log(.debug, "\(public: packet.channel.rawValue): \(hex: plaintext)")
            }
        case .realtimeGlucose, .historicalReadingPage, .clinicalReadingRecord:
            await log(.warning, "carga de Libre 3 en una sesión Lingo (\(public: packet.channel.rawValue))")
        }
    }

    private func handlePatchStatus(_ status: PatchStatus) async {
        await log(.info, "patchStatus: estado \(status.patchState), lc \(status.currentLifeCount), error \(status.errorData)")
        if status.patchState > 4 {
            await end(status.patchState == 6 || status.patchState == 8 ? .terminated : .expired)
            return
        }
        let lifeCount = Int(status.currentLifeCount)
        let warmup = profile?.warmupMinutes ?? SensorLifecycle.defaultWarmupDurationMinutes
        if let wear = profile?.wearMinutes, lifeCount >= wear {
            await end(.expired)
            return
        }
        switch state {
        case .pairing, .reconnecting:
            if lifeCount >= 0, lifeCount < warmup || !hasStreamed {
                await setIfLive(.warmingUp(remainingMinutes: max(0, warmup - lifeCount)))
            }
        default:
            break
        }
        await requestBackfillIfNeeded()
    }

    /// Backfill tras `patchStatus` (`docs/PROTOCOLO_LINGO.md` §6.1). El contador saliente
    /// empieza en 1 tras cada Phase 6.
    private func requestBackfillIfNeeded() async {
        guard let dataPlane, let crypto else { return }
        if let at = backfillRequestedAt, clock.now.timeIntervalSince(at) < timeouts.backfillAck.timeInterval { return }
        var commands = dataPlane.reconnectBackfillCommands(family: .lingo)
        // El fork no permite sembrar `lastLingoHistoricLifeCountReceived`: con el ancla
        // persistida se arman los mismos comandos sin volver a pedir todo el historial.
        if let persisted = persistedHistoricLifeCount,
           persisted > Int(dataPlane.lastLingoHistoricLifeCountReceived ?? 0),
           let current = dataPlane.latestPatchStatus?.currentLifeCount {
            commands = PatchControlCommand.lingoBackfillCommands(
                currentLifeCount: Int(current),
                lastHistoricLifeCountReceived: persisted,
                lastLifeCountReceived: (dataPlane.lastLingoLifeCountReceived ?? dataPlane.lastAcceptedGlucoseLifeCount).map(Int.init)
            )
        }
        guard !commands.isEmpty else { return }
        backfillRequestedAt = clock.now
        for command in commands {
            outSequence &+= 1
            do {
                let frame = try crypto.encrypt(plaintext: command.plaintext, sequence: outSequence, kind: .patchControlWrite)
                try await link.writePatchControl(frame.raw)
                await log(.info, "backfill \(public: command.label) (seq \(outSequence))")
            } catch {
                await log(.warning, "backfill \(public: command.label) no enviado: \(public: Self.typeName(error))")
                return
            }
        }
    }

    private func storeReadings(from payload: DataPlaneDecodedPayload) async {
        guard let mapper else { return }
        let readings = mapper.readings(from: payload, receivedAt: UTCInstant(clock.now))
        guard !readings.isEmpty else { return }
        do {
            _ = try await store.insertReadings(readings)
        } catch {
            await log(.error, "lecturas no guardadas: \(public: String(describing: error))")
            return
        }
        let historic = dataPlane?.lastLingoHistoricLifeCountReceived.map(Int.init)
        if let historic, historic > (persistedHistoricLifeCount ?? 0) { persistedHistoricLifeCount = historic }
        let live = readings.first { $0.origin == .live }
        await mutateSaved { saved in
            if let live { saved.lastLifeCount = max(saved.lastLifeCount ?? 0, live.lifeCount) }
            if let historic { saved.lastHistoricLifeCount = max(saved.lastHistoricLifeCount ?? 0, historic) }
        }
        if let live { await updateLiveState(live) }
    }

    private func updateLiveState(_ live: GlucoseReading) async {
        let warmup = profile?.warmupMinutes ?? SensorLifecycle.defaultWarmupDurationMinutes
        if !live.raw.qualityFlag, live.lifeCount >= warmup { hasStreamed = true }
        if hasStreamed {
            await setIfLive(.streaming(last: ReadingSummary(live)))
        } else {
            await setIfLive(.warmingUp(remainingMinutes: max(0, warmup - live.lifeCount)))
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        let interval = timeouts.staleCheckInterval
        let clock = clock
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) } catch { return }
                await self?.evaluateStaleness()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    // MARK: - Fin y fallos

    private func end(_ reason: SessionEndReason) async {
        terminal = true
        stopWatchdog()
        let now = UTCInstant(clock.now)
        await updateSessionRecord {
            $0.endedAt = now
            $0.endReason = reason
        }
        await set(.ended(reason: reason))
        await link.disconnect()
    }

    private func failActivation(sessionID id: String, reason: String) async {
        _ = try? await pairingStore.transition(sessionID: id, to: .failed, reason: reason, now: clock.now)
        await updateSessionRecord { $0.activationState = .failed }
        terminal = true
        await log(.error, "activación fallida: \(public: reason)")
        await set(.authenticationFailed(.activation, reason: .other(reason)))
    }

    /// Terminal: se persiste para que un relanzamiento no vuelva a emparejar solo.
    private func failAuthentication(phase: PairingPhase, reason: AuthenticationFailureReason) async {
        terminal = true
        stopWatchdog()
        await mutateSaved {
            $0.authFailurePhase = phase
            $0.authFailureSummary = reason.summary
        }
        if case .interrupted(let evidence) = reason {
            await log(.error, "autenticación interrumpida en \(public: phase.rawValue): último comando \(public: evidence.lastCommandText), recibido \(public: evidence.lastBytesRedacted ?? "nada"), \(Int((evidence.elapsedSeconds * 1000).rounded())) ms, \(public: evidence.underlying). No es un rechazo de credenciales; sin reintento automático")
        } else {
            await log(.error, "autenticación fallida en \(public: phase.rawValue): \(public: reason.summary); sin reintento automático")
        }
        await set(.authenticationFailed(phase, reason: reason))
    }

    /// Fase y motivo a partir de los errores del fork y de credenciales.
    static func classify(_ error: any Error) -> (PairingPhase, AuthenticationFailureReason) {
        switch error {
        case PairingFlowError.authenticationInterrupted(let phase, let evidence):
            return (PairingPhase(phase), .interrupted(AuthInterruptionEvidence(evidence)))
        case PairingFlowError.sensorCertificateVerificationFailed:
            return (.sensorCertificate, .sensorCertificateInvalid)
        case PairingFlowError.noTrustedSigningKeys, CredentialImportError.noSigningKeys:
            return (.certificateLoad, .noTrustedKeys)
        case CredentialImportError.noIdentity:
            return (.certificateLoad, .other("sin identidad de app para Lingo"))
        case PairingFlowError.writeTimeout(let label, let seconds):
            let evidence = AuthInterruptionEvidence(
                lastCommandSent: nil, lastBytesRedacted: nil, elapsedSeconds: seconds,
                underlying: "writeTimeout(\(label))"
            )
            return (PairingPhase(writeTimeoutLabel: label), .interrupted(evidence))
        case PairingFlowError.phase6VerificationFailed(let detail):
            return (.phase6, .other("Phase 6 no verificada: \(detail)"))
        case is AESCCMError, is Phase6ResponseError:
            return (.phase6, .other("Phase 6 no descifrada (\(typeName(error)))"))
        case is SensorCertError:
            return (.sensorCertificate, .other("certificado del sensor malformado"))
        default:
            return (.connecting, .other(typeName(error)))
        }
    }

    // MARK: - Persistencia auxiliar

    private func makeSessionRecord(
        _ saved: PairingState, profile: SensorProfile, state: ActivationState, epoch: Int64, source: ActivationTimeSource
    ) -> SensorSessionRecord {
        SensorSessionRecord(
            sessionID: saved.sessionID,
            sensorFamily: CoreSensorFamily(rawValue: profile.family.rawValue) ?? .unknown,
            productType: Int(profile.productType),
            securityVersion: Int(profile.securityVersion),
            sensorSerialHash: profile.serialHash,
            synthetic: false,
            sensorSerialRedacted: profile.redactedSerial,
            firmwareHex: profile.firmwareHex,
            warmupMinutes: profile.warmupMinutes,
            wearMinutes: profile.wearMinutes,
            activationTimeEpochS: epoch,
            activationTimeSource: source,
            activatedByAppID: Self.appID,
            activationSource: .thisApp,
            activationState: state,
            receiverIDPresent: true,
            lastLifeCount: saved.lastLifeCount
        )
    }

    private func sessionRecordForReadings(_ saved: PairingState) async throws -> SensorSessionRecord {
        if let existing = try await store.session(byID: saved.sessionID) { return existing }
        let restored = profile ?? saved.profile(serial: "")
        let record = makeSessionRecord(
            saved, profile: restored, state: saved.activation.state,
            epoch: saved.activationTimeEpochS ?? Int64(clock.now.timeIntervalSince1970),
            source: saved.activationTimeEpochS == nil ? .command : .nfcResponse
        )
        try await store.upsertSession(record)
        return record
    }

    private func updateSessionRecord(_ mutate: (inout SensorSessionRecord) -> Void) async {
        guard let id = sessionID, var record = try? await store.session(byID: id) else { return }
        mutate(&record)
        record.revision += 1
        do {
            try await store.upsertSession(record)
        } catch {
            await log(.error, "sesión SQLite no actualizada: \(public: Self.typeName(error))")
        }
    }

    private func mutateSaved(_ mutate: (inout PairingState) -> Void) async {
        guard let id = sessionID else { return }
        do {
            guard var saved = try await pairingStore.loadState(sessionID: id) else { return }
            mutate(&saved)
            try await pairingStore.saveState(saved)
        } catch {
            await log(.error, "estado de pairing no guardado: \(public: Self.typeName(error))")
        }
    }

    // MARK: - Estado y log

    private func set(_ new: SessionState) async {
        guard new != state || history.isEmpty else { return }
        state = new
        history.append(new)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        for continuation in observers.values { continuation.yield(new) }
        await log(.info, "estado → \(public: new.logLabel)")
    }

    /// Ignora transiciones de una sesión que ya terminó, falló o se pausó.
    private func setIfLive(_ new: SessionState) async {
        guard isLive else { return }
        await set(new)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func log(_ level: EventLogLevel, _ message: LogMessage) async {
        try? await store.logEvent(level, category: "session", message)
    }

    static func typeName(_ error: any Error) -> String {
        String(describing: type(of: error)) + "." + String(String(describing: error).prefix(80).split(separator: "(").first ?? "")
    }
}
