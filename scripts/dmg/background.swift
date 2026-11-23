// Draws the DMG window's background: dark like the app, with a line telling people to drag CAMR into Applications.
//   swift scripts/dmg/background.swift scripts/dmg   (writes background.png and background@2x.png)
import AppKit

let folder = CommandLine.arguments.dropFirst().first ?? "."
for scale in [1, 2] {
    let size = NSSize(width: 640, height: 400)
    let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
    picture.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: picture)
    NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    // The arrow between them.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: 200)); arrow.line(to: NSPoint(x: 370, y: 200))
    arrow.move(to: NSPoint(x: 356, y: 212)); arrow.line(to: NSPoint(x: 372, y: 200)); arrow.line(to: NSPoint(x: 356, y: 188))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.55).setStroke(); arrow.stroke()
    func say(_ text: String, y: CGFloat, size: CGFloat, alpha: CGFloat, weight: NSFont.Weight) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let words = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor(calibratedWhite: 1, alpha: alpha), .paragraphStyle: style])
        words.draw(in: NSRect(x: 0, y: y, width: 640, height: size * 1.5))
    }
    say("Drag CAMR into Applications", y: 330, size: 20, alpha: 0.92, weight: .semibold)
    say("Then open it from Applications. The first time, macOS asks you to allow it:", y: 70, size: 12, alpha: 0.6, weight: .regular)
    say("System Settings › Privacy & Security › Open Anyway", y: 50, size: 12, alpha: 0.6, weight: .medium)
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try! picture.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
}
