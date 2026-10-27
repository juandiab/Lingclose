# Especificación del plano de datos Abbott Lingo (según Juggluco 11.5.4)

Fuente analizada (solo lectura): `.../scratchpad/juggluco/` (HEAD `11.5.4`). Todas las rutas son relativas a ese directorio.
Abreviaturas de rutas:

| Alias | Ruta |
|---|---|
| `H` | `Common/src/main/cpp/libre3/lingo_realtime.h` |
| `C` | `Common/src/main/cpp/libre3/lingo_realtime.c` |
| `T` | `Common/src/main/cpp/libre3/lingo_realtime_test.c` |
| `BT` | `Common/src/main/cpp/libre3/bluetooth.cpp` |
| `NFCc` | `Common/src/main/cpp/libre3/nfc.cpp` |
| `DP` | `Common/src/main/cpp/libre3/dp_activation.hpp` |
| `BC` | `Common/src/main/cpp/bcrypt/bcrypt.cpp` (+ `ccm_mode.c`, tinycrypt) |
| `GC` | `Common/src/libre3/java/tk/glucodata/Libre3GattCallback.java` |
| `LC` | `Common/src/libre3/java/tk/glucodata/LingoCrypto.java` |
| `LS` | `Common/src/libre3/java/tk/glucodata/LingoSKB.java` |
| `LCr` | `Common/src/libre3/java/tk/glucodata/LingoCredentials.java` |
| `NFCj` | `Common/src/libre3/java/tk/glucodata/libre3/NFC.java` |
| `L3j` | `Common/src/main/java/tk/glucodata/Libre3.java` |
| `SGC` | `Common/src/main/java/tk/glucodata/SuperGattCallback.java` |
| `SGD` | `Common/src/main/cpp/SensorGlucoseData.hpp` |

Convenciones: todo multibyte es **little-endian** salvo que se indique lo contrario. Offsets en decimal, base 0. "Cita" = `alias:línea`.
Marcas: **[CÓDIGO]** = leído literalmente del código; **[DERIVADO]** = cálculo mío a partir de datos del repo (no afirmado por Juggluco); **[INFERENCIA]** = deducción plausible, no confirmada.

Nota de alcance: no existe `changes.html` ni changelog que mencione Lingo (`grep -ril lingo` solo devuelve código fuente; el único CHANGELOG es el de `LibAscon`). Ni `README.md` ni `index.html` mencionan Lingo.

---

## 0. Visión general del flujo (contexto mínimo para el plano de datos)

Lingo reutiliza la pila GATT de Libre 3 (mismos UUID, mismo cifrado de canal CCM). Lo que cambia: producttype en NFC, handshake de seguridad (ECDH P-256, `LingoCrypto`), tamaño/layout de la trama de tiempo real, historial, clínico y estado del parche.

### 0.1 UUIDs GATT (idénticos a Libre 3) — `SGC:68-86`

| Nombre | UUID | Rol |
|---|---|---|
| `LIBRE3_DATA_SERVICE` | `089810cc-ef89-11e9-81b4-2a2ae2dbcce4` | servicio de datos |
| `LIBRE3_SECURITY_SERVICE` | `0898203a-ef89-11e9-81b4-2a2ae2dbcce4` | servicio de seguridad |
| `PATCH_CONTROL` | `08981338-...` | escritura de comandos cifrados (kind 0) y notificación de respuesta (kind 1) |
| `PATCH_STATUS` | `08981482-...` | estado del parche (kind 2) |
| `EVENT_LOG` | `08981bee-...` | log de eventos (kind 6) |
| `GLUCOSE_DATA` | `0898177a-...` | lectura de 1 min (kind 3) |
| `HISTORIC_DATA` | `0898195a-...` | historial 5 min (kind 4) |
| `CLINICAL_DATA` | `08981ab8-...` | "fast data" / minuto retro-llenado (kind 5) |
| `FACTORY_DATA` | `08981d24-...` | no decodificado (kind 7 comentado, `GC:1360-1367`) |
| `SEC_COMMAND_RESPONSE` | `08982198-...` | comandos de seguridad (1 byte) |
| `SEC_CHALLENGE_DATA` | `089822ce-...` | challenge |
| `SEC_CERT_DATA` | `089823fa-...` | certificados / efímeras |

(sufijo común `-ef89-11e9-81b4-2a2ae2dbcce4`).

### 0.2 Orden de suscripción (CCCD) — `GC:1291-1359`, `GC:1614`
1. `SEC_COMMAND_RESPONSE` → `SEC_CERT_DATA` → `SEC_CHALLENGE_DATA` (handshake; al terminar el último CCCD arranca `handleMSLibre3SecurityNotificationsEnabledEvent`, `GC:1178-1207`).
2. Tras un `challenge67` correcto (§5.3): `PATCH_CONTROL` → `EVENT_LOG` → `HISTORIC_DATA` → `CLINICAL_DATA` → `FACTORY_DATA` → `GLUCOSE_DATA` → `PATCH_STATUS`. Al escribir el CCCD de `PATCH_STATUS` queda `subscriptionsReady=true` (`GC:1325-1328`).

### 0.3 Despacho de notificaciones — `GC:1090-1129`
`GLUCOSE_DATA`→`glucose_data` (kind 3, reensamblado); `PATCH_STATUS`→`receivedpatchstatus` (kind 2); `HISTORIC_DATA`→`save_history` (kind 4); `PATCH_CONTROL`→`access1100` (kind 1); `CLINICAL_DATA`→`fast_data` (kind 5); `EVENT_LOG`→`logevent` (kind 6); `SEC_*` → handshake. UUID desconocido → desconectar.

---

## 1. Detección NFC (patchInfo) y activación

### 1.1 Comando de lectura de patchInfo
ISO 15693 (NfcV) custom: `02 A1 7A` (`L3j:34`). Se reintenta hasta 10 veces; respuesta aceptable si `(data[0] & 1) == 0` (`AlgNfcV.java:49-51`, `Common/src/main/java/tk/glucodata/AlgNfcV.java`). Longitud mínima de la respuesta: **29 bytes** (`L3j:42-44`, si no → código 2).

### 1.2 Layout del frame de patchInfo (`struct firstnfc`, `NFCc:39-51`, `static_assert(sizeof==26)` en `NFCc:98`)

Parser (`NFCc:79-86`): `iter = buf+1; while(iter<end && *iter++ == 0xA5) ;` — salta el byte 0 (flags NFC) y consume bytes `A5`; **`firstnfc` comienza en el primer byte tras el primer byte != A5**. Con la respuesta habitual `00 A5 00 …` eso es el **índice 3**. Requiere `≥ 26` bytes restantes; si no → error. (Nota: tras el parseo Juggluco pone `crc16[0]=0`, `NFCc:87`.)

| Offset en frame completo | Offset en `firstnfc` | Tamaño | Campo | Notas |
|---|---|---|---|---|
| 0 | — | 1 | flags NFC (`00`) | |
| 1 | — | 1 | `A5` | prefijo |
| 2 | — | 1 | `00` | consumido como primer byte != A5 |
| 3 | 0 | 2 | `sec_version` | **Lingo = 3**; muestras Libre 3 en comentario: 1 (`NFCc:36-37`) |
| 5 | 2 | 2 | `localization` (región) | solo se registra en log (`NFCc:88-94`); valores Lingo no documentados |
| 7 | 4 | 2 | `puckgen` (generación) | solo log |
| 9 | 6 | 2 | `wearduration` | minutos. Muestra Libre 3 `C0 4E` = 0x4EC0 = 20160 = 14 d |
| 11 | 8 | 4 | `firmwareversion` | solo log; muestra `1E 0D 01 01` |
| 15 | 12 | 1 | **`producttype`** | **Lingo = 9** (`NFCc:103, 309`); muestras Libre 3 = 4 |
| 16 | 13 | 1 | `warmup` | unidades de 5 min: `warmup*5` min (`NFCc:88, 302`); muestra `0C`=60 min |
| 17 | 14 | 1 | `state` | **1 = sin activar → comando de activación `A0`**; otro → toma de control `A8` (`NFCj:52, 78`). Valores 6 y 8 → sensor terminado (`NFCc:264-272`). Muestras: 04, 01 |
| 18 | 15 | 9 | `serialnumber` | ASCII, 9 chars (muestra `3036385A4D524631 38` = "068ZMRF18") |
| 27 | 24 | 2 | `crc16` | Juggluco no lo valida; es CRC16 Abbott de los 24 B previos, LE (§1.7) |

Ejemplos del comentario (`NFCc:36-37`): `00A500 0100 0100 0000 C04E 1E0D0101 04 0C 04 3036385A4D524631 38 2F97` (state=4) y `… 04 0C 01 … 164A` (state=1). Son de Libre 3, no de Lingo (producttype 4).

### 1.3 Condiciones de aceptación como Lingo
- `lingoPatchSecurityVersion` (`NFCc:100-105`): error de parseo → **-1**; `producttype != 9` → **0** (= Libre 3, camino normal); `producttype == 9` → `sec_version` si ≠0, y si `sec_version == 0` → **-1**.
- `NFCj:41-49`: si el resultado ≠ 0 (incluye -1) → exige **exactamente 3**; si no, log "Unsupported Lingo security version or invalid patch info" y `return 0L` (fallo). Si es 3, activa con `secondWithID(..., manual != -1 ? manual : 1001L)`.
- Tras la activación se persiste `lingo = (producttype==9)` y `lingoSecurityVersion = sec_version` en el registro del sensor (`NFCc:309-310`; campo en `SGD:417, 464`). `getLingoSecurityVersion` devuelve 0 (Libre 3), la versión, o **-1** si hay flag lingo pero versión 0 ("necesita re-escaneo", `BT:37-43`).
- La detección de Lingo se basa **solo** en producttype=9 (+sec_version=3). `localization`/`puckgen` no intervienen.

### 1.4 Comando de activación / toma de control (NFC, 13 bytes)
`NFCj:70-89`:
```
cmd = 02 | (state==1 ? A0 : A8) | 7A | payload[10]
payload[0..3]  = u32 LE (nowSec - 1)          // DP:68 (a = p4 - 1)
payload[4..7]  = u32 LE accountId (receiver)   // DP:69
payload[8..9]  = CRC16 (ver abajo), byte bajo primero  // DP:79-80
```
CRC (`DP:46-62`): poly 0x1021, init 0xFFFF, **cada byte de entrada se invierte bit a bit (`bitrev8`) antes de XOR en el byte alto**, sin reflejar la salida, sin XOR final; el resultado se guarda `lo, hi`. Vectores `static_assert` (`DP:87-95`), con entradas de 8 bytes:

| Entrada (8 B) | CRC |
|---|---|
| `00 00 00 00 00 00 00 00` | `0x313E` |
| `01 00 00 00 00 00 00 00` | `0xCCBF` |
| `08 00 00 00 0C 00 00 00` | `0x2063` |

### 1.5 Receiver ID (accountId) — Lingo vs Libre 3
| | Lingo | Libre 3 |
|---|---|---|
| ID usado | `manualLibreAccountIDnumber()` si ≠ -1, **si no la constante 1001** (`NFCj:48`) | manual si existe; si no `getlibreAccountIDnumber()` / "nuevo receiver ID" con lógica activar/takeover y reintento con el otro ID si el sensor responde error `B1` (`NFCj:50-68`) |
| Formato en el comando | idéntico (u32 LE en bytes 4-7 del payload) | idéntico |
| Reintento con otro ID | **no** | sí (solo takeover, `!activate`) |

El origen/significado de 1001 no se explica en el código.

### 1.6 Respuesta de activación (`interpret3NFC2`, `NFCc:141-154, 219-316`)
- Éxito: **19 bytes** (`struct nfc2`, packed): `zero[1] | response[2] | deviceAddress[6] | pin[4] | activationTime u32 | crc16[2]`. Dirección BLE: bytes en orden inverso `inbuf[5..0]` (`NFCc:174-176`). `pin` = 4 bytes crudos (se usan tal cual en el challenge, §5.3). `activationTime<=0` → hora actual.
- Error: **4 bytes** `00 | A5 01 | err` (`recogn==0x01A5`). `err==0xB1` → rechazo de account-ID (retorno 1); si no, `state 8` o `6` → sensor terminado (códigos 5/6); otro → 3.
- Se crea el sensor con `warmup=first.warmup*5`, `wearduration=first.wearduration` (`NFCc:302`). Defaults si 0: warm-up 60 min, desgaste 14·24·60 min (`SGD:784-799`).

### 1.7 patchInfo de 64 B en activación, 27-oct

**Hecho (registro real, 17:55).** Dos sesiones NFC de activación terminaron con `patchInfo inválido (64 B)` y el sensor siguió en `state 1` (lo confirmaron las lecturas `0xA1` de diagnóstico de 17:55:22 y 17:55:37). El tercer intento recibió la respuesta de 19 B y llegó a `warmingUp`.

**Dónde se produce (código anterior al arreglo).**
- `Packages/RoundWhiteDiscKit/.../Pairing/CoreNFCActivationReader.swift:69-74`: cada `scan()` abre una `NFCTagReaderSession` nueva. Su primer comando es **un único** `0xA1` (mismo código y mismos parámetros vacíos en `.readPatchInfo` y en `.activateFreshSensor`), sin reintento. El resultado se parsea con `Libre3NFCPatchInfo(raw:)` **antes** de mirar el modo. Si el parseo falla, se sale por el `catch` (`:155-156`) y **nunca se llega al `0xA0`** (`:90`). Por eso el sensor no cambió de estado.
- `NFCActivationModels.swift:52-56` (antes): `normalizeResponse` solo admite `A5 …` o `00 A5 …`. Después, el guard exige `count >= 29 && frame[0] == 00 && frame[1] == A5`. **Una respuesta de 64 B que empezara por `00 A5` o `A5` habría pasado**, porque el guard es `>=`. Por tanto, los 64 B no empezaban por la cabecera esperada.
- `LingoScan/Services/NFCServiceError.swift:39,55` (antes): el error del fork llevaba los bytes, pero la app solo conservaba la longitud. **No hay forma de saber hoy qué contenían esos 64 B.**

**Hipótesis del encargo, descartada en parte.** No hay una segunda lectura `0xA1` dentro de la misma sesión NFC, ni una concatenación de bloques en el código: el lector lee `0xA1` una sola vez por sesión. La lectura de diagnóstico y la de activación son el mismo comando con el mismo parser, así que el parser no distingue entre los dos caminos. Lo que varió fue **la respuesta que entregó CoreNFC** en esas dos sesiones.

**Causa más probable.** El primer intercambio de la sesión fue transitorio o malformado: llegaron 64 B con algo antes de la cabecera, o sin la trama. Sin los bytes no se puede confirmar. Juggluco tiene en cuenta exactamente este caso: **repite `0xA1` hasta 10 veces** y acepta la respuesta cuando el bit de error está a 0 (§1.1, `AlgNfcV.java:49-51`). El fork no reintentaba.

**Hallazgo nuevo: el CRC de `firstnfc` se puede verificar.** Es el mismo CRC16 Abbott del comando de activación (§1.4) aplicado a los 24 bytes de datos del struct (offsets 3..26 del frame), guardado con el byte bajo primero. Coincide con las dos muestras de `NFCc:36-37` (`2F97` y `164A`) y con el fixture sintético del fork. Sigue sin confirmarse con una trama Lingo real (la `0xA1` real del 27-oct no se guardó).

**Corrección (fork + app).**
1. `Libre3NFCPatchInfo(raw:)` (`NFCActivationModels.swift:66-75, 137-166`): el camino directo no cambia (tampoco valida el CRC, para no rechazar tramas Lingo que hoy pasan). Si el camino directo falla, busca dentro de la respuesta una secuencia `A5…A5 00 + 26 B` **cuyo CRC coincida** y la normaliza a 29 B. Sin CRC válido sigue lanzando `invalidPatchInfo`.
2. `Libre3NFCActivationSequence` (archivo nuevo, se puede probar en macOS, y `CoreNFCActivationReader` lo usa): repite `0xA1` hasta **3 veces en la misma sesión NFC** si no parsea o si el intercambio falla. `0xA0` se envía **como máximo una vez**, solo tras un `0xA1` válido de esa misma sesión y solo si `state == 1`. Su respuesta nunca se reintenta.
3. App: `NFCServiceError.invalidPatchInfo(length:head:a5Offset:)` registra longitud, los 3 primeros bytes y la posición del primer `A5`, nunca el serial. Si la trama se extrajo de una respuesta más larga, el coordinador lo deja en el registro (`0xA1 de la activación normalizado …`).
4. Reintentos de la app: D-22. Un intento que falla antes de que el sensor acepte `0xA0` reutiliza la sesión y el Receiver ID (`SensorSessionCoordinator.swift:228`, `reusableActivation`).

**Pendiente.** Guardar los bytes de la próxima respuesta anómala (sin el serial) para confirmar la causa. Comprobar el CRC con una `0xA1` Lingo real; ya existe la de la sesión activa (`patchInfoRaw` en el Keychain), pero no se lee desde aquí.

---

## 2. Plano cifrado BLE (común a Libre 3 y Lingo)

### 2.1 Claves de sesión
Tras el challenge (§5.3) se obtienen `kEnc` (16 B) e `ivEnc` (8 B) (`GC:802-803, 812`). Inicializan `bcrypt` (`BC:123-130`, `outCryptoSequence=1`). **Este cifrado de canal es idéntico para Lingo y Libre 3** (comentario de `LC:50`: "Sensor data uses the existing native CCM path").

### 2.2 Formato del paquete cifrado (cualquier characteristic de datos) — `BC:112-121, 156-174`
```
paquete = ciphertext[n] | tag[4] | counter[2]       (longitud total n + 6)
nonce13 = counter[0..1] (tal cual, 2 B)  |  packetDescriptor[kind] (3 B)  |  ivEnc (8 B)
AES-128-CCM, clave = kEnc, nonce 13 B, tag 4 B, sin AAD
```
- El texto cifrado va primero, luego el tag CCM de 4 B, luego los 2 B de contador que se copian **sin transformar** a `nonce[0..1]` (`BC:116`). Longitud mínima aceptada: 7 (`BC:162`).
- Parámetros CCM (tinycrypt, `ccm_mode.c:39-266`): estándar RFC 3610 con **M=4, L=2** (nonce 13). B0: flags `= 0x08 | 0x01 = 0x09` (sin AAD), nonce, longitud del plaintext en 2 B **big-endian**. Bloques de contador: flags `0x01`, nonce, contador de 2 B big-endian; el keystream de datos empieza en contador **1**; el tag se enmascara con el bloque de contador **0** (`E(A0)[0..3]`). CBC-MAC con relleno de ceros del último bloque.
- Implementación en Swift: CryptoKit no ofrece CCM; implementar con AES-ECB (CommonCrypto) como hace `LC:273-307` pero con nonce de 13 B y L=2 (generalizar `L = 15 - nonceLen`).

`packetDescriptor` (`BC:33-41`) — **kind → 3 bytes**:

| kind | uso | descriptor (hex) | citas |
|---|---|---|---|
| 0 | comando escrito en PATCH_CONTROL (app→sensor) | `00 00 00` | `GC:1752` |
| 1 | respuesta en PATCH_CONTROL | `00 00 0F` | `GC:1369` |
| 2 | PATCH_STATUS | `00 00 F0` | `GC:1803` |
| 3 | GLUCOSE_DATA (tiempo real) | `00 0F 00` | `GC:1711` |
| 4 | HISTORIC_DATA | `00 F0 00` | `GC:1060` |
| 5 | CLINICAL_DATA (fast data) | `0F 00 00` | `GC:1146` |
| 6 | EVENT_LOG | `F0 00 00` | `GC:1209` |
| 7 | FACTORY (sin usar) | `44 00 00` | `BC:41` |

Cifrado saliente (`BC:80-94`): `nonce[0..1] = outCryptoSequence (LE, empieza en 1, ++ por mensaje)`, kind 0; salida = `ciphertext | tag | nonce[0] nonce[1]`.
Verificación del tag: falla → `intDecrypt` devuelve null → Java hace `recover()`/desconexión (`GC:1712-1715, 1804`).

### 2.3 Fragmentación de GLUCOSE_DATA — `GC:1699-1731`, `GC:1243`
- Búfer de reensamblado `oneMinuteRawData`: **57 bytes para Lingo** (35 para Libre 3), fijado en `resolveLingoVersion` (`GC:1243`).
- Cada notificación se copia al final del búfer sin cabecera ni número de secuencia (concatenación pura). Si `oneMinuteReadingSize + len > 57` o `len==0` → `recover` (reconexión).
- Cuando `size >= 57` se descifra el bloque entero con kind 3: 51 B texto + 4 B tag + 2 B contador = 57 → plaintext **51 B** (Lingo) ó 29 B (Libre 3). `decr.length != 51` → `recover`.
- **Tamaño de los fragmentos individuales: no determinable del código** (depende del MTU/ATT; el código es agnóstico). Con ATT_MTU 23 serían 20+20+17 [INFERENCIA, no en el repo].
- Las demás characteristics (historic, clinical, status, control) llegan completas en **una** notificación y se descifran individualmente (no hay reensamblado).

---

## 3. Trama de tiempo real (plaintext de 51 B, packet type 3)

Fuente: `H:19-93`, `C:21-140`. Equivalente Libre 3 (29 B): `struct oneminute` `BT:131-145` (lifeCount@0, reading@2, rate@4, esa@6, projected@8, histLC@10, histReading@12, trend:3@14, uncappedCur@15, uncappedHist@17, temp@19, fastdata[8]@21).

### 3.1 Mapa de la trama

| Offset | Tamaño | Campo | Descripción | Cita |
|---|---|---|---|---|
| 0 | 2 (u16) | `lifeCount` | minutos desde activación del sensor | `C:47, 77` |
| 2 | 2 (u16) | `historicLifeCount` | lifeCount al que corresponde el valor histórico (múltiplo de 5 en capturas) | `C:48, 78` |
| 4 | 15 | bloque de analito **canal 0** | ver §3.2 | `C:52-53, 101` |
| 19 | 15 | bloque de analito **canal 1** | ver §3.2 | idem |
| 34 | 1 | mapa de tipos | nibble bajo = tipo ch0, nibble alto = tipo ch1 | `C:49, 80-82` |
| 35 | 2 | sin decodificar | `00 00` en todas las capturas | [DERIVADO] |
| 37 | 2 (u16) | `temperature` | 1/100 °C sin signo; `0x8000` = inválida | `C:50, 130-137` |
| 39 | 12 | sin decodificar | ver §3.4 | [DERIVADO] |
| **Total** | **51** | | `LINGO_REALTIME_LEN` | `H:50` |

Códigos de analito (`H:55-60`, de `GKAnalyteType` decompilado): 0 INACTIVE, **1 GLUCOSE**, 2 KETONE, 3 LACTATE.

### 3.2 Bloque de analito (15 B, offsets relativos al inicio) — `C:55-63`

| Rel. | Tamaño | Campo (constante `GlucoseKetoneSPL`) | Uso en Juggluco |
|---|---|---|---|
| 0 | u16 | `RESULT_CAPPED` lectura "limitada" | bit15 inválido; `&0x0FFF` mg/dL; `(v&0x6000)>>13` rango de resultado (no usado) |
| 2 | s16 | `RATE_OF_CHANGE` | 0.01 mg/dL/min con signo; `-32768 (0x8000)` = desconocido |
| 4 | u16 | `EXTENDED_CODE` | **no usado** (0 en capturas) |
| 6 | u16 | `PROJECTED` | **no usado** (`FFFF` o valores como `0x3C28`) |
| 8 | u16 | `HISTORIC_CAPPED` | glucosa histórica limitada (mismas reglas que offset 0) |
| 10 | u8 | `ACTIONABLE_TREND` | `& 0x07` = tendencia; bit 3 (`0x08`) = bandera "accionable" separada; bits altos ignorados |
| 11 | u16 | `RESULT_UNCAPPED` | lectura sin recortar; bit15 inválido; `&0x0FFF` |
| 13 | u16 | `HISTORIC_UNCAPPED` | histórica sin recortar |

Las constantes y offsets proceden del decompilado de la app Lingo (`C:38-46`, `H:31-35`).

### 3.3 Cómo se extrae la glucosa (`lingo_parse_realtime`, `C:73-140`)
1. `len` debe ser 51 (si no → -2); punteros nulos → -1 (`C:74-75`).
2. Se lee el mapa de tipos @34: `ch0 = b & 0x0F`, `ch1 = b >> 4` (`C:80-82`).
3. Se itera ch = 0, 1 y se toma **el primer canal cuyo tipo == GLUCOSE (1)**; se leen sus campos de **su propio bloque** (ch0 @4, ch1 @19) y se hace `break` (`C:98-128`). Los canales inactivos nunca contribuyen a rate/trend (test `T:159-189`).
4. **Canal 1**: en todas las capturas el tipo es `0x10` → ch0 INACTIVE, **ch1 GLUCOSE**; por tanto la glucosa está en el bloque @19, `cappedReading` en bytes 19-20 (`T:90-97`). El JNI documenta "Channel 1 is glucose on the supported Lingo v3 sensors" (`BT:538-539`).
5. Glucosa limitada: `capped & 0x8000 == 0` → `glucose_valid=true`, `mg/dL = capped & 0x0FFF` (**escala 1**, entero mg/dL) (`C:103-106`). Rate = s16 @+2. Trend = `byte@+10 & 0x07`, y `>5 → 0` (valores 6 y 7 reservados → 0) (`C:107-109`).
6. Histórica limitada (@+8), sin limitar actual (@+11) e histórica sin limitar (@+13): misma regla (bit15 → inválido, `&0x0FFF`) (`C:112-126`).
7. Temperatura: `raw == 0x8000` → inválida; resto → `valid`, valor centi-°C **sin signo** (incluye 32769..65535 como positivos) (`C:130-137`, test `T:214-228`).
8. Valores iniciales cuando no hay canal glucosa: `valid=false, rate=-32768, trend=0` (`C:88-97`; test `T:203-206`).

**Tendencia** (`H:74-77`): 0 desconocida, 1 bajando rápido, 2 bajando, 3 estable, 4 subiendo, 5 subiendo rápido. Si `rate == -32768`, Juggluco usa `rate = (trend-3)*1.3` mg/dL/min (o NaN si trend==0) (`BT:148-155, 257-258`).

**Banderas de calidad/validez:**
| Bit/valor | Dónde | Significado |
|---|---|---|
| `0x8000` | cada palabra de lectura (+0, +8, +11, +13) | dato inválido / "data-quality flag" (warm-up o error). **Nunca** se reporta como número (`H:68-71`) |
| `0x6000` (`>>13`) | lectura limitada | "result range" (0..3). En la captura de 201 mg/dL vale 2 (`0x40C9`). Significado exacto **no determinado** |
| bit 12 (`0x1000`) | lecturas | descartado por la máscara `0x0FFF`; sin semántica documentada |
| `0x08` | byte de tendencia | "accionable"; separado de la tendencia |
| `0x8000` | temperatura | inválida |
| `-32768` | rate | desconocida |

**Cetona y lactato:** solo existen los códigos de tipo (2, 3). **Juggluco no decodifica sus bloques**; el único uso es un test que pone `typemap=0x32` y comprueba que no se emite glucosa (`T:204-206`). No hay layout específico de cetona/lactato en el repo.

### 3.4 Bytes sin decodificar (observados)
- @35-36: `00 00` en las 11 capturas.
- @39-50 (12 B) en las capturas: `6d 00 11 0c ba 49 68 0f 00 08 00 00`, `70 00 08 07 b1 49 4f 0e 00 00 00 00`, `70 00 16 06 ec 49 1c 0e …`, etc. Los primeros 4 B parecen `u16 constante (0x6d..0x71)` + `u16 variable`; los últimos 8 B recuerdan al `fastdata[8]` de Libre 3 (`BT:144`) [INFERENCIA]. Juggluco no los usa.

### 3.5 Camino de almacenamiento y validación (de plaintext a lectura guardada)
`saveLingoMinuteL` (`BT:355-378`): copia los campos a una `oneminute` de Libre 3 y reutiliza `save3current`/`save3history`. Con `#define UNCAPPED 1` (`BT:24`) **se guardan los valores SIN recortar**, no los de `RESULT_CAPPED`:

| Paso | Regla | Cita |
|---|---|---|
| valor actual | `uncappedCurrentMgDl` (@+11); si inválido → 0 | `BT:370, 215` |
| clamp | `v<39 && v>0 → 39`; `v>501 && v<1000 → 501`; `v≥1000` se deja (resultará inválido) | `BT:215-224` |
| válido | `39 ≤ v ≤ 501` (`validglucosevalue`) | `BT:157-159` |
| tiempo | `expect = lifeCount2time(lc)`; si `now - expect > 15 s` se usa `expect`; si no se usa `now` y se actualiza el mapeo | `BT:230-238` |
| `lifeCount2time` | sin referencia previa: `starttime + 60*(lc+1)`; con referencia: `timelastcurrent - 60*(lastlc - lc)` | `SGD:2476-2486` |
| inválido | se guarda un registro "solo ID" con 0, `sensorerror=true` (se muestra error durante 10 min) | `BT:263-268`, `SGD:2490-2492` |
| histórico en la misma trama | `uncappedHistoricMgDl` (@+13) con el mismo clamp; inválido → 0; se guarda en `idpos = round(historicLifeCount/5)` | `BT:172-193, 160-171` |
| rate | `rate = (roc == -32768) ? trend2rate(trend) : roc/100.0` mg/dL/min | `BT:257-258` |

Almacenamiento interno: `mgL = 10 × mg/dL` (décimas) — detalle de Juggluco, no del protocolo. Para Swift/HealthKit basta con mg/dL entero.

---

## 4. `patchStatus` (PATCH_STATUS, kind 2)

`struct Patchstatus` (packed, `BT:596-612`), tamaño 12 B (Libre 3). Lingo acepta **12 ó 14 bytes** (`BT:623-627`: `len==12 || (isLingo && len==14)`). Los 2 B adicionales de Lingo están **tras los campos comunes** (offsets 12-13) y Juggluco los ignora; el comentario dice "two additional analyte bytes" (`BT:623`).

| Offset | Tamaño | Campo | Uso |
|---|---|---|---|
| 0 | s16 | `lifeCount` | solo log |
| 2 | s16 | `errorData` | log |
| 4 | s16 | `eventData` | log (`4000 + eventData`) |
| 6 | s8 | `index` | índice de evento (se devuelve en bits 16+) |
| 7 | s8 | `patchState` | guardado en el sensor (`BT:637`) |
| 8 | s16 | `currentLifeCount` | se usa para el backfill (`BT:639`) |
| 10 | s8 | `stackDisconnectReason` | log |
| 11 | s8 | `appDisconnectReason` | log |
| 12 | 2 B | (solo Lingo) analitos | ignorados |

Paquete cifrado: 12+6 = 18 B (Libre 3) ó 14+6 = 20 B (Lingo).
`patchState`: la UI usa `state != 0 && state != 4 && isLibre3` → "no listo" si `<4`, "terminado" si `>4`; **4 = operativo** (`appcurve.cpp:2976-2982`). No hay una tabla completa de estados (warmup/terminado) en el código; el aviso de warm-up en la práctica viene de la bandera de calidad en la trama de 51 B (§3), no de `patchState`.
Uso: `currentLifeCount < 0` → ignorar (`GC:1809`). Si no hay backfill en curso, se inicia (`GC:1814-1818`): `backFillStartHistoricLifeCount = ((currentLifeCount - 16)/5)*5`, `backFillStartLifeCount = currentLifeCount`.

---

## 5. Cripto específica de Lingo (solo diferencias con Libre 3)

### 5.1 Selección
- Solo **versión de seguridad 3** (`LC:74-76`: `getKeyIndexFromVersion(3)=0`, otras → -1; `NFCj:44`).
- `LingoSKB` (`LS:31-105`) es un **adaptador de errores**: construye un `LingoCrypto` y envuelve cada operación en try/catch (log + `null`/`false`). No añade lógica criptográfica. Expone `create, canResume, getKeyIndexFromVersion, initECDH, getAppCertificate, setPatchCertificate, generateEphemeralKeys, generateKAuth, encrypt, decrypt, exportAuthorizationKey`.
- Libre 3 usa la librería nativa `KEYSCrypto` (2 claves de app, contexto de 176 B); Lingo usa JCA con credenciales propias (`LC:50`). `GC` bifurca por `lingoskb != null` (`GC:760, 784, 805, 1005-1020, 1484, 1542`).

### 5.2 Parámetros de `LingoCrypto`
| Elemento | Valor | Cita |
|---|---|---|
| Curva | secp256r1 (P-256) | `LC:65-67` |
| Certificado del parche | **140 B**: ECDSA-SHA256 sobre `cert[0..75]` (76 B); firma `r‖s` (2×32 B) en `cert[76..139]`; clave pública del parche (punto sin comprimir `04‖X‖Y`, 65 B) en `cert[11..75]`. Firma verificada con `PATCH_SIGNING_PUBLIC` | `LC:115-128, 252-265` |
| Certificado de la app | blob `APP_CERTIFICATE` de 162 B enviado en `SEC_CERT_DATA` | `LC:110-113` |
| Efímera de la app | par P-256 nuevo; se envía `04‖X‖Y` (65 B) | `LC:130-144` |
| Efímera del parche | 65 B (`04‖X‖Y`), validada en curva | `GC:1022-1032`, `LC:220-232` |
| `kAuth` (clave de autorización, 16 B) | `SHA256( 00 00 00 01 ‖ ECDH(ephemeral_app_priv, patch_ephemeral_pub) ‖ ECDH(APP_PRIVATE, patch_cert_pub) )[0..15]` | `LC:146-166` |
| AES-CCM del challenge | **implementado a mano** sobre AES-ECB con `kAuth`: **M=4, L=8, nonce de 7 B**; B0 flags `0x0F`; contador flags `0x07`; sin AAD | `LC:168-205, 267-307` |
| Registro de autorización guardado (149 B) | `"JLNGKA01"[8] ‖ version[1] ‖ 00 00 00 ‖ kAuth[16] (@12) ‖ relleno 0 ‖ SHA-256 de bytes 0..116 en los últimos 32 B (@117)`; `canResume` valida magia, versión y hash | `LC:52-54, 93-108, 207-218` |

Diferencia relevante: el CCM del **challenge** usa nonce de 7 B / L=8, mientras que el **canal de datos** (§2) usa nonce de 13 B / L=2.

### 5.3 Challenge y derivación de `kEnc`/`ivEnc` (necesario para el plano de datos) — `GC:741-824`, `GC:954-966`
1. Sensor → app por `SEC_CHALLENGE_DATA`: 23 B = `r1[16] ‖ nonce1[7]` (reensamblado en fragmentos `[seq][datos]`, seq empieza en 0 y debe ser consecutivo, `GC:706-733`).
2. App → sensor: `plain36 = r1[16] ‖ r2[16] ‖ pin[4]` (r2 aleatorio, `pin` = 4 B crudos de la activación NFC); se cifra con `LingoCrypto.encrypt(nonce1, plain36)` → **40 B** (`GC:752-764`), se escribe en `SEC_CHALLENGE_DATA` en fragmentos de `[offset u16 LE][≤18 B]` = 20 B (`GC:1446-1479`), luego comando de seguridad `8`.
3. Sensor → app: 67 B = `ciphertext+tag[60] ‖ nonce[7]`; `decrypt` → **56 B** = `r2[16] ‖ r1[16] ‖ kEnc[16] ‖ ivEnc[8]`. Se exige `r2` y `r1` iguales a los enviados (`GC:778-803`).
4. `kEnc`/`ivEnc` inicializan el canal de datos (`initcrypt`, §2). Se persiste el registro de 149 B (`setLibre3kAuth`).

Comandos de seguridad (byte único a `SEC_COMMAND_RESPONSE`): `1` inicio (sin autorización guardada), `2` pedir/enviar cert de app, `3` tras enviar cert (o `14` si ya hay autorización), `0x0D` tras recibir cert del parche (140 B), `17 (0x11)` tras recibir la efímera del parche (65 B), `9` tras notificación `04` (cert aceptado), `8` tras enviar el challenge. Con autorización guardada: comandos `17` y `14` directos (`GC:1198-1203`). Notificaciones `[8,n]`, `[10,n]`, `[15,n]` anuncian el tamaño `n` de la siguiente transferencia por `CHALLENGE_DATA`/`CERT_DATA` (`GC:1404-1443`).

### 5.4 Blobs de `LingoCredentials.java` (NO copiados)
| Blob | Archivo:líneas | Tamaño | Cabecera (2 primeros bytes) | Notas |
|---|---|---|---|---|
| `APP_PRIVATE` | `LCr:29-33` | 32 B | n/a (escalar P-256 crudo; **no se reproduce**) | clave privada estática de la app |
| `APP_CERTIFICATE` | `LCr:35-50` | 162 B | `03 01` | bytes 2..13 son ASCII (`DROIDALDADC0`). Hay un `04` en el offset 33; 33 + 65 + 64 = 162, consistente con `cabecera(33) ‖ clave pública 04‖X‖Y (65) ‖ firma (64)` [INFERENCIA, mismo esquema que el cert del parche de 140 B = 11+65+64] |
| `PATCH_SIGNING_PUBLIC` | `LCr:52-59` | 65 B | `04 e7` (`04` = punto sin comprimir; `e7` = primer byte de X) | clave pública que verifica el cert del parche |

Comentario del archivo: "Protocol credentials for Lingo security version 3, verified against its app certificate" (`LCr:26`).

---

## 6. Historial y clínico (comandos y respuestas)

### 6.1 Formato de petición (7 B, plaintext antes del kind 0) — `BT:681-719`
```
struct RequestData (packed): int8 kind[2]; int8 arg; int32 from  (LE)    // 7 bytes
```
| Comando | `kind[0..1]` | Libre 3 | **Lingo** | Cita |
|---|---|---|---|---|
| Historial 5 min | `01 02` | `01 00` | `01 02` (`lingoControlHistory`) | `BT:712-715` |
| Clínico (minuto) | `01 03` | `01 01` | `01 03` (`lingoClinicalControl`) | `BT:716-719` |
| Log de eventos | `04 …` | `04 | int32 | 00 00` (7 B) | **igual (sin variante Lingo)** | `BT:721-731` |

Resultado: `01 02 arg from[4]` y `01 03 arg from[4]`. Siempre se invoca con `arg = 1` (`GC:1784, 1795`); el significado de `arg` no se documenta. Se cifra con kind 0 (→ 13 B) y se escribe en `PATCH_CONTROL`; una cola serializa los comandos (`GC:1735-1771`). La respuesta/ack llega en `PATCH_CONTROL` (kind 1); `decr[0]==1` solo provoca un redibujado (`GC:1368-1372`) y limpia `backFillInProgress`.

**Rango de lifeCounts:** la petición solo lleva el límite inferior `from` (int32); el sensor envía desde `from` hasta lo actual. El límite superior no se especifica en la petición.

| Petición | Condición de envío | `from` | Cita |
|---|---|---|---|
| `{1,2}` historial | `((currentLC-16)/5)*5 > lastHistoricLifeCountReceived` | `max(lastHistoricLifeCountReceived, 5)` | `GC:1776-1788` |
| `{1,3}` clínico | `lastLifeCountReceived < currentLC` (`getlastLifeCountReceived` devuelve `último + 1`) | `lastLifeCountReceived` (ese +1) | `GC:1790-1800`, `BT:271-278` |

Se lanza desde `receivedpatchstatus` solo si no hay otro backfill en curso (`GC:1814`).

### 6.2 Respuesta de historial (HISTORIC_DATA, kind 4) — `saveLingoHistory`, `BT:540-568`
Plaintext (tras descifrar), longitud **4..14, par** (1..6 valores por notificación; cifrada ≤ 20 B):

| Offset | Tamaño | Campo | Regla |
|---|---|---|---|
| 0 | u16 | `start` | **bit 15 debe estar a 1**, si no se descarta toda la notificación (`return false`). `lifeCount = start & 0x7FFF`. El comentario del código lo relaciona con "canal 1 es glucosa; rechazar canal 0" [CÓDIGO: comentario `BT:538-539`; la interpretación bit15=canal1 es INFERENCIA] |
| 2 + 2·i | u16 | `raw[i]` | `raw == 0` → fin (`break`). Bit 15 → inválido; `v = raw & 0x0FFF`; válido si `39 ≤ v ≤ 501` |

- Cada valor `i` corresponde a `lifeCount + 5·i` (intervalo de 5 min, `SGD:772-779`) y a la posición `idpos = round(lifeCount/5) + i`.
- Se guarda `10 × v` (décimas). Los inválidos se **omiten** (no se guardan ceros). Avanza el puntero de último historial y `endhistory`.
- Diferencia con Libre 3 (`saveLibre3History`, `BT:470-527`): ahí `lifeCount` es u16 sin bandera, `n = len/2 - 1` sin tope, los valores no se enmascaran con `0x0FFF` y solo se comprueba el rango.

### 6.3 Respuesta clínica / "fast data" (CLINICAL_DATA, kind 5) — `saveLingoFastData`, `BT:570-594`
Plaintext **exactamente 14 B** (Libre 3: `struct fastData`, `BT:380-389`):

| Offset | Tamaño | Campo | Regla Lingo |
|---|---|---|---|
| 0 | u16 | `lifeCount` codificado | **bit 15 = 1 obligatorio** (si no → `return false`); `lifeCount = v & 0x7FFF` |
| 2 | 8 | `rawData[8]` | no usado |
| 10 | u16 | lectura actual | bit15 inválido; `&0x0FFF`; rango 39..501 |
| 12 | u16 | lectura histórica | idem |

Lógica:
- `histcount = lifeCount < 22 ? 0 : ((lifeCount - 17)/5)*5` (`BT:581`). (Libre 3: `round((lc-19)/5)*5`, `BT:385-387`.)
- Si la histórica es válida: se guarda en `histcount` (×10) y se avanza el historial consecutivo.
- Si la actual es válida: `tiempo = lifeCount2time(lc)`; se guarda solo si `tiempo ≥ 1666476000` (22-oct-2022) y no hay ya un registro con ese ID; se guarda como lectura de flujo (×10) (`BT:584-590`). No se usa el camino de alarmas/pantalla (es retro-llenado).
- `fastupdatelifecount(lc)` se llama siempre; devuelve `true` aunque no haya lecturas válidas (`BT:592-593`).

### 6.4 Qué registros se consideran válidos (resumen)
| Fuente | Condición |
|---|---|
| Tiempo real | tipo glucosa en un canal; palabra sin bit15; (almacenado: sin recortar, clamp a 39..501, rechazar ≥1000 o 0) |
| Histórico en trama RT | `uncappedHistoric` sin bit15, clamp + 39..501; si no → se guarda 0 |
| Historial 5 min | primera palabra con bit15; cada valor ≠0, sin bit15, `&0xFFF` en 39..501 |
| Clínico | palabra de lifeCount con bit15; lectura sin bit15, 39..501; tiempo ≥ 1666476000 |

---

## 7. Límites y validaciones

| Tema | Valor/regla | Cita |
|---|---|---|
| Rango válido de almacenamiento | **39–501 mg/dL** (con clamp previo 1–38→39; 502–999→501) | `BT:157-159, 215-224` |
| Rango de pantalla Lingo | máx **200**, mín 40 (`getmaxmgdL()` → 200 si `isLingo()`); solo afecta a clasificación/recorte en UI (`g.cpp:990`, `curve.cpp`, `watchvalue.cpp`), **no** al almacenamiento | `SGD:2548-2566` |
| Máscara de lectura | `0x0FFF` (0..4095) | `C:65` |
| Bandera de calidad | `0x8000` → nunca se emite número | `C:66, 103` |
| Warm-up | no hay umbral fijo en el protocolo; viene del byte `warmup` del NFC (`×5` min), por defecto 60 min si 0. En las capturas los 4 primeros minutos (lc 1–4) están marcados inválidos y lc 58 ya es válido | `SGD:794-802`, `T:68-71, 122` |
| Temperatura en warm-up | `0x8000` (inválida) en lc 1–4 | `T:105-108` |
| Vida útil | `wearduration` del NFC (min); por defecto 14·24·60 = 20160 min (14 d). Fin esperado = inicio + wear + 12 min | `SGD:784-789, 819-821` |
| Guardas de longitud | RT=51 (`H:50`, `BT:357`, `GC:1712`); historial 4..14 y par (`BT:544`); fast=14 (`BT:572`); status 12/14 (`BT:624`); reensamblado ≤57 (`GC:1703`) | |
| Seguridad | solo versión 3 (`NFCj:44`); bytes de `kEnc/ivEnc` 16/8; challenge 23→67→56 | |
| Cifrado | tag CCM de 4 B; fallo → null → reconexión (`recover`) | `BC:156-174`, `GC:1712` |
| Tiempo mínimo aceptado (fast data) | 1666476000 | `BT:439, 586` |
| Desfase de reloj | si `now - expected > 15 s` el sello de tiempo se deriva de `lifeCount` | `BT:232-238` |
| `assert`s | únicamente en el test host (`T:177-211, 224-226`); sin `assert` en producción | |
| Lecturas descartadas | inválidas → registro "error de sensor" (`sensorerror`) durante 10 min (Libre) | `BT:263-268`, `SGD:2490` |

---

## 8. Vectores de prueba (`lingo_realtime_test.c`)

El archivo solo compila con `-DLINGO_REALTIME_SELFTEST` (`T:38`; comando de build en `T:33-35`). Contiene **plaintexts ya descifrados de 51 B**, capturados de un sensor real del autor (las claves de sesión se leyeron del `GKSBCSecurityContext` en vivo, `T:22-24`). **No hay claves, nonces ni bloques cifrados**, por lo que no sirven para probar el descifrado CCM. Tampoco está en el repo `lastunixtime.txt` (citado en `T:159`).

### 8.1 Warm-up — `VECTORS[]` (`T:67-72`): 4 tramas (lc 1..4), ch0=INACTIVE, ch1=GLUCOSE (typemap `0x10`), `glucose_valid=false`, `rate=-32768`, `trend=0`, `temperature_valid=false`
| Nombre | Línea | lifeCount | Hex (51 B) |
|---|---|---|---|
| prior#1 | `T:68` | 1 | `01000000008000800000ffff00800800800080208000800000ffff0080082080008010000000806d00110cba49680f00080000` |
| prior#2 | `T:69` | 2 | `02000000008000800000ffff00800800800080208000800000ffff00800820800080100000008070000807b1494f0e00000000` |
| live#1 | `T:70` | 3 | `03000000008000800000ffff00800800800080208000800000ffff00800820800080100000008070001606ec491c0e00000000` |
| live#2 | `T:71` | 4 | `04000000008000800000ffff00800800800080008000800000ffff0080080080008010000000807000d805fe490d0e00000000` |

Esperado (asserts por `printf/ok`, `T:85-108`): `life_count` = 1..4; `channel0_type==0`; `channel1_type==1`; `glucose_valid==false`; `rate_of_change==-32768 && trend==0`; `temperature_valid==false`. `historic_life_count = 0` [DERIVADO]. En lc1-3 las palabras de ch1 @+0 y @+11 valen `0x8020` (inválidas con carga 0x20); en lc4 `0x8000` [DERIVADO].

### 8.2 Calentado — `WARM[]` (`T:121-124`): glucosa **201 mg/dL** (capturada; la app Lingo mostraba 201 en lc 63, `T:116-120`)
| Nombre | Línea | lifeCount | Hex |
|---|---|---|---|
| warm lc58 | `T:122` | 58 | `3a002800008000800000ffff00800800800080c94000800000ffff008008c9000080100000d30c7000b808764de60e00000000` |
| warm lc63 | `T:123` | 63 | `3f002d00008000800000ffff00800800800080c94000800000ffff008008d0000080100000b90c70000109e14ced0e00000000` |

Esperado (`T:131-133`): `rc==0`, `life_count`, `channel1_type==1`, `glucose_valid`, `glucose_mgdl==201`. `raw@19 = 0x40C9`: bit15 limpio, rango `0x4000`, lectura `0x0C9 = 201` (`T:119-120`).
[DERIVADO]: `historic_life_count` = 40 (lc58) y 45 (lc63); sin recortar @30: `0x00C9`=201 (lc58) y **`0x00D0`=208 (lc63)** — Juggluco almacena el valor sin recortar (208), mientras el test solo verifica el recortado (201); temperatura 0x0CD3 = 32.83 °C (lc58), 0x0CB9 = 32.57 °C (lc63); histórica @27 = 0x8000 (inválida) en ambas; rate = -32768, trend = 0 (byte @29 = `0x08`).

### 8.3 Rate/trend — `TRENDS[]` (`T:161-172`): 6 tramas reales con valores esperados `{rate, trend}`
| Línea | Hex | rate | trend |
|---|---|---|---|
| `T:166` | `0938F5370080EDFF0000FFFF00800B008000809D00EDFF0000283C9C000B9D009C0010000000806E0024074F48091100080000` | -19 | 3 |
| `T:167` | `4438313800808EFF0000FFFF00800A0080008089008EFF0000E02EAC000A8900AC001000000F0C7000C90609495D1000000000` | -114 | 2 |
| `T:168` | `49383638008034FF0000FFFF00800900800080780034FF0000C422A300097800A300100000100C710063060F49E70F00000000` | -204 | 1 |
| `T:169` | `BB3AA73A008000010000FFFF00800D008000809E0000010000904C63000D9E006300100000040B70004F052243F41100000000` | 256 | 5 |
| `T:170` | `473B333B008000800000FFFF00800B008000809B0000800000FFFFC3000B9B00C300100000320C7100F007D3497C1100000000` | -32768 | 3 |
| `T:171` | (= warm lc58) | -32768 | 0 |

[DERIVADO] (no asserted por el test; calculado del hex): lifeCount / histLC / glucosa limitada (=sin recortar) / histórica / temperatura:
| Línea | lc | histLC | mg/dL | hist mg/dL | temp |
|---|---|---|---|---|---|
| `T:166` | 14345 | 14325 | 157 | 156 | 0x8000 (inválida) |
| `T:167` | 14404 | 14385 | 137 | 172 | 30.87 °C |
| `T:168` | 14409 | 14390 | 120 | 163 | 30.88 °C |
| `T:169` | 15035 | 15015 | 158 | 99 | 28.20 °C |
| `T:170` | 15175 | 15155 | 155 | 195 | 31.22 °C (rate desconocido, trend 3) |

(Todas con typemap `0x10`; cumplen `histLC = ((lc-17)/5)*5`, coherente con §6.3.)

Bucle de test (`T:173-189`): para cada trama, tras comprobar `{rate,trend}`, **se intercambian los dos bloques de analito enteros** (`buf[4..18] ↔ buf[19..33]`), se pone `buf[34]=0x01` (ch0=GLUCOSE) y se contamina el bloque ahora inactivo (`buf[21]=0x7b, buf[22]=0x00, buf[29]=0x0c`); el resultado `{rate,trend}` debe ser el mismo.

### 8.4 Casos sintéticos adicionales
| Líneas | Qué verifica |
|---|---|
| `T:140-157` | glucosa en canal 0: copia `buf[19..20]`→`buf[4..5]`, pone ch1 inválido (`00 80`), typemap `0x01` → 201 mg/dL, `channel0_type==GLUCOSE` |
| `T:190-202` | sobre `TRENDS[0]`: `buf[21]=150,buf[22]=0,buf[29]=0xfc` → `rate==150`, `trend==4` (bits altos ignorados); `buf[29]=6` y `7` → `trend==0` |
| `T:203-206` | `buf[34]=0x32` (cetona+lactato, sin glucosa) tras un parseo previo → `glucose_valid==false, rate==-32768, trend==0` (no se arrastra estado) |
| `T:207-210` | `NULL` entrada → -1; `NULL` salida → -1; `len-1` y `len+1` → -2 |
| `T:214-228` | temperaturas `{0, 3054, 32767, 0x8000, 32769, 65535}` en `buf[37..38]` sobre trama de ceros: `temperature_valid == (raw != 0x8000)`; `temperature_centi == (raw==0x8000 ? 0 : raw)` |

### 8.5 Otros vectores reutilizables del repo
- CRC de activación: tres entradas/CRC en `DP:87-95` (§1.4).
- Ejemplos de patchInfo Libre 3 en `NFCc:36-37` (para probar el parser, no producttype 9).

---

## 9. Diferencias Lingo vs Libre 3 (resumen del plano de datos)

| Aspecto | Libre 3 | Lingo |
|---|---|---|
| NFC producttype / sec_version | ≠9 (muestras 4) / 1 | **9** / **3** |
| Receiver ID | cuenta Libre (con fallback) | manual o **1001** |
| Handshake | `KEYSCrypto` nativo | `LingoCrypto` (ECDH P-256, SHA-256 KDF, CCM 7 B nonce) |
| Cifrado del canal de datos | CCM 13 B nonce / L=2 / M=4 | **igual** |
| GLUCOSE_DATA cifrado | 35 B → 29 B | **57 B → 51 B** |
| Canales de analito | 1 (glucosa) | 2 (mapa de tipos @34; glucosa en ch1 en las capturas) |
| Estado del parche | 12 B | **14 B** (+2) |
| Comandos historial/clínico | `{1,0}` / `{1,1}` | **`{1,2}` / `{1,3}`** |
| Historial | `lifeCount` sin bandera, valores sin máscara | `lifeCount|0x8000`, máscara `0x0FFF`, `0` termina |
| Fast data | `lifeCount` sin bandera, `histLC=round((lc-19)/5)*5` | `lifeCount|0x8000`, `histLC=((lc-17)/5)*5` (0 si lc<22), máscara/bandera en lecturas |
| Máx. glucosa (UI) | 500 | 200 |
| Lectura inválida | valor fuera de rango | bit15 por palabra |

---

## 10. Lo que no pude determinar

1. Significado de `localization` y `puckgen` para Lingo, y valores reales de `wearduration` / `warmup` / `state` de un Lingo (no hay captura NFC de Lingo en el repo; las muestras son Libre 3 con producttype 4).
2. Origen/semántica del receiver ID por defecto `1001` (`NFCj:48`).
3. Tamaños de los fragmentos BLE individuales de los 57 B (el código es agnóstico; depende del MTU).
4. Bytes 35-36 y 39-50 de la trama de 51 B (valores observados en §3.4); campos `EXTENDED_CODE` (+4) y `PROJECTED` (+6) del bloque de analito; significado de `result range` (bits 13-14) y del bit 12; bits altos del byte de tendencia (solo se sabe que se ignoran).
5. Por qué la captura de 201 mg/dL lleva rango `0x4000` y el comentario hable de rango de visualización 40–200 (`H:84`): el valor recortado no se recorta a 200 en la captura.
6. Layout de los bloques de cetona y lactato (solo existen los códigos 2 y 3).
7. Los 2 bytes extra de `patchStatus` de Lingo; tabla completa de `patchState` (solo se sabe 4 = operativo, `>4` = terminado, `<4` no listo).
8. Significado de `arg` (siempre 1) en `{1,2}`/`{1,3}`, de `decr[0]` en la respuesta de PATCH_CONTROL, y cómo el sensor delimita el final del rango solicitado.
9. Que el bit 15 de la primera palabra de historial/fast data indique "canal 1" es solo inferencia a partir de un comentario.
10. Descifrado de FACTORY_DATA (kind 7) y esquema del EVENT_LOG específico de Lingo (se asume igual al de Libre 3).
11. Vectores de prueba **con** texto cifrado, claves o nonces: no existen en el repo; hay que generarlos con un sensor real o validar el CCM con vectores externos (RFC 3610 usa M=8, no M=4).
12. Duración real de calentamiento de Lingo: no está en el protocolo del código (solo flags de calidad y `warmup*5` del NFC).
13. Detalles del camino "autorización guardada" (comandos 14/17) más allá de lo citado en `GC:1198-1203`, y nombre/anuncio BLE del dispositivo Lingo (no analizado).
14. No existe `changes.html` ni changelog de Juggluco con notas sobre Lingo; no se examinó el historial git.
