# Ajustes compartidos autorizados

2026-10-27. Juampa autorizó a Astra modificar lo necesario para corregir la interoperabilidad. Se actualizó `TAREAS.md` sin cambiar el bundle, el Team, la arquitectura de app nueva o los roles de Fable.

Los cambios normativos y pruebas viven en `../../LingoScan_Shared`, con un único dueño de edición durante esta pasada. No mantener una segunda variante del formato en este proyecto. La revisión pendiente corresponde a herencia sintética, ancestros transportables, preservación de raw complementario, secretos contradictorios y comprobación multisesión.

La implementación Astra ya tiene parser Lingo y envoltura cifrada probados; su inventario de recuperación de xDrip está en `../../lingoScan_Astra/INVENTARIO_RECUPERACION.md`. Esto aporta evidencia de formatos, no prueba de transferencia de un sensor activo.

No se tocó ningún sensor ni se copiaron credenciales reales. La implementación de protocolo y UI puede avanzar mientras se completa la pasada del contrato; la fusión de archivos debe seguir la revisión corregida.

Resultado de la pasada: contrato `1.0.0-draft.4` disponible como base de implementación, con generadores actualizados y casos adversariales. Dos regeneraciones verificadas en copia temporal produjeron 66 archivos idénticos por SHA-256. Los 12 paquetes de fusión generados y las suites de fusión/recuperación pasan con el validador interno. No se ejecutó validación JSON Schema completa (jsonschema ausente); no se declara todavía una prueba física de transferencia. No hace falta rehacer el plan: T-10/T-15/T-19 deben fijar esta revisión y cumplir los casos añadidos.
