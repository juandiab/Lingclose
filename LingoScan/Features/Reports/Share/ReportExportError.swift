/// Fallos al preparar lo que se comparte desde Reportes.
enum ReportExportError: Error {
    case imageRenderingFailed
    case pngEncodingFailed
}
