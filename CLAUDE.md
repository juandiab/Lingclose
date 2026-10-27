# Reglas para agentes en LingoScan_Claude

Hereda todo lo de `../CLAUDE.md` y `../PROMPT.md`. Lo de abajo lo concreta para esta carpeta.

## Roles

- **Fable (orquestador):** planifica, reparte tareas de `TAREAS.md`, verifica cada entrega con build, tests y diff, y mantiene `PLAN.md`, `DECISIONES.md` y `../NOTAS.md`. No escribe código de producción salvo correcciones de una línea.
- **Opus:** protocolo (fork de RoundWhiteDiscKit), criptografía, sesión BLE, máquina de estados, persistencia SQLite, migraciones.
- **Sonnet:** SwiftUI, HealthKit, exportación e importación, fixtures y tests de parser, documentación, localización.
- Una tarea = un agente = un conjunto de archivos. Dos agentes nunca escriben el mismo archivo en paralelo. El proyecto Xcode (`project.pbxproj`), la firma y las migraciones tienen un solo dueño por tarea.

## Entregables de cada tarea

Cada agente devuelve: archivos cambiados, comandos ejecutados con su salida real, tests añadidos y su resultado, limitaciones y dudas. Pasar tests no sustituye la revisión: Fable lee el diff contra el contrato de la tarea.

## Skills obligatorios

| Cuándo | Skill | Cómo |
|---|---|---|
| Cualquier archivo SwiftUI nuevo o modificado | `swiftui-pro:swiftui-pro` | El agente que escribe la vista la revisa con el skill antes de entregar; Fable vuelve a pasarlo en la verificación |
| Superficies con Liquid Glass | `swiftui-liquid-glass` (`/Users/juampa/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-liquid-glass/SKILL.md` + `references/liquid-glass.md`) | `GlassEffectContainer` para grupos, `.glassEffect` después de layout, `.interactive()` solo en elementos tocables |
| Auditoría visual de una pantalla terminada | `ios-design-agent-skill` | Con capturas del simulador; prioridad legibilidad > decoración |
| Gestos, sheets, transiciones, haptics | `apple-design` | Principios (respuesta inmediata, interrumpible, consistencia espacial); no trasladar CSS/JS |
| Animaciones SwiftUI | `swiftui-animation`, `swiftui-microinteractions` | Respetar Reduce Motion |
| Rendimiento de listas y gráficas | `swiftui-performance` | Antes de cerrar la Fase 2 |
| Paquete Swift puro (`LingoCore`, fork RWDK) | `swiftpm-macos` (`/Users/juampa/.codex/plugins/cache/openai-curated-remote/build-macos-apps/0.1.4/skills/swiftpm-macos/SKILL.md`) | `swift build` y `swift test` en el Mac para lógica sin NFC/BLE |
| Build e instalación en dispositivo | XcodeBuildMCP (`mcp__XcodeBuildMCP__*`) y `xcodebuild` | NFC y BLE solo existen en el iPhone real |

## Reglas técnicas

- iOS 26.0 mínimo, Swift 6.2, concurrencia estricta, SwiftUI puro. Sin UIKit salvo lo que exijan CoreNFC o compartir archivos.
- Sin dependencias SPM de terceros salvo el fork de RoundWhiteDiscKit (paquete local). Cualquier otra se propone a Juampa antes.
- Un tipo por archivo; carpetas por feature (ver `ARQUITECTURA.md`).
- Bundle ID `com.otalvaro.lingoscan`, team `SR8DQF26N7`. No se cambian nunca.
- Unidad de adquisición y almacenamiento: mg/dL entero. Conversión a mmol/L solo en presentación.
- Nunca se exporta a HealthKit un valor con bandera de calidad (bit 15), fuera de 39..501 mg/dL, de calentamiento ni sintético. Se guarda igual en SQLite con su motivo de exclusión.
- Nunca se escriben claves, PIN BLE, kAuth, números de serie completos ni datos sanitarios reales en código, fixtures, logs compartidos ni commits. `Credentials/` y `*.lingoscan` están en `.gitignore`.
- El diagnóstico NFC usa exclusivamente `Libre3NFCActivationReader.scan(mode: .readPatchInfo)` (comando `0xA1`). Ningún camino de diagnóstico puede llegar a `0xA0`/`0xA8`. La activación vive en una pantalla aparte que exige confirmación explícita y muestra lo que va a enviar.
- `sensorCertSigningKeys` nunca vacío: RoundWhiteDiscKit omite la verificación con lista vacía; LingoScan lo rechaza antes de conectar.
- Variante desconocida (`productType != 9` o `securityVersion != 3`) se informa como no compatible. No se intenta activar.
- Nada toca un sensor real sin confirmación escrita de Juampa en el chat. El primer sensor es de sacrificio; si falla, no se activa otro hasta entender la causa.

## Verificación de Fable por tarea

1. `git diff` contra los archivos permitidos de la tarea.
2. `swift test` (paquetes) o `xcodebuild test` (app) con la salida real pegada en el cierre de la tarea.
3. Skill de revisión correspondiente sobre los archivos tocados.
4. Actualizar `TAREAS.md` (estado, commit) y, si cambia una decisión, `DECISIONES.md`.
5. Commit en este repo con mensaje `T-nn: <qué>`.
