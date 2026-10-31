# Auditoría de publicación en el App Store: Lingclose (LingoScan)

Fecha: 31-oct-2026 · Versión revisada: 0.4.7 (13), bundle `com.otalvaro.lingoscan`, iOS 26, solo iPhone.
Método: lectura del repositorio (sin compilar ni ejecutar), aplicando el skill `apple-appstore-reviewer` y las App Review Guidelines vigentes en developer.apple.com (consultadas el 31-oct-2026). Lo que no se pudo confirmar va marcado **(verificar)**. Este documento no es asesoría legal.

---

## 1. Veredicto

1. **Tal como está, no se puede enviar: lo rechazarían en la primera revisión, y no por pulido sino por diseño.** La función central (activar y leer un sensor Abbott por NFC y BLE) depende de material de Abbott que la app no tiene permiso para usar.
2. **Bloqueo 1, propiedad intelectual (5.2.1, 5.2.2):** el emparejamiento exige la clave privada y el certificado de la app oficial de Abbott, sacados de Juggluco, y un protocolo obtenido por ingeniería inversa. Apple puede pedir la autorización del dueño del servicio, y no existe.
3. **Bloqueo 2, salud regulada (1.4.1, 5.1.1(ix)):** en EE. UU. Lingo es un dispositivo con autorización 510(k) de la FDA. Una app que hace de lector principal, con alertas de glucosa baja y un reporte AGP "para el médico", recibe el escrutinio máximo. Además Apple espera que una app de salud la publique una persona jurídica, no un desarrollador individual.
4. **Bloqueo 3, datos de salud (5.1.3(ii), 5.1.2(i)):** los paquetes `.lingoscan`, con glucosa en claro, se guardan en el contenedor iCloud de la app, y Apple lo prohíbe expresamente. Los datos de salud van a seis proveedores de IA sin un consentimiento explícito previo que nombre a cada proveedor.
5. **Camino realista:** separar dos productos. Uno es la build personal con sensor, que sigue firmada localmente. El otro es una app para el App Store que **lee la glucosa de Apple Health** (donde la escriben las apps oficiales) y conserva diario, reportes, PDF e IA con compras dentro de la app. Con eso se caen los tres bloqueos y quedan unas 4 a 8 semanas de trabajo, más el trámite de crear la empresa.

---

## 2. Qué es la app para un revisor

- **Propósito:** ver la glucosa continua de un biosensor, registrar comidas y ejercicio, recibir alertas, generar reportes y un PDF, y usar un asistente de IA.
- **Tres flujos principales:** (1) leer y activar el sensor por NFC y luego recibir lecturas por BLE; (2) Hoy y Reportes, con la curva, las estadísticas y el análisis con IA; (3) el diario de comidas con foto o texto analizados por IA.
- **Qué necesita para funcionar:** un sensor Lingo físico sin activar, un archivo JSON con la "identidad de app" de Abbott importado en *Ajustes › Avanzado › Identidad del sensor* y una clave de API propia para la IA. **El revisor no tendrá ninguna de las tres cosas.**

---

## 3. Tabla de hallazgos

Severidad: **Bloqueante** = rechazo casi seguro · **Alta** = causa habitual de rechazo o de preguntas · **Media** = riesgo o fricción · **Baja** = pulido.
Esfuerzo: S ≤ 1 día · M 2 a 5 días · L > 1 semana.

| id | Severidad | Regla de Apple | Evidencia (archivo:línea) | Qué hacer | Esfuerzo |
|---|---|---|---|---|---|
| H-01 | Bloqueante | 5.2.1 (material protegido de terceros), 5.2.2 (servicios de terceros: "Authorization must be provided upon request") | `Credentials/README.md:3-24`: el JSON de identidad viene de `LingoCredentials.java` de Juggluco, que la sacó de la app oficial. `LingoScan/Features/Settings/Screens/SensorIdentityView.swift:28` (importador del JSON) · `LingoScan/Services/CredentialStore.swift:21` · `Localizable.xcstrings:2915` y `:3007` ("Claves para emparejar Lingo") · `PLAN.md:26` | Sin la clave de Abbott la app no empareja. Si se incrusta en el binario, se está distribuyendo un secreto criptográfico de Abbott. Si se pide al usuario que la importe, la función depende de conseguir un secreto ajeno, y el revisor ni siquiera puede probarla. Ninguna de las dos opciones se puede publicar sin licencia de Abbott. **Hay que quitar el emparejamiento del binario del App Store.** | L (rediseño) |
| H-02 | Bloqueante | 5.2.2, 5.2.1, 1.4.1 | Protocolo por ingeniería inversa: `docs/PROTOCOLO_LINGO.md`, `Packages/RoundWhiteDiscKit/Sources/RoundWhiteDiscKit/Pairing/Libre3NFCActivationSequence.swift`. La app activa sensores escribiendo por NFC (`LingoScan/Features/Sensor/ActivationConfirmationView.swift:53-67`) | Apple puede pedir permiso del fabricante para operar su hardware y su servicio. Las apps de CGM de terceros que no son del fabricante (xDrip4iOS, Juggluco, DiaBLE) **no están en el App Store** y se distribuyen compilándolas o por TestFlight privado (verificar el caso concreto de cada una). Igual que en H-01: fuera del binario público. | L |
| H-03 | Bloqueante | 1.4.1 (apps médicas: más escrutinio, recordar consultar al médico, enlazar la autorización regulatoria si existe) | Lingo tiene autorización 510(k) de la FDA (29-may-2024), pero el texto dice "Lingo es un producto de bienestar, no un dispositivo médico" en `Localizable.xcstrings:23707` (`medical.pdf.footer.disclaimer`) y `:26651` (`medical.pdf.method.source`). Alertas de glucosa baja y de bajada rápida como *time-sensitive* en `LingoScan/Services/Alerts/AlertNotifier.swift:56` y `LingoScan/LingoScan.entitlements:27`. Exportación a Salud con un decodificador no validado en `LingoScan/Services/HealthKitSink.swift:127-130` | Corregir el texto: en EE. UU. Lingo **sí** es un dispositivo médico; lo que se puede decir es que *esta app* no lo es. Si la app lee el sensor, es lector principal de un dispositivo regulado y no tiene autorización que enlazar ni datos de exactitud que mostrar, así que Apple puede rechazarla por 1.4.1. En la versión App Store, usar solo glucosa que ya esté en Apple Health. | M (si se adopta la arquitectura HealthKit) |
| H-04 | Bloqueante | 5.1.1(ix): servicios de salud "should be submitted by a legal entity… and not by an individual developer" | Firma con cuenta personal (`project.yml:11-12`, `NOTICE.md`). La app ofrece reporte para el médico, alertas e IA sobre datos de glucosa | Crear una persona jurídica (por ejemplo una S.A.S. en Colombia), obtener el D-U-N-S y una cuenta de Apple Developer de **organización**, y publicar desde ahí. Aun reposicionada como bienestar, una app de glucosa con IA y suscripción tiene alto riesgo de que le apliquen esta regla. | M (2 a 6 semanas de trámite) |
| H-05 | Bloqueante | 5.1.3(ii): "may not store personal health information in iCloud" | `LingoScan/Services/ArchiveService.swift:38`, `:94`, `:264` (escribe en `iCloud.com.otalvaro.lingoscan` por defecto y en segundo plano). El paquete es NDJSON en claro (`Packages/LingoCore/Sources/LingoCore/Archive/LingoScanArchiveWriter.swift`, sin cifrado). Entitlements iCloud en `LingoScan/LingoScan.entitlements:11-26` · `Localizable.xcstrings:11356` | Quitar el contenedor iCloud propio y el respaldo automático. Dejar solo una exportación **que inicia el usuario** (`fileExporter` o compartir), con un aviso de que el archivo contiene datos de salud. Si se quiere sincronizar, usar CloudKit con campos cifrados de extremo a extremo, y aun así consultarlo antes con Apple (verificar). | M |
| H-06 | Alta | 5.1.2(i): revelar qué datos van a una IA de terceros y "obtain explicit permission before doing so"; 5.1.3(i) para datos de HealthKit | No hay pantalla de consentimiento previo. En "Preguntar al asistente" y "Sugerir rango", el aviso aparece **mientras ya se está enviando** (`LingoScan/Features/Today/Coaching/CoachingLoadingSection.swift:12`, `LingoScan/Features/Settings/RangeSuggestion/RangeSuggestionSheet.swift:73`). El pie de Ajustes se queda corto ("solo lo necesario… por ejemplo la foto"): `LingoScan/Features/Settings/LLM/LLMSettingsView.swift:39`. Sueño, pasos y composición corporal de Salud se envían a la IA (`LingoScan/Features/Reports/Analysis/ReportAnalysisIntroView.swift:79-87`). Seis proveedores en `LingoScan/Services/LLM/LLMProviderID.swift:4` | Añadir un consentimiento explícito, una vez por proveedor y revocable: nombre de la empresa, lista exacta de datos (glucosa agregada, perfil, sueño, pasos, cuerpo, fotos), finalidad, enlace a la política del proveedor y botones "Permitir"/"No permitir". Volver a pedirlo si cambia el proveedor o el alcance. Reescribir `llm.privacy`. Que no salga nada antes de que el usuario toque. Quitar DeepSeek, xAI y OpenRouter de la versión pública, o justificar su retención y su jurisdicción. | M |
| H-07 | Alta | Privacy Manifest y Required Reason APIs (ITMS-91053; Apple rechaza subidas sin el manifiesto) | No existe `PrivacyInfo.xcprivacy` (búsqueda en todo el repo). Usos: `UserDefaults`, incluido el App Group (`LingoScan/Services/Alerts/AlertSettingsStore.swift:21`, `LingoScan/Services/Coaching/CoachingStore.swift:16`, `LingoScan/Features/Settings/Language/LanguagePreference.swift`). Fecha de archivo con `contentModificationDate` (`LingoScan/Features/Reports/MedicalPDF/MedicalReportViewModel.swift:184-186`) | Crear `LingoScan/PrivacyInfo.xcprivacy` con `NSPrivacyTracking=false`, sin dominios de tracking, `NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1 y 1C8F.1 por el App Group), `NSPrivacyAccessedAPICategoryFileTimestamp` (C617.1) y `NSPrivacyCollectedDataTypes` coherente con H-08. Los paquetes locales también necesitan el suyo si usan esas APIs. | S |
| H-08 | Alta | 5.1.1(i) (política de privacidad en metadatos y dentro de la app), 2.5.1 (HealthKit), App Privacy | Ajustes no enlaza ninguna política de privacidad, términos ni soporte (`LingoScan/Features/Settings/Rows/AboutRows.swift:11-14`, `LingoScan/Features/Settings/Screens/TechnicalInfoView.swift:10-17`) | Publicar una política de privacidad (qué datos, HealthKit, IA, retención, borrado, contacto, Ley 1581 de Colombia) y una URL de soporte, y enlazarlas en Ajustes › Acerca de. Llenar las etiquetas de privacidad: con BYOK directo, "datos no recopilados" puede defenderse (verificar); con backend propio hay que declarar Salud y forma física, Fotos y Contenido del usuario, vinculados o no según exista cuenta. | S |
| H-09 | Alta | 2.1 (completitud; el revisor debe poder probar), notas de revisión | El modo con datos de ejemplo solo existe en DEBUG (`LingoScan/App/AppLaunchMode.swift:12-17`). Sin sensor, Hoy queda vacío y remite a "activar un sensor" (`LingoScan/Features/Today/TodayEmptyView.swift:10-27`) | Añadir un modo demo visible en Release ("Probar con datos de ejemplo"), reutilizando `PreviewData`. Si queda algo que dependa de hardware, adjuntar un video en las notas de revisión. Para la IA: una cuenta de prueba con créditos en el backend, nunca una clave en el binario. | M |
| H-10 | Alta | 5.2.1 (derechos sobre lo que se publica); efecto práctico: retiro si hay reclamo | `LICENSE` (GPL-3), `README.md:136-139` y `DECISIONES.md:36` (D-29): partes portadas de Juggluco (GPL-3) | La FSF considera las condiciones del App Store incompatibles con la GPL (precedente: VLC, retirado en 2011). Juampa puede licenciar su propio código como quiera, **pero no lo derivado de Juggluco**. Opciones: permiso escrito del autor de Juggluco, reescritura limpia o dejar ese código fuera de la versión App Store (que es lo que pasa con la arquitectura HealthKit). | S a L |
| H-11 | Alta | 4.1(c) (no usar la marca o el nombre de otro en el nombre de la app), 2.3.7 (nombre único, sin marcas en palabras clave), 5.2.1 | Nombre "Lingclose" (`LingoScan/Info.plist:12-13`), derivado de "Lingo". Los avisos de permiso dicen "LingoScan" y "tu sensor Lingo" (`Info.plist:51-52`, `:59-60`); `Info.plist:16` dice "Identidad de app LingoScan"; la carpeta visible en Archivos se llama "LingoScan" (`Localizable.xcstrings:11356`) | Elegir un nombre y un ícono sin "Ling", "Libre" ni "Abbott". Unificar el nombre visible en todos los avisos de permiso y en la carpeta de Archivos. El bundle ID interno puede quedarse (el usuario no lo ve). Las palabras clave del App Store no pueden llevar Lingo, Libre, FreeStyle, Abbott, Dexcom ni Stelo. | S a M |
| H-12 | Media | 2.1 (nada de funciones de relleno ni de depuración), 2.3 | Interruptor "Registro detallado del sensor" que "aún no registra nada" (`LingoScan/Features/Settings/Rows/DiagnosticsRow.swift:5-13`). "Base del fork RoundWhiteDiscKit" en `TechnicalInfoView.swift:12-17`. Jerga en los bloqueos ("productType 9, securityVersion 3", "state 1"): `Localizable.xcstrings:3559`. IDs crudos en `LingoScan/Features/Data/RecoveryView.swift:217` | Esconder todo esto tras `#if DEBUG` o quitarlo. La versión App Store no debería tener Identidad del sensor, Recuperación del sensor ni Información técnica del fork. | S |
| H-13 | Media | 2.5.4 (modos de fondo solo para su uso previsto) | `UIBackgroundModes` declara `processing` y el identificador `…archive.processing` (`Info.plist:8`, `:70`), pero solo se registra `BGAppRefreshTask` (`LingoScan/App/BackgroundTasks.swift:19`, `:50`). `bluetooth-central` (`Info.plist:68`) se justifica solo por el sensor | Quitar `processing` y su identificador. Quitar también `bluetooth-central` y el entitlement NFC (`entitlements:19-22`) si la versión App Store no lee el sensor. Conservar `fetch` solo si hay una función visible que lo use. | S |
| H-14 | Media | 2.3.1 y 2.5 (comportamiento oculto o inesperado) | `CFBundleDocumentTypes` registra la app como visor alternativo de **cualquier** `public.json` para importar la identidad de Abbott (`Info.plist:14-27`). `UIFileSharingEnabled` expone Documentos (`Info.plist:72-73`) | Quitar el registro de JSON. Si hace falta un tipo de documento, declarar un UTI propio (`.lingoscan`) con `UTExportedTypeDeclarations`. Revisar qué queda visible en Documentos. | S |
| H-15 | Media | 1.4.1 (información médica inexacta o dañina) | Los prompts dan por hecho que el usuario "NO tiene diabetes" ni usa insulina: `LingoScan/Services/LLM/CoachingPrompt.swift:26`, `RangeSuggestionPrompt.swift:20`, `ReportAnalysisPrompt.swift:47` | En una app pública eso puede ser falso. Preguntarlo al empezar y, si usa insulina o tiene diabetes, desactivar o adaptar el consejo de la IA y remitir a su médico. Mantener el validador que descarta temas médicos (texto en `reports.analysis.error.rejected`) y mencionarlo en las notas de revisión. | S |
| H-16 | Media | 1.4.1 | Alertas de glucosa baja y de bajada rápida (`AlertNotifier.swift:56`); título "Reporte de glucosa para el médico" con AGP (`Localizable.xcstrings:23615`) | Son las funciones que más empujan hacia "dispositivo médico". En la versión App Store: alertas "informativas" sin lenguaje de seguridad, o quitar la de baja; renombrar el PDF ("Resumen para compartir con tu profesional de salud") y mantener los avisos de cada pantalla (ya bien hechos: `today.footer.note`, `alerts.disclaimer`, `coaching.sheet.disclaimer`). | S |
| H-17 | Media | 5.1.3(ii) (no escribir datos inexactos en HealthKit) | Se escribe glucosa decodificada por ingeniería inversa, sin validación externa (`HealthKitSink.swift:127-130`) | En la versión App Store la app no debería escribir glucosa: la lee. Comidas y macronutrientes sí se pueden escribir (son datos que registra el usuario). | S |
| H-18 | Media | Cumplimiento de exportación (cifrado) | `ITSAppUsesNonExemptEncryption = false` (`Info.plist:47-48`), con AES-CCM propio (`Packages/RoundWhiteDiscKit/Sources/RoundWhiteDiscKit/Crypto/AESCCM.swift`), ECDH y PBKDF+AES para la recuperación (`Packages/LingoCore/Sources/LingoCore/Recovery/RecoveryCrypto.swift`) | Si la versión App Store deja fuera RWDK y la recuperación, `false` es correcto (solo HTTPS y cifrado del sistema). Si los conserva, responder el cuestionario de App Store Connect con cuidado: probablemente aplique una exención de mercado masivo o de autenticación, pero hay que confirmarlo (verificar). | S |
| H-19 | Media | 2.1 y 4.2 (primera experiencia clara) | No hay pantalla de bienvenida (no aparece "onboarding" ni "bienvenida" en el código). La app abre en Hoy, vacía | Hacer una bienvenida de 2 o 3 pantallas: qué hace, que no es un dispositivo médico, de dónde vienen los datos (Apple Health), permisos en contexto y la entrada al modo demo. | M |
| H-20 | Media | 2.4.1 (las apps de iPhone deberían funcionar en iPad) | `TARGETED_DEVICE_FAMILY: "1"` (`project.yml:42`) y sin `UIRequiredDeviceCapabilities` | Si la versión App Store no usa NFC, comprobar que corre bien en iPad en modo compatibilidad (Apple la prueba ahí). Si conserva NFC o BLE, declarar `UIRequiredDeviceCapabilities` (`nfc`, `bluetooth-le`) para que no aparezca en iPad. | S |
| H-21 | Baja | 5.1.1(v) y buenas prácticas de privacidad | No hay "Borrar todos mis datos" (solo borrado por entrada: `LingoScan/Features/Diary/DiaryDeleteSwipeButton.swift:9`) | Añadir un borrado total (SQLite, Llavero, ajustes, historial de IA) y explicar que las muestras de Salud se borran desde Salud. Será obligatorio si se crean cuentas para los créditos. | S |
| H-22 | Baja | 5.1.1(iii) (minimizar datos), 2.5.1 | Se lee grupo sanguíneo y fecha de nacimiento para el PDF (`Info.plist:57-58`) | Pedirlos solo al generar el PDF (ya se hace en `MedicalReportViewModel.swift:144-151`) y valorar si el grupo sanguíneo aporta algo. Indicar la integración con HealthKit en la descripción y en la interfaz. | S |
| H-23 | Baja | 2.3 (metadatos y textos) | Textos sin localizar en `ArchiveService.swift:91` y `:95`. El catálogo está completo: 1168 de 1169 claves traducidas en es, en y pt-BR | Pasarlos a `String(localized:)`. Traducir también la ficha del App Store en los tres idiomas. | S |
| H-24 | Baja | Accesibilidad (HIG, etiquetas de accesibilidad de App Store Connect) | 33 usos de `.font(.system(size:))` sin Dynamic Type y 24 `accessibilityLabel` para muchas gráficas | Usar estilos de texto escalables y añadir `accessibilityLabel` y `accessibilityValue` a las gráficas (Swift Charts tiene `AXChartDescriptor`). Probar con VoiceOver y tamaño XXXL antes de declarar las etiquetas de accesibilidad. | M |
| H-25 | Baja | 2.3.3 y 2.3.7 (capturas y nombre), activos | Ícono de 1024 px sin canal alfa: correcto (`LingoScan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`). Solo hay variante universal. `UILaunchScreen` vacío y solo vertical (`Info.plist:74-79`): aceptable | Hacer variantes oscura y tintada (Icon Composer en iOS 26, opcional). Capturas en 6,9" del flujo real, con datos demo y sin marcas de Abbott ni el sensor de Abbott a la vista. Nombre de 30 caracteres o menos, subtítulo sin "CGM de Abbott". Cuestionario de edad: declarar "información médica o de tratamiento". Categoría Salud y forma física. | M |

---

## 4. Modelo de suscripción y créditos de IA

### Lo que exige Apple
- **3.1.1:** cualquier función o contenido digital que se desbloquee pagando se cobra con In-App Purchase. Las consultas de IA servidas por un backend propio son contenido digital consumido dentro de la app, así que **van por IAP, sin excepción**. Tampoco se puede enlazar a un pago en la web desde la app, salvo en jurisdicciones con *entitlement* específico (verificar si se piensa usar en EE. UU. o la UE).
- **3.1.1:** los créditos comprados **no pueden caducar** y debe haber un mecanismo de restauración para lo que sea restaurable.
- **3.1.2(a):** una suscripción autorrenovable tiene que dar valor continuo, durar al menos 7 días y estar disponible en todos los dispositivos del usuario.
- **3.1.2(c):** antes de comprar hay que mostrar el nombre, la duración, el precio y lo que incluye, con enlaces a los términos (EULA) y a la política de privacidad, también en la ficha del App Store. Hace falta el botón "Restaurar compras".
- **"Trae tu propia clave" (BYOK):** las guías no lo prohíben. Hay clientes de IA aprobados que lo hacen, porque la clave no desbloquea funciones de la app, sino que el usuario paga a otro servicio. Riesgos: (a) el revisor necesita una clave para probar la función; (b) si conviven BYOK y una suscripción, Apple puede ver BYOK como un camino para no pagar por IAP y preguntar por 3.1.1; (c) cada proveedor elegido es un tercero más que recibe datos de salud (5.1.2(i)).

### Recomendación concreta
1. **Primer envío: app gratis con IA incluida en un plan de prueba, sin BYOK en la versión App Store.**
   - Suscripción autorrenovable "Plus", mensual y anual, con una cuota mensual de consultas (por ejemplo 60 análisis de comida y 10 análisis de reporte) que se renueva con cada periodo. Si la cuota no usada no se acumula, decirlo en la pantalla de pago.
   - Paquetes **consumibles** de créditos para quien se pase de la cuota. No caducan nunca y el backend los guarda en su libro de saldo, vinculados al usuario.
   - Una oferta introductoria (prueba gratis de 1 semana) para que el revisor y el usuario prueben sin pagar. Para el revisor también sirve una cuenta sandbox en las notas.
   - Lo que no es IA (curva, reportes, PDF, diario manual) sigue gratis. Así la app cumple 4.2 aunque no se pague nada.
2. **BYOK:** dejarlo solo en la build personal. Si algún día se lleva al App Store, como opción avanzada "usa tu propia cuenta de Anthropic/OpenAI/Google" que no compita con el plan, con su propio consentimiento y sin ofrecer más funciones que el plan pago.
3. **Proveedores:** uno o dos con contrato de empresa que garantice que no entrenan con los datos y una retención mínima o nula (por ejemplo la API de Anthropic con retención cero, o la de OpenAI con *zero data retention*; verificar las condiciones vigentes). Sin DeepSeek, xAI ni OpenRouter en la versión pública.

### Qué necesita el backend
- **Ninguna clave en el binario.** El backend es un *proxy* que guarda las claves de los proveedores (en un gestor de secretos, por ejemplo AWS Secrets Manager) y recibe peticiones ya minimizadas.
- **Identidad sin fricción:** sin cuenta, usar `appAccountToken` (un UUID generado en el dispositivo y guardado en el Llavero) en cada compra de StoreKit 2, más **App Attest** (DeviceCheck) para que solo la app legítima consuma la cuota. Si se agrega cuenta, Sign in with Apple, y entonces es obligatorio el borrado de cuenta dentro de la app (5.1.1(v)).
- **Verificación de compras:** App Store Server API y App Store Server Notifications V2 (renovaciones, reembolsos, *revocations*), verificando el JWS de cada transacción en el servidor. El saldo de créditos vive en el servidor, nunca en `UserDefaults`.
- **Cuotas y abuso:** límite por usuario y por minuto, tamaño máximo de imagen, tope de tokens por petición y registro de costos por usuario.
- **Privacidad:** no guardar en el backend ni las fotos ni los datos de salud después de responder. Registros sin contenido, solo métricas. Política de retención publicada. Con backend propio, las etiquetas de privacidad cambian: hay que declarar Salud y forma física, Fotos y Contenido del usuario como datos recopilados (vinculados al usuario si existe `appAccountToken` o cuenta).
- **Legal:** contrato de encargado del tratamiento con el proveedor de IA. Transferencia internacional de datos sensibles conforme a la Ley 1581 de 2012 de Colombia (autorización expresa y previa del titular), y la regla de notificación de brechas de salud de la FTC (Health Breach Notification Rule) si hay usuarios en EE. UU. (verificar).

---

## 5. ¿Basta la limpieza de textos ("biosensor" en vez de "monitor de glucosa")?

**No basta, aunque ayuda.**
- **Sirve para:** quitar marcas del texto general y del nombre, alejar la lectura de "dispositivo médico" y cumplir 2.3.7 en la ficha. Mencionar "Abbott Lingo" solo donde se registra el sensor es un uso nominativo razonable ("compatible con…"), siempre que no haya logos, colores ni tipografía de Abbott y que se diga que no hay afiliación.
- **No resuelve:**
  - (a) El problema de fondo de 5.2.1 y 5.2.2 no está en las palabras, sino en usar la clave de Abbott y su protocolo (H-01, H-02).
  - (b) Lo que decide si algo es dispositivo médico es el **uso previsto** según su función y lo que promete. Una app que muestra mg/dL en tiempo real con alertas de baja es un monitor de glucosa aunque lo llame "biosensor".
  - (c) Siguen quedando "Lingclose", "LingoScan" en los avisos de permiso y "Lingo" en el aviso de NFC (H-11).
  - (d) El aviso "Lingo es un producto de bienestar, no un dispositivo médico" es incorrecto en EE. UU. y hay que reescribirlo, no solo cambiarle el sustantivo (H-03).
- **Texto sugerido para el lugar donde se registra el sensor:** "Fuente: lecturas de glucosa que otra app guardó en Apple Salud (por ejemplo, la app del fabricante de tu sensor). [Nombre de la app] no es un producto de ningún fabricante de sensores ni está afiliada a ellos. Las marcas pertenecen a sus dueños."

---

## 6. Riesgos legales fuera de Apple

> **Esto no es asesoría legal.** Son riesgos que conviene llevar a un abogado de propiedad intelectual y de regulación sanitaria antes de publicar o de abrir el código con más difusión. Todo lo jurídico está marcado (verificar).

**Abbott: marcas, derechos de autor, secretos y contrato**
- **Marcas:** usar "Lingo", "FreeStyle Libre" y "Libre" para identificar compatibilidad suele aceptarse como uso nominativo. Un nombre derivado ("Lingclose") o el uso en metadatos o en el ícono puede dar pie a un reclamo por confusión. (verificar)
- **Clave y certificado de la app oficial:** son material criptográfico de Abbott. Distribuirlos, o distribuir una app que solo sirve con ellos, puede verse como apropiación de un secreto empresarial o como infracción de derechos de autor. **Es el riesgo más alto del proyecto.** (verificar)
- **Código decompilado en el repositorio:** `docs/DiaBLE_Lingo_recovered.swift.txt` contiene clases de la app oficial recuperadas (`REFERENCIAS.md:7`). Aunque no entre al binario, tenerlo en un repositorio público es un riesgo de derechos de autor. Recomendación: sacarlo del repositorio y de su historial antes de cualquier difusión.
- **Términos de uso:** los términos de la app y del sensor Lingo probablemente prohíben la ingeniería inversa y el uso con software no autorizado. Incumplirlos es un riesgo contractual para quien los aceptó y afecta la garantía del sensor. (verificar)

**Ingeniería inversa y medidas tecnológicas**
- **EE. UU. (DMCA §1201):** la ley prohíbe eludir medidas de protección y, aparte, **traficar** con herramientas para eludirlas. Existen la excepción de interoperabilidad (§1201(f)) y una exención de la Oficina de Derechos de Autor para que el paciente acceda a los datos de su propio dispositivo médico. Ambas protegen sobre todo **el acto del usuario**, no la distribución pública de la herramienta. Una app en el App Store se parece más a distribuir. (verificar)
- **Colombia:** la Ley 1915 de 2018 regula las medidas tecnológicas de protección y sus excepciones, incluida la interoperabilidad (verificar su alcance exacto). El uso personal de Juampa tiene un perfil de riesgo muy distinto al de una distribución comercial.
- **Licencias:** RWDK es MIT, compatible con todo. Lo derivado de Juggluco es GPL-3, y la FSF lo considera incompatible con el App Store (H-10). Hay que conservar los avisos de copyright de RWDK en cualquier distribución.

**Regulación sanitaria**
- **EE. UU. (FDA):** Lingo tiene autorización 510(k) como CGM de venta libre. Un software que activa el sensor, decodifica la glucosa y emite alertas funciona como componente o lector principal de un dispositivo regulado, y quedaría fuera de la política de *general wellness* por tratarse de mediciones de glucosa. Las pantallas secundarias de CGM y los MDDS tienen sus propias reglas y excluyen la "monitorización activa" con alarmas. Riesgo: que la FDA lo considere un dispositivo sin autorización. Leer de Apple Health, mostrar tendencias de bienestar y no emitir alarmas de hipoglucemia reduce mucho el riesgo, aunque no lo elimina. (verificar)
- **Colombia (INVIMA):** el Decreto 4725 de 2005 regula los dispositivos médicos, y el software con finalidad médica puede requerir registro sanitario. Lingo no se comercializa en Colombia. Una app dirigida al público colombiano que prometa medir glucosa podría considerarse un dispositivo médico sin registro. Lo que más pesa es el posicionamiento (bienestar, sin diagnóstico ni tratamiento) y no prometer exactitud. (verificar)
- **Datos personales:** en Colombia, Ley 1581 de 2012 y Decreto 1377 de 2013 (los datos de salud son sensibles: autorización expresa, finalidad y transferencia internacional), y quizá el registro de bases de datos ante la SIC si la empresa supera los umbrales (verificar). En EE. UU., la Health Breach Notification Rule de la FTC y leyes estatales como la My Health My Data Act de Washington. En la UE, si se publica allí, el RGPD con datos de categoría especial.
- **Responsabilidad:** alertas que no llegan o un consejo de la IA mal interpretado. Los avisos ayudan, pero no reemplazan unos términos de uso con limitación de responsabilidad ni, más adelante, un seguro.

---

## 7. Lo que hará el revisor y si lo logra hoy

| Paso | ¿Lo logra hoy? |
|---|---|
| Instalar y abrir | Sí (sin crashes evidentes en la lectura del código; no se ejecutó) |
| Entender de qué trata la app al primer vistazo | No: no hay bienvenida y Hoy aparece vacío |
| Permisos | Se piden en contexto; los textos mezclan "LingoScan" y "Lingclose" |
| Función principal | No: requiere un sensor físico y la clave de Abbott |
| IA | No: requiere su propia clave de API |
| Comprar y restaurar | No aplica hoy; hará falta con el modelo de suscripción |
| Enlaces de soporte, privacidad y términos | No existen en la app |
| Casos límite (sin red, sin Salud) | Parcial: hay estados de error en los flujos de IA y del archivo |

### Borrador de notas para App Review (versión App Store con arquitectura HealthKit)

> [Nombre] es una app de bienestar que muestra la glucosa que el usuario ya tiene en Apple Health (escrita por la app de su sensor), junto a sus comidas, sueño y ejercicio. No se conecta a ningún sensor, no es un dispositivo médico, no da diagnósticos ni dosis, y cada pantalla de análisis lo recuerda.
>
> **Cómo probarla sin datos de salud:** en la bienvenida toca "Probar con datos de ejemplo". Se cargan 14 días de lecturas, comidas y ejercicio de ejemplo. Reportes › Compartir genera el PDF; Diario › + › Comida prueba el análisis por foto.
>
> **IA:** la prueba gratis de [Plan] incluye consultas. Cuenta sandbox: [usuario]/[contraseña]. Antes del primer envío, la app pide un consentimiento explícito que nombra al proveedor ([empresa]) y los datos que se enviarán. Las respuestas que mencionan diagnóstico o medicación se descartan automáticamente.
>
> **HealthKit:** lee glucosa, entrenamientos, sueño, pasos y composición corporal; escribe solo comidas (carbohidratos, calorías, proteínas, grasas). Ningún dato de Salud se guarda en iCloud ni se usa para publicidad.
>
> **Modos de fondo:** `fetch`, para actualizar los reportes con datos nuevos de Salud (si se conserva).

---

## 8. Pasos ordenados para llegar a un primer envío

1. **Decidir la arquitectura del producto público:** una app del App Store que lee la glucosa de Apple Health, y la build personal con sensor fuera del App Store. Dejarlo como decisión en `DECISIONES.md`. (H-01, H-02, H-03, H-10, H-17)
2. **Crear la persona jurídica**, sacar el D-U-N-S y la cuenta de Apple Developer de organización. Pedir asesoría legal sobre marcas, la Ley 1581 y el INVIMA. Empezar ya, porque es lo que más tarda. (H-04)
3. **Elegir el nombre y el ícono definitivos**, sin "Ling", y unificar el nombre visible en `Info.plist`, los avisos de permiso y Archivos. (H-11)
4. **Crear un target o configuración "AppStore"** que excluya RoundWhiteDiscKit, NFC, BLE, Identidad del sensor, Recuperación, Activación, Información técnica y Diagnóstico. Quitar los modos de fondo y entitlements sobrantes (NFC, `bluetooth-central`, `processing`, iCloud) y el registro de `public.json`. (H-12, H-13, H-14, H-18, H-20)
5. **Agregar una fuente de glucosa desde HealthKit** (lectura de `bloodGlucose` con `HKAnchoredObjectQuery` y entrega en segundo plano) y dejar de escribir glucosa en Salud. (H-03, H-17)
6. **Quitar el respaldo automático a iCloud** y dejar solo la exportación manual. (H-05)
7. **Privacidad:** `PrivacyInfo.xcprivacy`, política de privacidad, URL de soporte, términos, enlaces en Ajustes, borrado total de datos y etiquetas de App Privacy. (H-07, H-08, H-21)
8. **IA:** pantalla de consentimiento explícito por proveedor, prompts que no den por hecho que el usuario no tiene diabetes, y textos de privacidad corregidos. (H-06, H-15)
9. **Backend e IAP:** proxy con App Attest, StoreKit 2 (suscripción y consumibles), App Store Server API y Notifications V2, pantalla de pago conforme a 3.1.2(c) y "Restaurar compras". Configurar los productos y un archivo `.storekit` para las pruebas. (sección 4)
10. **Reposicionar como bienestar:** corregir el aviso sobre Lingo, renombrar el PDF, revisar las alertas de baja, completar los textos de "biosensor" y quitar marcas salvo en la línea de compatibilidad. (H-03, H-16, sección 5)
11. **Bienvenida y modo demo en Release.** (H-09, H-19)
12. **Pulido:** textos sin localizar, Dynamic Type y VoiceOver en las gráficas, variantes del ícono. (H-23, H-24, H-25)
13. **Activos del App Store:** capturas en 6,9" con datos demo (sin sensor ni marcas de Abbott), ficha en es, en y pt-BR, cuestionario de edad, categoría Salud y forma física, notas de revisión (sección 7) y cuenta sandbox.
14. **TestFlight externo:** pasa por una revisión beta más ligera que sirve de ensayo. Después, envío a App Review.

---

### Fuentes
- [App Review Guidelines (Apple)](https://developer.apple.com/app-store/review/guidelines/), consultadas el 31-oct-2026.
- [Abbott wins FDA clearance for its Lingo OTC glucose monitor (MassDevice)](https://www.massdevice.com/abbott-wins-fda-clearance-for-its-lingo-otc-glucose-monitor/)
- [Abbott Lingo FDA clearance (MedTech Dive)](https://www.medtechdive.com/news/abbott-lingo-fda-clearance-over-the-counter-cgm/717815/)
