import OSLog

/// `LLMLogSink` de la app sobre el registro unificado.
struct OSLogLLMSink: LLMLogSink {
    private let logger = Logger(subsystem: "com.otalvaro.lingoscan", category: "llm")

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
