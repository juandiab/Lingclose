import Foundation
import LingoCore

/// Construye la sugerencia: lecturas propias de los últimos 14 días (SQLite) → `GlucoseDistribution` →
/// propuesta estadística; perfil de Salud (solo lectura, opcional); y, si hay asistente configurado (proveedor,
/// clave y modelo), una sola llamada con los agregados. Sin reintentos. Un fallo de Salud o del asistente no
/// tumba la sugerencia: se anota y se muestra la propuesta estadística.
struct RangeSuggestionService: RangeSuggesting {
    let readings: any RangeReadingsSource
    let health: any HealthProfileReading
    let keys: LLMKeyStore
    let settings: LLMSettingsStore
    let makeProvider: @Sendable (LLMProviderID) -> any LLMProvider
    var locale: String = Locale.current.identifier
    var clock: @Sendable () -> Date = { .now }

    func suggest() async throws -> RangeSuggestion {
        let now = clock()
        let window = RangeSuggestionPolicy.window(endingAt: now)
        let stored: [GlucoseReading]
        do {
            stored = try await readings.readings(in: window)
        } catch {
            throw RangeSuggestionError.store(String(describing: type(of: error)))
        }
        let distribution = GlucoseDistribution(readings: stored)
        guard distribution.count > 0, let p5 = distribution.percentile(RangeSuggestionPolicy.lowPercentile),
              let p95 = distribution.percentile(RangeSuggestionPolicy.highPercentile),
              let mean = distribution.mean, let median = distribution.median else {
            throw RangeSuggestionError.noReadings
        }
        guard distribution.coveredHours >= RangeSuggestionPolicy.minimumCoverageHours else {
            throw RangeSuggestionError.insufficientCoverage(
                hours: distribution.coveredHours, required: RangeSuggestionPolicy.minimumCoverageHours)
        }
        let proposal = RangeSuggestionPolicy.statisticalProposal(percentile5: p5, percentile95: p95)
        let summary = RangeSuggestion.ReadingSummary(
            count: distribution.count, windowDays: RangeSuggestionPolicy.windowDays, coverageHours: distribution.coveredHours,
            first: distribution.first?.date, last: distribution.last?.date, percentile5: p5, percentile95: p95,
            median: median, mean: mean, standardDeviation: distribution.standardDeviation ?? 0)

        var profile = HealthProfile.empty
        var healthNote: String?
        do {
            profile = try await health.readProfile()
        } catch HealthProfileError.unavailable {
            healthNote = String(localized: "range.suggest.health.unavailable",
                                defaultValue: "Apple Salud no está disponible en este dispositivo: la sugerencia no usa el perfil.")
        } catch {
            healthNote = String(localized: "range.suggest.health.failed",
                                defaultValue: "No se pudo leer el perfil de Salud: la sugerencia no usa edad, sexo, peso ni altura.")
        }

        var suggestion = RangeSuggestion(
            low: proposal.low, high: proposal.high,
            explanation: Self.statisticalExplanation(summary: summary),
            origin: .statistics, readings: summary, statisticalLow: proposal.low, statisticalHigh: proposal.high,
            profile: profile, healthNote: healthNote)

        guard let configured = await configuredAssistant() else { return suggestion }
        let request = RangeSuggestionRequest(
            windowDays: summary.windowDays, readingCount: summary.count, coverageHours: summary.coverageHours,
            percentile5: p5, percentile95: p95, median: median, mean: mean,
            standardDeviation: summary.standardDeviation, statisticalLow: proposal.low, statisticalHigh: proposal.high,
            ageYears: profile.ageYears, biologicalSex: profile.biologicalSex?.rawValue,
            bodyMassIndex: profile.bodyMassIndex.map { ($0 * 10).rounded() / 10 }, locale: locale)
        do {
            let reply = try await makeProvider(configured.provider).suggestRange(request, model: configured.model, apiKey: configured.key)
            suggestion.low = reply.low
            suggestion.high = reply.high
            suggestion.explanation = reply.explanation
            suggestion.origin = .assistant(provider: configured.provider, modelName: configured.model.displayName)
        } catch {
            let detail = (error as? LLMError)?.description ?? error.localizedDescription
            suggestion.assistantNote = String(localized: "range.suggest.assistant.failed",
                                              defaultValue: "El asistente no respondió (\(detail)). Se muestra solo la propuesta estadística; no se reintentó para no cobrar dos veces.")
        }
        return suggestion
    }

    private struct ConfiguredAssistant {
        var provider: LLMProviderID
        var model: LLMModel
        var key: String
    }

    /// Proveedor elegido con clave guardada y modelo elegido; si falta algo, no hay asistente.
    private func configuredAssistant() async -> ConfiguredAssistant? {
        guard let provider = settings.selectedProvider(), let model = settings.selectedModel(for: provider),
              let key = try? await keys.key(for: provider) else { return nil }
        return ConfiguredAssistant(provider: provider, model: model, key: key)
    }

    static func statisticalExplanation(summary: RangeSuggestion.ReadingSummary) -> String {
        let days = summary.coverageHours / 24
        return String(localized: "range.suggest.explanation.statistics",
                      defaultValue: "La línea baja es el percentil 5 y la alta el percentil 95 de tus \(summary.count) lecturas válidas de los últimos \(summary.windowDays) días (\(days.formatted(.number.precision(.fractionLength(1)))) días con datos), redondeados a múltiplos de 5. El 90 por ciento de tus lecturas quedó entre ambas. Son líneas para leer la curva, no objetivos clínicos.")
    }
}
