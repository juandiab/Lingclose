/// Resultado de una importación de identidad, para un `alert`.
struct IdentityImportMessage: Sendable, Hashable {
    let title: String
    let text: String
}
