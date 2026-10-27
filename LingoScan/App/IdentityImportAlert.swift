import SwiftUI

/// Alerta del resultado de importar la identidad (Ajustes o AirDrop), visible en cualquier pestaña.
struct IdentityImportAlert: ViewModifier {
    let model: IdentityImportModel?

    func body(content: Content) -> some View {
        if let model {
            @Bindable var model = model
            content.alert(
                model.message?.title ?? "",
                isPresented: $model.isShowingMessage,
                presenting: model.message
            ) { _ in
                Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {}
            } message: { message in
                Text(message.text)
            }
        } else {
            content
        }
    }
}
