import Foundation
import AppKit

final class StubProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))!
    static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count < 0 { throw SolverFailure(message: "모의 요청 body 읽기 실패") }
            if count == 0 { return data }
            data.append(contentsOf: bytes.prefix(count))
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct SelfCheck {
    static var passed = 0
    static func check(_ name: String, _ body: () throws -> Void) throws {
        do { try body(); passed += 1 }
        catch { throw NSError(domain: "SelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): \(error.localizedDescription)"]) }
    }
    static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw NSError(domain: "SelfCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: reason]) }
    }
    static func rejects(_ body: () throws -> Void) throws {
        var rejected = false
        do { try body() } catch { rejected = true }
        try require(rejected, "잘못된 입력을 허용함")
    }
    static func question() -> Question {
        Question(page_session_id: "document-1", question_key: "question-4", question_number: "4", stem_text: "물의 분자식은?", options: [
            Question.Option(index: 1, label: "A", text: "H₂O"), Question.Option(index: 2, label: "B", text: "CO₂")
        ])
    }
    static func png() -> Data {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
    }
    static func main() async throws {
        let q = question()
        try check("startup preserves ready files and makes interrupted deletions retryable") {
            var config = Configuration()
            config.files = [.init(id: "ready", filename: "old.pdf", status: "준비됨"), .init(id: "deleting", filename: "old2.pdf", status: "삭제 중")]
            config.claudeFiles = [.init(id: "local-deleting", filename: "notes.txt", status: "삭제 중")]
            config.invalidateCachedStatuses()
            try require(config.files[0].status == "준비됨" && config.files[1].status == "삭제 실패" && config.claudeFiles[0].status == "삭제 실패", "재시작 뒤 자료 상태를 보존하지 못함")
        }
        let attachments = [ManagedFile(id: "file-1", filename: "lecture.pdf", status: "준비됨", attached: true, byteCount: 100)]
        let answer = SolveResult(status: "answered", answer_index: 1, answer_label: "A", explanation: "제공 자료의 물 분자식과 일치합니다.", sources: [SolveResult.Source(file_id: "file-1", quote: "물의 분자식은 H₂O이다.")])
        try check("accept complete question and grounded answer") {
            try q.validate()
            try answer.validate(question: q, mode: .attachments, attachments: attachments)
        }
        try check("reject model index outside actual options") {
            var invalid = answer; invalid.answer_index = 3
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
        }
        try check("reject wrong original label") {
            var invalid = answer; invalid.answer_label = "B"
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
        }
        try check("reject unknown attachment IDs and empty quotes") {
            var invalid = answer; invalid.sources = [.init(file_id: "other", quote: "물의 분자식은 H₂O이다.")]
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
            invalid.sources = [.init(file_id: "file-1", quote: "  ")]
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
        }
        try check("reject material answer without attribution") {
            var invalid = answer; invalid.sources = []
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
        }
        try check("abstention must not contain an answer") {
            var invalid = answer; invalid.status = "uncertain"
            try rejects { try invalid.validate(question: q, mode: .attachments, attachments: attachments) }
        }
        try check("reject invalid option ordering") {
            var invalid = q; invalid.options[1].index = 1
            try rejects { try invalid.validate() }
        }
        try check("reject oversized question text") {
            var invalid = q; invalid.stem_text = String(repeating: "가", count: 24000)
            try rejects { try invalid.validate() }
        }
        try check("partial and consecutive native frames") {
            let frame = Data([7, 0, 0, 0]) + Data("{\"x\":1}".utf8)
            var parser = NativeFrameParser()
            try require(try parser.append(frame.prefix(3)).isEmpty, "미완료 프레임을 내보냄")
            let packets = try parser.append(Data(frame.dropFirst(3)) + frame)
            try require(packets == [Data("{\"x\":1}".utf8), Data("{\"x\":1}".utf8)], "프레임 분리 오류")
            try require(try NativeFrameParser.encode(Data("{\"x\":1}".utf8)) == frame, "길이 prefix 오류")
        }
        try check("reject oversized native frame and unfinished EOF") {
            var parser = NativeFrameParser()
            try rejects { _ = try parser.append(Data([1, 0, 0, 1])) }
            var partial = NativeFrameParser()
            _ = try partial.append(Data([7, 0]))
            try rejects { try partial.finish() }
        }
        try check("native request validates PNG and request identity") {
            let json: [String: Any] = ["version": 1, "type": "solve", "request_id": UUID().uuidString,
                "remaining_ms": 40000, "question": try JSONSerialization.jsonObject(with: JSONEncoder().encode(q)), "png_base64": png().base64EncodedString()]
            let request = try NativeRequest.decode(JSONSerialization.data(withJSONObject: json))
            try require(try request.image().count > 0, "유효 PNG 거절")
            var invalid = json; invalid["png_base64"] = Data("not a PNG".utf8).base64EncodedString()
            try rejects { _ = try NativeRequest.decode(JSONSerialization.data(withJSONObject: invalid)).image() }
            invalid = json; invalid["request_id"] = "arbitrary"
            try rejects { _ = try NativeRequest.decode(JSONSerialization.data(withJSONObject: invalid)) }
        }
        try check("native host only accepts its installed extension origin") {
            let origin = "chrome-extension://" + String(repeating: "a", count: 32) + "/"
            try require(HostOrigin.valid(arguments: ["host", origin], allowed: origin), "정상 origin 거절")
            try require(!HostOrigin.valid(arguments: ["host", "chrome-extension://other/"], allowed: origin), "다른 확장 허용")
            try require(!HostOrigin.valid(arguments: ["host"], allowed: origin), "직접 실행 허용")
            try require(!HostOrigin.valid(arguments: ["host", origin], allowed: nil), "미설정 앱 허용")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = OpenAIClient(apiKey: "local-test-only", session: URLSession(configuration: configuration))
        StubProtocol.respond = { request in
            try require(request.url?.path == "/v1/responses", "풀이 주소가 잘못됨")
            let body = try JSONSerialization.jsonObject(with: StubProtocol.body(request)) as! [String: Any]
            try require(body["store"] as? Bool == false, "응답 저장 옵션 누락")
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            try require(format?["strict"] as? Bool == true, "strict schema 누락")
            let output = String(data: try JSONEncoder().encode(answer), encoding: .utf8)!
            let envelope: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": output]]]], "usage": ["input_tokens": 10, "output_tokens": 20]]
            return (200, try JSONSerialization.data(withJSONObject: envelope))
        }
        let solved = try await api.solve(question: q, png: png(), model: "gpt-4.1-mini", timeout: 5, mode: .attachments, attachments: attachments)
        try check("decode actual Responses envelope and validate attachment attribution") { try require(solved.answer_index == 1 && api.usage["input_tokens"] == 10, "응답 또는 사용량 파싱 오류") }
        for status in [401, 429, 500] {
            var calls = 0
            StubProtocol.respond = { _ in calls += 1; return (status, Data("{\"error\":{\"message\":\"test\"}}".utf8)) }
            var rejected = false
            do { _ = try await api.fileStatus(fileID: "file-1") } catch { rejected = true }
            try check("HTTP \(status) must fail once without retry") { try require(rejected && calls == 1, "오류를 성공으로 처리하거나 재시도함") }
        }
        for status in [200, 404] {
            var paths: [String] = []
            StubProtocol.respond = { request in
                paths.append(request.url!.path)
                return (status, Data("{\"deleted\":true}".utf8))
            }
            try await api.delete(fileID: "file-1")
            try check("file deletion is safe to retry") {
                try require(paths == ["/v1/files/file-1"], "파일 이외의 삭제 요청을 보냄")
            }
        }
        StubProtocol.respond = { request in
            switch (request.httpMethod!, request.url!.path) {
            case ("POST", "/v1/files"):
                let body = String(data: try StubProtocol.body(request), encoding: .utf8)!
                try require(body.contains("assistants") && body.contains("lecture text"), "multipart 내용 누락")
                return (200, Data("{\"id\":\"file-new\"}".utf8))
            case ("GET", "/v1/files/file-new"): return (200, Data("{\"id\":\"file-new\",\"bytes\":12}".utf8))
            default: throw SolverFailure(message: "잘못된 자료 관리 요청")
            }
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("lecture text".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let fileID = try await api.upload(fileURL)
        let ready = try await api.fileStatus(fileID: fileID)
        try check("multipart upload and Files metadata need no additional resource") { try require(fileID == "file-new" && ready == "준비됨", "자료 등록 수명 오류") }
        StubProtocol.respond = { _ in (500, Data("{}".utf8)) }
        var partialFailed = false
        do { try await api.delete(fileID: "file-new") } catch { partialFailed = true }
        try check("partial remote deletion must remain a failure") { try require(partialFailed, "원격 파일 삭제 실패를 성공으로 표시함") }
        for envelope: [String: Any] in [
            ["status": "incomplete", "output": []],
            ["status": "completed", "output": [["content": [["type": "refusal", "refusal": "test"]]]]],
            ["status": "completed", "output": [["content": [["type": "output_text", "text": "not JSON"]]]]]
        ] {
            StubProtocol.respond = { _ in (200, try JSONSerialization.data(withJSONObject: envelope)) }
            var rejected = false
            do { _ = try await api.solve(question: q, png: png(), model: "test", timeout: 5, mode: .attachments, attachments: attachments) } catch { rejected = true }
            try check("incomplete, refusal or malformed model output has no answer") { try require(rejected, "잘못된 응답을 수락함") }
        }
        StubProtocol.respond = { _ in throw URLError(.timedOut) }
        var timedOut = false
        do { _ = try await api.fileStatus(fileID: "file-1") } catch { timedOut = true }
        try check("network timeout cannot produce an answer") { try require(timedOut, "timeout 수락") }
        try await checkLED()
        try await checkModes()
        try await checkJobs()
        print("Native self-checks passed: \(passed)")
    }
}
