# Diseño técnico: fork de RoundWhiteDiscKit (RWDK) para LingoScan

Base analizada: clon en `scratchpad/rwdk/` (HEAD `7dd6396`, `RoundWhiteDiscKit.version = "0.0.1"`). Rutas relativas a `Sources/RoundWhiteDiscKit/` salvo indicación. Solo se afirma lo que está en el código; lo que no aparece se marca **(no está en el código)**.

## 1. Superficie pública para la app anfitriona

**RWDK no es agnóstico de transporte: maneja CoreBluetooth y CoreNFC por sí mismo**, pero expone costuras para sustituirlos. `PairingFlow` habla con un protocolo `PairingTransport`/`CommandPairingTransport` (`Pairing/PairingTransport.swift:18-33`), y el plano de datos es puro (bytes → tipos). Hay un adaptador CoreBluetooth listo (`SensorSessionTransport`, `Pairing/SensorSessionTransport.swift:18`). RWDK **no** trae un orquestador de alto nivel (tipo "SensorManager"): la máquina de estados de conexión, reintentos y persistencia es de la app (README:97-106).

| Necesidad | Punto de entrada | Forma |
|---|---|---|
| (a) NFC solo lectura (0xA1) | `Libre3NFCActivationReader().scan(mode: .readPatchInfo)` (`Pairing/CoreNFCActivationReader.swift:14`, A1 en :69-74) | `async throws -> Libre3NFCScanResult`; parser `Libre3NFCPatchInfo(raw:)` (`Pairing/NFCActivationModels.swift:17-34`, `productType` byte 15 en :29, `securityVersion` u16@3 en :24) |
| (b) Activación 0xA0 / switch 0xA8 | `scan(mode: .activateFreshSensor(receiverID:timeSeconds:))`, `.switchReceiver`, `.activateOrSwitchReceiver`, `.forceActivationCommand` (`NFCActivationModels.swift:148-154`); ejecución en `CoreNFCActivationReader.swift:160-199` | Devuelve `Libre3NFCActivationResponse` (MAC BLE, PIN 4 B, `activationTimeRaw`) `NFCActivationModels.swift:74-91`. Payload: `NFCActivationCommand.command/metcrc` (`Pairing/NFCActivationCommand.swift:19-39`) |
| BLE: escaneo/conexión | `SensorScanner` (`BLE/SensorScanner.swift:160`): `waitUntilReady` :186, `startScan` :204, `connect(_:timeout:)` :338 (default 120 s), `connectIndefinitely` :315, `resumeSession` :382. Alternativa orientada a eventos `SensorScannerNG` (`BLE/SensorScannerNG.swift:14-30`) | `async`, `AsyncStream` |
| Sesión GATT | `SensorSession` (`BLE/SensorSession.swift:82`): `discoverAndSubscribe` :197, `notifications()` :232, `refreshDataPlaneNotifications` :328, `send` :381 (con prefijo offset), `writeRaw` :392, `readPatchStatus` :445 | `async throws`, `AsyncStream<NotifyEvent>` |
| (c) Pairing BLE | `actor PairingFlow` (`Pairing/PairingFlow.swift:141`). Init con `phoneCert` y `sensorCertSigningKeys` (:163-175). Completo: `runCommandGatedAuthorizationHandshake(tail4:phase5RawKeyProvider:...)` (:462); alias `runCommandGatedFirstPairHandshake(blePIN:...)` (:521) | `phase5RawKeyProvider` es un closure síncrono que recibe el preámbulo (certificado sensor + efímeras) y debe devolver kAuth; la app lo calcula con `AppIdentity.authKey(...)` (`Pairing/AppIdentity.swift:27-36`) |
| (d) Sesión de datos | `DataPlaneCrypto(sessionMaterial:)` (`DataPlane/DataPlaneCrypto.swift:58`), `DataPlaneNotificationAssembler` (`DataPlane/DataPlaneDecoder.swift:129`), `DataFrame.parse` (`DataPlane/DataFrame.swift:29`), `DataPlaneDecoder.decrypt(frame:channel:)` (`DataPlaneDecoder.swift:76`), `Libre3DataPlaneState.record(_:)` (`DataPlane/Libre3DataPlaneState.swift:124`) | Síncrono y puro. Backfill: `PatchControlCommand.*BackfillGreaterEqual` (`DataPlane/PatchControlCommand.swift:20-47`) cifrado con `crypto.encrypt(..., kind: .patchControlWrite)`; el contador de secuencia saliente lo lleva la app **(no hay helper en el código)** |
| (e) Reconexión | Restauración CB: `SensorScannerConfiguration.background(...)` (`SensorScanner.swift:52`), `restorationEvents()` :255, `registerForConnectionEvents` :267, `retrievePeripherals` :291. Auth corta: `runCachedReconnectHandshake(tail4:phase5RawKey:)` (`PairingFlow.swift:375-448`); si falla, volver a la completa (README:248-268) | `async` |

**Estado a persistir para reconectar sin reactivar** (lo que RWDK modela vs. lo que la app debe añadir):

| Dato | ¿En `Libre3SensorState`? (`Pairing/Libre3SensorStateLoader.swift:3-12`) | Comentario |
|---|---|---|
| serial, MAC BLE, PIN BLE (= `tail4`), receiverID, warmup/wear, último lifeCount/mg/dL | Sí | JSON vía `Libre3SensorStateLoader.jsonData/load` |
| kAuth (16 B) | **No** | Requerido por el reconnect corto ("reuses the kAuth saved", protocol.md:287). Guardar en Keychain |
| Etiqueta de `AppIdentity` | **No** | README:67-69 dice que la app la persiste |
| `productType` / `securityVersion` | **No** | Necesario para Lingo (elegir identidad, parser, comandos) |
| kEnc/ivEnc | No | Se renuevan en cada Phase 6 (`Pairing/Phase6Response.swift:61-78`); persistir no es necesario |
| `CBPeripheral.identifier` | No | Para `retrievePeripherals`; lo guarda la app |

## 2. Instalación de credenciales

- `AppIdentity(label:privateKey:certificate:)` valida que la clave pública del certificado coincida con la privada (`AppIdentity.swift:16-23`). `PhoneCert` exige 162 B y `0x04` en el offset 33; **no valida la cabecera** `[0..2)` (`Pairing/PhoneCert.swift:8,21-27`), así que un certificado `03 01` se acepta tal cual.
- `AppIdentities.install(_:)` / `install(json:)` (`AppIdentity.swift:51-59`) guarda **una lista global** con `NSLock`. JSON: `{"format":1,"curve":"P-256","identities":[{"label","privateKeyHex","certificateHex"}]}` (:72-100); no hay campo de tipo de sensor.
- Hallazgo: `AppIdentities.installed()` **no se llama en ningún sitio de `Sources/`** (grep). `PairingFlow` recibe `phoneCert` directamente y kAuth vía closure. La frase del README "Authorization entry points throw `AppIdentityError.notInstalled`" no se refleja en el código: la selección de identidad ya es 100 % de la app.
- `sensorCertSigningKeys`: parámetro de `PairingFlow.init` con default `Libre3PatchSigningKey.known = [level0, level1]` (`Pairing/SensorCert.swift:20-49`; `PairingFlow.swift:153,167`). La verificación prueba la lista en orden (`SensorCert.swift:89-96`, `PairingFlow.swift:574-584`); lista vacía = verificación omitida.

**Cambio mínimo:** no hace falta tocar `PairingFlow`. La app, tras leer `patchInfo.productType`, pasa `phoneCert` de la identidad Lingo y `sensorCertSigningKeys: [lingoKey]`. Para dejarlo en la librería (recomendado, acotado): añadir `productTypes: [UInt8]?` opcional a `Entry`/`AppIdentity`, `AppIdentities.identity(forProductType:)`, y un `PatchSigningKeys.keys(forProductType:)` con `LingoPatchSigningKey`.

## 3. Cambios del fork

| # | Archivo | Cambio | Tipo |
|---|---|---|---|
| 1 | `Pairing/NFCActivationModels.swift` | Añadir `enum SensorFamily { libre3, lingo }` y `var family` derivado de `productType == 9 && securityVersion == 3`. El guard `frame.count >= 29` (:19) y `== 19` de la respuesta de activación (:83) deben verificarse con una captura A1/A0 de Lingo | acotado |
| 2 | `Pairing/AppIdentity.swift` | Campo opcional `productTypes` en JSON/`AppIdentity` + selector por `productType` (compatible hacia atrás) | acotado |
| 3 | `Pairing/SensorCert.swift` | Constante `LingoPatchSigningKey` (65 B, `0x04…`) y selector por familia. No cambia el formato de 140 B | datos |
| 4 | `Pairing/Libre3SensorStateLoader.swift` | Añadir `productType`, `identityLabel` (y opcionalmente referencia Keychain a kAuth) al estado/JSON, con decodificación tolerante a ausencia | acotado |
| 5 | `DataPlane/DataPlaneDecoder.swift` (`DataPlaneNotificationAssembler`, :129-152) | Hoy: si el fragmento de `glucoseData` mide **exactamente 15 B** se guarda como prefijo y el siguiente fragmento, del tamaño que sea, se concatena (:143-150) → 15+20 = 35 B. Con 57 B esto falla en silencio. Sustituir por ensamblado por longitud objetivo (35 o 57 según familia), acumulando hasta completar y descartando si sobra. La partición real de 57 B en Lingo hay que confirmarla con captura | acotado |
| 6 | `DataPlane/RealtimeGlucoseReading.swift` | El parser de 29 B exige `count == 29` (:4, :138-141). Se invoca solo desde `DataPlaneDecoder.decodePayload` (:96-101) con `try?`, de modo que 51 B termina como `.raw(Data)` sin error. Crear `LingoRealtimeReading` (51 B, dos analitos) en archivo nuevo | estructural |
| 7 | `DataPlane/DataPlaneDecoder.swift` | `DataPlaneDecoder` necesita la familia (init) o despachar por tamaño de plaintext (29/51). Añadir caso `DataPlaneDecodedPayload.lingoRealtime(...)` (:48-54) | estructural |
| 8 | `DataPlane/Libre3DataPlaneState.swift` | `record(_:)` hace `switch` exhaustivo (:124-162): añadir caso Lingo, lógica de "último aceptado" por analito y evaluación de calidad | estructural |
| 9 | `DataPlane/PatchStatus.swift` | `plaintextSize = 12` con guard `==` (:4, :141-144). Aceptar 14 B en Lingo y exponer los 2 B extra (semántica según la spec de Juggluco) | acotado |
| 10 | `DataPlane/HistoricalBackfill.swift` (`BackfillStream.wireValue`, :59-66) + `PatchControlCommand.swift` (:34-47) | Hoy `stream` = `0x00` (histórico) / `0x01` (clínico), `command = 0x01`. Para Lingo: `0x02`/`0x03`. Parametrizar por familia; `reconnectBackfillCommands` (`Libre3DataPlaneState.swift:183-206`) debe propagarla | datos/acotado |
| 11 | `DataPlane/HistoricalReadingPage.swift` (:17), `ClinicalReadingRecord.swift` (:56) | Ambos exigen 14 B. Si Lingo trae dos analitos, los registros cambiarán de tamaño: parsers nuevos **(formato no está en el código)** | estructural |
| 12 | `DataPlane/RealtimeGlucoseReading.swift:566-572` | `Libre3GlucoseValueStatus` fija el rango mostrable en 39…501 mg/dL: revisar para Lingo | datos |
| 13 | `DataPlane/SensorLifecycle.swift:10` | Warmup por defecto 60 min; usar siempre los valores del `patchInfo` de Lingo | datos |
| 14 | `Pairing/PairingFlow.swift:230` | Envolver el fallo en `0x04 CertificateAccepted` en un error explícito `certificateRejected` (ver §6) | acotado |
| 15 | Cadenas NFC (`CoreNFCActivationReader.swift:51-153`, `Resources/Localizations`) | Textos "Libre 3" → neutros | datos |

## 4. Tests existentes

`Tests/RoundWhiteDiscKitTests/` (XCTest, `swift test`). Todos los vectores son **hex en línea** en el propio test; no hay `Resources`/fixtures en el target de tests (`Package.swift:22-26`).

- `DataPlaneTests.swift`: framing, nonce, descriptores, **descifrado real de glucosa 15+20** con kEnc/ivEnc capturados (:63-90), patchStatus, histórico, comandos de patchControl (:516-567).
- `AppIdentityTests.swift`: escalares sintéticos (0x1111…0x4444) contra referencia Python; kAuth, Phase 5/6.
- `PublicSmokeTests.swift`: reconnect corto con `ScriptedCommandPairingTransport` (actor de respuestas guionadas, :352-389), verificación de certificado del sensor con `level1` (:118-127). **No hay test del handshake completo con certificados.**
- `NFCActivationCommandTests.swift`: patchInfo/activación con capturas reales, CRC.
- `BleFramingTests`, `AESCCMTests`, `Libre3ReceiverIDTests`, `Libre3SensorStateLoaderTests`, `LocalizationTests`.

**Añadir tests Lingo:** (1) `NFCActivationCommandTests`: A1 real de Lingo → `productType == 9`, `securityVersion == 3`. (2) Un certificado de sensor Lingo capturado verificado con `LingoPatchSigningKey`. (3) Copiar el patrón de `testLiveGlucoseDataFragmentsReassembleAndDecrypt` con kEnc/ivEnc y los fragmentos BLE crudos de una sesión Lingo (necesita un log que registre Phase 6 + notificaciones; el `eventLogger` de `PairingFlow`/`SensorSessionTransport` ya vuelca hex). (4) Extender `ScriptedCommandPairingTransport` para `.certHandshake` y probar el handshake completo. Para no subir claves al repo, mantener las capturas en un archivo de recursos ignorado por git o usar sesiones ya expiradas.

## 5. Plataforma

- `swift-tools-version: 5.10`, iOS 17 / macOS 14 (`Package.swift:1,7-10`). Modo de lenguaje Swift 5 (no hay `swiftSettings`); usa `nonisolated(unsafe)` (`Diagnostics/BLETimingLogger.swift:12`), que requiere Swift ≥ 5.10.
- **Sin dependencias SPM**: solo Foundation, CryptoKit, CommonCrypto, Security, CoreBluetooth, CoreNFC (`#if os(iOS) && canImport(CoreNFC)`, `CoreNFCActivationReader.swift:3`).
- Concurrencia: `PairingFlow` es `actor`; `SensorScanner`, `SensorSession`, `SensorSessionTransport`, `Libre3NFCActivationReader` son clases `@unchecked Sendable` serializadas con `DispatchQueue`+`NSLock`; los modelos son `struct … Sendable`. `AppIdentities` y `BLETiming` son estado global con lock.
- Biblioteca SPM estándar con recursos (`Bundle.module`), sin binarios: **usable como paquete local** (Xcode → Add Local Package / `.package(path:)`). La app necesita `NFCReaderUsageDescription`, el entitlement de lectura de etiquetas NFC (ISO 15693), `UIBackgroundModes: bluetooth-central` y `NSBluetoothAlwaysUsageDescription`.

## 6. Riesgos de integración

1. **Rechazo del certificado (la incógnita principal).** `waitFor(Data([0x04]))` (`PairingFlow.swift:230`) solo distingue "prefijo correcto o no". Según protocol.md:258-259, un sensor que no acepta el certificado **corta el enlace** tras `0x03`; eso llegará como `notifyTimeout` (2 s), `notifyStreamEnded` o `unexpectedCommandResponse`, sin un error "certificate rejected". Hay que clasificarlo para no reintentar a ciegas ni confundirlo con un fallo de enlace.
2. **Tamaños fijos del handshake**: R1 = 23 B (:291), Phase 6 = 67 B (`Phase6Response.swift:35`), cert. sensor = 140 B, cert. app = 162 B, efímera rellena a 72 B (:250). Si Lingo cambia alguno, falla con errores de tamaño.
3. **Fallos silenciosos del plano de datos**: `decodePayload` usa `try?` y devuelve `.raw` (`DataPlaneDecoder.swift:96-121`); el ensamblador de 15 B devuelve fragmentos sueltos. Añadir logs/contadores de "raw inesperado".
4. **GATT asumido**: escaneo, descubrimiento y `registerForConnectionEvents` filtran por las UUID de servicio de Libre 3 (`BLE/LibreSensorGATT.swift:19-23`; `SensorSession.swift:568-584` falla con "no Libre 3 services found"). Si Lingo usara otras UUID, falla en el descubrimiento. Confirmarlo en el primer escaneo BLE pasivo, antes de activar.
5. **Suscripciones**: `dataPlaneNotifying` no incluye `historicData` ni `clinicalData` (`LibreSensorGATT.swift:63-65`); la app debe activarlas con `setNotify` para recibir backfill.
6. **Timeouts**: comandos 2 s, escrituras 2 s (`PairingFlow.swift:209`; `0x11` en :287 y `0x08` en :634 no usan `withWriteTimeout`, aunque `writeRaw` tiene 5 s por defecto), fragmento notify 10 s (`SensorSessionTransport.swift:22`), descubrimiento 10 s, CCCD 15 s, conexión 120 s. Calibrarlos para Lingo.
7. **Reconexión**: la ruta corta depende de kAuth guardado (RWDK no lo persiste) y del PIN como `tail4`. Si es rechazada antes de Phase 6, el fallback completo exige reenviar el certificado; el NFC no se repite.
8. **NFC**: `recommendedCommandCode` decide 0xA0/0xA8 solo por `stateByte == 0x01` (`NFCActivationModels.swift:36-38`). En modo `.activateOrSwitchReceiver` puede activar sin confirmación: LingoScan debe usar `.readPatchInfo` primero y pedir confirmación antes de `.activateFreshSensor`. La hora de activación es `now - 1` (`CoreNFCActivationReader.swift:213-216`).
9. `BLETimingLogger.swift:7-9` se describe como "parche local" que "no sobrevivirá un re-resolve": es una señal de que este clon trae parches locales. Fijar el commit del fork.
