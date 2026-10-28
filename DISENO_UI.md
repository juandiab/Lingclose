# Diseño de LingoScan

Dirección: **calma, legibilidad, datos primero.** No es una app médica ni lo parece: nada de rojo de alarma permanente, ni semáforos. El valor actual, su antigüedad y su calidad siempre van juntos. iOS 26 con Liquid Glass nativo en el cromo (barras, acciones flotantes, chips) y superficies sólidas para texto y gráficas.

## Referencia de interacción (2026-10-27)

Juampa pidió usar como referencia la pantalla "Today" de la app oficial Lingo tal como aparece en la caja del producto (`docs/referencias/lingo-caja-pantalla-today.jpg`). Se toma el **modelo de interacción**, no la marca ni los iconos de Abbott:

- Cabecera con navegación por día (`‹ Hoy ▾ ›`) y chips de período 6 h / 12 h / 24 h.
- Curva con líneas de referencia a 70 y 140 mg/dL y **sombreado del área por encima de 140** en cada pico; bajo cada pico, un número de "cuenta de pico" (en Lingo es un índice propietario; en LingoScan será el área sobre 140 en mg/dL·min dividida por 10, redondeada, rotulado "índice de pico, no médico").
- Marcadores de comida y actividad sobre el eje de tiempo, con hora; tocar uno muestra su detalle.
- Cursor sobre la curva con línea vertical y lectura "142 mg/dL a las 12:02" (tocar o mantener pulsado y arrastrar; ver "Gestos de la curva").
- Botón "+" central para registrar comida, ejercicio o nota en dos toques; fila "Registro" con el conteo del día y acceso a editar.
- Pestañas: Hoy, Diario, Reportes, Datos, Ajustes (se mantienen las nuestras; el "+" central es un botón flotante de vidrio en Hoy y Diario).

Tarea: **T-11b** (después de T-12a).

## Gestos de la curva (27-oct, zoom y desplazamiento)

- **Deslizar** horizontalmente desplaza el tiempo con la física nativa de Swift Charts (`chartScrollableAxes(.horizontal)`, rebote en los extremos). No se puede pasar de ahora. Hacia el pasado no hay límite práctico: se cargan más lecturas al acercarse al borde.
- **Pellizcar** cambia la longitud visible entre 1 h y 24 h de forma continua; el instante bajo los dedos queda fijo. Al soltar no se ajusta a un chip; al cruzar 3/6/12/24 h hay un haptic de selección. La longitud libre se recuerda al abrir (`today.visibleSeconds`).
- **Chips 3 h / 6 h / 12 h / 24 h**: atajos de la longitud visible, conservando el fin de la ventana. Un chip solo aparece seleccionado si coincide (±1 min). Funcionan siempre, también en días anteriores.
- **En vivo y "Ahora"**: si la ventana termina a menos de 60 s de ahora, la curva sigue cada lectura nueva. Al desplazarse al pasado aparece un botón de vidrio "Ahora" (esquina superior derecha) que vuelve al presente.
- **‹ Hoy ▾ ›**: el título es el día del fin de la ventana visible; ‹ › la mueven un día conservando la longitud; el selector de fecha la deja terminando a la misma hora del reloj de ese día.
- **Cursor**: un toque lo coloca en la lectura más cercana y otro lo quita; mantener pulsado y arrastrar lo desliza (selección nativa de la gráfica desplazable), con haptic al activarse. El cursor se queda donde se suelta.
- Estadísticas ("Período visible (4 h 30 min)"), índices de pico y descriptor de VoiceOver se calculan sobre la ventana visible ~250 ms después del último movimiento. VoiceOver: acciones "Acercar"/"Alejar" sobre la gráfica y acción ajustable (±5 min) en el cursor.
- Reduce Motion: chips, ‹ › y "Ahora" cambian sin animación.
- Dibujo: con más de 900 puntos cargados la línea y las áreas se reducen a cubos de 2/5/10 min sin cruzar huecos; el cursor, las estadísticas y los picos usan las lecturas crudas.

## Marcas e insights de la curva (28-oct, T-23)

- Cada marca de comida o ejercicio tiene una línea vertical discontinua fina (1 pt, gris secundario al 45 %) de abajo arriba de la gráfica, que acompaña al desplazamiento y al zoom; en un grupo de botones, una línea por marca. El cursor queda encima.
- Episodios de subida o bajada rápida (≥ 2 mg/dL/min durante ≥ 10 min) sombreados muy tenues (rojo/azul al 6 %); se desactivan en la hoja de insights (`today.showRateEpisodes`).
- Popover de una comida: "Subió +N mg/dL, pico a los X min, volvió a los Y min" y una barra de puntuación 0–100 (informativa); de un ejercicio: "Bajó N mg/dL en 60 min". Sin datos suficientes, se dice ("todavía" si la marca es reciente).
- Fila "Insights · informativo" bajo En rango/Media/SD, con la misma estética: cambios rápidos ↑N ↓M y mejor/peor comida de la ventana visible. Si no hay nada, no aparece. Tocarla abre una hoja con la lista, el interruptor del sombreado y la nota no médica. Definiciones y fórmulas en `docs/T-23.md`.

## Pantallas de la v1

| Pantalla | Contenido | Comportamiento |
|---|---|---|
| **Hoy** | Valor válido más reciente en grande (`.rounded`, `monospacedDigit`), tendencia con flecha SF Symbol, "hace N min", chip de calidad/estado del sensor; curva Swift Charts desplazable con zoom (chips 3 h / 6 h / 12 h / 24 h y pellizco); marcas de comidas y ejercicio; pérdidas cortas de BLE (≤ 15 min) unidas con línea, huecos largos visibles sin interpolar (D-24) | Se actualiza al llegar cada lectura; `contentTransition(.numericText())` en el valor; haptic suave solo cuando cambia el estado del sensor, no cada minuto |
| **Sensor** | Estado (máquina de estados), calentamiento restante, días restantes, última conexión, Receiver ID (parcial), botón "Leer sensor (solo NFC)" y, en pantalla aparte, "Activar sensor" con resumen de lo que se enviará y confirmación | El diagnóstico nunca activa. La activación muestra `productType`, `securityVersion`, Receiver ID y exige un toggle "entiendo que es irreversible" + botón `.glassProminent` |
| **Diario** | Lista por día de comidas (gramos opcionales), ejercicio y notas; botón flotante "+" | Añadir en dos toques: tipo, hora (por defecto ahora), texto. Edición y borrado con tombstone |
| **Reportes** | Tiempo en rango (rango por defecto 70–180 mg/dL, editable, marcado "no médico"), promedio, SD y CV, respuesta a comidas (pico, tiempo al pico, retorno a línea base), noche (00:00–06:00), comparación semana a semana | Período seleccionable (7/14/30 días); cada métrica con su definición en un popover |
| **Datos** | Estado de Health (último export, pendientes), carpeta de archivo, última copia y verificación, exportar ahora, importar, export de recuperación cifrado, resumen de errores | Estados distintos: "archivo creado", "disponible en iCloud", "restaurado y verificado" |
| **Ajustes** | Unidad (mg/dL), alarmas y umbrales, permisos, apariencia, accesibilidad, diagnóstico privado, acerca de (versiones, commit del fork) | Texto fijo de no uso médico en alarmas |

Navegación: `TabView` con cinco pestañas (Hoy, Diario, Reportes, Datos, Ajustes); Sensor accesible desde el chip de estado en Hoy y desde Ajustes. `NavigationStack` por pestaña.

## Liquid Glass

Skill: `swiftui-liquid-glass` (`references/liquid-glass.md`). Reglas de uso en LingoScan:

- Vidrio en: barra de pestañas y de navegación (lo da el sistema), botón flotante "+" del Diario, chips de período (3 h/6 h/24 h, 7/14/30 d), chip de estado del sensor, acciones principales (`.buttonStyle(.glassProminent)` solo en "Activar sensor" y "Exportar ahora").
- Varios elementos de vidrio juntos van dentro de un `GlassEffectContainer(spacing:)`; `.glassEffect(...)` se aplica después de padding y fondo; `.interactive()` solo en lo tocable; `glassEffectID` con `@Namespace` cuando el chip se transforma en panel.
- Nunca vidrio sobre vidrio, ni vidrio bajo la gráfica o bajo texto largo: la curva y las tablas van sobre `Color(.systemBackground)` / `secondarySystemBackground`.
- Target iOS 26: no hace falta `#available` ni fallback de materiales.

## Tipografía y color

- San Francisco en sus ejes: `.rounded` para números grandes (valor actual, métricas), `.default` para texto, `.monospaced` solo en diagnóstico. `monospacedDigit()` en todo número que cambia. Tamaños semánticos y Dynamic Type siempre; nada de tamaños fijos.
- Color semántico: acento único (azul del sistema) para interacción; verde apagado para "en rango" en la banda de la gráfica; ámbar para "fuera de rango" y para "dato atrasado"; gris para huecos y calentamiento. El rojo se reserva a errores de la app, no a valores de glucosa. Todo definido en `DesignSystem/Tokens` como assets con variantes claro/oscuro y contraste aumentado.
- Superficies: fondo → tarjeta (`secondarySystemBackground`, radio 16) → contenido. Una sombra sutil (`radius 2, y 1`) solo en tarjetas elevadas.

## Movimiento y feedback

Skill `apple-design` (principios, no CSS): respuesta inmediata al toque, animaciones interrumpibles, mismo camino de entrada y salida, origen anclado al control que abre. Skills `swiftui-animation` y `swiftui-microinteractions` para la implementación.

- Springs críticamente amortiguados por defecto (`.smooth`); `.bouncy` solo tras gestos con velocidad.
- `sensoryFeedback(.success)` al confirmar activación, exportación y restauración; `.warning` al entrar en `stale`; nunca por cada lectura.
- `symbolEffect(.pulse)` en el icono de Bluetooth mientras reconecta; `.bounce` una vez al llegar la primera lectura válida.
- Reduce Motion: cross-fades en lugar de desplazamientos; sin pulsos continuos. Reduce Transparency: el sistema sustituye el vidrio; no se añade blur propio.

## Accesibilidad

- VoiceOver lee "N miligramos por decilitro, estable, hace 2 minutos, sensor conectado" en un solo elemento (`accessibilityElement(children: .combine)`).
- Gráfica con `accessibilityChartDescriptor` (resumen, rango, último valor) y tabla alternativa.
- Targets ≥ 44 pt; contraste AA en claro y oscuro; etiquetas de texto en todo botón con icono.

## Revisión obligatoria por pantalla

1. `swiftui-pro:swiftui-pro` sobre los archivos de la pantalla (API moderna, flujo de datos, navegación, accesibilidad, rendimiento).
2. `swiftui-liquid-glass` checklist (contenedor, orden de modificadores, interactividad, consistencia).
3. `ios-design-agent-skill` con capturas del simulador (iPhone 17 Pro Max, claro y oscuro, Dynamic Type grande).
4. `swiftui-performance` en Hoy y Reportes (listas y gráficas con 20 000 puntos: 14 días a 1/min).

## Datos de previsualización

`PreviewData` en el target de app genera una sesión sintética de 3 días (marcada `synthetic`) a partir de los vectores públicos de Juggluco más una curva simulada, para `#Preview` y para la pantalla de Reportes antes de la Fase 3. Nunca se exporta a Health.

## "+" de Hoy (27-oct, petición de Juampa)

El "+" se despliega con animación (morfología Liquid Glass, `glassEffectID`) en Comida / Ejercicio / Nota. Comida va directo a "Analizar con IA" con la cámara abierta; la foto tomada ahí lanza el análisis sin otro toque (un análisis = una llamada; cancelable). Sobre la cámara hay un botón "Entrada manual" que cierra el análisis y abre el registro de comida a mano. Ejercicio y Nota abren el registro rápido con el tipo ya elegido. Reducir movimiento: fundido sin resorte.

## Rediseño del layout de Hoy (27-oct, "espacio muerto" y gráfica)

Auditoría con `ios-design-agent-skill` y `dataviz` sobre capturas del simulador. Cambios:

- **Cabecera compacta** (`TodayHeader`): valor grande, "tendencia · hace N min" y estado de rango a la izquierda; chip del sensor arriba a la derecha (debajo con tamaños de accesibilidad). Sin huecos de 24 pt entre bloques.
- **Curva protagonista** (`GlucoseChartCard`): sin tarjeta, sobre el fondo; ≈ 43 % del alto de la pantalla (`heightFraction`). Encima, chips de período y una línea pequeña con el período visible o la lectura del cursor (alto fijo, la curva no salta) y un botón "i" con la leyenda en popover (`ChartLegendButton`).
- **Marcas** (`GlucoseChart`): línea 2,5 pt `lineJoin .round`; áreas roja/azul con lavado degradado hacia la referencia; referencias finas (0,75 pt, discontinuas, gris) con rótulos cortos ("140") sobre fondo de superficie; rejilla vertical en línea continua de 0,5 pt muy tenue; eje en `caption2`; huecos al 12 %; en vivo, punto final con halo del color del rango (verde en rango). Índice de pico encima de cada pico (antes pisaba la línea de 70). Dominio vertical con 45 mg/dL bajo la referencia baja (solo para marcadores).
- **Estadísticas** (`PeriodStatsCard` + `PeriodStatMetric`): fila de tres métricas sin tarjeta, cobertura en la línea de título. "Registro" en fila delgada. Aviso "no médico" en una línea `caption2` al pie (`TodayFooter`).
- Sin cambios de comportamiento (zoom, desplazamiento, cursor, marcas agrupadas, estadísticas sobre lo visible). `Card` queda en `DesignSystem` sin uso en Hoy.
