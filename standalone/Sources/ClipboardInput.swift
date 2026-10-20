import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ClipboardMonitor {
    var onImage: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    private let pasteboard: NSPasteboard
    private var enabled = false
    private var seen = 0
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    func setEnabled(_ value: Bool) {
        timer?.invalidate(); timer = nil; enabled = value
        guard value else { return }
        seen = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func poll() {
        guard enabled, pasteboard.changeCount != seen else { return }
        let version = pasteboard.changeCount; seen = version
        // Inspect types only: text, file URLs and their promised file contents are never read.
        let images = (pasteboard.pasteboardItems ?? []).compactMap { item -> (NSPasteboardItem, NSPasteboard.PasteboardType)? in
            guard !item.types.contains(.fileURL) else { return nil }
            let type = item.types.contains(.png) ? .png : item.types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
            return type.map { (item, $0) }
        }
        guard !images.isEmpty else { return }
        guard images.count == 1 else { onError?("이미지 하나만 클립보드에 복사하세요."); return }
        let data = images[0].0.data(forType: images[0].1)
        guard pasteboard.changeCount == version else { return }
        guard let data, !data.isEmpty else { onError?("클립보드 이미지를 읽지 못했습니다. 다시 캡처하세요."); return }
        onImage?(data)
    }
}

enum ClipboardImage {
    static func png(from data: Data) throws -> Data {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 64 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000 else {
            throw SolverFailure(message: "단일 이미지(64 MiB·40 MP·한 변 20,000 px 이하)를 복사하세요.", deferred: true)
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SolverFailure(message: "이미지를 해석하지 못했습니다. 다시 캡처하세요.", deferred: true)
        }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw SolverFailure(message: "PNG 변환을 시작하지 못했습니다.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 10 * 1024 * 1024 else {
            throw SolverFailure(message: "PNG가 10 MiB를 넘거나 변환에 실패했습니다. 문제만 포함하도록 작게 캡처하세요.", deferred: true)
        }
        try Task.checkCancellation()
        return output as Data
    }
}
