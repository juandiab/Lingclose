import SwiftUI

/// Gráfica AGP dibujada con trazados (`Path`), no con Swift Charts, para que en el PDF sea vectorial y su geometría sea
/// exacta (T-34): banda objetivo, percentiles 5–95 y 25–75 y mediana por media hora del día local.
struct MedicalPDFAGPChart: View {
    let agp: MedicalAGP

    private let leftInset: CGFloat = 34
    private let rightInset: CGFloat = 8
    private let topInset: CGFloat = 6
    private let bottomInset: CGFloat = 18

    var body: some View {
        let size = CGSize(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.agpChartHeight)
        let plot = CGRect(x: leftInset, y: topInset, width: size.width - leftInset - rightInset,
                          height: size.height - topInset - bottomInset)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(MedicalPDFPalette.paper)
            // Banda objetivo.
            Path(CGRect(x: plot.minX, y: y(agp.targetHigh, plot), width: plot.width, height: y(agp.targetLow, plot) - y(agp.targetHigh, plot)))
                .fill(MedicalPDFPalette.targetFill)
            grid(plot)
            if agp.hasData {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    band(run, lower: \.p5, upper: \.p95, plot).fill(MedicalPDFPalette.accent.opacity(0.14))
                    band(run, lower: \.p25, upper: \.p75, plot).fill(MedicalPDFPalette.accent.opacity(0.30))
                    median(run, plot).stroke(MedicalPDFPalette.accent, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
            } else {
                Text(verbatim: MedicalReportStrings.agpNoData)
                    .font(.system(size: 9))
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .position(x: plot.midX, y: plot.midY)
            }
            Path { path in
                path.addRect(plot)
            }
            .stroke(MedicalPDFPalette.hairline, lineWidth: 0.6)
            Path { path in
                for value in [agp.targetLow, agp.targetHigh] {
                    path.move(to: CGPoint(x: plot.minX, y: y(value, plot)))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y(value, plot)))
                }
            }
            .stroke(MedicalPDFPalette.targetLine, style: StrokeStyle(lineWidth: 0.7, dash: [3, 2]))
            axisLabels(plot)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Geometría

    private func x(_ minute: Double, _ plot: CGRect) -> CGFloat { plot.minX + plot.width * CGFloat(minute / 1_440) }

    private func y(_ value: Double, _ plot: CGRect) -> CGFloat {
        let clamped = min(max(value, agp.yMin), agp.yMax)
        return plot.maxY - plot.height * CGFloat((clamped - agp.yMin) / (agp.yMax - agp.yMin))
    }

    /// Tramos de medias horas contiguas: un hueco corta la banda y la línea.
    private var runs: [[MedicalAGPPoint]] {
        var result: [[MedicalAGPPoint]] = []
        for point in agp.points {
            if let last = result.last?.last, point.minute == last.minute + 30 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    private func center(_ point: MedicalAGPPoint) -> Double { Double(point.minute) + 15 }

    private func band(_ run: [MedicalAGPPoint], lower: KeyPath<MedicalAGPPoint, Double>,
                      upper: KeyPath<MedicalAGPPoint, Double>, _ plot: CGRect) -> Path {
        Path { path in
            guard run.count > 1 else { return }
            path.move(to: CGPoint(x: x(center(run[0]), plot), y: y(run[0][keyPath: upper], plot)))
            for point in run.dropFirst() {
                path.addLine(to: CGPoint(x: x(center(point), plot), y: y(point[keyPath: upper], plot)))
            }
            for point in run.reversed() {
                path.addLine(to: CGPoint(x: x(center(point), plot), y: y(point[keyPath: lower], plot)))
            }
            path.closeSubpath()
        }
    }

    private func median(_ run: [MedicalAGPPoint], _ plot: CGRect) -> Path {
        Path { path in
            for (index, point) in run.enumerated() {
                let location = CGPoint(x: x(center(point), plot), y: y(point.p50, plot))
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
            if run.count == 1, let point = run.first {
                let location = CGPoint(x: x(center(point), plot), y: y(point.p50, plot))
                path.addLine(to: CGPoint(x: location.x + 0.1, y: location.y))
            }
        }
    }

    // MARK: Rejilla y rótulos

    private func grid(_ plot: CGRect) -> some View {
        Path { path in
            for tick in agp.ticks {
                path.move(to: CGPoint(x: plot.minX, y: y(tick.mgdl, plot)))
                path.addLine(to: CGPoint(x: plot.maxX, y: y(tick.mgdl, plot)))
            }
            for hour in stride(from: 0, through: 24, by: 3) {
                path.move(to: CGPoint(x: x(Double(hour * 60), plot), y: plot.minY))
                path.addLine(to: CGPoint(x: x(Double(hour * 60), plot), y: plot.maxY))
            }
        }
        .stroke(MedicalPDFPalette.hairline.opacity(0.8), lineWidth: 0.4)
    }

    private func axisLabels(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(agp.ticks.enumerated()), id: \.offset) { _, tick in
                Text(verbatim: tick.label)
                    .font(.system(size: 7))
                    .monospacedDigit()
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .frame(width: leftInset - 6, alignment: .trailing)
                    .position(x: (leftInset - 6) / 2, y: y(tick.mgdl, plot))
            }
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                Text(verbatim: String(format: "%02d:00", hour % 24 == 0 && hour > 0 ? 24 : hour))
                    .font(.system(size: 7))
                    .monospacedDigit()
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .position(x: x(Double(hour * 60), plot), y: plot.maxY + 9)
            }
        }
    }
}
