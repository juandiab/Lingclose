/// Por qué un sensor leído por NFC no se activa ni se empareja.
enum IncompatibilityReason: Sendable, Equatable {
    /// `productType != 9` o `securityVersion != 3` (incluye Libre 3 y variantes desconocidas).
    case unsupportedVariant(productType: UInt8, securityVersion: UInt16)
    /// El parche informa estado terminado (6 u 8).
    case sensorEnded(stateByte: UInt8)
}
