#!/usr/bin/env swift
import AppKit

// Colours from https://www.accesstechnology.co.uk
let field = NSColor(srgbRed: 26 / 255, green: 44 / 255, blue: 65 / 255, alpha: 1)
let surface = NSColor(srgbRed: 245 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)
let shiftColor = NSColor(srgbRed: 36 / 255, green: 118 / 255, blue: 237 / 255, alpha: 1)
let accent = NSColor(srgbRed: 51 / 255, green: 222 / 255, blue: 207 / 255, alpha: 1)

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    field.setFill()
    rect.fill()

    let keyboardRect = NSRect(x: 168, y: 297, width: 688, height: 430)
    let keyboardPath = NSBezierPath(roundedRect: keyboardRect, xRadius: 48, yRadius: 48)
    surface.setFill()
    keyboardPath.fill()

    let rows = [10, 9, 7]
    let keySize: CGFloat = 48
    let gap: CGFloat = 12
    var y: CGFloat = keyboardRect.maxY - 86
    for (rowIndex, count) in rows.enumerated() {
        let rowWidth = CGFloat(count) * keySize + CGFloat(count - 1) * gap
        var x = keyboardRect.midX - rowWidth / 2
        if rowIndex == 2 {
            let shift = NSRect(x: x - 72, y: y, width: 60, height: keySize)
            shiftColor.setFill()
            NSBezierPath(roundedRect: shift, xRadius: 10, yRadius: 10).fill()
        }
        for _ in 0..<count {
            let keyRect = NSRect(x: x, y: y, width: keySize, height: keySize)
            field.setFill()
            NSBezierPath(roundedRect: keyRect, xRadius: 10, yRadius: 10).fill()
            x += keySize + gap
        }
        y -= keySize + 18
    }

    let space = NSRect(x: keyboardRect.midX - 160, y: keyboardRect.minY + 36, width: 320, height: 44)
    accent.setFill()
    NSBezierPath(roundedRect: space, xRadius: 10, yRadius: 10).fill()

    return true
}

guard let tiff = image.tiffRepresentation,
      let sourced = NSBitmapImageRep(data: tiff) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

// App Store Connect rejects 1024 icons that still have an alpha channel,
// even when every pixel is opaque.
guard let flattened = sourced.converting(to: .sRGB, renderingIntent: .default) else {
    fputs("Failed to convert icon to sRGB\n", stderr)
    exit(1)
}
let opaque = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: flattened.pixelsWide,
    pixelsHigh: flattened.pixelsHigh,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 24
)
guard let opaque else {
    fputs("Failed to allocate opaque icon bitmap\n", stderr)
    exit(1)
}
guard let context = NSGraphicsContext(bitmapImageRep: opaque) else {
    fputs("Failed to draw opaque icon\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSImage(cgImage: flattened.cgImage!, size: NSSize(width: flattened.pixelsWide, height: flattened.pixelsHigh))
    .draw(in: NSRect(x: 0, y: 0, width: flattened.pixelsWide, height: flattened.pixelsHigh))
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = opaque.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output)
print("Wrote \(output.path)")
