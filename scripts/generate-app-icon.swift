import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift generate-app-icon.swift <output.png>")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func sparkle(center: NSPoint, radius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for pointIndex in 0..<8 {
        let angle = CGFloat(pointIndex) * .pi / 4 - .pi / 2
        let pointRadius = pointIndex.isMultiple(of: 2) ? radius : innerRadius
        let point = NSPoint(
            x: center.x + cos(angle) * pointRadius,
            y: center.y + sin(angle) * pointRadius
        )
        if pointIndex == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    return path
}

let canvasSize = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let background = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
NSGradient(colors: [
    color(0.035, 0.32, 0.27),
    color(0.04, 0.62, 0.47)
])!.draw(in: background, angle: 45)

let device = roundedRect(NSRect(x: 156, y: 226, width: 712, height: 492), radius: 96)
let shadow = NSShadow()
shadow.shadowColor = color(0.01, 0.16, 0.13).withAlphaComponent(0.34)
shadow.shadowBlurRadius = 44
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
NSGradient(colors: [
    color(0.98, 1.0, 0.98),
    color(0.77, 0.91, 0.84)
])!.draw(in: device, angle: 90)
NSShadow().set()

let panel = roundedRect(NSRect(x: 226, y: 306, width: 572, height: 286), radius: 58)
NSGradient(colors: [
    color(1.0, 1.0, 0.98),
    color(0.90, 0.97, 0.92)
])!.draw(in: panel, angle: 90)

for rowY in [365.0, 439.0, 513.0] {
    let marker = NSBezierPath(ovalIn: NSRect(x: 286, y: rowY, width: 26, height: 26))
    color(0.12, 0.66, 0.48).setFill()
    marker.fill()
}

for (rowY, width) in [(369.0, 288.0), (443.0, 232.0), (517.0, 318.0)] {
    color(0.22, 0.40, 0.34).withAlphaComponent(0.82).setFill()
    roundedRect(NSRect(x: 338, y: rowY, width: width, height: 18), radius: 9).fill()
}

color(0.08, 0.34, 0.29).setFill()
roundedRect(NSRect(x: 274, y: 258, width: 370, height: 18), radius: 9).fill()
color(0.20, 0.75, 0.48).setFill()
NSBezierPath(ovalIn: NSRect(x: 716, y: 251, width: 32, height: 32)).fill()

color(1.0, 0.83, 0.33).setFill()
sparkle(center: NSPoint(x: 752, y: 770), radius: 112, innerRadius: 34).fill()
color(0.74, 0.96, 0.68).setFill()
sparkle(center: NSPoint(x: 248, y: 772), radius: 42, innerRadius: 14).fill()

NSGraphicsContext.restoreGraphicsState()

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pngData = bitmap.representation(using: .png, properties: [:])!
try pngData.write(to: outputURL, options: .atomic)