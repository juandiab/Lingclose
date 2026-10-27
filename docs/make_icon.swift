import AppKit

let size = 1024.0
let rgb = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { print("sin contexto"); exit(1) }

// Fondo: degradado azul profundo → turquesa (sin esquinas redondeadas: iOS aplica la máscara)
let colors = [NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.36, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.62, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Banda de rango sutil (referencia, no médica)
ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.08).cgColor)
ctx.fill(CGRect(x: 0, y: 330, width: size, height: 300))

// Curva de glucosa: Catmull-Rom → Bézier para un trazo suave
let pts: [CGPoint] = [CGPoint(x: 80, y: 440), CGPoint(x: 230, y: 400), CGPoint(x: 400, y: 470),
                      CGPoint(x: 560, y: 650), CGPoint(x: 720, y: 690), CGPoint(x: 930, y: 580)]
let path = CGMutablePath()
path.move(to: pts[0])
for i in 0..<(pts.count - 1) {
    let p0 = i > 0 ? pts[i-1] : pts[i], p1 = pts[i], p2 = pts[i+1], p3 = i + 2 < pts.count ? pts[i+2] : pts[i+1]
    let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
    let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
    path.addCurve(to: p2, control1: c1, control2: c2)
}
// Halo
ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.25).cgColor)
ctx.setLineWidth(70); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.addPath(path); ctx.strokePath()
// Trazo principal
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(38)
ctx.addPath(path); ctx.strokePath()

// Punto de lectura actual con anillo
let end = pts.last!
ctx.setFillColor(NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.85, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: end.x - 46, y: end.y - 46, width: 92, height: 92))
ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(16)
ctx.strokeEllipse(in: CGRect(x: end.x - 46, y: end.y - 46, width: 92, height: 92))

guard let cg = ctx.makeImage() else { print("sin imagen"); exit(1) }
let rep = NSBitmapImageRep(cgImage: cg)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: out))
print("ok \(rep.pixelsWide)x\(rep.pixelsHigh) alpha=\(rep.hasAlpha) -> \(out)")
