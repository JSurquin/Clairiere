import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    NSColor(srgbRed: 0.09, green: 0.10, blue: 0.075, alpha: 1).setFill()
    rect.fill()

    let leaf = NSColor(srgbRed: 0.78, green: 0.95, blue: 0.43, alpha: 1)
    let gold = NSColor(srgbRed: 0.94, green: 0.76, blue: 0.48, alpha: 0.9)
    let center = NSPoint(x: 512, y: 500)

    gold.setStroke()
    let outer = NSBezierPath()
    outer.lineWidth = 28
    outer.lineCapStyle = .round
    outer.appendArc(withCenter: center, radius: 300, startAngle: 210, endAngle: 18, clockwise: true)
    outer.stroke()

    leaf.setStroke()
    let arc = NSBezierPath()
    arc.lineWidth = 54
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: center, radius: 210, startAngle: 196, endAngle: -16, clockwise: true)
    arc.stroke()

    leaf.setFill()
    NSBezierPath(ovalIn: NSRect(x: 470, y: 678, width: 92, height: 92)).fill()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icône impossible à dessiner\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: url)
