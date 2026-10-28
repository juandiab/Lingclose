import LingoCore
import SwiftUI

/// Hoja de insights de la ventana visible: lista de subidas y bajadas rápidas (hora, de→a, pendiente),
/// respuesta a cada comida y el interruptor del sombreado de episodios en la curva. Informativo, no médico.
struct TodayInsightsSheet: View {
    let viewModel: TodayViewModel

    @AppStorage(TodayViewModel.showRateEpisodesKey) private var showRateEpisodes = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let insights = viewModel.insights
        NavigationStack {
            List {
                Section {
                    if let events = insights?.rateEvents, !events.isEmpty {
                        ForEach(events) { event in
                            RateEventRow(event: event)
                        }
                    } else {
                        Text(String(localized: "today.insights.rates.none", defaultValue: "Ninguno en el período visible"))
                            .foregroundStyle(.secondary)
                    }
                    Toggle(String(localized: "today.insights.shade", defaultValue: "Sombrear en la curva"), isOn: $showRateEpisodes)
                } header: {
                    Text(String(localized: "today.insights.rates.header", defaultValue: "Cambios rápidos"))
                } footer: {
                    Text(String(localized: "today.insights.rates.footer", defaultValue: "Pendiente de 2 mg/dL por minuto o más durante al menos 10 minutos (regresión lineal sobre ventanas de 15 minutos)."))
                }

                if let meals = insights?.meals, !meals.isEmpty {
                    Section {
                        ForEach(meals, content: MealInsightRow.init)
                    } header: {
                        Text(String(localized: "today.insights.meals.header", defaultValue: "Respuesta a las comidas"))
                    } footer: {
                        Text(String(localized: "today.insights.meals.footer", defaultValue: "Subida respecto a la media de los 15 minutos previos; vuelta cuando la glucosa regresa a 10 mg/dL de esa media. La puntuación (0–100) baja con subidas mayores y vueltas más lentas."))
                    }
                }

                Section {
                    Label(String(localized: "today.insights.note", defaultValue: "Informativo, no médico. Cálculos locales sobre tus lecturas; no sustituyen el consejo de un profesional."), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "today.insights.sheet.title", defaultValue: "Insights"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
