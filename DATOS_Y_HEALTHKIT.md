# Datos, archivo portable y HealthKit

Objetivo: que ningún dato se pierda al reinstalar o reemplazar la app, y que cualquier otra herramienta pueda leerlo. Tres copias con funciones distintas:

| Copia | Para qué | Sobrevive a |
|---|---|---|
| **SQLite** en el contenedor de la app | Fuente operativa: consultas, gráficas, outbox | Re-firma y actualización (mismo bundle ID). No a borrar la app |
| **Archivo `.lingoscan`** en la carpeta de iCloud Drive elegida por el usuario | Contrato abierto: importable por esta app, por la app de prueba o por un script | Borrar la app, cambiar de iPhone, cambiar de app |
| **Apple Health** | Repositorio canónico de glucosa y carbohidratos para otras apps y reportes | Borrar la app (las muestras quedan), cambio de iPhone con respaldo cifrado |

## Por qué SQLite y no Mongo (respuesta a la pregunta de Juampa)

SQLite sí corre dentro de la app: iOS lo incluye en el sistema (`libsqlite3`) y es lo que usan Core Data y SwiftData por debajo. No necesita servidor ni proceso aparte. MongoDB no puede ejecutarse en iOS; su SDK embebido (Realm / Atlas Device SDK) fue descontinuado por MongoDB en 2024-2025. Subir los datos a una API en un servidor de Juampa es una buena **cuarta copia**, y ya existe un estándar para CGM que usa Mongo: **Nightscout**. En la Fase 4 LingoScan puede subir `entries` a un Nightscout en Docker en ese servidor. No sustituye a las tres copias locales: la lectura debe seguir funcionando sin red.

Se usa SQLite a través de la API C del sistema (`import SQLite3`) envuelta en un actor pequeño, sin librerías de terceros. El esquema documentado abajo es parte del contrato.

## Esquema SQLite (v1)

```sql
PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA user_version = 1;

CREATE TABLE sensor_sessions (
  session_id        TEXT PRIMARY KEY,          -- UUID generado al activar
  family            TEXT NOT NULL,             -- 'lingo'
  product_type      INTEGER NOT NULL,          -- 9
  security_version  INTEGER NOT NULL,          -- 3
  serial_redacted   TEXT NOT NULL,             -- 3 primeros caracteres + '…'
  serial_hash       TEXT NOT NULL,             -- SHA-256 del serial, para dedupe sin exponerlo
  firmware          TEXT,
  warmup_minutes    INTEGER NOT NULL,
  wear_minutes      INTEGER NOT NULL,
  activated_at_utc  TEXT NOT NULL,             -- ISO 8601
  ended_at_utc      TEXT,
  receiver_id       INTEGER NOT NULL,
  ble_address       TEXT,                      -- MAC
  peripheral_uuid   TEXT,                      -- CBPeripheral.identifier
  last_life_count   INTEGER,
  identity_label    TEXT NOT NULL              -- 'lingo-v3'
);

CREATE TABLE readings (
  record_id         TEXT PRIMARY KEY,          -- '<session_id>:<life_count>:glucose'
  session_id        TEXT NOT NULL REFERENCES sensor_sessions(session_id),
  life_count        INTEGER NOT NULL,
  measured_at_utc   TEXT NOT NULL,             -- derivado de life_count y activated_at (regla única)
  received_at_utc   TEXT NOT NULL,
  tz_at_capture     TEXT NOT NULL,             -- 'America/Bogota'
  origin            TEXT NOT NULL,             -- 'live' | 'backfill_history' | 'backfill_fast' | 'import'
  analyte           TEXT NOT NULL,             -- 'glucose'
  unit              TEXT NOT NULL,             -- 'mg/dL'
  value_mgdl        INTEGER,                   -- valor elegido (uncapped) o NULL si excluido
  capped_mgdl       INTEGER,
  uncapped_mgdl     INTEGER,
  historic_mgdl     INTEGER,
  rate_centi        INTEGER,                   -- 0.01 mg/dL/min; NULL si -32768
  trend             INTEGER,                   -- 0..5
  temperature_centi INTEGER,
  quality_flag      INTEGER NOT NULL,          -- bit 15 presente
  range_bits        INTEGER,                   -- (raw & 0x6000) >> 13
  eligible          INTEGER NOT NULL,          -- 1 apto para Health y gráfica
  exclusion_reason  TEXT,                      -- 'qualityFlag' | 'outOfRange' | 'warmUp' | 'synthetic' | 'duplicate'
  decoder_version   TEXT NOT NULL,
  revision          INTEGER NOT NULL DEFAULT 1,
  raw_hex           TEXT                       -- solo si diagnóstico privado está activo
);
CREATE INDEX readings_time ON readings(measured_at_utc);

CREATE TABLE events (                          -- comidas, ejercicio, notas
  event_id    TEXT PRIMARY KEY,                -- UUID
  kind        TEXT NOT NULL,                   -- 'meal' | 'exercise' | 'note'
  at_utc      TEXT NOT NULL,
  carbs_g     REAL,
  text        TEXT,
  revision    INTEGER NOT NULL DEFAULT 1,
  deleted     INTEGER NOT NULL DEFAULT 0       -- tombstone
);

CREATE TABLE health_outbox (
  record_id   TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,                   -- 'glucose' | 'carbs'
  revision    INTEGER NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT,
  exported_at_utc TEXT                         -- NULL hasta que Health confirma
);

CREATE TABLE archives (
  archive_id  TEXT PRIMARY KEY,
  created_at_utc TEXT NOT NULL,
  path        TEXT NOT NULL,
  readings    INTEGER NOT NULL,
  sha256      TEXT NOT NULL,
  verified    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE event_log (
  id INTEGER PRIMARY KEY, at_utc TEXT NOT NULL, level TEXT NOT NULL,
  category TEXT NOT NULL, message TEXT NOT NULL                  -- siempre redactado
);
```

`measured_at_utc` se calcula como `activated_at + 60·life_count` corregido con la regla de Juggluco (si `now - esperado > 15 s`, manda el esperado). `record_id` no depende del reloj del teléfono.

## Archivo portable `.lingoscan`

Es una **carpeta** (paquete de documento) `LingoScan-<yyyyMMdd-HHmmss>Z-<archiveID>.lingoscan/` para no depender de una librería ZIP:

| Archivo | Contenido |
|---|---|
| `manifest.json` | `schemaVersion: 1`, `archiveID`, `createdAtUTC`, `app`, `appVersion`, `decoderVersion`, conteos, SHA-256 de cada archivo, `exportedBy` (bundle ID) |
| `sessions.json` | Filas de `sensor_sessions` sin `ble_address` ni `peripheral_uuid` |
| `readings.ndjson` | Una fila por línea con todos los campos de `readings` salvo `raw_hex` |
| `events.ndjson` | Eventos incluidos los tombstones |
| `health_ledger.ndjson` | `record_id`, `revision`, `exported_at_utc` (lo que ya está en Health) |
| `readings.csv` | `measured_at_local,measured_at_utc,value_mgdl,trend,origin,eligible,exclusion_reason` para humanos y hojas de cálculo |
| `schema/README.md` y `schema/readings.schema.json` | Para que otra implementación lo lea sin este código |

Reglas de escritura: exportar a una carpeta temporal, calcular hashes, renombrar al destino, y solo entonces registrar en `archives`. Conservar las últimas 7 copias y una mensual. Importación: validar manifest y hashes, rechazar `schemaVersion` futuro, cargar en una base temporal, unir por `record_id`/`event_id` + `revision` (gana la revisión mayor; los tombstones no resucitan), y solo al final fusionar. Importar tres veces el mismo archivo no cambia nada.

Destino: carpeta en iCloud Drive elegida con `fileImporter`/`UIDocumentPickerViewController` en modo carpeta, acceso persistido con bookmark con alcance de seguridad; si el bookmark caduca se pide de nuevo. Fallback: `Documents` del contenedor iCloud de la app (visible en Archivos → LingoScan). Cadencia: diaria por `BGAppRefreshTask`, al terminar un sensor, manual desde Datos, y obligatoria antes de reinstalar (el checklist lo exige).

## HealthKit

| Qué | Tipo | Metadatos |
|---|---|---|
| Glucosa elegible | `HKQuantityType(.bloodGlucose)`, `mg/dL`, `HKQuantitySample` con inicio = fin = `measured_at` | `HKMetadataKeySyncIdentifier` = `record_id`, `HKMetadataKeySyncVersion` = `revision`, `HKMetadataKeyWasUserEntered` = false, `com.otalvaro.lingoscan.session`, `.lifeCount`, `.origin`, `.trend` |
| Carbohidratos | `HKQuantityType(.dietaryCarbohydrates)`, gramos | `SyncIdentifier` = `event_id`, nota en `com.otalvaro.lingoscan.note` |
| Entrenamientos (lectura) | `HKWorkoutType` | Solo para superponer en la curva; nunca se escriben |

Los identificadores de sincronización hacen idempotentes los reintentos: Health reemplaza la muestra con la misma `SyncIdentifier` y versión mayor. La cola `health_outbox` se drena en orden; un fallo no bloquea al resto; cada intento se registra. La app no borra muestras de otras apps ni reexporta todo el historial importado de un archivo: lo que `health_ledger` marca como exportado se respeta.

**Matriz de elegibilidad** (fuente de verdad en `EligibilityPolicy`):

| Condición | Health | Gráfica | Se guarda |
|---|---|---|---|
| Sin bit 15, 39..501 mg/dL, fuera de calentamiento | Sí | Sí | Sí |
| Bit 15 (calidad) | No | Como hueco | Sí, `qualityFlag` |
| 1..38 o 502..999 | No (sin clamp a 39/501) | Marcador "fuera de rango" | Sí, `outOfRange` |
| Calentamiento (lifeCount < warmup) | No | Como hueco | Sí, `warmUp` |
| Dato sintético o de fixture | No | Solo en previews | Sí, `synthetic` |
| Duplicado de `record_id` con revisión menor o igual | No | — | No |

## Keychain y recuperación

Ver `ARQUITECTURA.md` §6. El export de recuperación cifra `{receiverID, sessions[{session_id, serial, pin, kAuth, ble_address}]}` con una clave derivada de una frase que Juampa guarda aparte; el formato (sal, iteraciones, nonce, versión) va en el propio archivo. Sin la frase no hay recuperación; sin el archivo tampoco. Probar con datos ficticios en la Fase 2 y con el sensor real en la Fase 3.

## Pruebas de aceptación (Fase 2)

| Caso | Resultado exigido |
|---|---|
| Exportar e importar | Mismos `record_id`, valores, banderas, tiempos, sesiones, eventos y revisiones |
| Importar tres veces | Sin duplicados ni cambios |
| Vivo + backfill del mismo minuto | Un solo registro; conflicto registrado en `event_log` |
| Corte durante la exportación | Copia anterior íntegra; temporal no registrada |
| Archivo corrupto o `schemaVersion` futuro | Rechazo con mensaje; base intacta |
| App con otro bundle ID (T-15) | Importa el `.lingoscan` y muestra el historial sin abrir la base original |
| Sin red o iCloud | Sigue guardando; Datos muestra "copia pendiente" |
| Health denegado o bloqueado | Outbox crece; captura continúa; se drena al volver |
| Reinstalar con Health poblado | No duplica muestras (SyncIdentifier) ni borra las anteriores |
| Zona horaria cambiada | `record_id` y `measured_at_utc` estables |
