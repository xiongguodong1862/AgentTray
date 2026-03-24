#!/usr/bin/env swift

import AppKit
import Foundation

let fileURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = fileURL.deletingLastPathComponent().deletingLastPathComponent()
let appBundleURL = rootURL.appending(path: "AppBundle", directoryHint: .isDirectory)
let iconsetURL = appBundleURL.appending(path: "CodexTray.iconset", directoryHint: .isDirectory)
let icnsURL = appBundleURL.appending(path: "CodexTray.icns")
let previewURL = appBundleURL.appending(path: "AppIcon-preview.png")

struct Palette {
    static let backgroundTop = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.28, alpha: 1)
    static let backgroundBottom = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1)
    static let shellTop = NSColor(calibratedRed: 0.26, green: 0.29, blue: 0.35, alpha: 1)
    static let shellBottom = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.19, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 0.94)
    static let panelInner = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 0.98)
    static let glyph = NSColor(calibratedRed: 0.90, green: 0.96, blue: 1.0, alpha: 0.96)
    static let glyphSoft = NSColor(calibratedRed: 0.69, green: 0.82, blue: 0.93, alpha: 0.96)
    static let line = NSColor(calibratedWhite: 1, alpha: 0.10)
    static let lineSoft = NSColor(calibratedWhite: 1, alpha: 0.05)
}

func makeGlow(in rect: CGRect, color: NSColor, blur: CGFloat) -> NSImage {
    let image = NSImage(size: rect.size)
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setShadow(offset: .zero, blur: blur, color: color.cgColor)
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: CGRect(x: rect.width * 0.32, y: rect.height * 0.32, width: rect.width * 0.001, height: rect.height * 0.001))
    image.unlockFocus()
    return image
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 0) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func strokeLine(points: [CGPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    guard let first = points.first else { return }
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    color.setStroke()
    path.stroke()
}

func drawLabel(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: -0.6
    ]

    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    let drawRect = CGRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2,
        width: textSize.width,
        height: textSize.height
    )
    attributed.draw(in: drawRect)
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard NSGraphicsContext.current?.cgContext != nil else {
        image.unlockFocus()
        return image
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.22

    let clipPath = NSBezierPath(roundedRect: canvas, xRadius: corner, yRadius: corner)
    clipPath.addClip()

    let background = NSGradient(starting: Palette.backgroundTop, ending: Palette.backgroundBottom)
    background?.draw(in: canvas, angle: -90)

    let shellRect = CGRect(x: size * 0.12, y: size * 0.12, width: size * 0.76, height: size * 0.76)
    let shellGradient = NSGradient(starting: Palette.shellTop, ending: Palette.shellBottom)
    let shellPath = NSBezierPath(roundedRect: shellRect, xRadius: size * 0.19, yRadius: size * 0.19)
    shellGradient?.draw(in: shellPath, angle: -90)
    Palette.line.setStroke()
    shellPath.lineWidth = max(2, size * 0.004)
    shellPath.stroke()

    let textBlock = CGRect(x: size * 0.18, y: size * 0.24, width: size * 0.64, height: size * 0.42)
    let topTextRect = CGRect(
        x: textBlock.minX,
        y: textBlock.midY + size * 0.06,
        width: textBlock.width,
        height: size * 0.24
    )
    let bottomTextRect = CGRect(
        x: textBlock.minX,
        y: textBlock.midY - size * 0.18,
        width: textBlock.width,
        height: size * 0.24
    )

    drawLabel("Agent", in: topTextRect, size: size * 0.264, color: Palette.glyph)
    drawLabel("Tray", in: bottomTextRect, size: size * 0.264, color: Palette.glyphSoft)

    let borderPath = NSBezierPath(roundedRect: canvas.insetBy(dx: size * 0.006, dy: size * 0.006), xRadius: corner * 0.96, yRadius: corner * 0.96)
    borderPath.lineWidth = max(2, size * 0.004)
    NSColor.black.withAlphaComponent(0.14).setStroke()
    borderPath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "CodexTrayIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG."])
    }

    try pngData.write(to: url)
}

let fileManager = FileManager.default
if fileManager.fileExists(atPath: iconsetURL.path()) {
    try fileManager.removeItem(at: iconsetURL)
}
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try writePNG(renderIcon(size: 1024), to: previewURL)

for (name, size) in sizes {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(size)", "\(size)",
        previewURL.path(),
        "--out", iconsetURL.appending(path: name).path()
    ]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "CodexTrayIcon",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "sips failed while generating \(name)."]
        )
    }
}

let pillowProcess = Process()
pillowProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
pillowProcess.arguments = [
    "-c",
    """
from PIL import Image
img = Image.open(r'\(previewURL.path())').convert('RGBA')
img.save(r'\(icnsURL.path())', format='ICNS', sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
"""
]
try pillowProcess.run()
pillowProcess.waitUntilExit()

guard pillowProcess.terminationStatus == 0 else {
    throw NSError(
        domain: "CodexTrayIcon",
        code: Int(pillowProcess.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "Python Pillow failed while generating the icns file."]
    )
}

print("Generated \(previewURL.path())")
print("Generated \(icnsURL.path())")
