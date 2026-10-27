# Fase 3 — dejar la app lista sin activar el sensor

Objetivo pedido por Juampa (2026-10-27): llegar al paso inmediatamente anterior a la activación con todo verificado, de modo que activar sea solo tocar el botón de confirmación cuando él lo decida. Ningún paso de esta lista envía `0xA0` ni `0xA8`.

## Checklist (en orden)

| # | Paso | Quién | Cómo se verifica | Estado |
|---|---|---|---|---|
| 1 | App instalada con la versión que incluye Fase 2a (Health, archivo `.lingoscan`, recuperación, alarmas, Datos/Ajustes) | Fable | `devicectl` instala; la app arranca; Ajustes muestra versión y commit | hecha (build `191b1ed` con la corrección de Recuperación instalada el 27-oct) |
| 2 | Identidad importada en el iPhone: AirDrop de `Credentials/lingo-identity.json` → LingoScan → Ajustes muestra `lingo-v3`, familia Lingo, claves de firma: sí | Juampa + Fable | Captura de Ajustes; `Documents/Inbox` sin restos | hecha (Juampa: "funciona") |
| 3 | Frase de recuperación elegida por Juampa (≥ 12 caracteres o 6 palabras), guardada fuera del teléfono | Juampa | Confirmación verbal; no se anota en ningún documento | hecha (Juampa la tiene fuera del teléfono) |
| 4 | Carpeta de iCloud Drive elegida en Datos (Q-06 del contrato) | Juampa | Datos muestra la carpeta y estado `icloud_uploaded` tras una exportación | hecha (`iCloud Drive/LingoScan`; Juampa: "funciona") |
| 5 | Exportación manual del paquete `.lingoscan` y verificación externa: `python3 -I ../LingoScan_Shared/tools/verify_archive.py <paquete>` → exit 0 | Fable | Salida del verificador | hecha: dos paquetes exportados a las 16:07 (`…210717Z-8782c63c`, `…210724Z-83ea88aa`), ambos `VALIDO` con `verify_archive.py` (exit 0) |
| 6 | Importación de ese paquete de vuelta en la app (idempotente: 0 nuevas, 0 conflictos) | Fable | Resumen de importación | hecha (16:5x): Juampa importó el paquete propio desde Datos; la app no cambió nada (el paquete lleva 1 sesión `prepared`, 0 lecturas, 0 eventos; 0 nuevas, 0 conflictos) |
| 7 | Exportación manual del archivo de recuperación con la frase; apertura en el Mac con `tools/recovery_vectors_check.py`-style (abrir con la frase) → carga válida contra `recovery_payload.schema.json` | Fable | Salida; la frase no se pega en ningún log | hecha (16:46): 4 archivos en `iCloud Drive/LingoScan`, sobre y carga válidos contra los esquemas, abiertos en el Mac con la frase tecleada en un prompt oculto (`sequence` 1–4, misma sesión y `attempt_id`, estado `prepared`, Receiver ID coincide con el anotado). La copia 2 lleva el material de identidad (interruptor encendido); 3 y 4 son toques repetidos de "Exportar ahora". Tras la corrección de carpeta |
| 8 | Reinstalación de prueba NO se hace con la app real: la restauración desde otro bundle ID queda para R-03 con LingoScan_Astra | — | — | fuera de alcance aquí |
| 9 | Lectura NFC de solo lectura repetida con el sensor que se va a usar (ya hecha una vez el 27-oct: Lingo 9/3, estado 1) | Juampa | Pantalla Sensor "Listo para activar" | hecha (1 vez) |
| 10 | Receiver ID generado y persistido en estado `prepared`: en Sensor tocar "Activar sensor" abre la confirmación tras generar y guardar el Receiver ID y exportar el archivo de recuperación con `sequence 1`; **cancelar** la confirmación deja el intento en `prepared` sin enviar nada. Juampa anota el Receiver ID completo que muestra la pantalla | Juampa + Fable | Archivo `*.lingoscan-recovery.json` nuevo en la carpeta; Sensor sigue en "Listo para activar"; `event_log` sin comandos NFC de escritura | hecha en parte: Receiver ID generado y confirmación cancelada (captura 16:08; Juampa lo anotó fuera). La copia de `prepared` quedó **pendiente** porque no había frase en memoria; sale sola al dar la frase |
| 11 | Escaneo BLE pasivo de 60 s para confirmar que no hay otros sensores Libre/Lingo anunciando cerca (LingoScan_Astra en pausa o cerrada) | Fable | Log del coordinador | pendiente |
| 12 | Backup final: segunda exportación `.lingoscan` + recuperación (`sequence 2` si hubo cambios) y copia del archivo de recuperación al Mac | Juampa | Archivos presentes en dos sitios | pendiente |

### Corrección del 27-oct (paso 7)

Las capturas de Juampa (16:08 y 16:09) mostraron en Recuperación "Se guarda en Documentos de la app: aún no hay carpeta elegida" pese a tener la carpeta elegida en Datos, y el aviso "la frase debe tener al menos 12 caracteres". Causa: `RecoveryService` recibía `Documents/` como carpeta fija y nunca leía el bookmark de T-10. Cambios (commit `191b1ed`):

- `RecoveryService` resuelve en cada exportación el mismo bookmark con alcance de seguridad que el archivo `.lingoscan` (carpeta elegida > contenedor iCloud propio > `Documents/`; un bookmark que ya no resuelve se marca `unavailable` y la UI pide elegir de nuevo). La escritura va dentro de `startAccessingSecurityScopedResource`.
- Frase: interruptor opcional "Recordar en el Llavero" (`AfterFirstUnlockThisDeviceOnly`, sin iCloud; D-21). "Olvidar frase" borra la copia. El botón "Usar frase" solo se activa con 12 caracteres o más tras recortar bordes, y pulsar Intro con el campo vacío ya no dispara el aviso.
- Al arrancar, `installRecovery()` llama a `start()`: con frase recordada, las exportaciones pendientes salen sin abrir la pantalla.
- Tests nuevos: `RecoveryFolderAndPassphraseTests` (3). App: 155 tests.
- Segunda captura de Juampa (16:39): el campo de la frase se veía como una fila en blanco, sin forma de comprobar lo escrito ni de confirmar que ya la guardó fuera. Rediseño (Sonnet, revisado por Fable): hoja "Frase de recuperación" con campo y botón de ojo, repetición de la frase con estado en vivo, interruptor obligatorio "Ya guardé la frase fuera del teléfono", "Recordar en el Llavero" apagado por defecto y botón "Usar frase" que solo se activa con todo correcto. Sin `textContentType(.newPassword)` para que iOS no ofrezca guardar la frase en el Llavero de iCloud. En Recuperación queda la fila de estado (Sin frase / En memoria / En el Llavero) con "Introducir frase…" u "Olvidar frase". App: 161 tests.

Cuando los 12 estén en verde, la activación es: Sensor → "Activar sensor" → revisar resumen → interruptor "entiendo que es irreversible" → botón. Antes de ese toque, Juampa lo confirma por escrito en el chat (regla de `CLAUDE.md`).

## Qué NO está probado y no se puede probar sin activar

- Que el sensor acepte el certificado de app Lingo (incógnita principal).
- Reparto real de los 57 bytes en fragmentos BLE; condiciones de backfill; relleno de la clave efímera a 72 bytes.
- Reconexión corta con kAuth tras reinicio.

## Si la activación falla

Fase 3b de `PLAN.md`: no reactivar, no cambiar receptor, guardar `event_log` redactado y el archivo de recuperación (`state: failed` o `sent`), comparar con `docs/PROTOCOLO_LINGO.md` §5.3 y decidir el parche.
