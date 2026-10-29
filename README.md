# Lingclose

> [!CAUTION]
> **Proyecto experimental, personal y sin fines comerciales** para verificar el funcionamiento
> de biosensores de glucosa de uso continuo. **No es un producto de Abbott** ni está afiliado,
> patrocinado ni aprobado por Abbott. **No es un dispositivo médico**: no lo uses para decisiones
> de tratamiento. Lee [NOTICE.md](NOTICE.md) completo antes de compilar nada.
>
> **Experimental, personal, non-commercial project** to verify how continuous glucose biosensors
> work. **Not an Abbott product**, not affiliated with or endorsed by Abbott. **Not a medical
> device**: do not use it for treatment decisions. Read [NOTICE.md](NOTICE.md) first.

Lingclose es una app iOS escrita en SwiftUI que activa un biosensor de glucosa compatible por NFC,
recibe sus lecturas por Bluetooth LE, las guarda en una base SQLite local y en un archivo abierto
portable, y las escribe en Apple Health. Nació como proyecto personal de aprendizaje para entender,
byte a byte, cómo funciona un sensor de este tipo cuando la app oficial no está disponible en tu
país. Su autor no usa insulina ni toma decisiones médicas con estos datos.

El nombre interno del código, del target de Xcode y del bundle sigue siendo `LingoScan` por
compatibilidad con la instalación ya activa; el proyecto público se llama Lingclose.

## Qué hace

- **Activación por NFC** con confirmación explícita, mostrando lo que se va a enviar. El
  diagnóstico solo lee información del parche; nunca activa sin confirmación.
- **Sesión BLE** con handshake corto (reconexión) y completo (primer emparejamiento),
  reconexión indefinida en segundo plano y relleno de huecos con el histórico del sensor.
- **Almacenamiento abierto**: SQLite en el dispositivo, archivo `.lingoscan` en iCloud Drive y
  exportación de recuperación cifrada con frase de paso, para sobrevivir a una reinstalación.
- **Apple Health** como repositorio canónico de glucosa; nunca se exportan lecturas marcadas
  como dudosas por el sensor, fuera de rango ni de calentamiento.
- **Pantalla Hoy** con gráfica, estadísticas, diario de comidas y ejercicio, insights locales
  (subidas y bajadas rápidas, respuesta a comidas), alertas configurables y consejos por reglas.
- Español, inglés y portugués (pt-BR). iOS 26, Liquid Glass, Swift 6.2 con concurrencia estricta.

## Qué no hace

- No incluye credenciales de app, certificados ni claves. Sin ellas no empareja con un sensor;
  ver [`Credentials/README.md`](Credentials/README.md).
- No se distribuye: cada persona compila e instala su copia con su propio Apple ID.
- No sugiere medicación ni dosis. El asistente opcional rechaza cualquier respuesta sobre
  insulina o fármacos.
- No ha sido probado con más de un sensor ni con más de un iPhone.

## Requisitos

- macOS con Xcode 26 y [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- iPhone con NFC e iOS 26 o posterior, y un Apple ID para firmar la build localmente.
- Un sensor compatible (ver `docs/PROTOCOLO_LINGO.md` para la variante soportada) que **todavía
  no haya sido activado**: cada sensor se activa una sola vez.

## Compilar

```bash
xcodegen generate
```

```bash
xcodebuild -project LingoScan.xcodeproj -scheme LingoScan -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Cambia `PRODUCT_BUNDLE_IDENTIFIER` y `DEVELOPMENT_TEAM` en `project.yml` por los tuyos antes de
generar el proyecto. Los tests de la app corren en el simulador; NFC y BLE solo existen en un
iPhone real:

```bash
xcodebuild test -project LingoScan.xcodeproj -scheme LingoScan -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:LingoScanTests
```

Los paquetes Swift puros se prueban en el Mac con `swift test` dentro de `Packages/LingoCore` y
`Packages/RoundWhiteDiscKit`.

## Estructura

| Carpeta o archivo | Qué contiene |
|---|---|
| `LingoScan/` | La app: features por pantalla, servicios (sesión del sensor, credenciales, Health, alertas) y recursos |
| `Packages/LingoCore` | Dominio puro: modelos, políticas de elegibilidad, SQLite, archivo portable, recuperación |
| `Packages/RoundWhiteDiscKit` | Fork local de [RoundWhiteDiscKit](https://github.com/airedev326/RoundWhiteDiscKit) con soporte de la variante Lingo (`docs/FORK_RWDK.md`) |
| `LingoScanTests/`, `LingoScanHealthSimTests/` | Tests de la app y de la integración con Health en simulador |
| `Fixtures/` | Vectores de prueba sintéticos (AES-CCM, tramas de tiempo real) |
| `docs/PROTOCOLO_LINGO.md` | Especificación byte a byte del plano de datos, escrita a partir de Juggluco |
| `docs/FORK_RWDK.md` | Diseño técnico del fork de RoundWhiteDiscKit |
| `docs/T-*.md`, `docs/capturas/` | Cierre de cada tarea y capturas de pantalla |
| `PLAN.md`, `ARQUITECTURA.md`, `DATOS_Y_HEALTHKIT.md`, `DISENO_UI.md` | Plan por fases, módulos y contratos, esquema de datos, diseño de interfaz |
| `DECISIONES.md`, `TAREAS.md`, `REFERENCIAS.md` | Registro de decisiones, backlog y fuentes consultadas |
| `CLAUDE.md` | Reglas para los agentes de IA que trabajan en el repositorio |

## Cómo se construyó

El proyecto se desarrolló con agentes de IA (Claude Fable 5.1 como orquestador; Claude Opus y
Sonnet implementando) bajo dirección y revisión humana, con el sensor real del autor como único
banco de pruebas. `PLAN.md`, `TAREAS.md` y `DECISIONES.md` documentan ese proceso.

## Seguridad y privacidad

El repositorio no contiene claves, certificados, PIN, identificadores de receptor, números de
serie completos ni datos de sesión; `Credentials/`, los archivos `.lingoscan` y las bases SQLite
están en `.gitignore`. Los logs compartidos redactan los seriales. Si encuentras algo que no
debería estar aquí, abre un issue sin pegar el dato.

## Licencia y atribuciones

Lingclose se distribuye bajo la **GNU General Public License v3.0 o posterior** ([LICENSE](LICENSE)).
Se eligió GPL-3 porque la especificación del protocolo y parte de la lógica de decodificación se
escribieron estudiando [Juggluco](https://github.com/j-kaltes/Juggluco) (GPL-3).

- [RoundWhiteDiscKit](https://github.com/airedev326/RoundWhiteDiscKit), MIT: base del
  emparejamiento, transporte BLE y criptografía. Su licencia se conserva en
  `Packages/RoundWhiteDiscKit/LICENSE`; las adiciones del fork están bajo GPL-3.
- [Juggluco](https://github.com/j-kaltes/Juggluco), GPL-3: referencia del plano de datos y de
  la secuencia de activación de la variante soportada.
- [xDrip4iOS](https://github.com/JohanDegraeve/xdripswift) y [DiaBLE](https://github.com/gui-dos/DiaBLE):
  referencias de arquitectura y de interoperabilidad.

Lingo, FreeStyle Libre y Libre son marcas de Abbott, usadas solo para identificar los sensores
con los que este software interopera. Ver [NOTICE.md](NOTICE.md).
