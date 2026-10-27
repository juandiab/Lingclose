import Foundation

/// Reglas de escritura vigentes (contrato §7). Las fija la app; el exportador solo las obedece.
public struct HealthExportPolicy: Sendable, Hashable {
    /// Modo "en pausa": no escribe nada.
    public var isPaused: Bool
    /// `health.handover_at_utc`: solo se escriben sujetos con `measuredAt > handoverAt`.
    public var handoverAt: UTCInstant?
    /// "Rellenar huecos en Health" explícito: ignora `handoverAt`.
    public var fillGaps: Bool

    public init(isPaused: Bool = false, handoverAt: UTCInstant? = nil, fillGaps: Bool = false) {
        self.isPaused = isPaused
        self.handoverAt = handoverAt
        self.fillGaps = fillGaps
    }

    public static let active = HealthExportPolicy()
}

/// Espera entre reintentos de un sujeto `failed`: `base · 2^(fallos-1)`, con tope.
public struct HealthBackoff: Sendable, Hashable {
    public var baseSeconds: Int64
    public var maxSeconds: Int64

    public init(baseSeconds: Int64 = 60, maxSeconds: Int64 = 6 * 3600) {
        self.baseSeconds = baseSeconds
        self.maxSeconds = maxSeconds
    }

    public static let `default` = HealthBackoff()

    public func delay(consecutiveFailures: Int) -> Int64 {
        guard consecutiveFailures > 0 else { return 0 }
        let exponent = min(consecutiveFailures - 1, 30)
        let raw = baseSeconds.multipliedReportingOverflow(by: Int64(1) << Int64(exponent))
        return raw.overflow ? maxSeconds : min(raw.partialValue, maxSeconds)
    }
}

/// Decisión pura de qué hacer con cada sujeto pendiente en un drenado.
public struct HealthExportPlan: Sendable, Hashable {
    public struct Candidate: Sendable, Hashable {
        public let subject: PendingHealthSubject
        public let state: DerivedHealthState
        public let lastAttemptAt: UTCInstant?
        public let consecutiveFailures: Int

        public init(subject: PendingHealthSubject, state: DerivedHealthState, lastAttemptAt: UTCInstant?,
                    consecutiveFailures: Int) {
            self.subject = subject
            self.state = state
            self.lastAttemptAt = lastAttemptAt
            self.consecutiveFailures = consecutiveFailures
        }
    }

    /// `unknown`: consultar Health por `sync_identifier` antes de escribir.
    public let reconcile: [PendingHealthSubject]
    /// `none`, `failed` (fuera de espera) y `unknown` que Health no tenía.
    public let write: [PendingHealthSubject]
    /// Anteriores al traspaso: huecos pendientes visibles, no se escriben.
    public let heldByHandover: [PendingHealthSubject]
    /// `failed` todavía dentro de su espera.
    public let deferredByBackoff: [PendingHealthSubject]

    public static func make(
        candidates: [Candidate], policy: HealthExportPolicy, now: UTCInstant, backoff: HealthBackoff, force: Bool = false
    ) -> HealthExportPlan {
        guard !policy.isPaused else {
            return HealthExportPlan(reconcile: [], write: [], heldByHandover: [], deferredByBackoff: [])
        }
        var reconcile: [PendingHealthSubject] = [], write: [PendingHealthSubject] = []
        var held: [PendingHealthSubject] = [], deferred: [PendingHealthSubject] = []
        for c in candidates {
            if c.state == .written { continue }
            if c.state == .unknown { reconcile.append(c.subject) }
            if !policy.fillGaps, let handover = policy.handoverAt, c.subject.measuredAt <= handover {
                held.append(c.subject)
                continue
            }
            if c.state == .failed, !force, let last = c.lastAttemptAt,
               now.epochSeconds < last.epochSeconds + backoff.delay(consecutiveFailures: c.consecutiveFailures) {
                deferred.append(c.subject)
                continue
            }
            write.append(c.subject)
        }
        return HealthExportPlan(reconcile: reconcile, write: write, heldByHandover: held, deferredByBackoff: deferred)
    }
}
