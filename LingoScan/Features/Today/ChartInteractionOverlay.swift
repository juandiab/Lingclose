import Charts
import SwiftUI

/// Capa sobre la curva: rótulos de las referencias, índices de pico, marcadores de comida y ejercicio con su
/// popover, y el cursor de lectura. Los gestos del cursor viven en `GlucoseChart` (`chartGesture`), así que
/// esta capa no intercepta el desplazamiento salvo en los marcadores.
///
/// En una gráfica desplazable `ChartProxy.position(forX:)` mide desde el inicio del contenido y `plotFrame`
/// es el rectángulo de todo el contenido, desplazado (`frame.minX` = −desplazamiento). `frame.minX + x` da la
/// coordenada en la capa visible, cuyo ancho es el de `geometry`; lo que cae fuera no se dibuja.
struct ChartInteractionOverlay: View {
    let proxy: ChartProxy
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                // Parte visible del área de trazado, en coordenadas de esta capa.
                let visible = CGRect(x: 0, y: frame.minY, width: geometry.size.width, height: frame.height)
                ZStack(alignment: .topLeading) {
                    referenceLabels(visible: visible)
                    ChartCursorAccessibility(viewModel: viewModel, selection: selection, visible: visible)
                    ChartCursor(proxy: proxy, frame: frame, visible: visible, viewModel: viewModel, selection: selection)
                    spikeLabels(frame: frame, visible: visible)
                    markers(frame: frame, visible: visible)
                }
            }
        }
    }

    /// Rótulos "140 mg/dL" fijos en el borde derecho visible (las anotaciones del chart se irían con el contenido).
    private func referenceLabels(visible frame: CGRect) -> some View {
        ForEach([viewModel.referenceHigh, viewModel.referenceLow], id: \.self) { value in
            if let y = proxy.position(forY: value) {
                Text(String(localized: "today.reference.value", defaultValue: "\(value) mg/dL"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: frame.width, alignment: .trailing)
                    .position(x: frame.midX, y: frame.minY + y - 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func spikeLabels(frame: CGRect, visible: CGRect) -> some View {
        ForEach(viewModel.spikes.filter { $0.index > 0 }) { spike in
            if let x = proxy.position(forX: spike.peakAt).map({ frame.minX + $0 }), (12...(visible.width - 12)).contains(x) {
                Text(spike.index, format: .number.grouping(.never))
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .position(x: x, y: frame.maxY - 62)
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(localized: "today.spike.a11y", defaultValue: "Índice de pico \(spike.index), pico de \(spike.peakValue) miligramos por decilitro, no médico"))
            }
        }
    }

    private func markers(frame: CGRect, visible: CGRect) -> some View {
        ForEach(viewModel.marks) { mark in
            if let x = proxy.position(forX: mark.date).map({ frame.minX + $0 }), (0...visible.width).contains(x) {
                ChartMarkButton(mark: mark)
                    .position(x: min(max(x, 22), visible.width - 22), y: frame.maxY - 22)
            }
        }
    }
}

/// Elemento de VoiceOver del cursor: valor leído y acción ajustable (±5 min). Sin toque: no bloquea el desplazamiento.
private struct ChartCursorAccessibility: View {
    let viewModel: TodayViewModel
    let selection: ChartSelection
    let visible: CGRect

    var body: some View {
        Color.clear
            .frame(width: visible.width, height: visible.height)
            .offset(x: visible.minX, y: visible.minY)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "today.cursor.label", defaultValue: "Cursor de la curva"))
            .accessibilityValue(selection.date.map(viewModel.readoutText(at:)) ?? String(localized: "today.cursor.idle", defaultValue: "Sin selección"))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = 300
                let base = selection.date ?? viewModel.windowEnd
                let next = base.addingTimeInterval(direction == .increment ? step : -step)
                selection.date = min(max(next, viewModel.windowStart), viewModel.windowEnd)
            }
    }
}

/// Línea vertical y punto sobre la lectura más cercana. Sin interacción propia.
private struct ChartCursor: View {
    let proxy: ChartProxy
    let frame: CGRect
    let visible: CGRect
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        if let date = selection.date, let rawX = proxy.position(forX: date) {
            let x = frame.minX + rawX
            let point = viewModel.nearestPoint(to: date)
            ZStack(alignment: .topLeading) {
                if (0...visible.width).contains(x) {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 1.5, height: frame.height)
                        .position(x: x, y: frame.midY)
                }
                if let point, let pointX = proxy.position(forX: point.date).map({ frame.minX + $0 }),
                   (0...visible.width).contains(pointX), let pointY = proxy.position(forY: point.value) {
                    Circle()
                        .fill(Color.accentColor)
                        .stroke(.background, lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(x: pointX, y: frame.minY + pointY)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .sensoryFeedback(.selection, trigger: point?.id)
        }
    }
}

/// Icono de comida o ejercicio con la hora; al tocarlo muestra el detalle en un popover.
private struct ChartMarkButton: View {
    let mark: DiaryMark
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            VStack(spacing: 0) {
                Image(systemName: mark.kind.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: .circle)
                Text(mark.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mark.kind.title), \(mark.date.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint(String(localized: "today.mark.hint", defaultValue: "Muestra el detalle"))
        .popover(isPresented: $isShowingDetail) {
            DiaryMarkDetail(mark: mark)
                .presentationCompactAdaptation(.popover)
        }
    }
}
