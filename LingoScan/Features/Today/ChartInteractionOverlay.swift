import Charts
import SwiftUI

/// Capa sobre la curva: rótulos de las referencias, índices de pico, marcadores de comida y ejercicio con su
/// popover (con la respuesta a la comida o el efecto del ejercicio, T-23), y el cursor de lectura. Las líneas
/// verticales de las marcas son `RuleMark` de la propia gráfica (`GlucoseChart`), bajo esta capa. Marcadores e índices cercanos en pantalla se agrupan (`ChartXGrouping`)
/// con las posiciones actuales, así que la agrupación cambia con el zoom y el desplazamiento. Los gestos del cursor viven en `GlucoseChart` (`chartGesture`), así que
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

    /// Rótulos cortos ("140") pegados al borde derecho visible, sobre su línea y con fondo de la superficie
    /// para que la curva no los tape (las anotaciones del chart se irían con el contenido).
    private func referenceLabels(visible frame: CGRect) -> some View {
        ForEach([viewModel.referenceHigh, viewModel.referenceLow], id: \.self) { value in
            if let y = proxy.position(forY: Double(value)) {
                Text(value, format: .number.grouping(.never))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .background(.background.opacity(0.85), in: .capsule)
                    .fixedSize()
                    .frame(width: frame.width, alignment: .trailing)
                    .position(x: frame.midX, y: frame.minY + y - 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Separación mínima entre centros de marcadores (su área táctil) e índices de pico.
    static let markerSpacing: CGFloat = 44
    static let spikeLabelSpacing: CGFloat = 28

    /// Índices de pico visibles, justo encima de cada pico; si dos rótulos quedan a menos de
    /// `spikeLabelSpacing`, solo el de mayor pico.
    private func spikeLabels(frame: CGRect, visible: CGRect) -> some View {
        ForEach(visibleSpikes(frame: frame, visible: visible), id: \.spike.id) { item in
            let peakY = proxy.position(forY: Double(item.spike.peakValue)).map { frame.minY + $0 } ?? frame.minY
            Text(item.spike.index, format: .number.grouping(.never))
                .font(.caption2.bold())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .position(x: item.x, y: max(peakY - 12, frame.minY + 8))
                .allowsHitTesting(false)
                .accessibilityLabel(String(localized: "today.spike.a11y", defaultValue: "Índice de pico \(item.spike.index), pico de \(item.spike.peakValue) miligramos por decilitro, no médico"))
        }
    }

    private func visibleSpikes(frame: CGRect, visible: CGRect) -> [(spike: TodaySpike, x: CGFloat)] {
        var positioned: [TodaySpike.ID: (spike: TodaySpike, x: CGFloat)] = [:]
        for spike in viewModel.spikes where spike.index > 0 {
            guard let x = proxy.position(forX: spike.peakAt).map({ frame.minX + $0 }),
                  (12...(visible.width - 12)).contains(x) else { continue }
            positioned[spike.id] = (spike, x)
        }
        let groups = ChartXGrouping.groups(positioned.values.map { (x: $0.x, id: $0.spike.id) }, minDistance: Self.spikeLabelSpacing)
        return groups.compactMap { ids in
            ids.compactMap { positioned[$0] }.max { $0.spike.peakValue < $1.spike.peakValue }
        }
    }

    /// Marcadores visibles; los que quedan a menos de `markerSpacing` del anterior se fusionan en un grupo.
    private func markers(frame: CGRect, visible: CGRect) -> some View {
        ForEach(markGroups(frame: frame, visible: visible)) { group in
            ChartMarkGroupButton(group: group, viewModel: viewModel)
                .position(x: min(max(group.x, 22), visible.width - 22), y: frame.maxY - 22)
        }
    }

    private func markGroups(frame: CGRect, visible: CGRect) -> [ChartMarkGroup] {
        var positioned: [DiaryMark.ID: (mark: DiaryMark, x: CGFloat)] = [:]
        for mark in viewModel.marks {
            guard let x = proxy.position(forX: mark.date).map({ frame.minX + $0 }),
                  (0...visible.width).contains(x) else { continue }
            positioned[mark.id] = (mark, x)
        }
        let groups = ChartXGrouping.groups(positioned.values.map { (x: $0.x, id: $0.mark.id) }, minDistance: Self.markerSpacing)
        return groups.compactMap { ids in
            let members = ids.compactMap { positioned[$0] }
            guard let first = members.first else { return nil }
            return ChartMarkGroup(marks: members.map(\.mark), x: first.x)
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
                        .fill(.secondary)
                        .frame(width: 1, height: frame.height)
                        .position(x: x, y: frame.midY)
                }
                if let point, let pointX = proxy.position(forX: point.date).map({ frame.minX + $0 }),
                   (0...visible.width).contains(pointX), let pointY = proxy.position(forY: Double(point.value)) {
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
