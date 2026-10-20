import AppKit
import PDFKit

final class ClaudeStub: URLProtocol {
    static var replies: [[String: Any]] = []
    static var requests: [URLRequest] = []
    static var bodies: [[String: Any]] = []
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
        }
        Self.requests.append(request)
        Self.bodies.append((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        let reply = Self.replies.isEmpty ? [:] : Self.replies.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ClaudeCheck {
    static var passed = 0
    static func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); passed += 1 }
    static var read: [String: Any] { ["status": "readable", "question_count": 1, "question_number": "7", "stem_text": "전압 voltage란?", "options": [["index": 1, "label": "A", "text": "전위차"], ["index": 2, "label": "B", "text": "전류"]], "reason": ""] }
    static func message(_ object: [String: Any], stop: String = "end_turn") -> [String: Any] {
        ["stop_reason": stop, "content": [["type": "text", "text": String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!]], "usage": ["input_tokens": 10, "output_tokens": 5]]
    }
    static var answer: [String: Any] { ["status": "answered", "answer_index": 1, "answer_label": "A", "explanation": "전압은 전위차입니다.", "sources": [], "basis": "general"] }
    @MainActor static func main() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("claude-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let materials = ClaudeMaterials(root: temp.appendingPathComponent("materials"))
        let document = temp.appendingPathComponent("lecture.txt")
        try Data("Voltage is the difference in electric potential. 전압은 전위차이다.".utf8).write(to: document)
        let file = try materials.add(document)
        check(file.status == "준비됨", "local text is ready to attach")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ClaudeStub.self]
        func api(_ replies: [[String: Any]], status: Int = 200) -> ClaudeClient {
            ClaudeStub.requests = []; ClaudeStub.bodies = []; ClaudeStub.replies = replies; ClaudeStub.status = status
            return ClaudeClient(apiKey: "fixture-claude-key", session: URLSession(configuration: configuration), materials: materials)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = bitmap.representation(using: .png, properties: [:])!
        let blank = PDFDocument(); blank.insert(PDFPage(image: NSImage(data: image)!)!, at: 0)
        let pdfURL = temp.appendingPathComponent("scan.pdf"); try blank.dataRepresentation()!.write(to: pdfURL)
        let pdf = try materials.add(pdfURL)
        let pdfInput = try materials.input(pdf)
        check(pdf.status == "준비됨" && (pdfInput["source"] as? [String: Any])?["media_type"] as? String == "application/pdf", "scanned PDF is ready as an original document")
        var config = Configuration(); config.provider = .anthropic; config.claudeModel = "claude-fixture"; config.mode = .general
        config.files = [ManagedFile(id: "file-openai-private", filename: "private.pdf", status: "준비됨", attached: true)]
        config.claudeFiles = [file]
        var client = api([message(read), message(answer)])
        var result = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in })
        check(result.result.answer_index == 1 && result.usage["input_tokens"] == 20, "Claude recognition and solve")
        check(ClaudeStub.requests.count == 2 && ClaudeStub.requests.allSatisfy { $0.url?.absoluteString == "https://api.anthropic.com/v1/messages" }, "Claude uses only Messages API")
        check(ClaudeStub.requests.allSatisfy { $0.value(forHTTPHeaderField: "x-api-key") == "fixture-claude-key" && $0.value(forHTTPHeaderField: "Authorization") == nil }, "provider credentials stay on provider host")
        for body in ClaudeStub.bodies {
            check(body["model"] as? String == "claude-fixture" && body["output_config"] != nil && body["max_tokens"] != nil, "native model and structured output")
            let content = (body["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
            check(content.contains { $0["type"] as? String == "image" }, "native image block")
            check(!String(describing: body).contains(file.id) && !String(describing: body).contains("file-openai-private"), "general sends no material data")
        }
        config.mode = .attachments
        client = api([message(read), message(answer)])
        _ = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in })
        check(String(describing: ClaudeStub.bodies.last!).contains("Voltage is the difference"), "Claude attaches full text")
        var cited = answer; cited["basis"] = "mixed"; cited["sources"] = [["file_id": file.id, "quote": "Voltage is the difference in electric potential."]]
        client = api([message(read), message(cited)])
        result = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in })
        check(result.attachments.map(\.id) == [file.id] && result.result.basis == "mixed" && ClaudeStub.requests.count == 2, "Claude combines original documents and model knowledge")
        config.claudeFiles = []
        client = api([message(read), message(answer)])
        result = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in })
        check(result.result.basis == "general" && result.usage["input_tokens"] == 20, "attachment mode can answer without files")
        config.mode = .general
        for response in [message(read, stop: "max_tokens"), ["stop_reason": "refusal", "content": []], ["stop_reason": "end_turn", "content": [["type": "text", "text": "bad-json"]]]] {
            client = api([response])
            do { _ = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in }); fatalError("invalid Claude result accepted") } catch { passed += 1 }
            check(ClaudeStub.requests.count == 1, "invalid recognition never solves")
        }
        client = api([[:]], status: 401)
        do { _ = try await client.answerScreenshot(image: image, configuration: config, timeout: 45, onStage: { _ in }); fatalError("bad key accepted") } catch { passed += 1 }
        check(ClaudeStub.requests.count == 1, "no retry on API failure")
        var tooLarge = image; tooLarge.append(Data(repeating: 0, count: 7_600_000))
        client = api([])
        do { _ = try await client.structured(model: "claude-fixture", instructions: "", input: [.image(tooLarge)], name: "test", schema: [:], timeout: 5); fatalError("oversized image sent") } catch { passed += 1 }
        check(ClaudeStub.requests.isEmpty, "oversized image rejected before any API call")
        try materials.remove(file.id)
        do { _ = try materials.data(file.id); fatalError("deleted file readable") } catch { passed += 1 }
        do { _ = try materials.data("../../private"); fatalError("path traversal accepted") } catch { passed += 1 }
        print("Claude checks: \(passed) passed; no real API/key/clipboard")
    }
}
