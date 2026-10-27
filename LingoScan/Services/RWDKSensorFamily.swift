import RoundWhiteDiscKit

/// `SensorFamily` del fork. LingoCore define otro `SensorFamily` y ambos módulos
/// tienen un tipo con su propio nombre (`enum RoundWhiteDiscKit`, `enum LingoCore`),
/// así que `Módulo.SensorFamily` no resuelve. Los archivos que importan los dos
/// módulos usan este alias.
typealias RWDKSensorFamily = SensorFamily
