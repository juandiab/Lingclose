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
- **Reportes** con siete vistas de tus lecturas (resumen del período, perfil por hora, días superpuestos,
  semana a semana, comidas, noche y ejercicio, patrones por franja) y un **análisis opcional con IA**
  (ver más abajo). Fondo animado que toma el color de tu última lectura, desactivable en Ajustes.
- Español, inglés y portugués (pt-BR). iOS 26, Liquid Glass, Swift 6.2 con concurrencia estricta.

## Qué no hace

- No incluye credenciales de app, certificados ni claves. Sin ellas no empareja con un sensor;
  ver [`Credentials/README.md`](Credentials/README.md).
- No se distribuye: cada persona compila e instala su copia con su propio Apple ID.
- No sugiere medicación ni dosis. El asistente opcional y el análisis de reportes rechazan
  cualquier respuesta sobre insulina o fármacos.
- No ha sido probado con más de un sensor ni con más de un iPhone.

## Reportes y análisis con IA

La pestaña Reportes calcula en el iPhone, a partir de tus lecturas y del diario, siete reportes para un período de
7, 14, 30 o 90 días:

1. Resumen del período: tiempo por banda (bajo, en rango, alto, muy alto), media, desviación, variabilidad,
   cobertura y huecos.
2. Perfil por hora del día (tipo AGP): mediana y bandas de percentiles por cada media hora.
3. Días superpuestos sobre un mismo reloj de 24 horas.
4. Semana a semana: últimos 7 días frente a los 7 anteriores.
5. Respuesta a comidas: subida, pico y tiempo hasta volver al nivel previo.
6. Noche: mediana, mínimo y bajadas dentro de la ventana nocturna.
7. Efecto del ejercicio y patrones por franja del día.

Cada reporte dice qué mínimo de datos necesita y queda vacío hasta tenerlo. Puedes compartir los datos del reporte
(JSON) o un resumen como imagen.

**Análisis con IA (opcional).** Si configuras un proveedor, su clave y un modelo en Ajustes (son los mismos del
asistente de comidas), el botón "Analizar con IA" envía el reporte completo y devuelve una guía con panorama general,
secciones (qué muestran los datos, por qué puede ocurrir, qué probar, qué observar), avisos y preguntas para explorar.

- **Qué recibe la IA:** solo cifras del reporte: estadísticas, series de glucosa y la hora, los carbohidratos o la
  duración de comidas y ejercicios. **No recibe** nombres, notas, fotos ni identificadores.
- **Una llamada por toque**, sin reintentos automáticos. Antes de enviar ves el modelo, el tamaño y un coste estimado;
  el proveedor puede cobrarte.
- **Es guía, no diagnóstico.** La app descarta por completo cualquier respuesta que mencione enfermedades, insulina,
  fármacos o dosis. No es un dispositivo médico ni consejo médico.
- **La clave es tuya** y se guarda solo en el Llavero de tu iPhone; el repositorio no contiene ninguna.
- Los análisis se guardan en la base local y puedes borrarlos desde el historial.

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
