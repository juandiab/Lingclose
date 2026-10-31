import Charts
import LingoCore
import SwiftUI

/// Barra apilada del tiempo por banda (azul bajo, verde en rango, ámbar alto y muy alto). La leyenda la pone
/// `ReportBandLegend`; esta barra se oculta a VoiceOver salvo que se pida su resumen.
struct ReportBandBar: View {
    let stats: GlucoseStats
    var height: CGFloat = 14

    var body: some View {
        let shares = ReportBandShare.shares(stats)
        Chart(shares) { share in
            BarMark(
                x: .value("Fracción", share.fraction),
                y: .value("Período", "periodo"),
                height: .fixed(height)
            )
            .foregroundStyle(ReportPalette.color(for: share.band))
        }
        .chartXScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }

    /// "Bajo 3 %, en rango 71 %, alto 22 %, muy alto 4 %".
    static func spokenSummary(_ stats: GlucoseStats) -> String {
        ReportBandShare.shares(stats)
            .map { "\(ReportNames.band($0.band)) \(ReportFormat.percent($0.fraction) ?? "")" }
            .joined(separator: ", ")
    }
}
