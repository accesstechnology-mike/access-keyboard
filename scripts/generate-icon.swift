#!/usr/bin/env swift
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    NSColor(srgbRed: 0.33, green: 0.42, blue: 0.50, alpha: 1).setFill()
    rect.fill()

    let keyboardRect = NSRect(x: 168, y: 250, width: 688, height: 430)
    let keyboardPath = NSBezierPath(roundedRect: keyboardRect, xRadius: 48, yRadius: 48)
    NSColor(srgbRed: 0.82, green: 0.84, blue: 0.87, alpha: 1).setFill()
    keyboardPath.fill()

    let keyColor = NSColor.white
    let rows = [10, 9, 7]
    let keySize: CGFloat = 48
    let gap: CGFloat = 12
    var y: CGFloat = keyboardRect.maxY - 86
    for (rowIndex, count) in rows.enumerated() {
        let rowWidth = CGFloat(count) * keySize + CGFloat(count - 1) * gap
        var x = keyboardRect.midX - rowWidth / 2
        if rowIndex == 2 {
            let shift = NSRect(x: x - 72, y: y, width: 60, height: keySize)
            NSColor(srgbRed: 0.68, green: 0.71, blue: 0.75, alpha: 1).setFill()
            NSBezierPath(roundedRect: shift, xRadius: 10, yRadius: 10).fill()
        }
        for _ in 0..<count {
            let keyRect = NSRect(x: x, y: y, width: keySize, height: keySize)
            keyColor.setFill()
            NSBezierPath(roundedRect: keyRect, xRadius: 10, yRadius: 10).fill()
            x += keySize + gap
        }
        y -= keySize + 18
    }

    let space = NSRect(x: keyboardRect.midX - 160, y: keyboardRect.minY + 36, width: 320, height: 44)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: space, xRadius: 10, yRadius: 10).fill()

    let badge = NSRect(x: 392, y: 118, width: 240, height: 72)
    NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1).setFill()
    NSBezierPath(roundedRect: badge, xRadius: 36, yRadius: 36).fill()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "accessibility", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let symbolRect = NSRect(x: badge.midX - 17, y: badge.midY - 17, width: 34, height: 34)
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output)
print("Wrote \(output.path)")
