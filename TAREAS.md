# Backlog de tareas

Formato: cada tarea tiene un modelo asignado, archivos con dueño, dependencias, criterios de aceptación y cómo la verifica Fable. Estado: `pendiente` → `en curso` → `en verificación` → `cerrada (commit)`. Una tarea no se cierra sin la salida real de build y tests.

## Ajuste autorizado por Juampa — interoperabilidad (Astra, 2026-10-27)

El contrato compartido está recibiendo correcciones posteriores a draft.3. T-01..T-08 pueden avanzar sobre sus interfaces; T-10, T-15 y la fusión de T-19 deben fijar la revisión corregida antes de cerrarse. No copiar el importador de referencia draft.3 como implementación final. Consultar `../LingoScan_Shared/RESPUESTA_ASTRA_DRAFT3.md` y el siguiente registro de cambios del contrato.

Criterios adicionales concretos:

- T-07/T-09/T-10: rechazar una lectura marcada real si pertenece a una sesión sintética, incluso cuando el manifest no sea sintético. La exportación a Health valida la procedencia persistida.
- T-10: transportar los ancestros necesarios de ediciones, preservar observaciones crudas complementarias con su origen y comprobar dos sesiones con el mismo minuto. Un cambio de `origin` no debe atribuir a live los bytes de otra ruta.
- T-19: un snapshot más reciente del mismo intento no autoriza reemplazar secretos contradictorios. Distinguir campos inmutables de valores que evolucionan; conservar el conflicto y no conectar automáticamente. Importar y validar no ejecuta NFC ni BLE.
- T-15: comprobar datos crudos, procedencia, sesiones, ledger y conflictos, además de conteos. Documentar diferencias intencionales entre la vista local de cada app; no llamarlas convergencia completa.

Para ahorrar contexto: entregar diff, revisión probada y rutas de logs; no pegar logs completos en cada nivel. El revisor repite las pruebas cuando un cambio, fallo o duda lo justifique, no automáticamente por cada agente. Esto no elimina criterios de aceptación.

| ID | Fase | Modelo | Título | Depende de | Estado |
|---|---|---|---|---|---|
| T-01 | 1 | Opus | Fork de RoundWhiteDiscKit: clon fijado y línea base | — | cerrada |
| T-02 | 1 | Opus | Fork: familia Lingo, identidad por `productType`, clave de firma, errores explícitos | T-01 | cerrada |
| T-03 | 1 | Opus | Fork: plano de datos Lingo (51 B, 14 B, historial, fast data) | T-02 | cerrada |
| T-04 | 1 | Sonnet | Vectores AES-CCM independientes y tests negativos | T-01 | cerrada |
| T-05 | 1 | Sonnet | Cargador de credenciales JSON → Keychain | T-02, T-06 | cerrada |
| T-06 | 1 | Sonnet | Proyecto Xcode LingoScan + paquete LingoCore | — | cerrada |
| T-07 | 1 | Opus | LingoCore: dominio, elegibilidad y almacén SQLite | T-06 | cerrada |
| T-08 | 1 | Opus | SensorSessionCoordinator y NFCService | T-03, T-05, T-07 | cerrada |
| T-11 | 1 | Sonnet | Shell de la app, Hoy y Sensor con Liquid Glass | T-06, T-07 | cerrada |
| T-14 | 1 | Fable | Firma, instalación en iPhone, permisos, diagnóstico NFC solo lectura | T-08, T-11 | cerrada |
| T-09 | 2a | Sonnet | HealthExporter con outbox y elegibilidad | T-07 | cerrada |
| T-10 | 2a | Sonnet | ArchiveService: paquete `.lingoscan` según `../LingoScan_Shared/CONTRATO_V1.md`, carpeta del usuario, cadencia | T-07 | cerrada |
| T-19 | 2a | Fable + Opus | Archivo de recuperación cifrado y transferencia de rol según `../LingoScan_Shared/RECUPERACION_V1.md` | T-05, T-07, T-08 | cerrada |
| T-12a | 2a | Sonnet | Diario, Datos, Ajustes y gráfica básica (sin reportes avanzados) | T-09, T-10, T-11 | cerrada |
| T-13 | 2a | Sonnet | Alarmas alta, baja y sin datos | T-07 | cerrada |
| T-15 | 2a | Fable + Sonnet | Pruebas cruzadas con Astra (P-01..P-11, R-01..R-05) con paquetes de ambas apps y el verificador externo; app de prueba solo si hace falta | T-10, T-19 | pendiente |
| T-16 | 3 | Fable + Juampa | Protocolo del sensor de sacrificio | Fase 2a cerrada (T-09, T-10, T-12a, T-13, T-15, **T-19**) | pendiente |
| T-11b | 2a | Sonnet | Hoy según la referencia de la caja Lingo: navegación por día, 6/12/24 h, picos sombreados con índice, marcadores de comida, arrastre con lectura, "+" para registrar | T-12a | cerrada |
| T-21 | 2b | Sonnet + Fable | Asistente de comidas con LLM (foto, nombre, tabla nutricional; clave por proveedor en Keychain; modelos económicos) y entrenamientos importados de Salud/Apple Watch | T-11b | pendiente |
| T-12b | 2b | Sonnet | Reportes avanzados: respuesta a comidas, noche, comparación semanal, pulido visual | T-16 con lecturas reales | pendiente |
| T-17 | 4 | Sonnet | Nightscout uploader (opcional) | T-16 | pendiente |
| T-18 | 4 | Sonnet | Apple Watch | T-16 | pendiente |

---

## T-01 — Fork de RoundWhiteDiscKit: clon fijado y línea base

**Modelo:** Opus. **Skill:** `swiftpm-macos`.
**Archivos:** `Packages/RoundWhiteDiscKit/**` (nuevo), `docs/FORK_RWDK.md` (añadir sección "Línea base").
**Objetivo:** tener el paquete compilando y con sus tests verdes en el Mac, con commit base registrado, antes de tocarlo.
**Pasos:** `git clone https://github.com/airedev326/RoundWhiteDiscKit` en `Packages/`, `git checkout 7dd6396`, eliminar `.git` del clon (el historial del fork vive en este repo) y anotar el commit en `Package.swift` (comentario) y en `docs/FORK_RWDK.md`. `swift build`, `swift test`. Clonar xdripswift 7.2.0 en el scratchpad y hacer `diff -r` entre `Sources/RoundWhiteDiscKit/` y `xDrip/BluetoothTransmitter/CGM/Libre/Libre3/Protocol/`; resumir divergencias en `docs/FORK_RWDK.md`.
**Aceptación:** `swift test` verde con la salida pegada; sección "Línea base" con commit, versión de Swift tools, lista de tests existentes y resumen del diff con xdripswift.
**Verificación Fable:** repetir `swift test`; comprobar que no hay `.git` anidado; commit `T-01`.

## T-02 — Fork: familia Lingo, identidad por `productType`, clave de firma, errores explícitos

**Modelo:** Opus. **Skill:** `swiftpm-macos`; revisión de Swift con `swiftui-pro` (`references/swift.md`, `hygiene.md`).
**Archivos:** `Pairing/NFCActivationModels.swift`, `Pairing/AppIdentity.swift`, `Pairing/SensorCert.swift`, `Pairing/PairingFlow.swift`, `Pairing/Libre3SensorStateLoader.swift`, `Pairing/CoreNFCActivationReader.swift` (solo textos), `Resources/Localizations/**`, `Tests/**`.
**Objetivo:** cambios 1, 2, 3, 4, 14 y 15 de `docs/FORK_RWDK.md` §3.
**Detalle:**
- `enum SensorFamily: Sendable { case libre3, lingo, unknown }` y `var family` en `Libre3NFCPatchInfo` (`lingo` si `productType == 9 && securityVersion == 3`; `libre3` si `productType == 4`; si no `unknown`).
- `AppIdentity` gana `productTypes: [UInt8]?` y `patchSigningPublicKey: Data?`; el JSON acepta `productTypes`, `securityVersions`, `patchSigningPublicKeyHex`. `AppIdentities.identity(for: SensorFamily)` y `PatchSigningKeys.keys(for:)`.
- `PairingFlow.init` lanza `PairingFlowError.noTrustedSigningKeys` si `sensorCertSigningKeys` está vacío (nuevo comportamiento; mantener un init interno para tests que lo necesiten).
- `PairingFlowError.authenticationInterrupted(phase:evidence:)` cuando tras `0x03` el transporte reporta fin de flujo o timeout antes de `0x04`: la fase (`certificateLoad`, `certificateAcceptance`, `sensorCertificate`, `ephemeral`, `challenge`) y la evidencia (último comando enviado, último byte recibido, tiempo transcurrido). `PairingFlowError.certificateRejected` **solo** cuando el sensor responde con un código o notificación que lo demuestre; una desconexión nunca se clasifica como rechazo de credenciales (ajuste 1 de Astra).
- `Libre3SensorState` gana `productType`, `securityVersion`, `identityLabel` opcionales con decodificación tolerante.
- Textos "Libre 3" de NFC → "sensor".
**Aceptación:** tests nuevos: patchInfo sintético con `productType 9`/`sec 3` → `.lingo`; `productType 9`/`sec 2` → `.unknown`; JSON con `productTypes` se parsea y se selecciona por familia; lista vacía → error; `ScriptedCommandPairingTransport` que corta tras `0x03` → `authenticationInterrupted(phase: .certificateAcceptance, …)` con evidencia; respuesta negativa explícita guionada → `certificateRejected`; `Libre3SensorStateLoader` carga JSON antiguo sin los campos nuevos. `swift test` verde.
**Verificación Fable:** diff limitado a los archivos listados; tests; commit `T-02`.

## T-03 — Fork: plano de datos Lingo

**Modelo:** Opus. **Skill:** `swiftpm-macos`.
**Archivos:** `DataPlane/DataPlaneDecoder.swift`, `DataPlane/LingoRealtimeReading.swift` (nuevo), `DataPlane/Libre3DataPlaneState.swift`, `DataPlane/PatchStatus.swift`, `DataPlane/HistoricalBackfill.swift`, `DataPlane/PatchControlCommand.swift`, `DataPlane/LingoHistoricalPage.swift` (nuevo), `DataPlane/LingoFastData.swift` (nuevo), `DataPlane/SensorLifecycle.swift`, `Tests/RoundWhiteDiscKitTests/LingoDataPlaneTests.swift` (nuevo), `Fixtures/lingo_realtime_vectors.json` (nuevo, público).
**Objetivo:** cambios 5 a 13 de `docs/FORK_RWDK.md` §3 siguiendo `docs/PROTOCOLO_LINGO.md` §2.3, §3, §4, §6 y §7.
**Detalle:**
- `DataPlaneNotificationAssembler(targetLength:)`: acumula fragmentos de cualquier tamaño hasta `targetLength` (35 o 57 según familia); si se excede o llega un fragmento vacío, descarta y reporta `.overflow`.
- `LingoRealtimeReading.parse(_: Data) throws`: 51 B exactos; mapa de tipos @34; primer canal con tipo 1; bloque de 15 B con `capped`, `rate`, `historicCapped`, `trend & 0x07` (6 y 7 → 0), `actionable = bit 3`, `uncapped`, `historicUncapped`; temperatura @37 (`0x8000` inválida); banderas por palabra (bit 15); `rangeBits`. Expone también los bytes @35-36 y @39-50 como `reserved` sin interpretar.
- `DataPlaneDecoder(family:)` despacha por familia y longitud; nuevo caso `.lingoRealtime(LingoRealtimeReading)`. Los `try?` pasan a registrar el error en un contador `unexpectedRawCount` accesible.
- `PatchStatus`: 12 B (Libre 3) o 14 B (Lingo); los 2 B extra se exponen como `analyteBytes: Data` sin semántica.
- `BackfillStream.wireValue(for family:)`: `{0x02, 0x03}` en Lingo; `reconnectBackfillCommands(family:)`.
- `LingoHistoricalPage`: plaintext 4..14 B par; primera palabra con bit 15 obligatorio; valores `0` terminan; bit 15 inválido; `& 0x0FFF`.
- `LingoFastData`: 14 B exactos; `histLC = lc < 22 ? 0 : ((lc-17)/5)*5`.
- `SensorLifecycle`: calentamiento desde `patchInfo.warmup * 5`.
**Aceptación:** los 12 vectores de `docs/PROTOCOLO_LINGO.md` §8 (4 warm-up, 2 de 201 mg/dL, 6 de tendencia) con los valores esperados; intercambio de canales (§8.3) y canal 0 (§8.4) dan el mismo resultado; `typemap 0x32` → sin glucosa; 50 y 52 B → error; ensamblador con cortes en 1, 15, 20, 28, 56 B y duplicado; `patchStatus` 12 y 14; historial con 1..6 valores, sin bit 15 → rechazo; fast data con `lc` 21 y 22. `swift test` verde.
**Verificación Fable:** tests; grep de `try?` nuevos; commit `T-03`.

## T-04 — Vectores AES-CCM independientes y tests negativos

**Modelo:** Sonnet. **Skill:** `swiftpm-macos`.
**Archivos:** `Fixtures/ccm_vectors.json` (nuevo), `Fixtures/tools/gen_ccm_vectors.py` (nuevo), `Packages/RoundWhiteDiscKit/Tests/RoundWhiteDiscKitTests/CCMVectorTests.swift` (nuevo).
**Objetivo:** probar `AESCCM` del fork contra una implementación independiente (Python `cryptography`, `AESCCM(key, tag_length=4)`) en los dos perfiles: nonce 13 B / L=2 (canal de datos) y nonce 7 B / L=8 (challenge). 20 vectores por perfil con longitudes 1, 15, 29, 35, 51, 57 B, más 10 negativos (tag alterado, nonce alterado, byte de texto alterado, longitud truncada).
**Aceptación:** el script se ejecuta con `python3 -I` desde el scratchpad y escribe el JSON; los tests cargan el JSON (`Bundle.module`) y pasan; los negativos fallan con error, no con pánico.
**Verificación Fable:** regenerar vectores con otra semilla y volver a pasar los tests; commit `T-04`.

## T-05 — Cargador de credenciales JSON → Keychain

**Modelo:** Sonnet. **Skill:** `swiftui-pro` (`swift.md`, `hygiene.md`).
**Archivos:** `LingoScan/Services/CredentialStore.swift`, `LingoScan/Services/KeychainItem.swift`, `LingoScanTests/CredentialStoreTests.swift`, `Credentials/README.md` (actualizar si cambia el formato).
**Objetivo:** actor `CredentialStore` que importa el JSON (desde Archivos o AirDrop vía `onOpenURL`/`fileImporter`), valida con `AppIdentity` (clave pública = certificado), guarda en Keychain (`AfterFirstUnlockThisDeviceOnly`, sin iCloud), expone `identity(for: .lingo)` y `signingKeys(for: .lingo)`, y borra **solo la copia temporal propia** del archivo importado; nunca borra ni mueve el archivo que Juampa eligió (puede ser su única copia) (ajuste 2 de Astra). Ningún `print`/log con el contenido; `description` de los tipos redactada. Los tests de integración en iOS requieren el proyecto de T-06.
**Aceptación:** tests con una identidad sintética (clave P-256 generada en el test y certificado de 162 B construido con esa clave); JSON inválido → error tipado; segunda importación reemplaza; `signingKeys` nunca devuelve vacío (error si no hay).
**Verificación Fable:** grep de `print(`/`os_log` con `privateKey|certificate|kAuth|pin`; tests en simulador; commit `T-05`.

## T-06 — Proyecto Xcode LingoScan + paquete LingoCore

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `swiftpm-macos`.
**Archivos:** `LingoScan.xcodeproj`, `LingoScan/App/**`, `LingoScan/Resources/**`, `LingoScan/LingoScan.entitlements`, `LingoScan/Info.plist`, `Packages/LingoCore/Package.swift`, `Packages/LingoCore/Sources/LingoCore/LingoCore.swift`, `Packages/LingoCore/Tests/**`, `LingoScanTests/**`.
**Objetivo:** esqueleto que compila y se instala en simulador. Bundle ID `com.otalvaro.lingoscan`, team `SR8DQF26N7`, iOS 26.0, Swift 6.2, `SWIFT_STRICT_CONCURRENCY = complete`. Entitlements y claves de Info.plist de `ARQUITECTURA.md` §7. Dependencias locales: `Packages/RoundWhiteDiscKit` y `Packages/LingoCore` (este con plataformas iOS 26 y macOS 15 para `swift test` en Mac). `TabView` con cinco pestañas vacías y `ContentUnavailableView` en cada una. `Localizable.xcstrings` con `es` base y `en`.
**Aceptación:** `xcodebuild -scheme LingoScan -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build test` verde; `swift test` de `LingoCore` verde en Mac; captura de la app en simulador.
**Verificación Fable:** `mcp__XcodeBuildMCP__build_run_sim`; revisar `project.pbxproj` (bundle ID, team, target); commit `T-06`.

## T-07 — LingoCore: dominio, elegibilidad y almacén SQLite

**Modelo:** Opus. **Skill:** `swiftpm-macos`, `swiftui-pro` (`swift.md`).
**Archivos:** `Packages/LingoCore/Sources/LingoCore/Domain/**`, `Store/**`, `Diagnostics/**`, `Tests/LingoCoreTests/**`.
**Objetivo:** tipos `GlucoseReading`, `SensorSessionRecord`, `DiaryEvent`, `Eligibility`; `EligibilityPolicy` con la matriz de `DATOS_Y_HEALTHKIT.md`; actor `SQLiteStore` con el esquema v1, migraciones por `user_version`, inserción idempotente por `record_id`/`revision`, consultas por rango de tiempo, outbox de Health, registro de archivos, `event_log` con `Redactor`. API C de SQLite envuelta en un tipo `SQLiteConnection` con statements preparados; todo `Sendable`.
**Aceptación:** tests en Mac: creación de esquema, migración v0→v1, idempotencia (insertar tres veces), reconciliación vivo/backfill, consulta de 20 000 lecturas < 50 ms, `Redactor` sobre blobs y seriales, política de elegibilidad con los 12 vectores de Juggluco convertidos a `GlucoseReading` (lc 1-4 excluidos `warmUp`/`qualityFlag`, 201 y 208 elegibles, tendencias elegibles).
**Verificación Fable:** `swift test`; revisar que no hay `sqlite3_exec` con strings interpolados; commit `T-07`.

## T-08 — SensorSessionCoordinator y NFCService

**Modelo:** Opus. **Skills:** `swiftui-pro` (`swift.md`, `data.md`), revisión cruzada de Fable con `docs/FORK_RWDK.md` §1 y §6.
**Archivos:** `LingoScan/Services/NFCService.swift`, `LingoScan/Services/SensorSessionCoordinator.swift`, `LingoScan/Services/PairingStateStore.swift`, `LingoScan/Services/SessionState.swift`, `LingoScanTests/SessionCoordinatorTests.swift` (con transportes guionados del fork).
**Objetivo:** la máquina de estados de `ARQUITECTURA.md` §3 sobre la API del fork (`docs/FORK_RWDK.md` §1): NFC solo lectura (`.readPatchInfo`), activación solo con `ActivationTicket`, pairing completo (`runCommandGatedFirstPairHandshake` con `phase5RawKeyProvider` calculando kAuth desde `CredentialStore`), suscripciones incluidas `historicData` y `clinicalData`, `DataPlaneCrypto` + ensamblador + decodificador por familia, backfill tras `patchStatus`, persistencia de `PairingState` (kAuth en Keychain), reconexión corta con fallback a completa, restauración de CoreBluetooth en segundo plano, contador de secuencia saliente, timeouts configurables, `EventLog` redactado, contador de raw inesperados.
**Aceptación:** tests con transporte guionado: pairing feliz → `warmingUp`; corte tras `0x03` → `authenticationFailed(phase: .certificateAcceptance, reason: .interrupted)` con evidencia en `event_log` y sin reintento automático de credenciales; respuesta negativa explícita → `reason: .rejected`; trama de 57 B en tres fragmentos → lectura en el almacén; 5 min sin tramas → `stale`; reconexión corta rechazada → completa; restauración con `PairingState` guardado → `reconnecting`. Ningún camino de `NFCService.readPatchInfo` puede invocar `.activateFreshSensor` (test de tipo: `ActivationTicket` solo se construye desde la vista de activación).
**Verificación Fable:** tests; lectura completa del archivo del coordinador; grep de `activateOrSwitchReceiver` y `forceActivationCommand` (no deben usarse); commit `T-08`.

## T-09 — HealthExporter con outbox y elegibilidad

**Modelo:** Sonnet. **Skill:** `swiftui-pro`.
**Archivos:** `LingoScan/Services/HealthExporter.swift`, `Packages/LingoCore/Sources/LingoCore/Health/HealthSampleMapper.swift`, `LingoScanTests/HealthExporterTests.swift`.
**Objetivo:** autorización (escritura de glucosa y carbohidratos; lectura de entrenamientos), drenado del outbox con `HKQuantitySample` y metadatos de `DATOS_Y_HEALTHKIT.md`, reintentos con backoff, ledger append-only por `attempt_id` y estado derivado (`CONTRATO_V1.md` §5.4), nunca exportar `eligible == 0` ni `synthetic == true` (filtro estructural: el exportador recibe un tipo `HealthEligibleReading` que solo se construye desde registros no sintéticos), lectura de entrenamientos por rango para la curva.
**Diseño de pruebas (ajuste 6 de Astra):** el exportador escribe contra un protocolo `HealthSink`; los tests usan un `HealthSink` en memoria inyectado. La integración con HealthKit del simulador vive en un target de tests separado activado por una condición de compilación de pruebas (`LINGOSCAN_HEALTH_SIM_TESTS`) que no existe en la build que se instala en el iPhone; no hay ningún interruptor en tiempo de ejecución que permita escribir datos sintéticos en Health.
**Aceptación:** con el sink en memoria: 100 lecturas elegibles → 100 muestras con `SyncIdentifier`; reintento no duplica; `qualityFlag`, `synthetic` y tombstones nunca aparecen; `failed` seguido de `written` deja estado derivado `written`; carbohidratos con nota en metadatos; denegación de permiso deja el outbox intacto. En el target de simulador: las mismas comprobaciones contra `HKHealthStore`.
**Verificación Fable:** tests en simulador; consulta `HKSampleQuery` de comprobación; commit `T-09`.

## T-10 — ArchiveService: `.lingoscan` export/import

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `swiftpm-macos`.
**Archivos:** `Packages/LingoCore/Sources/LingoCore/Archive/**`, `LingoScan/Services/ArchiveService.swift`, `LingoScan/Services/FolderBookmark.swift`, `LingoScan/App/BackgroundTasks.swift`, tests en ambos targets, `docs/FORMATO_LINGOSCAN.md` (nuevo, es el `schema/README.md` del archivo).
**Objetivo:** exportación e importación **exactamente** según `../LingoScan_Shared/CONTRATO_V1.md` (carpeta `.partial` → renombrado, manifest con hashes al final, `producer_tag` `lingoscan`, esquemas de `../LingoScan_Shared/schemas/`), bookmark de carpeta, fallback al contenedor iCloud, estados de iCloud con las claves `NSURLUbiquitousItem*`, `BGAppRefreshTask` diario, importación validada y transaccional con las reglas de unión de §8 y `conflicts.ndjson`.
**Aceptación:** el paquete de `../LingoScan_Shared/examples/` se importa sin cambios en tres pasadas; los cinco de `examples/invalid/` se rechazan con el motivo exacto; un paquete exportado por LingoScan pasa `python3 -I ../LingoScan_Shared/tools/verify_archive.py`; los casos P-03, P-05, P-06, P-07, P-08, P-09 de `PRUEBAS_INTEROPERABILIDAD.md` con fixtures; `readings.csv` abre en Numbers.
**Verificación Fable:** tests; `verify_archive.py` sobre un paquete real del simulador; commit `T-10`.

## T-11 — Shell de la app, Hoy y Sensor con Liquid Glass

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `swiftui-liquid-glass`, `ios-design-agent-skill`, `apple-design`, `swiftui-animation`.
**Archivos:** `LingoScan/DesignSystem/**`, `LingoScan/Features/Today/**`, `LingoScan/Features/Sensor/**`, `LingoScan/App/PreviewData.swift`, `LingoScanTests/TodayViewModelTests.swift`.
**Objetivo:** las pantallas Hoy y Sensor de `DISENO_UI.md` con view models `@Observable` alimentados por `SQLiteStore` y `SensorSessionCoordinator`; `PreviewData` sintético; chip de estado con `GlassEffectContainer`; selector de período; curva Swift Charts con huecos y marcas; pantalla de activación separada con confirmación y `ActivationTicket`.
**Aceptación:** capturas claro/oscuro/Dynamic Type grande en iPhone 17 Pro Max; checklist de `swiftui-liquid-glass` cumplido; VoiceOver lee el valor combinado; sin `foregroundColor`, `NavigationView` ni `onChange` de un parámetro; `Instruments`-free: scroll de 24 h sin hitches en simulador.
**Verificación Fable:** `swiftui-pro` sobre los archivos; `ios-design-agent-skill` con capturas; commit `T-11`.

## T-12a — Diario, Datos, Ajustes y gráfica básica (Fase 2a)

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `swiftui-liquid-glass`, `ios-design-agent-skill`.
**Archivos:** `LingoScan/Features/Diary/**`, `Data/**`, `Settings/**`, `Packages/LingoCore/Sources/LingoCore/Reports/BasicStats.swift`, tests.
**Objetivo (ajuste 4 de Astra):** lo mínimo para validar el sensor: Diario (comidas, ejercicio, notas con linaje de ediciones `edit_id`/`parent_edit_id`), Datos (estado de Health con huecos pendientes, exportar/importar, estado de iCloud, recuperación), Ajustes (unidad, alarmas, permisos, diagnóstico), y en Hoy la curva 3/6/24 h con huecos y marcas más tiempo en rango, media y SD del período visible. Sin pulido visual más allá del checklist de accesibilidad.
**Aceptación:** `BasicStats` con 4 fixtures (huecos, calentamiento, vacío, 24 h completas); capturas claro/oscuro; VoiceOver en Diario y Datos.
**Verificación Fable:** tests; capturas; commit `T-12a`.

## T-11b — Hoy según la referencia de la caja Lingo (Fase 2a, tras T-12a)

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `swiftui-liquid-glass`, `ios-design-agent-skill`, `apple-design` (arrastre interrumpible, respuesta inmediata).
**Archivos:** `LingoScan/Features/Today/**`, `LingoScan/Features/Diary/QuickAdd*.swift` (nuevo), `Packages/LingoCore/Sources/LingoCore/Reports/SpikeIndex.swift` (nuevo) + test, `LingoScanTests/Today*`, `docs/T-11b.md`, capturas.
**Objetivo:** el modelo de interacción de `DISENO_UI.md` "Referencia de interacción": navegación por día con `‹ Hoy ›` y selector de fecha; chips 6 h / 12 h / 24 h; líneas de referencia 70 y 140 mg/dL (editables en Ajustes, marcadas no médicas); sombreado del área sobre 140 en cada pico e índice de pico bajo cada uno (`SpikeIndex`: área sobre 140 en mg/dL·min ÷ 10, redondeado); marcadores de comida y ejercicio sobre el eje de tiempo con icono y hora; arrastre sobre la curva con línea vertical y lectura "N mg/dL a las HH:MM" (gesto interrumpible, sin bloquear el scroll); botón "+" flotante de vidrio que abre un registro rápido en dos toques (comida con gramos opcionales, ejercicio, nota) que escribe en el Diario con linaje; fila "Registro de hoy" con conteo y acceso al Diario. Huecos siguen visibles y sin interpolar; datos sintéticos siguen rotulados.
**Aceptación:** `SpikeIndex` con 4 fixtures (sin picos, un pico, dos picos, pico cortado por hueco); arrastre devuelve la lectura más cercana al instante (test del view model); capturas claro/oscuro con la curva de `PreviewData`; checklist de `swiftui-liquid-glass`; sin `foregroundColor` ni API obsoleta; VoiceOver lee el valor arrastrado.
**Verificación Fable:** tests; capturas comparadas con `docs/referencias/lingo-caja-pantalla-today.jpg`; commit `T-11b`.

## T-21 — Asistente de registro con LLM y entrenamientos desde Salud (Fase 2b, tras T-11b)

**Modelo:** Sonnet implementa; Fable revisa el manejo de claves y las llamadas HTTP. **Skills:** `swiftui-pro`, `swiftui-liquid-glass`; para Anthropic la referencia es el skill `claude-api` (`curl/examples.md`: Swift no tiene SDK oficial, se usa HTTP con `URLSession`); para los demás proveedores, su documentación oficial consultada con WebFetch en el momento de implementar (los identificadores de modelo cambian).
**Archivos:** `LingoScan/Services/LLM/**` (`LLMProvider` protocolo, `LLMProviderID` enum, `LLMKeychain`, `LLMClient` con `URLSession`, un archivo por proveedor: `AnthropicProvider`, `OpenAIProvider`, `GeminiProvider`, `GrokProvider`, `OpenRouterProvider`, `DeepSeekProvider`), `Packages/LingoCore/Sources/LingoCore/Nutrition/**` (`FoodEstimate`, `NutritionLabelReading`, `EstimateParser` con validación estricta del JSON), `LingoScan/Features/Diary/FoodAssistant*.swift` (cámara/galería, reducción a ≤ 1024 px JPEG calidad 0,8, texto libre, propuesta editable), `LingoScan/Features/Settings/LLMSettingsView.swift` (proveedor, clave, modelo editable con valor por defecto, botón "Probar"), `LingoScan/Features/Diary/WorkoutImport*.swift`, tests, `docs/T-21.md`.
**Comportamiento:**
1. **Ajustes → Asistente de comidas:** elegir proveedor; pegar clave (Keychain `com.otalvaro.lingoscan.llm.<proveedor>`, `AfterFirstUnlockThisDeviceOnly`, nunca en logs ni en el archivo `.lingoscan`); campo de modelo prellenado con el **económico por defecto** y editable; "Probar" hace una llamada mínima y muestra tokens usados y coste estimado. Aviso fijo: "La foto o el texto se envían al proveedor elegido; las estimaciones son aproximadas y no médicas".
2. **Entradas:** (a) foto del plato, (b) nombre del plato o snack escrito, (c) foto de la tabla nutricional (modo "etiqueta": extraer porción, calorías, carbohidratos, azúcares, proteína, grasa por porción y por envase). Las tres devuelven una **propuesta** `FoodEstimate` (ítems con porción estimada en gramos, carbohidratos g, calorías kcal, proteína, grasa, confianza 0–1 y notas) que el usuario edita y confirma; solo al confirmar se crea el evento `meal` con `carbs_g`, `calories_kcal` (campo nuevo en `DiaryEvent`, opcional, propagado al contrato como clave opcional `calories_kcal`) y el texto. Nada se guarda sin confirmación. Sin clave configurada, el flujo manual sigue funcionando igual.
3. **Salida estructurada:** se pide JSON con esquema fijo en el prompt y, donde el proveedor lo soporte, modo JSON/esquema nativo; `EstimateParser` rechaza respuestas incompletas y muestra "no se pudo estimar" sin inventar números. Las fotos no se guardan en SQLite; opcionalmente una miniatura local de 256 px fuera del backup.
4. **Modelos económicos por defecto** (editables; verificar identificadores y precios al implementar): Anthropic `claude-haiku-5-5` (0,10 $/M entrada, 0,50 $/M salida según la tabla del skill `claude-api` del 2026-10); OpenAI el "mini" vigente con visión; Gemini el "Flash-Lite" o "Flash" vigente; Grok el modelo con visión más barato vigente; OpenRouter el identificador que el usuario escriba (enruta a cualquiera; por defecto el Haiku 5.5 vía OpenRouter); DeepSeek **solo texto** (su API no acepta imágenes; en modo foto se avisa y se ofrece cambiar de proveedor). Coste orientativo por foto con Haiku 5.5: ~2 000 tokens de entrada + 300 de salida ≈ 0,0004 $.
5. **Ejercicio:** no usa LLM. `WorkoutImport` lee `HKWorkout` de Salud (los registra el Apple Watch con la app nativa Entrenamiento): tipo, inicio, fin, duración, energía activa, distancia y frecuencia cardíaca media si está; crea o actualiza eventos `exercise` con `source: "healthkit"`, `health_workout_uuid` (campo nuevo opcional, para no duplicar) y, en la curva de Hoy, los muestra como marcadores. Importación al abrir la app y al refrescar Hoy; se pide permiso de lectura de entrenamientos (ya contemplado en T-09).
**Aceptación:** tests con respuestas grabadas (fixtures JSON) por proveedor: parseo correcto, respuesta incompleta → error, JSON con números fuera de rango (calorías negativas, > 5 000 kcal por porción) → rechazo; claves nunca aparecen en `description`, logs ni exportación; prueba manual con tu clave en el iPhone de los tres modos de entrada; importación de un entrenamiento del Watch sin duplicados en tres refrescos.
**Verificación Fable:** revisión del código HTTP y del Keychain; `grep` de claves en logs y fixtures; commit `T-21`.

## T-12b — Reportes avanzados y pulido (Fase 2b, después del primer sensor)

**Modelo:** Sonnet. **Skills:** `swiftui-pro`, `ios-design-agent-skill`, `apple-design`, `swiftui-performance`.
**Archivos:** `LingoScan/Features/Reports/**`, `Packages/LingoCore/Sources/LingoCore/Reports/ReportsEngine.swift`, tests.
**Objetivo:** `ReportsEngine` con respuesta a comidas (pico, tiempo al pico, retorno a ±10 % de la línea base en 3 h), noche 00:00–06:00, CV y comparación semanal; definiciones visibles; pulido de movimiento y Liquid Glass. Se hace con lecturas reales de T-16 para calibrar definiciones.
**Aceptación:** `ReportsEngine` con fixtures y valores esperados calculados a mano (al menos 6 casos, incluidos huecos y comidas sin retorno); capturas; checklist de skills; scroll de 14 días sin hitches.
**Verificación Fable:** tests; capturas; commit `T-12b`.

## T-13 — Alarmas

**Modelo:** Sonnet. **Skill:** `swiftui-pro`.
**Archivos:** `LingoScan/Services/AlarmService.swift`, `LingoScan/Features/Settings/AlarmsView.swift`, tests.
**Objetivo:** alarmas alta, baja y sin datos con `UNUserNotificationCenter`, umbrales de D-12 editables, histéresis de 15 min, texto fijo de no uso médico, respeto de Focus.
**Aceptación:** tests de la lógica de disparo con series sintéticas; notificación visible en simulador.
**Verificación Fable:** tests; commit `T-13`.

## T-14 — Firma, instalación en iPhone, permisos, diagnóstico NFC

**Modelo:** Fable (con XcodeBuildMCP y `xcodebuild`), Juampa presente.
**Objetivo:** instalar en "iPhone 17 JP", conceder Bluetooth, NFC y Health, importar `lingo-identity.json`, y leer un sensor con `0xA1` sin activarlo (primero dentro del aplicador; si no responde, después de aplicarlo y antes de activar).
**Aceptación:** app abre; estado `identified` con `productType`, `securityVersion`, calentamiento y duración; nada enviado salvo `0xA1` (verificado en `event_log`). Resultado anotado en `../NOTAS.md` sin el serial completo.

## T-15 — Pruebas cruzadas con Astra

**Modelo:** Fable coordina; Sonnet prepara paquetes y automatiza.
**Archivos:** `../LingoScan_Shared/interop/lingoscan/**` (paquetes exportados por LingoScan), `../LingoScan_Shared/interop/RESULTADOS.md`, `LingoScanTests/InteropTests.swift`.
**Objetivo (ajuste 5 de Astra):** la prueba de independencia del importador son los paquetes producidos por **las dos implementaciones** más el verificador externo (`tools/verify_archive.py`, `tools/verify_merge_fixtures.py`), no una tercera app que reutiliza `LingoCore`. LingoScan importa los paquetes de `interop/astra/` y los fixtures de `examples/merge/` en todos los órdenes y compara con `expected.json`; exporta los suyos a `interop/lingoscan/` para Astra.
**Aceptación:** P-01..P-11 y R-01..R-05 de `PRUEBAS_INTEROPERABILIDAD.md` registradas en `RESULTADOS.md` con commit y evidencia. Una app de prueba con otro bundle ID (`LingoScanReplacementProbe`) se crea **solo** si la prueba R-03 (recuperación desde otro bundle ID sin Keychain original) no puede hacerse con LingoScan_Astra a tiempo.
**Verificación Fable:** ejecutar `verify_archive.py` sobre cada paquete de `interop/lingoscan/`; commit `T-15`.

## T-19 — Archivo de recuperación cifrado y transferencia de rol

**Modelo:** Fable escribe `RecoveryCrypto` (PBKDF2 + ChaChaPoly, envoltura, AAD) y sus tests contra `../LingoScan_Shared/examples/recovery/vectors.json`; Opus integra `RecoveryExporter`/`RecoveryImporter` con `CredentialStore`, `PairingStateStore` y `SensorSessionCoordinator`. **Skills:** `swiftui-pro` (`swift.md`), `swiftpm-macos`.
**Archivos:** `Packages/LingoCore/Sources/LingoCore/Recovery/**` (cripto y modelo de carga útil, sin Keychain), `LingoScan/Services/RecoveryService.swift`, `LingoScan/Features/Data/RecoveryViews.swift`, `LingoScan/Features/Sensor/ConnectActiveSensorView.swift`, tests en ambos targets.
**Objetivo:** `RECUPERACION_V1.md` completo: exportación en `prepared`, `response_saved` y `authenticated` durante la activación y a petición; importación con frase; "Conectar sensor activo" para sesiones importadas; modo "en pausa" (sin reconexión, sin restauración CB, sin Health) para transferir el rol; nunca `0xA0`/`0xA8` desde el flujo de importación.
**Aceptación:** R-01 (los 7 vectores), R-04, R-05 y el registro durable de activación con transportes guionados (muerte simulada entre `sent` y `response_saved` deja el intento marcado y no reactiva). Apertura de un archivo con 600 000 iteraciones medida en el iPhone (< 1 s).
**Verificación Fable:** tests; revisión de que ningún camino de importación alcanza `.activateFreshSensor`; commit `T-19`.

## T-16 — Protocolo del sensor de sacrificio

**Modelo:** Fable + Juampa. Pasos en `PLAN.md` Fase 3. Requiere confirmación escrita en el chat antes del paso 5. **Precondiciones duras (ajuste 3 de Astra):** T-19 cerrada y probada (R-01, R-04, R-05 verdes; exportación de recuperación en `prepared` funcionando), T-10 con exportación verificada por `verify_archive.py`, y Fase 2a cerrada. Ninguna activación real antes de eso.

## T-17 — Nightscout uploader (Fase 4, opcional)

**Modelo:** Sonnet. Subida de `entries` (`sgv`, `date`, `dateString`, `direction`, `device: "LingoScan"`) por REST con `API_SECRET` hasheado, cola propia, Docker Compose de Nightscout + MongoDB para el servidor de Juampa.

## T-18 — Apple Watch (Fase 4)

**Modelo:** Sonnet. App watchOS con valor, tendencia y antigüedad vía `WatchConnectivity`; complicación.
