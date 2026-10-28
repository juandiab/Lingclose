/// Catálogo de consejos de T-25 (16). Cada `body` es una sola frase de ≤ 120 caracteres, en español por defecto;
/// la app traduce con las claves `coaching.<id>.title` / `.body` de `Localizable.xcstrings`.
public enum CoachingCatalog {
    public static let all: [CoachingTip] = [
        walkAfterMeal, waterNoSugar, mealOrder, noteContext, moveLight, alreadyFalling, risingWait, highPersisting,
        lowSymptoms, lowCompression, afterExercise, fallingWatch, fallingSnack, noDataPhone, noDataBluetooth, restBreath,
    ]

    public static let walkAfterMeal = CoachingTip(
        id: "walkAfterMeal", title: "Camina un poco",
        body: "Caminar 10–15 min ayuda a suavizar el pico.", category: .move)
    public static let waterNoSugar = CoachingTip(
        id: "waterNoSugar", title: "Agua, sin más azúcar",
        body: "Bebe agua y evita más azúcar ahora.", category: .hydrate)
    public static let mealOrder = CoachingTip(
        id: "mealOrder", title: "Para la próxima comida",
        body: "Empezar por verdura o proteína y dejar los carbohidratos al final suele dar un pico más suave.",
        category: .food)
    public static let noteContext = CoachingTip(
        id: "noteContext", title: "Anota el contexto",
        body: "¿Estrés, poco sueño o café? Anótalo para ver el patrón.", category: .rest)
    public static let moveLight = CoachingTip(
        id: "moveLight", title: "Movimiento suave",
        body: "Unos minutos de movimiento suave, como subir escaleras o caminar, suelen ayudar.", category: .move)
    public static let alreadyFalling = CoachingTip(
        id: "alreadyFalling", title: "Ya va bajando",
        body: "La curva ya baja: espera y vuelve a mirar en 30 min.", category: .wait)
    public static let risingWait = CoachingTip(
        id: "risingWait", title: "Espera y mira",
        body: "Sin síntomas, lo normal es esperar: vuelve a mirar la curva en 30 min.", category: .wait)
    public static let highPersisting = CoachingTip(
        id: "highPersisting", title: "Si se repite",
        body: "Si ves valores altos a menudo sin motivo claro, coméntalo con un profesional de la salud.",
        category: .check)
    public static let lowSymptoms = CoachingTip(
        id: "lowSymptoms", title: "Si tienes síntomas",
        body: "Con mareo o temblor, toma algo con carbohidratos y vuelve a mirar en 15 min.", category: .food)
    public static let lowCompression = CoachingTip(
        id: "lowCompression", title: "Sin síntomas, espera",
        body: "Puede ser compresión del sensor al dormir sobre él: espera la siguiente lectura.", category: .wait)
    public static let afterExercise = CoachingTip(
        id: "afterExercise", title: "Normal tras entrenar",
        body: "Es normal tras entrenar; hidrátate y toma algo ligero si vas a seguir.", category: .hydrate)
    public static let fallingWatch = CoachingTip(
        id: "fallingWatch", title: "Vuelve a mirar",
        body: "Mira de nuevo en 15 min para ver si se estabiliza.", category: .check)
    public static let fallingSnack = CoachingTip(
        id: "fallingSnack", title: "Algo ligero",
        body: "Si llevas horas sin comer y sigue bajando, toma algo ligero.", category: .food)
    public static let noDataPhone = CoachingTip(
        id: "noDataPhone", title: "Acerca el teléfono",
        body: "Acerca el iPhone al sensor y abre LingoScan un momento.", category: .check)
    public static let noDataBluetooth = CoachingTip(
        id: "noDataBluetooth", title: "Revisa Bluetooth",
        body: "Comprueba que Bluetooth está activado y que el sensor sigue bien pegado.", category: .check)
    public static let restBreath = CoachingTip(
        id: "restBreath", title: "Pausa y respira",
        body: "Unos minutos de calma o de respiración lenta ayudan cuando el estrés sube la glucosa.",
        category: .rest)
}
