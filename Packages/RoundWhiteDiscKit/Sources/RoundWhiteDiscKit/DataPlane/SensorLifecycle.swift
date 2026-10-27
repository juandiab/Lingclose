import Foundation

public enum SensorLifecyclePhase: String, Equatable, Sendable {
    case warmup
    case active
    case expired
}

public struct SensorLifecycle: Equatable, Sendable {
    public static let defaultWarmupDurationMinutes = 60
    /// 14 days. Juggluco default when the NFC `wearduration` is 0
    /// (`SensorGlucoseData.hpp:784-799`, `docs/PROTOCOLO_LINGO.md` §1.6, §7).
    public static let defaultWearDurationMinutes = 20160

    /// Warm-up from the NFC patch info. `Libre3NFCPatchInfo.warmupMinutes`
    /// is already `warmup byte × 5`. For Lingo a 0 byte means "not reported"
    /// and falls back to 60 min (Juggluco). Libre 3 keeps the raw value
    /// (unchanged upstream behaviour).
    public static func warmupDurationMinutes(for patchInfo: Libre3NFCPatchInfo) -> Int {
        warmupDurationMinutes(rawMinutes: patchInfo.warmupMinutes, family: patchInfo.family)
    }

    public static func warmupDurationMinutes(rawMinutes: UInt16, family: SensorFamily) -> Int {
        if family == .lingo, rawMinutes == 0 {
            return defaultWarmupDurationMinutes
        }
        return Int(rawMinutes)
    }

    /// Wear duration from the NFC `wearduration` (minutes). For Lingo 0
    /// falls back to 20160 min (Juggluco). Libre 3 keeps the raw value.
    public static func wearDurationMinutes(for patchInfo: Libre3NFCPatchInfo) -> Int {
        wearDurationMinutes(rawMinutes: patchInfo.wearDurationMinutes, family: patchInfo.family)
    }

    public static func wearDurationMinutes(rawMinutes: UInt16, family: SensorFamily) -> Int {
        if family == .lingo, rawMinutes == 0 {
            return defaultWearDurationMinutes
        }
        return Int(rawMinutes)
    }

    public let currentLifeCountMinutes: Int
    public let warmupDurationMinutes: Int
    public let wearDurationMinutes: Int?

    public init(
        currentLifeCountMinutes: Int,
        warmupDurationMinutes: Int = Self.defaultWarmupDurationMinutes,
        wearDurationMinutes: Int? = nil
    ) {
        self.currentLifeCountMinutes = currentLifeCountMinutes
        self.warmupDurationMinutes = max(0, warmupDurationMinutes)
        self.wearDurationMinutes = wearDurationMinutes.map { max(0, $0) }
    }

    /// Lifecycle with warm-up and wear taken from the NFC patch info,
    /// applying the per-family defaults above.
    public init(currentLifeCountMinutes: Int, patchInfo: Libre3NFCPatchInfo) {
        self.init(
            currentLifeCountMinutes: currentLifeCountMinutes,
            warmupDurationMinutes: Self.warmupDurationMinutes(for: patchInfo),
            wearDurationMinutes: Self.wearDurationMinutes(for: patchInfo)
        )
    }

    public var elapsedMinutes: Int {
        max(0, currentLifeCountMinutes)
    }

    public var remainingWarmupMinutes: Int {
        max(0, warmupDurationMinutes - elapsedMinutes)
    }

    public var remainingWearMinutes: Int? {
        wearDurationMinutes.map { max(0, $0 - elapsedMinutes) }
    }

    public var isWarmupComplete: Bool {
        elapsedMinutes >= warmupDurationMinutes
    }

    public var isWarmingUp: Bool {
        !isWarmupComplete && !isExpired
    }

    public var isExpired: Bool {
        guard let wearDurationMinutes else {
            return false
        }
        return elapsedMinutes >= wearDurationMinutes
    }

    public var isActive: Bool {
        phase == .active
    }

    public var phase: SensorLifecyclePhase {
        if isExpired {
            return .expired
        }
        if !isWarmupComplete {
            return .warmup
        }
        return .active
    }
}
