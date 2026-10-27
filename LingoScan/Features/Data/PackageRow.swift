import SwiftUI

/// Una copia de la carpeta con el estado de iCloud en texto (el icono nunca es la única señal).
struct PackageRow: View {
    let package: ArchivePackageStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack {
                Text(package.createdAt.date, format: .dateTime.day().month().year().hour().minute())
                    .monospacedDigit()
                Spacer(minLength: Tokens.Spacing.xs)
                Text(package.isOwn
                     ? String(localized: "data.archive.own", defaultValue: "LingoScan")
                     : package.producerTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(package.upload.title, systemImage: package.upload.systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
