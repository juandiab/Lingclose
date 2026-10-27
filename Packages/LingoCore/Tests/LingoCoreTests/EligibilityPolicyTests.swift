import Testing
@testable import LingoCore

/// Política `lingoscan-v1` con los 12 vectores públicos de Juggluco (`docs/PROTOCOLO_LINGO.md` §8)
/// convertidos a `RawReading`, más casos sintéticos.
struct EligibilityPolicyTests {
    /// Las capturas de Juggluco ya dan valores válidos en lc 58 (§7): con calentamiento real desconocido,
    /// los vectores se evalúan con `warmupMinutes = 0` y el bit 15 marca el warm-up. El caso con el
    /// valor por defecto (60 min) se prueba aparte en `warmUpByLifeCount`.
    static let vectorWarmup = 0

    static func evaluate(_ d: LingoFrameFixture.Decoded, warmup: Int = vectorWarmup) -> (Eligibility, Int?) {
        let e = LingoScanV1Policy.evaluate(raw: d.raw, lifeCount: d.lifeCount, warmupMinutes: warmup,
                                           synthetic: false, deleted: false)
        return (e, LingoScanV1Policy.value(for: d.raw, eligibility: e))
    }

    @Test func warmUpVectorsLC1to4AreQualityFlag() {
        for (i, hex) in LingoFrameFixture.warmUp.enumerated() {
            let d = LingoFrameFixture.decode(hex)
            #expect(d.lifeCount == i + 1)
            #expect(d.raw.qualityFlag)
            #expect(d.raw.channel == 1)
            #expect(d.raw.capped == nil && d.raw.uncapped == nil)
            #expect(d.raw.rateCenti == nil && d.raw.trend == 0 && d.raw.temperatureCenti == nil)
            // Con warm-up 0 y con el valor por defecto (60): bit 15 tiene precedencia sobre warm_up.
            for warmup in [0, 60] {
                let (e, v) = Self.evaluate(d, warmup: warmup)
                #expect(e.status == .excluded && e.reason == .qualityFlag && v == nil)
            }
        }
    }

    @Test func warmVectorsLC58And63AreEligibleWith201And208() {
        let d58 = LingoFrameFixture.decode(LingoFrameFixture.warmLC58)
        let d63 = LingoFrameFixture.decode(LingoFrameFixture.warmLC63)
        #expect(d58.lifeCount == 58 && d63.lifeCount == 63)
        #expect(d58.raw.capped == 201 && d58.raw.uncapped == 201)
        #expect(d63.raw.capped == 201 && d63.raw.uncapped == 208)
        #expect(d58.raw.rangeBits == 2 && d58.raw.historicLifeCount == 40 && d63.raw.historicLifeCount == 45)
        #expect(d58.raw.temperatureCenti == 3283 && d63.raw.temperatureCenti == 3257)
        #expect(d63.raw.reservedHex == "0000b90c70000109e14ced0e00000000")  // ejemplo del contrato §5.2
        let (e58, v58) = Self.evaluate(d58)
        let (e63, v63) = Self.evaluate(d63)
        #expect(e58 == .eligible(policyID: "lingoscan-v1", policyVersion: "1.0.0") && v58 == 201)
        #expect(e63.isEligible && v63 == 208)  // valor = uncapped, no capped
    }

    @Test func trendVectorsAreEligibleWithTheirValues() {
        for vector in LingoFrameFixture.trends {
            let d = LingoFrameFixture.decode(vector.hex)
            #expect(d.raw.rateCenti == vector.rate)
            #expect(d.raw.trend == vector.trend)
            #expect(d.raw.channel == 1)
            let (e, v) = Self.evaluate(d)
            #expect(e.isEligible && e.reason == nil, "lc \(d.lifeCount)")
            #expect(v == vector.mgdl, "lc \(d.lifeCount)")
        }
        #expect(LingoFrameFixture.warmUp.count + 2 + LingoFrameFixture.trends.count == 12)
    }

    @Test func warmUpByLifeCount() {
        let d58 = LingoFrameFixture.decode(LingoFrameFixture.warmLC58)
        let (e, v) = Self.evaluate(d58, warmup: 60)
        #expect(e.reason == .warmUp && v == nil)
        let raw = TestSupport.raw(uncapped: 110)
        #expect(LingoScanV1Policy.evaluate(raw: raw, lifeCount: 59, warmupMinutes: 60, synthetic: false, deleted: false).reason == .warmUp)
        #expect(LingoScanV1Policy.evaluate(raw: raw, lifeCount: 60, warmupMinutes: 60, synthetic: false, deleted: false).isEligible)
    }

    @Test(arguments: [(1, false), (38, false), (39, true), (501, true), (502, false), (999, false), (0, false)])
    func rangeWithoutClamping(value: Int, eligible: Bool) {
        let raw = TestSupport.raw(uncapped: value)
        let e = LingoScanV1Policy.evaluate(raw: raw, lifeCount: 500, warmupMinutes: 60, synthetic: false, deleted: false)
        #expect(e.isEligible == eligible)
        if !eligible { #expect(e.reason == .outOfRange) }
        #expect(LingoScanV1Policy.value(for: raw, eligibility: e) == (eligible ? value : nil))
    }

    @Test func cappedIsUsedOnlyWithoutUncapped() {
        let onlyCapped = TestSupport.raw(capped: 120)
        let e = LingoScanV1Policy.evaluate(raw: onlyCapped, lifeCount: 500, warmupMinutes: 60, synthetic: false, deleted: false)
        #expect(LingoScanV1Policy.value(for: onlyCapped, eligibility: e) == 120)
        let both = TestSupport.raw(uncapped: 600, capped: 501)
        #expect(LingoScanV1Policy.evaluate(raw: both, lifeCount: 500, warmupMinutes: 60, synthetic: false, deleted: false).reason == .outOfRange)
        let none = TestSupport.raw()
        #expect(LingoScanV1Policy.evaluate(raw: none, lifeCount: 500, warmupMinutes: 60, synthetic: false, deleted: false).reason == .decoderError)
    }

    @Test func reasonPrecedence() {
        let bad = TestSupport.raw(uncapped: 700, qualityFlag: true)
        func reason(_ synthetic: Bool, _ deleted: Bool, lc: Int = 5) -> ExclusionReason? {
            LingoScanV1Policy.evaluate(raw: bad, lifeCount: lc, warmupMinutes: 60, synthetic: synthetic, deleted: deleted).reason
        }
        #expect(reason(true, true) == .deleted)
        #expect(reason(true, false) == .synthetic)
        #expect(reason(false, false) == .qualityFlag)
        let warmAndRange = TestSupport.raw(uncapped: 700)
        #expect(LingoScanV1Policy.evaluate(raw: warmAndRange, lifeCount: 5, warmupMinutes: 60, synthetic: false, deleted: false).reason == .warmUp)
        #expect(LingoScanV1Policy.evaluate(raw: TestSupport.raw(), lifeCount: 5000, warmupMinutes: 60, synthetic: false, deleted: false).reason == .decoderError)
        #expect(ExclusionReason.allCases.sorted { $0.precedence > $1.precedence } ==
                [.deleted, .synthetic, .qualityFlag, .warmUp, .outOfRange, .decoderError, .duplicate, .other])
    }

    @Test func syntheticPackageComputesEligibilityAsReal() {
        let raw = TestSupport.raw(uncapped: 150)
        let inRealStore = LingoScanV1Policy.evaluate(raw: raw, lifeCount: 500, warmupMinutes: 60, synthetic: true, deleted: false)
        #expect(inRealStore.reason == .synthetic)
        let inSyntheticPackage = LingoScanV1Policy.evaluate(raw: raw, lifeCount: 500, warmupMinutes: 60,
                                                            synthetic: true, deleted: false, inSyntheticPackage: true)
        #expect(inSyntheticPackage.isEligible)
    }

    @Test func healthExportableOnlyFromRealEligibleLiveData() throws {
        let real = TestSupport.session()
        let eligible = TestSupport.reading(real, lc: 100, raw: TestSupport.raw(uncapped: 150, trend: 3), origin: .live)
        let exportable = try #require(HealthExportable(reading: eligible))
        #expect(exportable.valueMgdl == 150 && exportable.syncIdentifier == eligible.recordID && exportable.syncVersion == 1)
        #expect(HealthExportable(reading: eligible, session: real) != nil)

        // Sintético con elegibilidad calculada "como real" (paquete sintético): sigue sin poder exportarse.
        var synthetic = eligible
        synthetic.synthetic = true
        #expect(synthetic.eligibility.isEligible)
        #expect(HealthExportable(reading: synthetic) == nil)

        var deleted = eligible
        deleted.deleted = true
        #expect(HealthExportable(reading: deleted) == nil)

        let excluded = TestSupport.reading(real, lc: 100, raw: TestSupport.raw(qualityFlag: true), origin: .live)
        #expect(HealthExportable(reading: excluded) == nil)

        // Procedencia persistida: lectura marcada real pero sesión sintética.
        var syntheticSession = real
        syntheticSession.synthetic = true
        #expect(HealthExportable(reading: eligible, session: syntheticSession) == nil)
        #expect(HealthExportable(reading: eligible, session: TestSupport.session()) == nil)  // otra sesión
    }
}
