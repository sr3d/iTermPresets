// Draws the app icon and builds Icon/AppIcon.icns.  Run: swift Icon/make-icon.swift
import AppKit

let size: CGFloat = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(_ ctx: CGContext) {
    // Flip so y grows downward, like the layout sketches.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: an 824pt body with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x0F172A).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0x334155).cgColor, rgb(0x0B1220).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Tabs: three colored pills, the first one "active".
    let tabs: [(UInt32, CGFloat)] = [(0x3B82F6, 1), (0x22C55E, 0.85), (0xF97316, 0.85)]
    var x: CGFloat = 176
    for (i, tab) in tabs.enumerated() {
        let r = CGRect(x: x, y: 196, width: 200, height: 64)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(rgb(tab.0, i == 0 ? 1 : 0.32).cgColor)
        ctx.fillPath()
        let dot = CGRect(x: r.minX + 26, y: r.midY - 12, width: 24, height: 24)
        ctx.setFillColor((i == 0 ? NSColor.white : rgb(tab.0)).cgColor)
        ctx.fillEllipse(in: dot)
        x += 224
    }

    // Terminal area split into panes: big left pane, right column split top/bottom.
    let area = CGRect(x: 176, y: 292, width: 672, height: 556)
    let gap: CGFloat = 16
    let left = CGRect(x: area.minX, y: area.minY, width: (area.width - gap) * 0.56, height: area.height)
    let rightX = left.maxX + gap, rightW = area.maxX - rightX
    let topRight = CGRect(x: rightX, y: area.minY, width: rightW, height: (area.height - gap) / 2)
    let bottomRight = CGRect(x: rightX, y: topRight.maxY + gap, width: rightW, height: topRight.height)

    for (pane, active) in [(left, true), (topRight, false), (bottomRight, false)] {
        ctx.addPath(CGPath(roundedRect: pane, cornerWidth: 26, cornerHeight: 26, transform: nil))
        ctx.setFillColor((active ? rgb(0x0B1A33, 0.85) : NSColor.black.withAlphaComponent(0.45)).cgColor)
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: pane.insetBy(dx: 2, dy: 2), cornerWidth: 24, cornerHeight: 24, transform: nil))
        ctx.setStrokeColor(rgb(0x3B82F6, active ? 0.9 : 0.35).cgColor)
        ctx.setLineWidth(active ? 5 : 3)
        ctx.strokePath()
    }

    // Prompt in the active pane.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let font = NSFont.monospacedSystemFont(ofSize: 120, weight: .heavy)
    let prompt = NSMutableAttributedString(string: "❯", attributes: [.font: font, .foregroundColor: rgb(0x22C55E)])
    prompt.append(NSAttributedString(string: "_", attributes: [.font: font, .foregroundColor: NSColor.white]))
    prompt.draw(at: CGPoint(x: left.minX + 40, y: left.minY + 36))
    NSGraphicsContext.restoreGraphicsState()

    // "Output" lines in the other panes.
    func lines(in pane: CGRect, widths: [CGFloat], color: UInt32, top: CGFloat = 44) {
        var y = pane.minY + top
        for w in widths {
            let line = CGRect(x: pane.minX + 36, y: y, width: (pane.width - 72) * w, height: 20)
            ctx.addPath(CGPath(roundedRect: line, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.setFillColor(rgb(color, 0.75).cgColor)
            ctx.fillPath()
            y += 44
        }
    }
    lines(in: left, widths: [0.8, 0.55, 0.7], color: 0x94A3B8, top: 230)
    lines(in: topRight, widths: [0.85, 0.6, 0.75], color: 0x94A3B8)
    lines(in: bottomRight, widths: [0.5, 0.8, 0.35], color: 0xF97316)

    // Subtle top highlight on the body.
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Icon")
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: dir.appendingPathComponent("AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try! task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(dir.path)/AppIcon.icns" : "iconutil failed")
