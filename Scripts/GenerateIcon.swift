#!/usr/bin/swift
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let s = size
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
    ])?.draw(in: bg, angle: 270)

    let accent = NSColor(calibratedRed: 0.36, green: 0.85, blue: 0.76, alpha: 1)
    let accentDeep = NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.50, alpha: 1)

    let driveRect = NSRect(x: s * 0.22, y: s * 0.18, width: s * 0.56, height: s * 0.36)
    let drive = NSBezierPath(roundedRect: driveRect, xRadius: s * 0.08, yRadius: s * 0.08)
    NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.16, alpha: 1).setFill()
    drive.fill()
    accent.setStroke()
    drive.lineWidth = max(1.5, s * 0.028)
    drive.stroke()

    let slot = NSBezierPath(roundedRect: NSRect(x: s * 0.34, y: s * 0.42, width: s * 0.32, height: s * 0.045), xRadius: s * 0.02, yRadius: s * 0.02)
    accent.withAlphaComponent(0.85).setFill()
    slot.fill()

    let light = NSBezierPath(ovalIn: NSRect(x: s * 0.66, y: s * 0.26, width: s * 0.055, height: s * 0.055))
    accent.setFill()
    light.fill()

    let arrow = NSBezierPath()
    let stemW = s * 0.085
    let stemTop = s * 0.78
    let stemBottom = s * 0.48
    let midX = s * 0.5
    arrow.move(to: NSPoint(x: midX - stemW / 2, y: stemBottom + s * 0.08))
    arrow.line(to: NSPoint(x: midX - stemW / 2, y: stemTop))
    arrow.line(to: NSPoint(x: midX + stemW / 2, y: stemTop))
    arrow.line(to: NSPoint(x: midX + stemW / 2, y: stemBottom + s * 0.08))
    arrow.line(to: NSPoint(x: midX + s * 0.16, y: stemBottom + s * 0.08))
    arrow.line(to: NSPoint(x: midX, y: s * 0.36))
    arrow.line(to: NSPoint(x: midX - s * 0.16, y: stemBottom + s * 0.08))
    arrow.close()

    NSGradient(colors: [accent, accentDeep])?.draw(in: arrow, angle: 270)

    image.unlockFocus()
    return image
}

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    let name: String
    switch size {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_16x16@2x.png"
    case 64: name = "icon_32x32@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_128x128@2x.png"
    case 512: name = "icon_256x256@2x.png"
    default: name = "icon_512x512@2x.png"
    }
    try png.write(to: URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent(name)))
    if size == 32 {
        try png.write(to: URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("icon_32x32.png")))
    }
    if size == 256 {
        try png.write(to: URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("icon_256x256.png")))
    }
    if size == 512 {
        try png.write(to: URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("icon_512x512.png")))
    }
}

print("Icons written to \(outputDir)")
