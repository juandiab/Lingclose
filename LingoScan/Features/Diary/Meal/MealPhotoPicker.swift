import PhotosUI
import SwiftUI
import UIKit

/// Elegir una foto de la biblioteca (`PhotosPicker`, sin permiso de Fotos) o tomarla con la cámara.
/// Entrega siempre un JPEG ya reducido (`MealImageDownscaler`); la foto original no se guarda.
///
/// UIKit solo aquí: no existe una API de SwiftUI para capturar con la cámara del sistema, así que
/// `CameraPicker` envuelve `UIImagePickerController`. La miniatura usa `UIImage` por el mismo motivo.
struct MealPhotoPicker: View {
    let photoJPEG: Data?
    let onPhoto: (Data?) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isLoading = false
    @State private var didFail = false

    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            if let photoJPEG, let image = UIImage(data: photoJPEG) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                    .accessibilityLabel(String(localized: "meal.photo.preview", defaultValue: "Foto elegida"))
            }
            HStack(spacing: Tokens.Spacing.sm) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(
                        photoJPEG == nil
                            ? String(localized: "meal.photo.library", defaultValue: "Elegir foto")
                            : String(localized: "meal.photo.replace", defaultValue: "Cambiar foto"),
                        systemImage: "photo.on.rectangle")
                }
                if cameraAvailable {
                    Button(String(localized: "meal.photo.camera", defaultValue: "Cámara"), systemImage: "camera") {
                        isCameraPresented = true
                    }
                }
                if photoJPEG != nil {
                    Button(String(localized: "meal.photo.remove", defaultValue: "Quitar"), systemImage: "xmark.circle", role: .destructive) {
                        onPhoto(nil)
                    }
                }
            }
            .buttonStyle(.borderless)
            if isLoading {
                ProgressView()
            }
            if didFail {
                Text(String(localized: "meal.photo.failed", defaultValue: "No se pudo leer esa foto. Prueba con otra."))
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.error)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { image in
                isCameraPresented = false
                guard let image else { return }
                Task { await reduce(image.jpegData(compressionQuality: 0.9)) }
            }
            .ignoresSafeArea()
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        didFail = false
        defer {
            isLoading = false
            pickerItem = nil
        }
        await reduce(try? await item.loadTransferable(type: Data.self))
    }

    private func reduce(_ data: Data?) async {
        guard let data, let jpeg = await MealImageDownscaler.jpeg(from: data) else {
            didFail = true
            return
        }
        didFail = false
        onPhoto(jpeg)
    }
}

/// Cámara del sistema. Se descarta sin guardar nada en la fototeca.
private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
