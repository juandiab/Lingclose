import Charts
import SwiftUI

/// Curva de glucosa con Swift Charts: un `LineMark` por tramo (los huecos quedan abiertos, sin interpolar),
/// líneas de referencia finas, área sobre la línea alta (rojo) y bajo la baja (azul) con un lavado que se
/// desvanece hacia la referencia, huecos sombreados y, en vivo, la última lectura con un halo.
/// La línea cambia de color por valor: rojo por encima de la referencia alta, neutro en el rango y azul por
/// debajo de la baja (`GlucoseColorRun`: trozos por color con cruces interpolados; sin degradado, que en una
/// gráfica desplazable se aplica sobre un rectángulo distinto según el dispositivo).
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    yStart: .value("Mínimo", Double(domain.lowerBound)),
                    yEnd: .value("Máximo", Double(domain.upperBound))
                )
                .foregroundStyle(Tokens.Palette.gap.opacity(0.12))
            }

            // Umbrales finos en gris (`Color.secondary` explícito: el estilo jerárquico dentro de Charts hereda el tinte).
            RuleMark(y: .value("Referencia alta", Double(high)))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(Self.referenceStroke)
            RuleMark(y: .value("Referencia baja", Double(low)))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(Self.referenceStroke)

            ForEach(viewModel.drawSegments) { segment in
                // Área sobre la línea alta: cada punto se recorta a `max(valor, referencia alta)`.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Referencia alta", Double(high)),
                        yEnd: .value("Exceso", Double(max(point.value, high))),
                        series: .value("Pico", "alta-\(segment.id)")
                    )
                    .foregroundStyle(Self.highWash)
                }
                // Área bajo la línea baja: simétrica a la de los picos, en frío.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Defecto", Double(min(point.value, low))),
                        yEnd: .value("Referencia baja", Double(low)),
                        series: .value("Bajo", "baja-\(segment.id)")
                    )
                    .foregroundStyle(Self.lowWash)
                }
                // Un `LineMark` por trozo de color; los cruces con las referencias se interpolan.
                ForEach(GlucoseColorRun.runs(for: segment, low: low, high: high)) { run in
                    ForEach(run.vertices) { vertex in
                        LineMark(
                            x: .value("Hora", vertex.date),
                            y: .value("mg/dL", vertex.value),
                            series: .value("Tramo", "linea-\(run.id)")
                        )
                        .foregroundStyle(run.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                if segment.points.count == 1, let only = segment.points.first {
                    PointMark(x: .value("Hora", only.date), y: .value("mg/dL", Double(only.value)))
                        .foregroundStyle(Self.color(for: only.value, low: low, high: high))
                        .symbolSize(24)
                }
            }

            // En vivo: el final de la curva con un halo del color de su rango. Se usa el último punto dibujado
            // (con la reducción por cubos puede diferir un poco de la lectura cruda) para que caiga sobre la línea.
            if viewModel.isLive, let last = viewModel.drawSegments.last?.points.last {
                let color = Self.endColor(for: last.value, low: low, high: high)
                PointMark(x: .value("Hora", last.date), y: .value("mg/dL", Double(last.value)))
                    .foregroundStyle(color.opacity(0.22))
                    .symbolSize(220)
                PointMark(x: .value("Hora", last.date), y: .value("mg/dL", Double(last.value)))
                    .foregroundStyle(.background)
                    .symbolSize(90)
                PointMark(x: .value("Hora", last.date), y: .value("mg/dL", Double(last.value)))
                    .foregroundStyle(color)
                    .symbolSize(50)
            }
        }
        // Margen final para que el halo de la última lectura no se corte en el borde.
        .chartXScale(domain: viewModel.loadedStart...viewModel.loadedEnd, range: .plotDimension(endPadding: 16))
        .chartYScale(domain: Double(domain.lowerBound)...Double(domain.upperBound))
        // El eje vertical sigue a la ventana asentada; el cambio se anima salvo con Reduce Motion.
        .animation(reduceMotion ? nil : .snappy, value: domain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: viewModel.visibleLength)
        .chartScrollPosition(x: $viewModel.scrollPosition)
        // Tras una carga que mueve el inicio del dominio, se recrea en la fecha de `scrollPosition`.
        .id(viewModel.chartIdentity)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: Self.axisDates(from: viewModel.loadedStart, to: viewModel.loadedEnd, stride: stride, calendar: viewModel.calendar)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel(format: stride.component == .minute ? .dateTime.hour().minute() : .dateTime.hour())
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
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
        .containerRelativeFrame(.vertical) { height, _ in height * GlucoseChartCard.heightFraction }
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

    /// Referencias: discontinuas (son umbrales, no rejilla) y finas.
    static let referenceStroke = StrokeStyle(lineWidth: 0.75, dash: [3, 3])

    /// Áreas fuera del rango: lavado que se desvanece hacia la referencia (rojo de arriba abajo, azul al revés).
    static let highWash = LinearGradient(
        colors: [Tokens.Palette.high.opacity(0.34), Tokens.Palette.high.opacity(0.04)],
        startPoint: .top, endPoint: .bottom
    )
    static let lowWash = LinearGradient(
        colors: [Tokens.Palette.low.opacity(0.34), Tokens.Palette.low.opacity(0.04)],
        startPoint: .bottom, endPoint: .top
    )

    /// Punto final en vivo: verde de "en rango" dentro de las referencias; rojo o azul fuera.
    static func endColor(for value: Int, low: Int, high: Int) -> Color {
        if value > high { return Tokens.Palette.high }
        if value < low { return Tokens.Palette.low }
        return Tokens.Palette.inRange
    }

    /// Color de un valor aislado: azul bajo la referencia baja, rojo sobre la alta, neutro en el rango.
    static func color(for value: Int, low: Int, high: Int) -> Color {
        if value > high { return Tokens.Palette.high }
        if value < low { return Tokens.Palette.low }
        return .primary
    }
}
