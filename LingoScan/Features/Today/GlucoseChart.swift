import Charts
import SwiftUI

/// Curva de glucosa con Swift Charts: un `LineMark` por tramo (los huecos quedan abiertos, sin interpolar),
/// líneas de referencia, área sombreada sobre la línea alta (rojo) y bajo la baja (azul), y huecos sombreados.
/// La línea lleva un degradado por valor: rojo por encima de la referencia alta, neutro en el rango y azul
/// por debajo de la baja. En la gráfica desplazable el degradado se aplica sobre el rectángulo de cada tramo
/// (no sobre el área del trazado), así que las paradas se calculan con el mínimo y el máximo del tramo.
///
/// Gestos: deslizar desplaza el tiempo (física nativa de `chartScrollableAxes`), pellizcar cambia la longitud
/// visible manteniendo fijo el instante bajo el pellizco, tocar coloca el cursor en la lectura más cercana y
/// mantener pulsado (0,35 s) y arrastrar lo desliza. Se dibujan los tramos reducidos de `drawSegments`.
/// Marcas, índices de pico y cursor se dibujan en `ChartInteractionOverlay`.
struct GlucoseChart: View {
    @Bindable var viewModel: TodayViewModel
    let selection: ChartSelection

    @AppStorage(TodayViewModel.visibleSecondsKey) private var storedSeconds = 0.0
    @State private var pinch: PinchStart?
    @State private var pinchHaptic = 0
    @State private var cursorHaptic = 0
    @State private var isSliding = false
    @State private var chartWidth: CGFloat = 0

    /// Estado al empezar el pellizco: longitud y el instante bajo los dedos.
    private struct PinchStart {
        let length: TimeInterval
        let anchorDate: Date
        let anchorFraction: Double
    }

    var body: some View {
        let domain = viewModel.chartValueDomain
        let high = viewModel.referenceHigh
        let low = viewModel.referenceLow
        let stride = Self.axisStride(for: viewModel.visibleLength)
        Chart {
            ForEach(viewModel.gaps) { gap in
                RectangleMark(
                    xStart: .value("Inicio del hueco", gap.start),
                    xEnd: .value("Fin del hueco", gap.end),
                    yStart: .value("Mínimo", domain.lowerBound),
                    yEnd: .value("Máximo", domain.upperBound)
                )
                .foregroundStyle(Tokens.Palette.gap.opacity(0.22))
            }

            RuleMark(y: .value("Referencia alta", high))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("Referencia baja", low))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ForEach(viewModel.drawSegments) { segment in
                let lineGradient = Self.segmentGradient(segment, low: low, high: high)
                // Área sobre la línea alta: cada punto se recorta a `max(valor, referencia alta)`.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Referencia alta", high),
                        yEnd: .value("Exceso", max(point.value, high)),
                        series: .value("Pico", "alta-\(segment.id)")
                    )
                    .foregroundStyle(Tokens.Palette.high.opacity(0.18))
                }
                // Área bajo la línea baja: simétrica a la de los picos, en frío.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Defecto", min(point.value, low)),
                        yEnd: .value("Referencia baja", low),
                        series: .value("Bajo", "baja-\(segment.id)")
                    )
                    .foregroundStyle(Tokens.Palette.low.opacity(0.18))
                }
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Hora", point.date),
                        y: .value("mg/dL", point.value),
                        series: .value("Tramo", "linea-\(segment.id)")
                    )
                    .foregroundStyle(lineGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if segment.points.count == 1, let only = segment.points.first {
                    PointMark(x: .value("Hora", only.date), y: .value("mg/dL", only.value))
                        .foregroundStyle(Self.color(for: only.value, low: low, high: high))
                        .symbolSize(24)
                }
            }
        }
        .chartXScale(domain: viewModel.loadedStart...viewModel.loadedEnd)
        .chartYScale(domain: domain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: viewModel.visibleLength)
        .chartScrollPosition(x: $viewModel.scrollPosition)
        // Tras una carga que mueve el inicio del dominio, se recrea en la fecha de `scrollPosition`.
        .id(viewModel.chartIdentity)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: Self.axisDates(from: viewModel.loadedStart, to: viewModel.loadedEnd, stride: stride, calendar: viewModel.calendar)) {
                AxisGridLine()
                AxisValueLabel(format: stride.component == .minute ? .dateTime.hour().minute() : .dateTime.hour())
            }
        }
        .chartXSelection(value: selectionBinding)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        .simultaneousGesture(tapGesture)
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, viewModel: viewModel, selection: selection)
        }
        .simultaneousGesture(pinchGesture)
        .sensoryFeedback(.selection, trigger: pinchHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: cursorHaptic)
        .accessibilityChartDescriptor(
            GlucoseChartDescriptor(
                points: viewModel.visiblePoints,
                start: viewModel.windowStart,
                end: viewModel.windowEnd,
                valueDomain: domain,
                periodTitle: Self.lengthTitle(viewModel.visibleLength),
                referenceLow: viewModel.referenceLow,
                referenceHigh: viewModel.referenceHigh
            )
        )
        .accessibilityAction(named: String(localized: "today.chart.zoomIn", defaultValue: "Acercar")) {
            zoom(by: 0.5)
        }
        .accessibilityAction(named: String(localized: "today.chart.zoomOut", defaultValue: "Alejar")) {
            zoom(by: 2)
        }
        .containerRelativeFrame(.vertical) { height, _ in height * 0.36 }
    }

    // MARK: Desplazamiento y zoom

    /// Selección nativa (pulsación larga y arrastre en una gráfica desplazable) hacia `ChartSelection`.
    /// Se usa un `Binding` manual a propósito: un `@State` intermedio con `onChange` haría que este `body`
    /// (cientos de marcas) se recalculara en cada paso del arrastre; así solo cambian el cursor y la lectura.
    private var selectionBinding: Binding<Date?> {
        Binding(
            get: { selection.date },
            set: { newValue in
                // La selección nativa de una gráfica desplazable se activa con pulsación larga y escribe `nil`
                // al soltar: el cursor se queda donde se soltó (un toque lo quita).
                guard let newValue else {
                    isSliding = false
                    return
                }
                if !isSliding {
                    isSliding = true
                    cursorHaptic += 1
                }
                selection.date = min(max(newValue, viewModel.loadedStart), viewModel.loadedEnd)
            }
        )
    }

    /// Toque: coloca el cursor en el instante tocado (la lectura más cercana la resuelve el cursor) o lo quita.
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard selection.date == nil else {
                    selection.date = nil
                    return
                }
                guard chartWidth > 0 else { return }
                let fraction = min(max(value.location.x / chartWidth, 0), 1)
                selection.date = viewModel.visibleStart.addingTimeInterval(fraction * viewModel.visibleLength)
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinch ?? PinchStart(
                    length: viewModel.visibleLength,
                    anchorDate: viewModel.visibleStart.addingTimeInterval(value.startAnchor.x * viewModel.visibleLength),
                    anchorFraction: value.startAnchor.x
                )
                if pinch == nil { pinch = start }
                let old = viewModel.visibleLength
                viewModel.pinch(
                    startLength: start.length,
                    magnification: value.magnification,
                    anchorDate: start.anchorDate,
                    anchorFraction: start.anchorFraction
                )
                if TodayViewModel.crossesPeriod(from: old, to: viewModel.visibleLength) { pinchHaptic += 1 }
            }
            .onEnded { _ in
                pinch = nil
                storedSeconds = viewModel.visibleLength
            }
    }

    private func zoom(by factor: Double) {
        viewModel.zoom(by: factor)
        storedSeconds = viewModel.visibleLength
    }

    // MARK: Ayudas

    /// Marcas del eje según la longitud visible: cada 30 min hasta 2 h; luego 1, 2, 3 o 4 h.
    static func axisStride(for length: TimeInterval) -> (component: Calendar.Component, count: Int) {
        switch length {
        case ...7_200: (.minute, 30)
        case ...14_400: (.hour, 1)
        case ...28_800: (.hour, 2)
        case ...50_400: (.hour, 3)
        default: (.hour, 4)
        }
    }

    /// Marcas del eje alineadas al reloj (en punto o a la media hora), no al inicio del dominio.
    static func axisDates(
        from start: Date, to end: Date,
        stride: (component: Calendar.Component, count: Int), calendar: Calendar
    ) -> [Date] {
        let step = TimeInterval(stride.count) * (stride.component == .minute ? 60 : 3_600)
        let day = calendar.startOfDay(for: start)
        let first = day.addingTimeInterval((start.timeIntervalSince(day) / step).rounded(.up) * step)
        return Array(Swift.stride(from: first, through: end, by: step))
    }

    /// "4 h 30 min" para la longitud visible.
    static func lengthTitle(_ length: TimeInterval) -> String {
        Duration.seconds(Int((length / 60).rounded()) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// Color de un valor aislado: azul bajo la referencia baja, rojo sobre la alta, neutro en el rango.
    static func color(for value: Int, low: Int, high: Int) -> Color {
        if value > high { return Tokens.Palette.high }
        if value < low { return Tokens.Palette.low }
        return .primary
    }

    /// Degradado de un tramo: las paradas van sobre su propio rango de valores (su rectángulo).
    static func segmentGradient(_ segment: GlucoseSegment, low: Int, high: Int) -> LinearGradient {
        LinearGradient(stops: segmentStops(segment, low: low, high: high), startPoint: .bottom, endPoint: .top)
    }

    /// Paradas de un tramo. Las recortadas al borde (una referencia que el tramo no alcanza) se quitan para
    /// que el borde no tome su color; un tramo plano o de un punto lleva un color único.
    static func segmentStops(_ segment: GlucoseSegment, low: Int, high: Int) -> [Gradient.Stop] {
        let values = segment.points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max(), minimum < maximum else {
            let color = color(for: values.first ?? low, low: low, high: high)
            return [.init(color: color, location: 0), .init(color: color, location: 1)]
        }
        var stops = gradientStops(domain: minimum...maximum, low: low, high: high)
        while stops.count > 1, stops[0].location == stops[1].location { stops.removeFirst() }
        while stops.count > 1, stops[stops.count - 1].location == stops[stops.count - 2].location { stops.removeLast() }
        return stops
    }

    /// Paradas (fracción 0 = mínimo del dominio, 1 = máximo). Se recortan al dominio y quedan ordenadas.
    static func gradientStops(domain: ClosedRange<Int>, low: Int, high: Int, band: Double = 3) -> [Gradient.Stop] {
        let span = Double(max(1, domain.upperBound - domain.lowerBound))
        func fraction(_ value: Double) -> Double { min(1, max(0, (value - Double(domain.lowerBound)) / span)) }
        let neutral = Color.primary
        return [
            .init(color: Tokens.Palette.low, location: 0),
            .init(color: Tokens.Palette.low, location: fraction(Double(low) - band)),
            .init(color: neutral, location: fraction(Double(low) + band)),
            .init(color: neutral, location: fraction(Double(high) - band)),
            .init(color: Tokens.Palette.high, location: fraction(Double(high) + band)),
            .init(color: Tokens.Palette.high, location: 1),
        ]
    }
}
