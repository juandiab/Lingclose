# Referencias

## En esta carpeta

- `docs/PROTOCOLO_LINGO.md` — spec byte a byte del plano de datos Lingo (Juggluco 11.5.4, commit `e41f4aa`). Incluye los 12 vectores plaintext de 51 B y los CRC de activación.
- `docs/FORK_RWDK.md` — superficie pública de RoundWhiteDiscKit (commit `7dd6396`), estado a persistir, 15 cambios del fork clasificados, tests existentes, riesgos.
- `docs/DiaBLE_Lingo_recovered.swift.txt` — clases de la app oficial Lingo (`DCSCore`, `DCMGK`) recuperadas del commit `f181824^` de DiaBLE.

## En la carpeta del proyecto (`..`)

- `PROMPT.md`, `CLAUDE.md` — encargo original y reglas.
- `NOTAS.md` — bitácora compartida con Astra.
- `REPORTE_COMPATIBILIDAD_CLAUDE.md` — investigación de Claude, con correlación.
- `REPORTE_COMPATIBILIDAD_LINGO.md` — investigación de Astra, con adenda de identificación del sensor.
- `lingoScan_Astra/` — plan de Astra (`PLAN.md`, `CORRELACION.md`, `DATOS_PORTABLES.md`, `AGENTS.md`). Puntos adoptados aquí: canal por mapa de tipos, capped/uncapped separados, lista de claves no vacía, fixtures plaintext ≠ prueba cripto, Receiver ID persistido antes de activar, tres dominios de datos, tombstones, prueba con otro bundle ID, estados explícitos.

## Clones de solo lectura (scratchpad de la sesión, se pierden al cerrarla)

`/private/tmp/claude-501/-Users-juampa-Code-Projects-LingoScan/015d4607-873d-44f2-a991-d614c2e2df9a/scratchpad/`: `rwdk/`, `juggluco/`, `diable/`, `glucosedirect/`. En T-01 se vuelve a clonar RWDK dentro de `Packages/`; Juggluco se consulta por los enlaces de abajo.

## Repositorios

- RoundWhiteDiscKit: https://github.com/airedev326/RoundWhiteDiscKit (MIT). `README.md`, `protocol.md`, `Sources/RoundWhiteDiscKit/`.
- Juggluco: https://github.com/j-kaltes/Juggluco (GPL-3). Lingo: `Common/src/main/cpp/libre3/lingo_realtime.{h,c}`, `lingo_realtime_test.c`, `bluetooth.cpp`, `nfc.cpp`; `Common/src/libre3/java/tk/glucodata/LingoCrypto.java`, `LingoCredentials.java`, `LingoSKB.java`, `Libre3GattCallback.java`.
- xdripswift 7.2.0: https://github.com/JohanDegraeve/xdripswift/releases/tag/7.2.0 — copia interna del protocolo en `xDrip/BluetoothTransmitter/CGM/Libre/Libre3/Protocol/`.
- DiaBLE (archivado): https://github.com/gui-dos/DiaBLE.

## Apple

- Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- HealthKit sync identifier: https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- Acceso a carpetas elegidas por el usuario: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- Core Bluetooth en segundo plano y restauración de estado: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager
- Capacidades por tipo de cuenta: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Sensor: https://accessgudid.nlm.nih.gov/devices/00357599852009

## Skills

| Skill | Ruta |
|---|---|
| `swiftui-pro:swiftui-pro` | `/Users/juampa/.agents/skills/swiftui-pro/SKILL.md` + `references/` |
| `swiftui-liquid-glass` | `/Users/juampa/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-liquid-glass/SKILL.md` |
| `ios-design-agent-skill` | `/Users/juampa/.agents/skills/ios-design-agent-skill/SKILL.md` |
| `apple-design` | `/Users/juampa/.agents/skills/apple-design/SKILL.md` |
| `swiftpm-macos` | `/Users/juampa/.codex/plugins/cache/openai-curated-remote/build-macos-apps/0.1.4/skills/swiftpm-macos/SKILL.md` |
| `swiftui-animation`, `swiftui-microinteractions`, `swiftui-performance` | `/Users/juampa/.agents/skills/<nombre>/SKILL.md` |
| Otros útiles del mismo plugin de Codex | `swiftui-performance-audit`, `ios-debugger-agent`, `swiftui-ui-patterns` en `.../build-ios-apps/0.1.2/skills/` |

## Herramientas de la sesión

- XcodeBuildMCP (`mcp__XcodeBuildMCP__*`) para build, run y tests en simulador; `xcodebuild` y `xcrun devicectl` para el dispositivo (`00008150-001615E13E78401C`, "iPhone 17 JP").
- Simulador iOS (`mcp__Claude_Code_iOS_Simulator__control`) para capturas y pruebas de UI.
