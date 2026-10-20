import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HostOrigin {
    static func valid(arguments: [String], allowed: String?) -> Bool {
        guard arguments.count == 2, let allowed, allowed.range(of: "^chrome-extension://[a-p]{32}/$", options: .regularExpression) != nil else { return false }
        return arguments[1] == allowed
    }
}

struct NativeFrameParser {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var packets: [Data] = []
        while buffer.count >= 4 {
            let size = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            guard size > 0, size <= 16 * 1024 * 1024 else { throw SolverFailure(message: "Native 메시지 크기가 올바르지 않습니다.") }
            guard buffer.count >= 4 + size else { break }
            packets.append(Data(buffer.dropFirst(4).prefix(size)))
            buffer.removeFirst(4 + size)
        }
        return packets
    }
    func finish() throws { if !buffer.isEmpty { throw SolverFailure(message: "Native 메시지가 전송 중 끊겼습니다.") } }
    static func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count < 1_000_000 else { throw SolverFailure(message: "출력 메시지 크기가 올바르지 않습니다.") }
        var length = UInt32(data.count)
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
}

struct NativeRequest: Decodable {
    var version: Int
    var type: String
    var request_id: String
    var remaining_ms: Int?
    var question: Question?
    var png_base64: String?
    var reason: String?
    static func decode(_ data: Data) throws -> NativeRequest {
        let request = try JSONDecoder().decode(NativeRequest.self, from: data)
        guard request.version == 1, UUID(uuidString: request.request_id) != nil, ["begin", "solve", "cancel"].contains(request.type) else {
            throw SolverFailure(message: "지원하지 않는 Native 메시지입니다.")
        }
        if request.type == "solve" {
            guard let q = request.question, let ms = request.remaining_ms, (1...45000).contains(ms), request.png_base64 != nil else {
                throw SolverFailure(message: "풀이 메시지에 필요한 값이 없습니다.")
            }
            try q.validate()
        }
        return request
    }
    func image() throws -> Data {
        guard let encoded = png_base64, encoded.utf8.count <= 14 * 1024 * 1024,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= 10 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20000, height <= 20000, width * height <= 40_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw SolverFailure(message: "유효한 크기의 PNG 이미지가 아닙니다.")
        }
        return data
    }
}
