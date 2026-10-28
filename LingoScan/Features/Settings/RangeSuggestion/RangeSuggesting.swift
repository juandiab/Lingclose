/// Quien construye la sugerencia. La app usa `RangeSuggestionService`; la previsualización, `PreviewRangeSuggester`.
protocol RangeSuggesting: Sendable {
    func suggest() async throws -> RangeSuggestion
}
