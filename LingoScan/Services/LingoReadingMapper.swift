import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Convierte cargas Lingo decodificadas en `GlucoseReading` (contrato §5.2): `RawReading`
/// completo, `origin` por ruta, `measured_at` con `MeasuredAt.compute` y elegibilidad
/// `lingoscan-v1` con el calentamiento de la sesión (`GlucoseReading.make`).
///
/// `quality_flag` = bit 15 en cualquiera de las dos palabras del par (recortada / sin recortar):
/// la política nunca debe convertir en número una palabra marcada.
struct LingoReadingMapper: Sendable {
    let session: SensorSessionRecord
    let tzAtCapture: String

    func readings(from payload: DataPlaneDecodedPayload, receivedAt: UTCInstant) -> [GlucoseReading] {
        switch payload {
        case .lingoRealtime(let frame):
            realtime(frame, receivedAt: receivedAt)
        case .lingoHistoricalPage(let page):
            page.samples.map { sample in
                make(lifeCount: Int(sample.lifeCount), raw: Self.single(sample.word), origin: .backfillHistory, receivedAt: receivedAt)
            }
        case .lingoFastData(let fast):
            fastData(fast, receivedAt: receivedAt)
        default:
            []
        }
    }

    private func realtime(_ frame: LingoRealtimeReading, receivedAt: UTCInstant) -> [GlucoseReading] {
        guard let block = frame.glucose else { return [] }
        let live = RawReading(
            capped: block.capped.mgDL.map(Int.init),
            uncapped: block.uncapped.mgDL.map(Int.init),
            historicCapped: block.historicCapped.mgDL.map(Int.init),
            historicUncapped: block.historicUncapped.mgDL.map(Int.init),
            historicLifeCount: Int(frame.historicLifeCount),
            rateCenti: block.rateCenti.map(Int.init),
            trend: Int(block.trend),
            actionable: block.actionable,
            temperatureCenti: frame.temperatureCentiCelsius.map(Int.init),
            rangeBits: Int(block.capped.rangeBits),
            qualityFlag: block.capped.qualityFlag || block.uncapped.qualityFlag,
            channel: frame.channel,
            reservedHex: frame.reserved.lowercaseHex
        )
        var out = [make(lifeCount: Int(frame.lifeCount), raw: live, origin: .live, receivedAt: receivedAt)]
        if frame.historicLifeCount > 0 {
            let embedded = RawReading(
                capped: block.historicCapped.mgDL.map(Int.init),
                uncapped: block.historicUncapped.mgDL.map(Int.init),
                qualityFlag: block.historicCapped.qualityFlag || block.historicUncapped.qualityFlag,
                channel: frame.channel
            )
            out.append(make(lifeCount: Int(frame.historicLifeCount), raw: embedded, origin: .embeddedHistory, receivedAt: receivedAt))
        }
        return out
    }

    private func fastData(_ fast: LingoFastData, receivedAt: UTCInstant) -> [GlucoseReading] {
        var out = [make(lifeCount: Int(fast.lifeCount), raw: Self.single(fast.current), origin: .backfillFast, receivedAt: receivedAt)]
        if fast.historicLifeCount > 0 {
            out.append(make(lifeCount: Int(fast.historicLifeCount), raw: Self.single(fast.historic),
                            origin: .backfillHistory, receivedAt: receivedAt))
        }
        return out
    }

    private static func single(_ word: LingoReadingWord) -> RawReading {
        RawReading(uncapped: word.mgDL.map(Int.init), rangeBits: Int(word.rangeBits), qualityFlag: word.qualityFlag)
    }

    private func make(lifeCount: Int, raw: RawReading, origin: ReadingOrigin, receivedAt: UTCInstant) -> GlucoseReading {
        GlucoseReading.make(session: session, lifeCount: lifeCount, raw: raw, origin: origin,
                            receivedAt: receivedAt, tzAtCapture: tzAtCapture)
    }
}
