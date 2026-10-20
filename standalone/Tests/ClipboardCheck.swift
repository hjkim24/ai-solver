import AppKit
import ImageIO
import UniformTypeIdentifiers

final class Stub: URLProtocol {
    static var replies: [[String: Any]] = []
    static var requests: [[String: Any]] = []
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n))
            }
        }
        var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        object["_path"] = request.url!.path
        Self.requests.append(object)
        let reply = Self.replies.isEmpty ? [:] : Self.replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PromisedText: NSObject, NSPasteboardItemDataProvider {
    var reads = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        reads += 1; item.setString("private promised text", forType: type)
    }
}

@main struct ClipboardCheck {
    static var passed = 0
    static func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else { fatalError("FAIL: \(name)") }; passed += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("FAIL: \(name)") } catch { passed += 1 }
    }
    static func image(_ type: UTType = .png, frames: Int = 1) -> Data {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil)!
        for _ in 0..<frames { CGImageDestinationAddImage(destination, context.makeImage()!, nil) }
        precondition(CGImageDestinationFinalize(destination)); return data as Data
    }
    static var question: [String: Any] { ["status": "readable", "question_count": 1, "question_number": "7", "stem_text": "1 + 1은?", "options": [["index": 1, "label": "A", "text": "1"], ["index": 2, "label": "B", "text": "2"]], "reason": ""] }
    static func envelope(_ object: [String: Any]) -> [String: Any] {
        ["status": "completed", "output": [["content": [["type": "output_text", "text": String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!]]]], "usage": ["input_tokens": 10, "output_tokens": 5]]
    }
    static var answer: [String: Any] { ["status": "answered", "answer_index": 2, "answer_label": "B", "explanation": "1 + 1 = 2입니다.", "sources": [], "basis": "general"] }
    static func api(_ replies: [[String: Any]], status: Int = 200) -> OpenAIClient {
        Stub.requests = []; Stub.replies = replies; Stub.status = status
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [Stub.self]
        return OpenAIClient(apiKey: "test-only", session: URLSession(configuration: configuration))
    }
    @MainActor static func main() async throws {
        let png = image()
        for type in [UTType.png, .tiff, .jpeg] {
            let converted = try ClipboardImage.png(from: image(type))
            check(converted.starts(with: [137, 80, 78, 71]), "normalize \(type)")
        }
        rejects("invalid image") { _ = try ClipboardImage.png(from: Data("bad".utf8)) }
        rejects("animated image") { _ = try ClipboardImage.png(from: image(.gif, frames: 2)) }
        rejects("oversized bytes") { _ = try ClipboardImage.png(from: Data(repeating: 0, count: 64 * 1024 * 1024 + 1)) }

        let pasteboard = NSPasteboard(name: .init("ClipboardSolverTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        func copyImage(_ data: Data = png) { pasteboard.clearContents(); pasteboard.setData(data, forType: .png) }
        copyImage()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        var images = 0; var errors = 0
        monitor.onImage = { _ in images += 1 }; monitor.onError = { _ in errors += 1 }
        monitor.poll(); check(images == 0, "disabled")
        monitor.setEnabled(true); monitor.poll(); check(images == 0, "skip existing clipboard")
        copyImage(); monitor.poll(); monitor.poll(); check(images == 1, "new image exactly once")
        pasteboard.clearContents(); pasteboard.setString("private text", forType: .string); monitor.poll()
        check(images == 1 && errors == 0, "ignore text")
        pasteboard.clearContents(); pasteboard.setString("file:///tmp/example.png", forType: .fileURL); monitor.poll()
        check(images == 1 && errors == 0, "ignore file URL")
        let provider = PromisedText(); let promised = NSPasteboardItem()
        promised.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents(); pasteboard.writeObjects([promised]); monitor.poll()
        check(provider.reads == 0, "never read promised text")
        let filePreview = NSPasteboardItem()
        filePreview.setString("file:///tmp/example.png", forType: .fileURL); filePreview.setData(png, forType: .png)
        pasteboard.clearContents(); pasteboard.writeObjects([filePreview]); monitor.poll()
        check(images == 1 && errors == 0, "ignore file copy with image preview")
        let items = (0..<2).map { _ -> NSPasteboardItem in let item = NSPasteboardItem(); item.setData(png, forType: .png); return item }
        pasteboard.clearContents(); pasteboard.writeObjects(items); monitor.poll()
        check(images == 1 && errors == 1, "reject multiple images")
        monitor.setEnabled(false); copyImage(); monitor.poll(); check(images == 1, "stop watching")
        monitor.setEnabled(true); monitor.poll(); check(images == 1, "no replay on restart")
        copyImage(); monitor.poll(); check(images == 2, "resume new images"); monitor.setEnabled(false)

        var config = Configuration(); config.mode = .general
        config.files = [ManagedFile(id: "file-private", filename: "private.pdf", status: "준비됨", attached: true, byteCount: 10)]
        config.vectorStoreID = "vs-private"
        var client = api([envelope(question), envelope(answer)])
        let result = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in })
        check(result.result.answer_index == 2 && result.question.stem_text == "1 + 1은?", "image to answer")
        check(result.usage["input_tokens"] == 20 && result.usage["output_tokens"] == 10, "combined usage")
        check(Stub.requests.count == 2 && Stub.requests.allSatisfy { $0["_path"] as? String == "/v1/responses" }, "two Responses calls")
        for request in Stub.requests {
            check(request["store"] as? Bool == false, "store false")
            let content = (request["input"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
            check(content.contains { $0["type"] as? String == "input_image" && $0["detail"] as? String == "high" }, "image input")
            check(!content.contains { $0["type"] as? String == "input_file" }, "general sends no files")
            check(!String(describing: request).contains("file-private"), "general does not leak attachment IDs")
        }
        let format = (Stub.requests[0]["text"] as! [String: Any])["format"] as! [String: Any]
        check(format["strict"] as? Bool == true, "strict extraction schema")

        for bad in [question.merging(["question_count": 2]) { _, new in new }, question.merging(["status": "unreadable"]) { _, new in new }, question.merging(["unexpected": true]) { _, new in new }, question.merging(["options": [["index": 2, "label": "B", "text": "2"]]]) { _, new in new }] {
            client = api([envelope(bad)])
            do { _ = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in }); fatalError("bad extraction accepted") } catch { passed += 1 }
            check(Stub.requests.count == 1, "invalid extraction never solves")
        }
        for reply: [String: Any] in [["status": "incomplete", "output": []], ["status": "completed", "output": [["content": [["type": "refusal"]]]]]] {
            client = api([reply])
            do { _ = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in }); fatalError("invalid response accepted") } catch { passed += 1 }
            check(Stub.requests.count == 1, "incomplete or refusal stops")
        }
        for status in [401, 429] {
            client = api([[:]], status: status)
            do { _ = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in }); fatalError("HTTP failure accepted") } catch { passed += 1 }
            check(Stub.requests.count == 1, "no automatic retry")
        }
        var rag = Configuration(); rag.mode = .rag
        client = api([])
        do { _ = try await client.answerScreenshot(image: png, configuration: rag, timeout: 45, onStage: { _ in }); fatalError("empty RAG accepted") } catch { passed += 1 }
        check(Stub.requests.isEmpty, "empty RAG costs no requests")
        client = api([])
        do { _ = try await client.answerScreenshot(image: png, configuration: config, timeout: 0, onStage: { _ in }); fatalError("expired deadline accepted") } catch { passed += 1 }
        check(Stub.requests.isEmpty, "expired deadline never sends")

        config.mode = .attachments
        client = api([envelope(question), envelope(answer)])
        _ = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in })
        let attachedContent = (Stub.requests[1]["input"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
        check(attachedContent.contains { $0["type"] as? String == "input_file" && $0["file_id"] as? String == "file-private" }, "attachment bridge")
        check(Stub.requests.count == 2, "known attachment size avoids metadata request")
        config.mode = .rag
        var ragAnswer = answer; ragAnswer["basis"] = "materials"; ragAnswer["sources"] = [["file_id": "file-private", "quote": "one plus one is two"]]
        let search: [String: Any] = ["data": [["file_id": "file-private", "filename": "private.pdf", "content": [["type": "text", "text": "one plus one is two"]]]]]
        client = api([envelope(question), search, envelope(ragAnswer)])
        let ragResult = try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in })
        check(ragResult.result.answer_index == 2 && ragResult.evidence.count == 1, "RAG bridge and citation validation")
        check(Stub.requests.count == 3 && Stub.requests[1]["_path"] as? String == "/v1/vector_stores/vs-private/search", "RAG search between recognition and answer")
        config.mode = .general
        client = api([envelope(question), envelope(answer)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.answerScreenshot(image: png, configuration: config, timeout: 45, onStage: { _ in })
        }
        do { _ = try await task.value; fatalError("cancelled task accepted") } catch { passed += 1 }
        check(Stub.requests.isEmpty, "cancelled task never sends")
        print("Clipboard checks: \(passed) passed (private pasteboard and mock API only)")
    }
}
