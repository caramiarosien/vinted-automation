import AppKit
import Foundation
let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Georgia-Italic", size: 740) ?? NSFont.systemFont(ofSize: 740), .foregroundColor: NSColor(calibratedRed: 0.19, green: 0.36, blue: 0.27, alpha: 1)]
("w" as NSString).draw(at: NSPoint(x: 130, y: 120), withAttributes: attributes)
NSColor(calibratedRed: 0.83, green: 0.53, blue: 0.32, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 775, y: 410, width: 100, height: 100)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
