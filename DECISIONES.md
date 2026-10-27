# Registro de decisiones

| # | Fecha | Decisión | Quién | Motivo / alternativa descartada |
|---|---|---|---|---|
| D-01 | 2026-10-27 | Base: app propia **LingoScan** (SwiftUI) sobre fork de RoundWhiteDiscKit | Juampa | Descartado xDrip4iOS como base (ver `../REPORTE_COMPATIBILIDAD_CLAUDE.md`). xdripswift 7.2.0 queda como referencia de comparación del protocolo |
| D-02 | 2026-10-27 | Credenciales Lingo: las de Juggluco 11.5.4 (`LingoCredentials.java`), uso personal, sin distribución | Juampa | Alternativa: plan B Android con Juggluco |
| D-03 | 2026-10-27 | Bundle ID `com.otalvaro.lingoscan`, team `SR8DQF26N7` | Juampa | Team con certificado Apple Distribution. No se cambia nunca |
| D-04 | 2026-10-27 | Almacenamiento: SQLite (API del sistema, sin librerías) + archivo abierto `.lingoscan` en carpeta de iCloud Drive elegida por el usuario + Apple Health | Fable, pendiente de confirmación de Juampa | Juampa preguntó por Mongo o NoSQL: Mongo no corre en iOS y Realm está descontinuado; SQLite viene en iOS. Subida a servidor propio = Nightscout (Mongo) en Fase 4, como cuarta copia |
| D-05 | 2026-10-27 | Alcance v1: núcleo + reportes en app | Juampa | Nightscout y Watch a Fase 4 |
| D-06 | 2026-10-27 | Modelo de trabajo: todo en Claude. Fable orquesta y verifica; Opus y Sonnet implementan. Juampa compara con Astra | Juampa | Descartado el flujo Astra/Terra/Sol para esta carpeta |
| D-07 | 2026-10-27 | iOS 26.0 mínimo, Swift 6.2, concurrencia estricta | Fable | El iPhone tiene iOS 27.0.1; Liquid Glass exige iOS 26; sin fallback |
| D-08 | 2026-10-27 | Receiver ID: u32 aleatorio generado una vez, en Keychain con sincronización iCloud y anotado fuera del teléfono; `1001` de Juggluco solo como alternativa si el sensor responde `B1` | Fable | Sin servicio de descarga para Lingo |
| D-09 | 2026-10-27 | Identidad y clave de firma por `productType`; `sensorCertSigningKeys` nunca vacío | Fable (aporte de Astra) | RWDK omite la verificación con lista vacía |
| D-10 | 2026-10-27 | El parser elige el canal de glucosa por el mapa de tipos (byte 34), guarda capped y uncapped por separado; Health recibe el uncapped elegible | Fable (aporte de Astra) | No asumir canal 1 ni descartar > 200 mg/dL |
| D-11 | 2026-10-27 | Archivo portable como carpeta de documento, no ZIP | Fable | Evita dependencia ZIP; legible por Finder y scripts |
| D-12 | 2026-10-27 | Umbrales iniciales de alarma 70 / 180 mg/dL y 20 min sin datos, marcados no médicos | Fable, pendiente de Juampa | Se confirman en la Fase 2 |
| D-13 | 2026-10-27 | Idioma de la UI: español, con `Localizable.xcstrings` preparado para inglés | Fable | Juampa es hispanohablante; coste cero de preparar la segunda lengua |
| D-14 | 2026-10-27 | git local en `LingoScan_Claude/` para verificar cada tarea por commit | Fable | Reversible; sin remoto hasta que Juampa lo pida |

Pendientes de Juampa: confirmar D-04, D-12; indicar la carpeta de iCloud Drive para los archivos; identificar la segunda caja de sensores.
