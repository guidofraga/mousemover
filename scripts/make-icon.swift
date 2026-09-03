import AppKit

let symbolName = "cursorarrow.motionlines"

let scriptDir = URL(fileURLWithPath: (#filePath as NSString).deletingLastPathComponent)
let repoRoot = scriptDir.deletingLastPathComponent()
let resourcesDir = repoRoot.appendingPathComponent("Resources")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let iconsetDir = repoRoot.appendingPathComponent(".build/AppIcon.iconset")

func tintedSymbol(width: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: width, weight: .bold)) else { return nil }
    let size = symbol.size
    return NSImage(size: size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.setFill()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func drawIcon(size: CGFloat) {
    let inset = size * (100 / 1024)
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    let top = NSColor(srgbRed: 0.33, green: 0.56, blue: 0.99, alpha: 1)
    let bottom = NSColor(srgbRed: 0.45, green: 0.32, blue: 0.96, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

    guard let tinted = tintedSymbol(width: rect.width * 0.56) else {
        FileHandle.standardError.write("error: symbol \(symbolName) not available on this macOS version\n".data(using: .utf8)!)
        exit(1)
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: rect.midX - s.width / 2,
                           y: rect.midY - s.height / 2,
                           width: s.width,
                           height: s.height))
}

func pngData(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(size: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

do {
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    for (name, px) in sizes {
        guard let data = pngData(pixelSize: px) else {
            throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to render \(name)"])
        }
        try data.write(to: iconsetDir.appendingPathComponent(name))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: Int(iconutil.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
    try FileManager.default.removeItem(at: iconsetDir)

    if CommandLine.arguments.count > 1 {
        let preview = URL(fileURLWithPath: CommandLine.arguments[1])
        try pngData(pixelSize: 512)?.write(to: preview)
        print("preview: \(preview.path)")
    }
    print("wrote \(icnsURL.path)")
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
