#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourceDir = root.appendingPathComponent("Sources/MacBridge/Resources", isDirectory: true)
let iconsetDir = resourceDir.appendingPathComponent("MacBridgeIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

struct Stop {
    let position: CGFloat
    let color: NSColor
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0,
            alpha: alpha
        )
    }
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

func withShadow(color: NSColor, blur: CGFloat, offset: NSSize, draw: () -> Void) {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSShadow().set()
}

func fill(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

func drawGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, alpha: CGFloat = 1.0) {
    color.withAlphaComponent(alpha).setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    graphics.cgContext.setAllowsAntialiasing(true)
    graphics.cgContext.setShouldAntialias(true)
    NSGraphicsContext.current = graphics

    let scale = CGFloat(size) / 1024.0
    graphics.cgContext.scaleBy(x: scale, y: scale)

    let background = roundedRect(72, 72, 880, 880, 210)
    withShadow(color: NSColor(hex: 0x16345D, alpha: 0.28), blur: 38, offset: NSSize(width: 0, height: -18)) {
        drawGradient(background, colors: [
            NSColor(hex: 0xF7FBFF),
            NSColor(hex: 0xCBE9FF),
            NSColor(hex: 0x8BA9FF)
        ], angle: -52)
    }

    let lowerWave = NSBezierPath()
    lowerWave.move(to: NSPoint(x: 166, y: 305))
    lowerWave.curve(to: NSPoint(x: 860, y: 418), controlPoint1: NSPoint(x: 290, y: 224), controlPoint2: NSPoint(x: 612, y: 160))
    lowerWave.line(to: NSPoint(x: 860, y: 196))
    lowerWave.curve(to: NSPoint(x: 784, y: 120), controlPoint1: NSPoint(x: 860, y: 154), controlPoint2: NSPoint(x: 826, y: 120))
    lowerWave.line(to: NSPoint(x: 240, y: 120))
    lowerWave.curve(to: NSPoint(x: 164, y: 196), controlPoint1: NSPoint(x: 198, y: 120), controlPoint2: NSPoint(x: 164, y: 154))
    lowerWave.close()
    fill(lowerWave, color: NSColor(hex: 0x3455B7, alpha: 0.14))

    let bridge = NSBezierPath()
    bridge.move(to: NSPoint(x: 251, y: 553))
    bridge.curve(to: NSPoint(x: 773, y: 553), controlPoint1: NSPoint(x: 314, y: 721), controlPoint2: NSPoint(x: 710, y: 721))
    stroke(bridge, color: NSColor(hex: 0x243B73), width: 92, alpha: 0.16)
    stroke(bridge, color: NSColor(hex: 0x35BDEB, alpha: 0.38), width: 90, alpha: 0.36)
    stroke(bridge, color: NSColor(hex: 0x37BDF8), width: 64)

    fill(roundedRect(164, 221, 696, 184, 54), color: NSColor(hex: 0x15345A, alpha: 0.18))
    fill(roundedRect(188, 250, 648, 190, 48), color: NSColor(hex: 0x1D3557, alpha: 0.92))
    fill(roundedRect(224, 349, 576, 52, 18), color: NSColor(hex: 0xEAF3FA, alpha: 0.18))

    withShadow(color: NSColor(hex: 0x16345D, alpha: 0.24), blur: 24, offset: NSSize(width: 0, height: -22)) {
        drawGradient(roundedRect(178, 414, 252, 224, 58), colors: [
            NSColor(hex: 0xFFFFFF),
            NSColor(hex: 0xEDF4FA)
        ], angle: 90)
        drawGradient(roundedRect(594, 414, 252, 224, 58), colors: [
            NSColor(hex: 0xFFFFFF),
            NSColor(hex: 0xEDF4FA)
        ], angle: 90)
    }

    let paneColor = NSColor(hex: 0x255D91)
    for x in [262.0, 312.0] {
        for y in [481.0, 531.0] {
            fill(roundedRect(CGFloat(x), CGFloat(y), 36, 36, 6), color: paneColor)
        }
    }

    let deck = NSBezierPath()
    deck.move(to: NSPoint(x: 395, y: 524))
    deck.line(to: NSPoint(x: 629, y: 524))
    stroke(deck, color: NSColor(hex: 0x31B8E8), width: 34)

    let rightArrow = NSBezierPath()
    rightArrow.move(to: NSPoint(x: 596, y: 487))
    rightArrow.line(to: NSPoint(x: 648, y: 524))
    rightArrow.line(to: NSPoint(x: 596, y: 561))
    stroke(rightArrow, color: NSColor(hex: 0x31B8E8), width: 34)

    let leftArrow = NSBezierPath()
    leftArrow.move(to: NSPoint(x: 428, y: 561))
    leftArrow.line(to: NSPoint(x: 376, y: 524))
    leftArrow.line(to: NSPoint(x: 428, y: 487))
    stroke(leftArrow, color: NSColor(hex: 0x31B8E8), width: 34)

    let command = "\u{2318}" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 132, weight: .semibold),
        .foregroundColor: NSColor(hex: 0x1C3352),
        .paragraphStyle: paragraph
    ]
    command.draw(in: NSRect(x: 614, y: 455, width: 212, height: 154), withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in outputs {
    let rep = drawIcon(size: size)
    let url = iconsetDir.appendingPathComponent(filename)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

let preview = drawIcon(size: 1024)
try preview.representation(using: .png, properties: [:])!.write(to: resourceDir.appendingPathComponent("MacBridgeIcon-preview.png"))

func bigEndianUInt32(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

func writeICNS(iconsetDir: URL, outputURL: URL) throws {
    let entries = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png")
    ]

    var chunks: [Data] = []
    var totalLength: UInt32 = 8
    for (type, filename) in entries {
        let pngData = try Data(contentsOf: iconsetDir.appendingPathComponent(filename))
        var chunk = Data(type.utf8)
        chunk.append(bigEndianUInt32(UInt32(8 + pngData.count)))
        chunk.append(pngData)
        totalLength += UInt32(chunk.count)
        chunks.append(chunk)
    }

    var icns = Data("icns".utf8)
    icns.append(bigEndianUInt32(totalLength))
    for chunk in chunks {
        icns.append(chunk)
    }
    try icns.write(to: outputURL)
}

try writeICNS(
    iconsetDir: iconsetDir,
    outputURL: resourceDir.appendingPathComponent("MacBridgeIcon.icns")
)

print("Generated iconset, preview, and icns in \(resourceDir.path)")
