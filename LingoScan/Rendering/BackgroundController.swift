import LingoCore
import SwiftUI

/// Envía al engine del fondo el estado de la app: tono de glucosa, estilo, Reduce Motion y fase de escena.
/// Va una sola vez, en `RootTabView` (`.background { BackgroundController(today: todayViewModel) }`).
///
/// El tono sale de la última lectura elegible de `TodayViewModel` y del rango de referencia del usuario;
/// se reevalúa cada minuto para que un dato atrasado pase a neutro aunque no llegue nada nuevo.
struct BackgroundController: View {
    let today: TodayViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue
    @AppStorage(ReferenceLines.lowKey) private var referenceLow = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var referenceHigh = ReferenceLines.defaultHigh

    var body: some View {
        TimelineView(.everyMinute) { context in
            let range = ReferenceLines.normalized(low: referenceLow, high: referenceHigh)
            let tone = GlucoseBackgroundTone.resolve(
                value: today.latest?.value,
                measuredAt: today.latest?.measuredAt.date,
                now: context.date,
                low: range.low,
                high: range.high
            )
            Color.clear
                .onChange(of: tone, initial: true) { _, newTone in
                    BackgroundStage.shared.engine?.setPalette(BackgroundPalette(tone: newTone))
                }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: reduceMotion, initial: true) { _, on in
            BackgroundStage.shared.engine?.setReduceMotion(on)
        }
        .onChange(of: styleRaw, initial: true) { _, raw in
            BackgroundStage.shared.engine?.setStyle(BackgroundStyle(stored: raw))
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            BackgroundStage.shared.engine?.setActive(phase == .active)
        }
    }
}
