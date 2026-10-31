import SwiftUI

@main
struct LingoScanApp: App {
    /// Se construye una sola vez, al arrancar (también en relanzamientos por BLE).
    @State private var root = AppRoot.make()

    var body: some Scene {
        WindowGroup {
            rootContent
                // En la raíz: cambia al instante en toda la app, incluidas hojas y la barra de pestañas.
                .appColorScheme()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch root {
        case .live(let environment):
            RootTabView(environment: environment)
                .onOpenURL { url in
                    // JSON de identidad recibido por AirDrop o "Abrir con".
                    guard url.pathExtension.lowercased() == "json" else { return }
                    Task {
                        await environment.identityImport.importIdentity(from: url)
                        // La copia que deja AirDrop/"Abrir con" en Documents/Inbox es del sistema, no el
                        // archivo elegido por el usuario: contiene la clave privada y se borra tras importar.
                        if url.path.contains("/Documents/Inbox/") {
                            try? FileManager.default.removeItem(at: url)
                        }
                    }
                }
        case .preview(let state):
            RootTabView(previewState: state)
        case .failed(let reason):
            ContentUnavailableView(
                String(localized: "app.failed.title", defaultValue: "No se pudo abrir la base de datos"),
                systemImage: "externaldrive.badge.xmark",
                description: Text(reason)
            )
        }
    }
}
