import SwiftUI

/// Qué es cada capa del perfil por hora.
struct HourlyProfileLegend: View {
    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            item(String(localized: "reports.profile.legend.median", defaultValue: "Mediana")) {
                Capsule().fill(Color.primary).frame(width: 16, height: 3)
            }
            item(String(localized: "reports.profile.legend.inner", defaultValue: "50 % de los días")) {
                RoundedRectangle(cornerRadius: 2).fill(ReportPalette.innerBand).frame(width: 16, height: 10)
            }
            item(String(localized: "reports.profile.legend.outer", defaultValue: "90 %")) {
                RoundedRectangle(cornerRadius: 2).fill(ReportPalette.outerBand).frame(width: 16, height: 10)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: Tokens.Spacing.xxs) {
            swatch()
            Text(title)
        }
    }
}
