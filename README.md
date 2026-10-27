# LingoScan_Claude

Espacio de trabajo de **Claude** (orquestador: Fable 5.1; implementación: subagentes Opus y Sonnet) para construir **LingoScan**, una app iOS propia en SwiftUI que lee biosensores Abbott Lingo por NFC + BLE sin la app oficial, escribe en Apple Health y guarda los datos en un formato abierto que sobrevive a un reemplazo de la app.

Juampa compara en paralelo este trabajo con el de Astra (`../lingoScan_Astra/`). Las dos carpetas son independientes; esta no modifica nada fuera de sí misma salvo `../NOTAS.md`.

## Estado

| Fecha | Estado |
|---|---|
| 2026-10-27 | Plan cerrado con las decisiones de Juampa. Sin código, sin build, sin sensor tocado. Esperando OK para la Fase 1. |

## Cómo está organizada la carpeta

| Archivo | Qué contiene |
|---|---|
| `PLAN.md` | Plan por fases con compuertas, criterios de salida y qué agente hace qué |
| `ARQUITECTURA.md` | Módulos, contratos, máquina de estados, concurrencia, estructura del proyecto Xcode |
| `DATOS_Y_HEALTHKIT.md` | Esquema SQLite, archivo portable, cola a HealthKit, Keychain y recuperación |
| `DISENO_UI.md` | Pantallas, Liquid Glass, tipografía, accesibilidad y qué skill se aplica en cada revisión |
| `DECISIONES.md` | Registro de decisiones (bundle ID, team, almacenamiento, alcance, credenciales) |
| `TAREAS.md` | Backlog de tareas con modelo asignado, archivos, criterios de aceptación y verificación |
| `REFERENCIAS.md` | Rutas y enlaces: clones de solo lectura, reportes, carpeta de Astra |
| `CLAUDE.md` | Reglas para cualquier agente que trabaje dentro de esta carpeta |
| `docs/PROTOCOLO_LINGO.md` | Especificación byte a byte del plano de datos Lingo (de Juggluco 11.5.4) |
| `docs/FORK_RWDK.md` | Diseño técnico del fork de RoundWhiteDiscKit |
| `docs/DiaBLE_Lingo_recovered.swift.txt` | Volcado de clases de la app oficial Lingo, recuperado del historial de DiaBLE |
| `Credentials/` | Solo un README. Los blobs de credenciales nunca se guardan aquí ni se commitean |

## Cómo empezar (Fase 1)

1. Leer `CLAUDE.md`, `PLAN.md` y `ARQUITECTURA.md`.
2. Tomar las tareas `T-01` a `T-04` de `TAREAS.md` en orden; cada una indica el modelo (Opus o Sonnet) y el skill que debe revisarla.
3. Nada se instala en el iPhone hasta `T-12`; nada toca un sensor hasta la Fase 3, con confirmación escrita de Juampa.

## Modelo de trabajo

Claude (Fable) planifica, reparte, verifica y decide. Opus implementa protocolo, criptografía, BLE y persistencia. Sonnet implementa UI, HealthKit, exportación, fixtures y documentación. Cada tarea termina con build y tests que Fable ejecuta por su cuenta antes de darla por cerrada. Detalle en `CLAUDE.md` y `TAREAS.md`.
