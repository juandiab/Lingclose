import Foundation

/// Cálculos puros sobre el ledger append-only (contrato §5.4, C4) que alimentan `manifest.health`.
public enum ArchiveHealthDerivation {
    /// Par (sujeto, escritora).
    public struct Key: Sendable, Hashable {
        public let subjectID: String
        public let writerAppID: String
    }

    /// Estado derivado por (sujeto, escritora): `written` si hay un intento `written` con el `sync_version` más
    /// alto conocido; si no, `unknown` si el último intento de esa versión fue `unknown`, y `failed` en otro caso.
    /// "Último" = mayor (`exported_at`, `attempt_id`), un orden total que no depende del orden de unión.
    public static func derivedStates(_ ledger: [HealthLedgerEntry]) -> [Key: DerivedHealthState] {
        var grouped: [Key: [HealthLedgerEntry]] = [:]
        for l in ledger { grouped[Key(subjectID: l.subjectID, writerAppID: l.writerAppID), default: []].append(l) }
        var out: [Key: DerivedHealthState] = [:]
        for (key, attempts) in grouped {
            let top = attempts.filter { $0.syncVersion == (attempts.map(\.syncVersion).max() ?? 0) }
            if top.contains(where: { $0.result == .written }) {
                out[key] = .written
            } else {
                let last = top.max { ($0.exportedAt, $0.attemptID) < ($1.exportedAt, $1.attemptID) }
                out[key] = last?.result == .unknown ? .unknown : .failed
            }
        }
        return out
    }

    /// Mejor estado por sujeto entre todas las escritoras: `written` > `unknown` > `failed` > `none`.
    public static func bestStates(_ ledger: [HealthLedgerEntry]) -> [String: DerivedHealthState] {
        func rank(_ s: DerivedHealthState) -> Int {
            switch s {
            case .written: 3
            case .unknown: 2
            case .failed: 1
            case .none: 0
            }
        }
        var best: [String: DerivedHealthState] = [:]
        for (key, state) in derivedStates(ledger) where rank(state) > rank(best[key.subjectID] ?? .none) {
            best[key.subjectID] = state
        }
        return best
    }

    /// Huecos pendientes (§5.4): lecturas elegibles, no borradas y no sintéticas, y comidas con carbohidratos,
    /// sin estado `written` para ninguna escritora.
    public static func pendingSubjects(readings: [GlucoseReading], events: [DiaryEvent],
                                       ledger: [HealthLedgerEntry]) -> [PendingHealthSubject] {
        // Por tipo: una comida comparte `subject_id` con energía, proteína y grasa (draft.5). Estos tres no
        // cuentan aquí: dependen de `meal_nutrition`, que no viaja en el paquete.
        let best = bestStates(ledger.filter { $0.subjectKind == .glucose })
        let bestCarbs = bestStates(ledger.filter { $0.subjectKind == .carbs })
        var out: [PendingHealthSubject] = []
        for r in readings where r.eligibility.isEligible && !r.deleted && !r.synthetic && best[r.recordID] != .written {
            out.append(PendingHealthSubject(subjectID: r.recordID, subjectKind: .glucose, measuredAt: r.measuredAt))
        }
        for e in events where e.kind == .meal && e.carbsG != nil && !e.deleted && !e.synthetic
            && bestCarbs[e.eventID] != .written {
            out.append(PendingHealthSubject(subjectID: e.eventID, subjectKind: .carbs, measuredAt: e.at))
        }
        return out.sorted { ($0.measuredAt, $0.subjectID) < ($1.measuredAt, $1.subjectID) }
    }

    /// Mayor `measured_at` con estado derivado `written` para `writerAppID` (pista, no prueba: §4).
    public static func lastConfirmed(writerAppID: String?, readings: [GlucoseReading],
                                     ledger: [HealthLedgerEntry]) -> UTCInstant? {
        guard let writerAppID else { return nil }
        let states = derivedStates(ledger)
        var latest: UTCInstant?
        for r in readings where states[Key(subjectID: r.recordID, writerAppID: writerAppID)] == .written {
            if latest == nil || r.measuredAt > latest! { latest = r.measuredAt }
        }
        return latest
    }

    /// Bloque `health` del manifest para un contenido y una escritora.
    public static func healthBlock(content: ArchiveContent, writerAppID: String?, handoverAt: UTCInstant?) -> ArchiveManifest.Health {
        let pending = pendingSubjects(readings: content.readings, events: content.events.map(\.event), ledger: content.ledger)
        return ArchiveManifest.Health(
            writerAppID: writerAppID, handoverAt: handoverAt,
            lastConfirmedMeasuredAt: lastConfirmed(writerAppID: writerAppID, readings: content.readings, ledger: content.ledger),
            pendingSubjects: pending.count)
    }
}
