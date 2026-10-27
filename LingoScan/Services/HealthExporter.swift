import Foundation
import LingoCore

/// Resumen de un drenado, para tests y diagnóstico.
struct HealthDrainSummary: Sendable, Hashable {
    var written = 0
    var reconciled = 0
    var failed = 0
    var heldByHandover = 0
    var deferredByBackoff = 0
    var skippedIneligible = 0
    var paused = false
    var stoppedByError = false
}

/// Drena los sujetos pendientes hacia un `HealthSink` y deja cada intento en el ledger (contrato §5.4 y §7).
///
/// Solo acepta `HealthExportable`, `HealthCarbExportable` y `HealthNutrientExportable`, que no se pueden construir
/// desde datos sintéticos.
/// No hay interruptor en tiempo de ejecución que cambie eso.
actor HealthExporter {
    static let writerAppID = "com.otalvaro.lingoscan"

    private let store: SQLiteStore
    private let sink: any HealthSink
    private let writerAppID: String
    private let policy: @Sendable () -> HealthExportPolicy
    private let now: @Sendable () -> Date
    private let backoff: HealthBackoff
    private let batchSize: Int
    private var isDraining = false

    private(set) var pendingCount = 0
    private(set) var lastError: String?
    private(set) var isAuthorized = false

    init(
        store: SQLiteStore,
        sink: any HealthSink,
        writerAppID: String = HealthExporter.writerAppID,
        policy: @escaping @Sendable () -> HealthExportPolicy = { .active },
        now: @escaping @Sendable () -> Date = { Date() },
        backoff: HealthBackoff = .default,
        batchSize: Int = 100
    ) {
        self.store = store
        self.sink = sink
        self.writerAppID = writerAppID
        self.policy = policy
        self.now = now
        self.backoff = backoff
        self.batchSize = max(1, batchSize)
    }

    /// Pide permisos (escritura de glucosa, carbohidratos, energía, proteína y grasa; lectura de entrenamientos). La denegación no toca el outbox.
    func requestAuthorization() async {
        do {
            try await sink.requestAuthorization()
            await refreshAuthorization()
        } catch {
            isAuthorized = false
            lastError = Self.describe(error)
        }
    }

    func refreshAuthorization() async {
        let status = await sink.authorizationStatus()
        isAuthorized = status == .authorized
        if status == .unavailable { lastError = Self.describe(HealthSinkError.unavailable) }
    }

    /// Recalcula `pendingCount` desde el ledger (todos los huecos, incluidos los retenidos por el traspaso).
    func refreshPending() async {
        pendingCount = (try? await store.pendingHealthSubjects().count) ?? pendingCount
    }

    /// Entrenamientos por rango para la curva. Nunca escribe.
    func workouts(in range: ClosedRange<UTCInstant>) async throws -> [HealthWorkoutSummary] {
        try await sink.workouts(in: range)
    }

    /// Un drenado. `force` ignora la espera de reintento (acción explícita del usuario).
    @discardableResult
    func drain(force: Bool = false) async -> HealthDrainSummary {
        var summary = HealthDrainSummary()
        guard !isDraining else { return summary }
        isDraining = true
        defer { isDraining = false }

        let currentPolicy = policy()
        await refreshPending()
        if currentPolicy.isPaused {
            summary.paused = true
            return summary
        }
        let instant = UTCInstant(now())

        let pending: [PendingHealthSubject]
        let candidates: [HealthExportPlan.Candidate]
        do {
            pending = try await store.pendingHealthSubjects()
            var built: [HealthExportPlan.Candidate] = []
            for subject in pending { built.append(try await candidate(for: subject)) }
            candidates = built
        } catch {
            lastError = Self.describe(error)
            summary.stoppedByError = true
            return summary
        }
        let plan = HealthExportPlan.make(candidates: candidates, policy: currentPolicy, now: instant, backoff: backoff, force: force)
        summary.heldByHandover = plan.heldByHandover.count
        summary.deferredByBackoff = plan.deferredByBackoff.count
        guard !plan.reconcile.isEmpty || !plan.write.isEmpty else {
            lastError = nil
            return summary
        }

        let status = await sink.authorizationStatus()
        isAuthorized = status == .authorized
        guard isAuthorized else {
            lastError = Self.describe(status == .unavailable ? HealthSinkError.unavailable : HealthSinkError.authorizationDenied)
            summary.stoppedByError = true
            return summary
        }

        var errorText: String?
        do {
            // 1. Reconciliar `unknown`: si Health ya tiene la muestra, se registra como `written` sin reescribir.
            // Por sujeto completo: una comida tiene hasta cuatro sujetos con el mismo `subject_id`.
            var alreadyThere: Set<PendingHealthSubject> = []
            var unreconciled: Set<PendingHealthSubject> = []
            if !plan.reconcile.isEmpty {
                let prepared = try await prepare(plan.reconcile)
                do {
                    let found = try await sink.query(syncIdentifiers: Set(prepared.map(\.spec.syncIdentifier)))
                    for item in prepared where found.contains(item.spec.syncIdentifier) {
                        try await record(item, .written, at: instant)
                        alreadyThere.insert(item.subject)
                        summary.reconciled += 1
                    }
                } catch let error as HealthSinkError where error == .authorizationDenied || error == .unavailable {
                    throw error
                } catch {
                    // Sin saber si existe, no se escribe este sujeto ahora (se reintenta en el próximo drenado).
                    unreconciled = Set(prepared.map(\.subject))
                    errorText = Self.describe(error)
                }
            }

            // 2. Escribir en tandas, en orden de tiempo.
            let writable = plan.write.filter { !alreadyThere.contains($0) && !unreconciled.contains($0) }
            var prepared = try await prepare(writable)
            summary.skippedIneligible = writable.count - prepared.count
            while !prepared.isEmpty {
                let batch = Array(prepared.prefix(batchSize))
                prepared.removeFirst(batch.count)
                let results: [HealthWriteResult]
                do {
                    results = try await sink.write(samples: batch.map(\.spec))
                    guard results.count == batch.count else {
                        throw HealthSinkError.failed("el destino devolvió \(results.count) resultados para \(batch.count) muestras")
                    }
                } catch let error as HealthSinkError where error == .authorizationDenied || error == .unavailable {
                    throw error
                } catch {
                    // Fallo de la tanda: cada sujeto queda `failed` y se reintenta con espera.
                    for item in batch { try await record(item, .failed, at: instant) }
                    summary.failed += batch.count
                    errorText = Self.describe(error)
                    try? await store.logEvent(.warning, category: "health", "tanda de \(batch.count) muestras fallida: \(public: Self.describe(error))")
                    continue
                }
                for (item, result) in zip(batch, results) {
                    try await record(item, result.outcome, at: instant)
                    switch result.outcome {
                    case .written: summary.written += 1
                    case .failed, .unknown:
                        summary.failed += 1
                        errorText = result.detail ?? "una muestra no se pudo escribir"
                    }
                }
            }
        } catch {
            // Permiso o disponibilidad: no es un intento sobre ningún sujeto; el outbox queda intacto.
            errorText = Self.describe(error)
            summary.stoppedByError = true
            if let sinkError = error as? HealthSinkError, sinkError == .authorizationDenied { isAuthorized = false }
        }
        lastError = errorText
        await refreshPending()
        return summary
    }

    // MARK: - Internos

    private struct Prepared {
        let subject: PendingHealthSubject
        let spec: HealthSampleSpec
    }

    /// Estado derivado, último intento y fallos consecutivos de un sujeto.
    private func candidate(for subject: PendingHealthSubject) async throws -> HealthExportPlan.Candidate {
        let state = try await store.derivedHealthState(
            subjectID: subject.subjectID, writerAppID: writerAppID, subjectKind: subject.subjectKind,
            currentVersion: subject.revision)
        let own = try await store.ledgerEntries(subjectID: subject.subjectID, subjectKind: subject.subjectKind)
            .filter { $0.writerAppID == writerAppID }
        var failures = 0
        for entry in own.reversed() {
            guard entry.result == .failed else { break }
            failures += 1
        }
        return HealthExportPlan.Candidate(subject: subject, state: state, lastAttemptAt: own.last?.exportedAt,
                                          consecutiveFailures: failures)
    }

    /// Construye la muestra desde el almacén, revalidando elegibilidad y procedencia. Lo que no pasa se omite.
    private func prepare(_ subjects: [PendingHealthSubject]) async throws -> [Prepared] {
        var out: [Prepared] = []
        for subject in subjects {
            // Conserva el identificador ya usado por esta escritora en intentos previos (contrato §7.3).
            let previousID = try await store.ledgerEntries(subjectID: subject.subjectID, subjectKind: subject.subjectKind)
                .last { $0.writerAppID == writerAppID }?.syncIdentifier
            switch subject.subjectKind {
            case .glucose:
                guard let reading = try await store.reading(recordID: subject.subjectID),
                      let session = try await store.session(byID: reading.sessionID),
                      let exportable = HealthExportable(reading: reading, session: session)
                else { continue }
                out.append(Prepared(subject: subject, spec: HealthSampleMapper.spec(for: exportable, syncIdentifier: previousID)))
            case .carbs:
                guard let event = try await store.event(id: subject.subjectID),
                      let meal = HealthCarbExportable(event: event)
                else { continue }
                out.append(Prepared(subject: subject, spec: HealthSampleMapper.spec(for: meal, syncIdentifier: previousID)))
            case .energyKcal, .proteinG, .fatG:
                // Valor efectivo actual; si dejó de conocerse, no se escribe nada (la muestra anterior queda).
                guard let event = try await store.event(id: subject.subjectID),
                      let nutrient = HealthNutrientExportable(
                        event: event, nutrition: try await store.mealNutrition(eventID: subject.subjectID),
                        kind: subject.subjectKind)
                else { continue }
                out.append(Prepared(subject: subject, spec: HealthSampleMapper.spec(for: nutrient, syncIdentifier: previousID)))
            }
        }
        return out
    }

    private func record(_ item: Prepared, _ result: HealthLedgerResult, at instant: UTCInstant) async throws {
        try await store.appendLedger(HealthLedgerEntry(
            attemptID: UUID().uuidString.lowercased(), subjectID: item.subject.subjectID, subjectKind: item.subject.subjectKind,
            writerAppID: writerAppID, syncIdentifier: item.spec.syncIdentifier, syncVersion: item.spec.syncVersion,
            exportedAt: instant, result: result))
    }

    private static func describe(_ error: any Error) -> String {
        (error as? HealthSinkError)?.description ?? String(describing: type(of: error))
    }
}
