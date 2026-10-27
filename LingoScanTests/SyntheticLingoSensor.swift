import CryptoKit
import Foundation
import RoundWhiteDiscKit
@testable import LingoScan

/// Sensor Lingo sintético que responde al protocolo de seguridad como transporte guionado de
/// `PairingFlow`: certificado firmado con una clave de firma inventada, ECDH real, Phase 5/6
/// con AES-CCM real y plano de datos con `DataPlaneCrypto`. Ningún valor es real.
actor SyntheticLingoSensor: CommandPairingTransport {
    enum Behaviour: Sendable {
        case normal
        /// Corta el enlace tras `0x03` (sin `0x04`), como un sensor que no acepta el certificado.
        case dropAfterCertificateLoadDone
    }

    nonisolated let signingKey = P256.Signing.PrivateKey()
    private let staticKey = P256.KeyAgreement.PrivateKey()
    private var behaviour: Behaviour
    private var rejectNextCached = false

    private(set) var commands: [UInt8] = []
    private(set) var acceptedKAuth: Data?
    private var dropped = false
    private var fullHandshake = false
    private var phoneStatic: P256.KeyAgreement.PublicKey?
    private var phoneEphemeral: P256.KeyAgreement.PublicKey?
    private var pendingKAuth: Data?
    private var r1 = Data()
    private var nonce7 = Data()
    private var phase5 = Data()
    private var responses: [Data] = []
    private var notifies: [BleCharRef: [Data]] = [:]
    private var crypto: DataPlaneCrypto?
    private var outbound: [DataPlanePacketKind: UInt16] = [:]

    init(behaviour: Behaviour = .normal) {
        self.behaviour = behaviour
    }

    var signingPublicKey: Data { signingKey.publicKey.x963Representation }

    func setBehaviour(_ value: Behaviour) { behaviour = value }
    func rejectNextCachedHandshake() { rejectNextCached = true }
    func setAcceptedKAuth(_ key: Data) { acceptedKAuth = key }
    func count(of command: UInt8) -> Int { commands.count(where: { $0 == command }) }

    /// Trama cifrada del plano de datos tal como llega por BLE: `ct || tag || seq LE`.
    func frame(_ plaintext: Data, kind: DataPlanePacketKind) throws -> Data {
        guard let crypto else { throw SensorLinkError.notConnected }
        let sequence = (outbound[kind] ?? 0) + 1
        outbound[kind] = sequence
        return try crypto.encrypt(plaintext: plaintext, sequence: sequence, kind: kind).raw
    }

    func decryptPatchControl(_ frame: Data) throws -> Data {
        guard let crypto else { throw SensorLinkError.notConnected }
        return try crypto.decrypt(try DataFrame.parse(frame), kind: .patchControlWrite)
    }

    // MARK: - CommandPairingTransport

    func write(_ message: Data, to characteristic: BleCharRef) async throws {
        switch characteristic {
        case .certHandshake where message.count == PhoneCert.totalSize:
            phoneStatic = try EphemeralExchange.parsePeerPubkey(try PhoneCert(raw: message).staticPub)
        case .certHandshake:
            phoneEphemeral = try EphemeralExchange.parsePeerPubkey(message.prefix(65))
        case .challenge:
            phase5 = message
        }
    }

    func awaitNotify(on characteristic: BleCharRef, exactly n: Int) async throws -> Data {
        guard var queue = notifies[characteristic], !queue.isEmpty else {
            throw SensorSessionTransportError.notifyTimeout(characteristic: characteristic.rawValue, seconds: 0)
        }
        let next = queue.removeFirst()
        notifies[characteristic] = queue
        return Data(next.prefix(n))
    }

    func writeCommand(_ command: UInt8) async throws {
        commands.append(command)
        switch command {
        case 0x01:
            fullHandshake = true
        case 0x03:
            if case .dropAfterCertificateLoadDone = behaviour { dropped = true } else { responses.append(Data([0x04])) }
        case 0x09:
            responses.append(Data([0x0a]))
            notifies[.certHandshake, default: []].append(try certificate())
        case 0x0e:
            // El teléfono ya escribió su efímera: aquí se deriva kAuth del lado del sensor.
            let key = P256.KeyAgreement.PrivateKey()
            if let phoneEphemeral, let phoneStatic {
                let ze = try EphemeralExchange.sharedSecret(privateKey: key, peer: phoneEphemeral)
                let zs = try EphemeralExchange.sharedSecret(privateKey: staticKey, peer: phoneStatic)
                pendingKAuth = Data(SHA256.hash(data: Data([0, 0, 0, 1]) + ze + zs).prefix(16))
            }
            responses.append(Data([0x0f]))
            notifies[.certHandshake, default: []].append(key.publicKey.x963Representation)
        case 0x11:
            r1 = Self.random(16)
            nonce7 = Self.random(7)
            responses.append(Data([0x08]))
            notifies[.challenge, default: []].append(r1 + nonce7)
        case 0x08:
            responses.append(Data([0x08]))
            notifies[.challenge, default: []].append(try phase6())
        default:
            break
        }
    }

    func awaitCommandResponse(timeout: TimeInterval) async throws -> Data {
        if dropped { throw SensorSessionTransportError.notifyStreamEnded(have: 0, want: 0) }
        guard !responses.isEmpty else {
            throw SensorSessionTransportError.notifyTimeout(characteristic: "secCommandResponse", seconds: timeout)
        }
        return responses.removeFirst()
    }

    // MARK: - Privado

    private func certificate() throws -> Data {
        var payload = Data([0x03, 0x00, 0x01]) + Data(repeating: 0x5A, count: 8)
        payload.append(staticKey.publicKey.x963Representation)
        let signature = try signingKey.signature(for: payload).rawRepresentation
        return payload + signature
    }

    private func phase6() throws -> Data {
        defer { fullHandshake = false }
        if !fullHandshake, rejectNextCached {
            rejectNextCached = false
            return Self.random(Phase6Response.wireSize)
        }
        guard let key = fullHandshake ? pendingKAuth : acceptedKAuth else { return Self.random(Phase6Response.wireSize) }
        let challenge = try Phase5Challenge.decode(phase5)
        let plain36 = try challenge.decrypt(sessionKey: key, nonce: nonce7)
        let r2 = plain36.subdata(in: 16..<32)
        let kEnc = Self.random(16)
        let ivEnc = Self.random(8)
        let nonce = Self.random(7)
        let (ciphertext, tag) = try AESCCM.encrypt(
            nonce: nonce, plaintext: r2 + r1 + kEnc + ivEnc, tagLength: 4, aes: AESCCM.commonCryptoBlockEncrypt(key: key)
        )
        acceptedKAuth = key
        crypto = try DataPlaneCrypto(kEnc: kEnc, ivEnc: ivEnc)
        outbound = [:]
        return ciphertext + tag + nonce
    }

    private static func random(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}
