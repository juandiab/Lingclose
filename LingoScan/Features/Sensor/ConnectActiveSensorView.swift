import LingoCore
import SwiftUI

/// "Conectar sensor activo" para una sesión importada (`RECUPERACION_V1.md` §5 paso 6 y §6 paso 4):
/// reconecta con kAuth/PIN o con el handshake completo. Nunca inicia un sensor nuevo: esta vista no
/// conoce la activación NFC.
struct ConnectActiveSensorView: View {
    let detail: RecoveryService.ImportedSessionDetail
    let connector: (any RecoveryActiveSensorConnecting)?

    @State private var connecting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "connect.state", defaultValue: "Estado importado"), value: detail.state.rawValue)
                LabeledContent(String(localized: "connect.receiver", defaultValue: "Receiver ID"), value: detail.receiverIDMasked ?? "—")
                LabeledContent(String(localized: "connect.origin", defaultValue: "Origen"), value: detail.fromAppID)
                LabeledContent(String(localized: "connect.sequence", defaultValue: "Copia"), value: "seq \(detail.sequence)")
                LabeledContent(String(localized: "connect.pin", defaultValue: "PIN BLE"), value: detail.hasPIN ? "✓" : "—")
                LabeledContent(String(localized: "connect.kauth", defaultValue: "kAuth"), value: detail.hasKAuth ? "✓" : "—")
                if detail.paused {
                    Label(String(localized: "connect.paused", defaultValue: "En pausa: no se conecta solo"), systemImage: "pause.circle")
                }
            }
            if detail.openConflicts > 0 {
                Section {
                    Label(String(localized: "connect.conflicts", defaultValue: "Hay conflictos de secretos sin resolver; no se conecta"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Button(String(localized: "connect.button", defaultValue: "Conectar sensor activo")) {
                    Task { await connect() }
                }
                .disabled(!detail.isConnectable || connector == nil || connecting)
            } footer: {
                Text(footer)
            }
            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle(String(localized: "connect.title", defaultValue: "Sensor activo"))
    }

    private var footer: String {
        if connector == nil {
            return String(localized: "connect.unavailable", defaultValue: "El coordinador del sensor no está disponible en esta pantalla.")
        }
        return detail.hasKAuth
            ? String(localized: "connect.footer.short", defaultValue: "Intenta el handshake corto con kAuth y PIN; si el sensor lo rechaza, el completo con la identidad de esta app. Nunca activa un sensor nuevo.")
            : String(localized: "connect.footer.full", defaultValue: "Sin kAuth: handshake completo con el PIN y la identidad de esta app. Nunca activa un sensor nuevo.")
    }

    private func connect() async {
        guard let connector else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await connector.connectActiveSensor(importedState: detail.state)
            message = String(localized: "connect.started", defaultValue: "Conexión iniciada; sigue el estado en la pestaña Sensor.")
        } catch {
            message = String(describing: error)
        }
    }
}
