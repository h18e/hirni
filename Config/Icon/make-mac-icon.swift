import AppKit
// Mac-Icon nach Apples Raster: Form 824×824 in 1024, Ecken rund (kontinuierlich), Rand transparent.
let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!
let out = args[2]
let inset = 100.0, shape = 824.0, radius = 185.4
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: inset, y: inset, width: shape, height: shape)
// leichter Schatten wie bei Systemsymbolen
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 10; shadow.shadowOffset = NSSize(width: 0, height: -6)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
NSGraphicsContext.restoreGraphicsState()
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: out))

