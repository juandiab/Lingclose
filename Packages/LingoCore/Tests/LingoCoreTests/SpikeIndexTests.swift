import Testing
@testable import LingoCore

struct SpikeIndexTests {
    static let t0 = UTCInstant(epochSeconds: TestSupport.activationEpoch)

    private func sample(_ minute: Int, _ value: Int) -> BasicStats.Sample {
        BasicStats.Sample(measuredAt: Self.t0.adding(seconds: Int64(minute) * 60), valueMgdl: value)
    }

    /// Fixture 1: sin picos (nunca por encima de 140; tocar 140 no cuenta).
    @Test func noSpikes() {
        let samples = [100, 120, 140, 130, 90].enumerated().map { sample($0.offset, $0.element) }
        #expect(SpikeIndex.spikes(in: samples).isEmpty)
        #expect(SpikeIndex.spikes(in: []).isEmpty)
    }

    /// Fixture 2: un pico triangular. 100, 180, 100 cada minuto: cruces a 40/80 de cada tramo.
    /// Cada mitad: (180-140)/2 * 0,5 min... se calcula a mano abajo.
    @Test func singleSpike() throws {
        // t=0:100, t=1:180, t=2:100, t=3:100.
        // Subida: cruce a fracción 0,5 (140 entre 100 y 180): área = 40 * 0,5 / 2 * 1 min = 10.
        // Bajada: igual = 10. Total 20 mg/dL·min -> índice 2.
        let samples = [sample(0, 100), sample(1, 180), sample(2, 100), sample(3, 100)]
        let spikes = SpikeIndex.spikes(in: samples)
        #expect(spikes.count == 1)
        let spike = try #require(spikes.first)
        #expect(abs(spike.areaMgdlMin - 20) < 1e-9)
        #expect(spike.index == 2)
        #expect(spike.peakValue == 180)
        #expect(spike.peakAt == Self.t0.adding(seconds: 60))
        #expect(spike.start == Self.t0.adding(seconds: 30))
        #expect(spike.end == Self.t0.adding(seconds: 90))
    }

    /// Fixture 3: dos picos separados por una caída bajo el umbral; el segundo con meseta.
    @Test func twoSpikes() {
        // Pico A: 100,160,100 -> subida (20*(1/3)... fracción 40/60): 20*(1-2/3)=... se calcula abajo.
        // Subida: excess 20, fracción (140-100)/(160-100)=2/3, área = 20 * (1/3) / 2 = 3,333...
        // Bajada: excess 20, fracción 20/60=1/3, área = 20 * (1/3) / 2 = 3,333... -> A = 6,667 -> índice 1.
        // Pico B: 100,200,200,100: subida 60*0,5... excess 60, fracción 40/100 -> 60*0,6/2 = 18;
        // meseta (60+60)/2*1 = 60; bajada 18 -> 96 -> índice 10.
        let samples = [
            sample(0, 100), sample(1, 160), sample(2, 100),
            sample(3, 100),
            sample(4, 100), sample(5, 200), sample(6, 200), sample(7, 100),
        ]
        let spikes = SpikeIndex.spikes(in: samples)
        #expect(spikes.count == 2)
        #expect(abs(spikes[0].areaMgdlMin - 20.0 / 3) < 1e-9)
        #expect(spikes[0].index == 1)
        #expect(abs(spikes[1].areaMgdlMin - 96) < 1e-9)
        #expect(spikes[1].index == 10)
        #expect(spikes[1].peakValue == 200)
        #expect(spikes[0].end < spikes[1].start)
    }

    /// Fixture 4: un pico cortado por un hueco se cierra en el hueco, sin interpolar a través de él.
    @Test func spikeCutByGapClosesAtTheGap() throws {
        // 100, 180, 180 y luego 10 min sin datos; después 180, 100.
        // Primer pico: subida 40*0,5/2=10 + meseta 40 = 50 -> cierra en t=2 (índice 5).
        // Segundo pico: abre en t=12 (180) y baja a 100 en t=13: excess 40, fracción 0,5 -> 10 (índice 1).
        let samples = [sample(0, 100), sample(1, 180), sample(2, 180), sample(12, 180), sample(13, 100)]
        let spikes = SpikeIndex.spikes(in: samples)
        #expect(spikes.count == 2)
        #expect(spikes[0].end == Self.t0.adding(seconds: 120))
        #expect(abs(spikes[0].areaMgdlMin - 50) < 1e-9)
        #expect(spikes[0].index == 5)
        #expect(spikes[1].start == Self.t0.adding(seconds: 12 * 60))
        #expect(abs(spikes[1].areaMgdlMin - 10) < 1e-9)
        #expect(spikes[1].index == 1)
    }

    @Test func unsortedAndDuplicateSamplesGiveTheSameResult() {
        let ordered = [sample(0, 100), sample(1, 180), sample(2, 100)]
        let shuffled = [sample(2, 100), sample(1, 180), sample(0, 100), sample(1, 180)]
        #expect(SpikeIndex.spikes(in: ordered) == SpikeIndex.spikes(in: shuffled))
    }

    @Test func customThreshold() {
        let samples = [sample(0, 100), sample(1, 180), sample(2, 100)]
        #expect(SpikeIndex.spikes(in: samples, threshold: 200).isEmpty)
        #expect(SpikeIndex.spikes(in: samples, threshold: 120).count == 1)
    }
}
