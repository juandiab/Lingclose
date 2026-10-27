import Charts
import SwiftUI

/// Capa interactiva sobre la curva: índices de pico, marcadores de comida y ejercicio con su popover,
/// y el arrastre que mueve una línea vertical y lee el valor.
struct ChartInteractionOverlay: View {
    let proxy: ChartProxy
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let frame = geometry[plotFrame]
                ZStack(alignment: .topLeading) {
                    ChartDragLayer(proxy: proxy, frame: frame, viewModel: viewModel, selection: selection)
                    ChartCursor(proxy: proxy, frame: frame, viewModel: viewModel, selection: selection)
                    spikeLabels(frame: frame)
                    markers(frame: frame)
                }
            }
        }
    }

    private func spikeLabels(frame: CGRect) -> some View {
        ForEach(viewModel.spikes.filter { $0.index > 0 }) { spike in
            if let x = proxy.position(forX: spike.peakAt), (0...frame.width).contains(x) {
                Text(spike.index, format: .number.grouping(.never))
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .position(x: frame.minX + x, y: frame.maxY - 62)
                    .accessibilityLabel(String(localized: "today.spike.a11y", defaultValue: "Índice de pico \(spike.index), pico de \(spike.peakValue) miligramos por decilitro, no médico"))
            }
        }
    }

    private func markers(frame: CGRect) -> some View {
        ForEach(viewModel.marks) { mark in
            if let x = proxy.position(forX: mark.date), (0...frame.width).contains(x) {
                ChartMarkButton(mark: mark)
                    .position(x: frame.minX + min(max(x, 22), frame.width - 22), y: frame.maxY - 22)
            }
        }
    }
}

/// Arrastre horizontal sobre la curva. No bloquea el scroll vertical: es un gesto simultáneo y solo se
/// activa si el movimiento inicial es más horizontal que vertical.
private struct ChartDragLayer: View {
    let proxy: ChartProxy
    let frame: CGRect
    let viewModel: TodayViewModel
    let selection: ChartSelection
    @State private var isHorizontal: Bool?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: frame.width, height: frame.height)
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if isHorizontal == nil {
                            isHorizontal = abs(value.translation.width) >= abs(value.translation.height)
                        }
                        guard isHorizontal == true else { return }
                        select(atX: value.location.x)
                    }
                    .onEnded { _ in isHorizontal = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if selection.date == nil { select(atX: value.location.x) } else { selection.date = nil }
                    }
            )
            .offset(x: frame.minX, y: frame.minY)
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

    private func select(atX x: CGFloat) {
        let clamped = min(max(x, 0), frame.width)
        guard let date = proxy.value(atX: clamped, as: Date.self) else { return }
        selection.date = min(max(date, viewModel.windowStart), viewModel.windowEnd)
    }
}

/// Línea vertical y punto sobre la lectura más cercana. Sin interacción propia.
private struct ChartCursor: View {
    let proxy: ChartProxy
    let frame: CGRect
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        if let date = selection.date, let x = proxy.position(forX: date) {
            let point = viewModel.nearestPoint(to: date)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.primary)
                    .frame(width: 1.5, height: frame.height)
                    .position(x: frame.minX + x, y: frame.midY)
                if let point, let pointX = proxy.position(forX: point.date), let pointY = proxy.position(forY: point.value) {
                    Circle()
                        .fill(Color.accentColor)
                        .stroke(.background, lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(x: frame.minX + pointX, y: frame.minY + pointY)
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
