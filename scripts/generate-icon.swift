import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let size = Double(CommandLine.arguments[2]),
      size.isFinite, size >= 1, size <= 4_096, size.rounded() == size else {
    fputs("usage: generate-icon.swift OUTPUT SIZE\n", stderr)
    exit(2)
}

let output = CommandLine.arguments[1]
// Render exact pixels without a Retina-sized intermediate or TIFF conversion.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: Int(size) * 4, bitsPerPixel: 32
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(3) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let inset = size * 0.035
let tileRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.22, yRadius: size * 0.22)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.55, blue: 0.32, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.22, blue: 0.15, alpha: 1)
])!
gradient.draw(in: tile, angle: -55)

NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSColor.white.withAlphaComponent(0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: size * 0.05, y: size * 0.47, width: size * 0.90, height: size * 0.58)).fill()

let handle = NSBezierPath()
handle.lineWidth = size * 0.075
handle.lineCapStyle = .round
handle.move(to: NSPoint(x: size * 0.31, y: size * 0.74))
handle.line(to: NSPoint(x: size * 0.63, y: size * 0.42))
NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.72, alpha: 1).setStroke()
handle.stroke()

let collar = NSBezierPath()
collar.lineWidth = size * 0.12
collar.lineCapStyle = .round
collar.move(to: NSPoint(x: size * 0.56, y: size * 0.47))
collar.line(to: NSPoint(x: size * 0.68, y: size * 0.35))
NSColor(calibratedRed: 0.84, green: 0.63, blue: 0.25, alpha: 1).setStroke()
collar.stroke()

let bristles = NSBezierPath()
bristles.move(to: NSPoint(x: size * 0.63, y: size * 0.42))
bristles.line(to: NSPoint(x: size * 0.82, y: size * 0.24))
bristles.line(to: NSPoint(x: size * 0.91, y: size * 0.33))
bristles.line(to: NSPoint(x: size * 0.73, y: size * 0.53))
bristles.close()
NSColor.white.withAlphaComponent(0.94).setFill()
bristles.fill()

let bristleLines = [
    (0.68, 0.43, 0.82, 0.29),
    (0.73, 0.47, 0.87, 0.33),
    (0.78, 0.49, 0.89, 0.38)
]
NSGraphicsContext.saveGraphicsState()
bristles.addClip()
for (startX, startY, endX, endY) in bristleLines {
    let line = NSBezierPath()
    line.lineWidth = size * 0.018
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: size * startX, y: size * startY))
    line.line(to: NSPoint(x: size * endX, y: size * endY))
    NSColor(calibratedRed: 0.05, green: 0.35, blue: 0.23, alpha: 0.55).setStroke()
    line.stroke()
}
NSGraphicsContext.restoreGraphicsState()

func sparkle(x: Double, y: Double, radius: Double) {
    let path = NSBezierPath()
    path.lineWidth = size * 0.026
    path.lineCapStyle = .round
    path.move(to: NSPoint(x: size * x, y: size * (y - radius)))
    path.line(to: NSPoint(x: size * x, y: size * (y + radius)))
    path.move(to: NSPoint(x: size * (x - radius), y: size * y))
    path.line(to: NSPoint(x: size * (x + radius), y: size * y))
    NSColor.white.setStroke()
    path.stroke()
}

sparkle(x: 0.70, y: 0.75, radius: 0.085)
sparkle(x: 0.48, y: 0.28, radius: 0.055)

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(4)
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
