import Foundation

public enum Libre3DataPlaneStateUpdate: Equatable, Sendable {
    case patchStatus(PatchStatus, lifecycle: SensorLifecycle)
    case realtimeGlucose(RealtimeGlucoseReading, assessment: Libre3GlucoseQualityAssessment)
    case historicalReadingPage(HistoricalReadingPage)
    case clinicalReadingRecord(ClinicalReadingRecord)
    case lingoRealtime(LingoRealtimeReading)
    case lingoHistoricalPage(LingoHistoricalPage)
    case lingoFastData(LingoFastData)
    case raw(DataPlaneDecodedPacket)
}

/// Last Lingo realtime glucose block seen on a given channel, with its raw
/// words and quality flag. No eligibility policy is applied here (that is
/// LingoCore's job): a flagged reading is recorded too, with
/// `qualityFlag == true` and no numeric value.
public struct LingoGlucoseSnapshot: Equatable, Sendable {
    public let channel: Int
    public let lifeCount: UInt16
    public let historicLifeCount: UInt16
    public let block: LingoAnalyteBlock

    /// Bit 15 of the capped word.
    public var qualityFlag: Bool {
        block.capped.qualityFlag
    }

    public var rangeBits: UInt8 {
        block.capped.rangeBits
    }
}

public struct Libre3DataPlaneState: Equatable, Sendable {
    public let warmupDurationMinutes: Int
    public let wearDurationMinutes: Int?
    public private(set) var latestPatchStatus: PatchStatus?
    public private(set) var latestLifecycle: SensorLifecycle?
    public private(set) var latestRealtimeGlucose: RealtimeGlucoseReading?
    public private(set) var latestQualityAssessment: Libre3GlucoseQualityAssessment?
    public private(set) var lastAcceptedGlucoseLifeCount: UInt16?
    public private(set) var lastAcceptedGlucoseMgDL: UInt16?
    public private(set) var historicalBackfill: HistoricalBackfill
    /// Latest Lingo realtime frame (any content).
    public private(set) var latestLingoRealtime: LingoRealtimeReading?
    /// Latest Lingo glucose block per glucose channel index (0 or 1).
    public private(set) var latestLingoGlucoseByChannel: [Int: LingoGlucoseSnapshot] = [:]
    public private(set) var lingoHistoricalPages: [LingoHistoricalPage] = []
    public private(set) var latestLingoFastData: LingoFastData?
    /// Highest lifeCount received in Lingo realtime or fast data frames.
    public private(set) var lastLingoLifeCountReceived: UInt16?
    /// Highest lifeCount of a non-flagged value received in a Lingo
    /// historical page or as the historic word of a fast-data frame.
    public private(set) var lastLingoHistoricLifeCountReceived: UInt16?

    public init(
        warmupDurationMinutes: Int = SensorLifecycle.defaultWarmupDurationMinutes,
        wearDurationMinutes: Int? = nil,
        latestPatchStatus: PatchStatus? = nil,
        lastAcceptedGlucoseLifeCount: UInt16? = nil,
        lastAcceptedGlucoseMgDL: UInt16? = nil,
        historicalBackfill: HistoricalBackfill = HistoricalBackfill()
    ) {
        self.warmupDurationMinutes = max(0, warmupDurationMinutes)
        self.wearDurationMinutes = wearDurationMinutes.map { max(0, $0) }
        self.latestPatchStatus = latestPatchStatus
        self.latestLifecycle = latestPatchStatus.map {
            $0.lifecycle(
                warmupDurationMinutes: max(0, warmupDurationMinutes),
                wearDurationMinutes: wearDurationMinutes.map { max(0, $0) }
            )
        }
        self.latestRealtimeGlucose = nil
        self.latestQualityAssessment = nil
        self.lastAcceptedGlucoseLifeCount = lastAcceptedGlucoseLifeCount
        self.lastAcceptedGlucoseMgDL = lastAcceptedGlucoseMgDL
        self.historicalBackfill = historicalBackfill
    }

    /// Seed reconnect state from persisted sensor state. When `warmup`/`wear`
    /// are not supplied, fall back to the sensor's persisted cycle (captured at
    /// pairing) and only then to the assumed default, so reconnects reflect the
    /// sensor's reported warmup/wear without re-scanning NFC.
    public init(
        sensorState: Libre3SensorState,
        warmupDurationMinutes: Int? = nil,
        wearDurationMinutes: Int? = nil,
        latestPatchStatus: PatchStatus? = nil,
        historicalBackfill: HistoricalBackfill = HistoricalBackfill()
    ) {
        self.init(
            warmupDurationMinutes: warmupDurationMinutes
                ?? sensorState.warmupDurationMinutes
                ?? SensorLifecycle.defaultWarmupDurationMinutes,
            wearDurationMinutes: wearDurationMinutes ?? sensorState.wearDurationMinutes,
            latestPatchStatus: latestPatchStatus,
            lastAcceptedGlucoseLifeCount: sensorState.lastGlucoseLifeCount,
            lastAcceptedGlucoseMgDL: sensorState.lastGlucoseMgDL,
            historicalBackfill: historicalBackfill
        )
    }

    /// Seed the data-plane state with warmup/wear durations taken from the NFC
    /// patch info, so lifecycle reflects the sensor's reported cycle rather
    /// than the assumed defaults.
    public init(
        patchInfo: Libre3NFCPatchInfo,
        latestPatchStatus: PatchStatus? = nil,
        lastAcceptedGlucoseLifeCount: UInt16? = nil,
        lastAcceptedGlucoseMgDL: UInt16? = nil,
        historicalBackfill: HistoricalBackfill = HistoricalBackfill()
    ) {
        self.init(
            warmupDurationMinutes: SensorLifecycle.warmupDurationMinutes(for: patchInfo),
            wearDurationMinutes: SensorLifecycle.wearDurationMinutes(for: patchInfo),
            latestPatchStatus: latestPatchStatus,
            lastAcceptedGlucoseLifeCount: lastAcceptedGlucoseLifeCount,
            lastAcceptedGlucoseMgDL: lastAcceptedGlucoseMgDL,
            historicalBackfill: historicalBackfill
        )
    }

    public init(
        sensorState: Libre3SensorState,
        patchInfo: Libre3NFCPatchInfo,
        latestPatchStatus: PatchStatus? = nil,
        historicalBackfill: HistoricalBackfill = HistoricalBackfill()
    ) {
        self.init(
            patchInfo: patchInfo,
            latestPatchStatus: latestPatchStatus,
            lastAcceptedGlucoseLifeCount: sensorState.lastGlucoseLifeCount,
            lastAcceptedGlucoseMgDL: sensorState.lastGlucoseMgDL,
            historicalBackfill: historicalBackfill
        )
    }

    public var lifecyclePhase: SensorLifecyclePhase? {
        latestLifecycle?.phase
    }

    public var isInWarmup: Bool {
        latestLifecycle?.isWarmingUp ?? false
    }

    public var latestSensorAttention: Libre3SensorAttention {
        latestPatchStatus?.sensorAttention ?? .none
    }

    public var shouldNotifyUser: Bool {
        latestSensorAttention.shouldNotifyUser
    }

    public var shouldNotifyReplaceSensor: Bool {
        latestSensorAttention.isReplaceSensor
    }

    public mutating func record(_ packet: DataPlaneDecodedPacket) -> Libre3DataPlaneStateUpdate {
        switch packet.payload {
        case .patchStatus(let status):
            let lifecycle = status.lifecycle(
                warmupDurationMinutes: warmupDurationMinutes,
                wearDurationMinutes: wearDurationMinutes
            )
            latestPatchStatus = status
            latestLifecycle = lifecycle
            if let latestRealtimeGlucose {
                let assessment = latestRealtimeGlucose.currentGlucoseQualityAssessment(lifecycle: lifecycle)
                latestQualityAssessment = assessment
                recordAcceptedGlucoseIfUsable(latestRealtimeGlucose, assessment: assessment)
            }
            return .patchStatus(status, lifecycle: lifecycle)

        case .realtimeGlucose(let reading):
            let assessment = assess(reading)
            latestRealtimeGlucose = reading
            latestQualityAssessment = assessment
            recordAcceptedGlucoseIfUsable(reading, assessment: assessment)
            return .realtimeGlucose(reading, assessment: assessment)

        case .historicalReadingPage(let page):
            historicalBackfill.append(page)
            return .historicalReadingPage(page)

        case .clinicalReadingRecord(let record):
            // Pass through unchanged. Apps that want minute-resolution
            // backfill consume the record's currentGlucose at its
            // lifeCount; we don't fold clinical records into
            // historicalBackfill because the two streams have different
            // commit cadences and different per-value semantics.
            return .clinicalReadingRecord(record)

        case .lingoRealtime(let reading):
            recordLingoRealtime(reading)
            return .lingoRealtime(reading)

        case .lingoHistoricalPage(let page):
            lingoHistoricalPages.append(page)
            if let last = page.samples.last(where: { $0.word.isValid })?.lifeCount {
                lastLingoHistoricLifeCountReceived = max(lastLingoHistoricLifeCountReceived ?? 0, last)
            }
            return .lingoHistoricalPage(page)

        case .lingoFastData(let fastData):
            latestLingoFastData = fastData
            lastLingoLifeCountReceived = max(lastLingoLifeCountReceived ?? 0, fastData.lifeCount)
            if fastData.historic.isValid, fastData.historicLifeCount > 0 {
                lastLingoHistoricLifeCountReceived = max(
                    lastLingoHistoricLifeCountReceived ?? 0,
                    fastData.historicLifeCount
                )
            }
            return .lingoFastData(fastData)

        case .raw:
            return .raw(packet)
        }
    }

    public func assess(_ reading: RealtimeGlucoseReading) -> Libre3GlucoseQualityAssessment {
        reading.currentGlucoseQualityAssessment(lifecycle: latestLifecycle)
    }

    private mutating func recordAcceptedGlucoseIfUsable(
        _ reading: RealtimeGlucoseReading,
        assessment: Libre3GlucoseQualityAssessment
    ) {
        guard assessment.isUsable, let mgDL = reading.currentGlucoseMgDL else {
            return
        }
        lastAcceptedGlucoseLifeCount = reading.lifeCount
        lastAcceptedGlucoseMgDL = mgDL
    }

    /// Records a Lingo realtime frame. Raw values only: the glucose
    /// snapshot is kept per channel whether or not it carries the quality
    /// flag. `lastAcceptedGlucoseLifeCount`/`MgDL` (the persisted reconnect
    /// anchor) only move when the uncapped word (what Juggluco stores) has
    /// no quality flag, so an invalid word never becomes a number.
    private mutating func recordLingoRealtime(_ reading: LingoRealtimeReading) {
        latestLingoRealtime = reading
        lastLingoLifeCountReceived = max(lastLingoLifeCountReceived ?? 0, reading.lifeCount)
        guard let channel = reading.channel, let block = reading.glucose else {
            return
        }
        latestLingoGlucoseByChannel[channel] = LingoGlucoseSnapshot(
            channel: channel,
            lifeCount: reading.lifeCount,
            historicLifeCount: reading.historicLifeCount,
            block: block
        )
        if let mgDL = block.uncapped.mgDL {
            lastAcceptedGlucoseLifeCount = reading.lifeCount
            lastAcceptedGlucoseMgDL = mgDL
        }
    }

    /// Latest Lingo glucose snapshot on the most recent frame's glucose channel.
    public var latestLingoGlucose: LingoGlucoseSnapshot? {
        guard let channel = latestLingoRealtime?.channel else {
            return nil
        }
        return latestLingoGlucoseByChannel[channel]
    }

    public var reconnectBackfillLowerBoundLifeCount: UInt16? {
        lastAcceptedGlucoseLifeCount
    }

    /// Backfill requests for the given family.
    ///
    /// - `.libre3`: upstream behaviour, `>= lastAcceptedGlucoseLifeCount`.
    /// - `.lingo`: `PatchControlCommand.lingoBackfillCommands` with the §6.1
    ///   conditions; needs a patch status (`currentLifeCount`), otherwise `[]`.
    ///   `lastLifeCountReceived` falls back to the persisted
    ///   `lastAcceptedGlucoseLifeCount`.
    /// - `.unknown`: always `[]`.
    public func reconnectBackfillCommands(
        selector: UInt8 = 0x01,
        includeClinical: Bool = true,
        family: SensorFamily = .libre3
    ) -> [PatchControlCommand] {
        switch family {
        case .unknown:
            return []
        case .lingo:
            guard let current = latestPatchStatus?.currentLifeCount else {
                return []
            }
            return PatchControlCommand.lingoBackfillCommands(
                currentLifeCount: Int(current),
                lastHistoricLifeCountReceived: lastLingoHistoricLifeCountReceived.map(Int.init),
                lastLifeCountReceived: (lastLingoLifeCountReceived ?? lastAcceptedGlucoseLifeCount).map(Int.init),
                selector: selector,
                includeClinical: includeClinical
            )
        case .libre3:
            break
        }
        guard let lifeCount = reconnectBackfillLowerBoundLifeCount else {
            return []
        }

        var commands = [
            PatchControlCommand.historicalBackfillGreaterEqual(
                lifeCount: lifeCount,
                selector: selector
            )
        ]
        if includeClinical {
            commands.append(
                PatchControlCommand.clinicalBackfillGreaterEqual(
                    lifeCount: lifeCount,
                    selector: selector
                )
            )
        }
        return commands
    }
}
