# Fase 3 — dejar la app lista sin activar el sensor

Objetivo pedido por Juampa (2026-10-27): llegar al paso inmediatamente anterior a la activación con todo verificado, de modo que activar sea solo tocar el botón de confirmación cuando él lo decida. Ningún paso de esta lista envía `0xA0` ni `0xA8`.

## Checklist (en orden)

| # | Paso | Quién | Cómo se verifica | Estado |
|---|---|---|---|---|
| 1 | App instalada con la versión que incluye Fase 2a (Health, archivo `.lingoscan`, recuperación, alarmas, Datos/Ajustes) | Fable | `devicectl` instala; la app arranca; Ajustes muestra versión y commit | pendiente |
| 2 | Identidad importada en el iPhone: AirDrop de `Credentials/lingo-identity.json` → LingoScan → Ajustes muestra `lingo-v3`, familia Lingo, claves de firma: sí | Juampa + Fable | Captura de Ajustes; `Documents/Inbox` sin restos | pendiente |
| 3 | Frase de recuperación elegida por Juampa (≥ 12 caracteres o 6 palabras), guardada fuera del teléfono | Juampa | Confirmación verbal; no se anota en ningún documento | pendiente |
| 4 | Carpeta de iCloud Drive elegida en Datos (Q-06 del contrato) | Juampa | Datos muestra la carpeta y estado `icloud_uploaded` tras una exportación | pendiente |
| 5 | Exportación manual del paquete `.lingoscan` y verificación externa: `python3 -I ../LingoScan_Shared/tools/verify_archive.py <paquete>` → exit 0 | Fable | Salida del verificador | pendiente |
| 6 | Importación de ese paquete de vuelta en la app (idempotente: 0 nuevas, 0 conflictos) | Fable | Resumen de importación | pendiente |
| 7 | Exportación manual del archivo de recuperación con la frase; apertura en el Mac con `tools/recovery_vectors_check.py`-style (abrir con la frase) → carga válida contra `recovery_payload.schema.json` | Fable | Salida; la frase no se pega en ningún log | pendiente |
| 8 | Reinstalación de prueba NO se hace con la app real: la restauración desde otro bundle ID queda para R-03 con LingoScan_Astra | — | — | fuera de alcance aquí |
| 9 | Lectura NFC de solo lectura repetida con el sensor que se va a usar (ya hecha una vez el 27-oct: Lingo 9/3, estado 1) | Juampa | Pantalla Sensor "Listo para activar" | hecha (1 vez) |
| 10 | Receiver ID generado y persistido en estado `prepared`: en Sensor tocar "Activar sensor" abre la confirmación tras generar y guardar el Receiver ID y exportar el archivo de recuperación con `sequence 1`; **cancelar** la confirmación deja el intento en `prepared` sin enviar nada. Juampa anota el Receiver ID completo que muestra la pantalla | Juampa + Fable | Archivo `*.lingoscan-recovery.json` nuevo en la carpeta; Sensor sigue en "Listo para activar"; `event_log` sin comandos NFC de escritura | pendiente |
| 11 | Escaneo BLE pasivo de 60 s para confirmar que no hay otros sensores Libre/Lingo anunciando cerca (LingoScan_Astra en pausa o cerrada) | Fable | Log del coordinador | pendiente |
| 12 | Backup final: segunda exportación `.lingoscan` + recuperación (`sequence 2` si hubo cambios) y copia del archivo de recuperación al Mac | Juampa | Archivos presentes en dos sitios | pendiente |

Cuando los 12 estén en verde, la activación es: Sensor → "Activar sensor" → revisar resumen → interruptor "entiendo que es irreversible" → botón. Antes de ese toque, Juampa lo confirma por escrito en el chat (regla de `CLAUDE.md`).

## Qué NO está probado y no se puede probar sin activar

- Que el sensor acepte el certificado de app Lingo (incógnita principal).
- Reparto real de los 57 bytes en fragmentos BLE; condiciones de backfill; relleno de la clave efímera a 72 bytes.
- Reconexión corta con kAuth tras reinicio.

## Si la activación falla

Fase 3b de `PLAN.md`: no reactivar, no cambiar receptor, guardar `event_log` redactado y el archivo de recuperación (`state: failed` o `sent`), comparar con `docs/PROTOCOLO_LINGO.md` §5.3 y decidir el parche.
