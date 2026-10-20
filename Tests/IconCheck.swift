import AppKit
import ImageIO

@main struct IconCheck {
    @MainActor static func main() throws {
        let path = "build/Clipboard AI Solver.app"
        let bundle = Bundle(path: path)!
        precondition(bundle.bundleIdentifier == "com.hjkim24.clipboard-ai-solver")
        precondition(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.2.3")
        precondition(bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "AppIcon.icns")
        let url = bundle.url(forResource: "AppIcon", withExtension: "icns")!
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        var sizes = Set<Int>()
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as! [CFString: Any]
            let width = properties[kCGImagePropertyPixelWidth] as! Int
            precondition(width == properties[kCGImagePropertyPixelHeight] as! Int)
            sizes.insert(width)
        }
        precondition(sizes.contains(16) && sizes.contains(1024))
        let icon = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).path)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/resolved-app-icon.png"))
        print("Icon checks passed: bundle reference, version, square variants \(sizes.sorted()), native icon resolution")
    }
}
