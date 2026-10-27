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

| D-15 | 2026-10-27 | El formato portable y el de recuperación los define el contrato compartido `../LingoScan_Shared/` (`CONTRATO_V1.md`, `RECUPERACION_V1.md`), propuesto por Claude y pendiente de revisión de Astra. LingoScan lo implementa en T-10 y T-19 con `contract_version 1.0.0-draft.N` hasta que sea estable | Juampa (encargo), Claude (propuesta) | Poder combinar historial de las dos apps y transferir un sensor activo |
| D-16 | 2026-10-27 | Una sola app escribe muestras nuevas en Health a la vez (la recolectora BLE); transferencia explícita del rol con pausa, exportación, importación y verificación; sin reexportar historial importado | Juampa | `SyncIdentifier` no deduplica entre apps |
| D-17 | 2026-10-27 | `producer_tag` de LingoScan: `lingoscan`. Astra usa `com.otalvaro.lingoscan.astra` / `astra` | Juampa y Astra | Coexistencia de dos apps con el mismo Team |
| D-18 | 2026-10-27 | Fable (orquestador) puede escribir código delicado y de alto valor y revisa toda entrega de Opus y Sonnet | Juampa | Calidad en criptografía, protocolo y contrato |

Pendientes de Juampa: confirmar D-04, D-12; indicar la carpeta de iCloud Drive para los archivos (Q-06 del contrato); identificar la segunda caja de sensores; decidir `include_material` (Q-05).
| D-19 | 2026-10-27 | Asistente de comidas con LLM (T-21): clave por proveedor en Keychain, nunca exportada; foto, nombre del plato o tabla nutricional → propuesta editable que el usuario confirma; modelos económicos por defecto (Anthropic `claude-haiku-5-5`), editables; DeepSeek solo texto. Ejercicio sin LLM: entrenamientos importados de Salud (Apple Watch, app nativa) | Juampa (petición), Fable (diseño) | Coste por foto ≈ 0,0004 $ con Haiku 5.5; privacidad avisada en pantalla; estimaciones no médicas |
