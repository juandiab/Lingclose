import SwiftUI

/// Mini-curva de un día (288 ranuras de 5 min) con la banda objetivo, dibujada con trazados (T-34).
struct MedicalPDFMiniCurve: View {
    let values: [Int?]
    let targetLow: Double
    let targetHigh: Double
    let width: CGFloat
    let height: CGFloat

    private let yMin = 40.0
    private let yMax = 320.0
    /// Huecos de hasta 3 ranuras (15 min) se unen; mayores cortan la línea.
    private let maxJoinedGap = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path(CGRect(x: 0, y: y(targetHigh), width: width, height: y(targetLow) - y(targetHigh)))
                .fill(MedicalPDFPalette.targetFill)
            Path(CGRect(x: 0, y: 0, width: width, height: height))
                .stroke(MedicalPDFPalette.hairline, lineWidth: 0.5)
            curve.stroke(MedicalPDFPalette.accent, style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }

    private func y(_ value: Double) -> CGFloat {
        let clamped = min(max(value, yMin), yMax)
        return height - height * CGFloat((clamped - yMin) / (yMax - yMin))
    }

    private var curve: Path {
        Path { path in
            guard values.count > 1 else { return }
            var last: Int?
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let point = CGPoint(x: width * CGFloat(index) / CGFloat(values.count - 1), y: y(Double(value)))
                if let last, index - last <= maxJoinedGap { path.addLine(to: point) } else { path.move(to: point) }
                last = index
            }
        }
    }
}
