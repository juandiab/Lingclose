import CoreGraphics
import UIKit

/// Mide cuántas líneas ocupa un texto con la fuente del sistema, para que el reparto de páginas sepa la altura de
/// subtítulos y párrafos sin depender de SwiftUI (T-34). Usa `UIFont` solo para medir; no se dibuja con él.
enum MedicalTextMetrics {
    /// Altura (pt) de `text` con la fuente del sistema de `size` pt, ajustado a `width`, como mucho `maxLines` líneas.
    static func height(of text: String, size: CGFloat, weight: UIFont.Weight = .regular, width: CGFloat,
                       maxLines: Int = .max) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        let lineHeight = font.lineHeight
        let lines = max(1, Int((bounds.height / lineHeight).rounded(.up)))
        return CGFloat(min(lines, maxLines)) * lineHeight
    }
}
