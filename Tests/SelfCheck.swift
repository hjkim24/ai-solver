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
        try check("cached ready files need fresh startup confirmation") {
            var config = Configuration()
            config.files = [.init(id: "ready", filename: "old.pdf", status: "준비됨"), .init(id: "deleting", filename: "old2.pdf", status: "삭제 중")]
            config.invalidateCachedStatuses()
            try require(config.readyIDs.isEmpty && config.files[1].status == "삭제 실패", "재시작 뒤 미확인 준비/삭제 상태를 허용함")
        }
        try check("unchanged indexing polls preserve the ready file set") {
            var config = Configuration()
            config.files = [.init(id: "ready", filename: "a.pdf", status: "준비됨"), .init(id: "pending", filename: "b.pdf", status: "인덱싱 중")]
            for _ in 0..<3 {
                try require(!config.setFileStatus("ready", "준비됨"), "준비 상태를 반복 무효화함")
                try require(!config.setFileStatus("pending", "인덱싱 중"), "변하지 않은 인덱싱이 풀이를 취소함")
                try require(config.readyIDs == ["ready"], "준비된 자료를 검색 대상에서 제거함")
            }
            try require(config.setFileStatus("pending", "준비됨"), "새 자료가 준비됐는데 결과를 무효화하지 않음")
        }
        let evidence = [Evidence(file_id: "file-1", filename: "lecture.pdf", text: "물의 분자식은 H₂O이다.", score: 0.8)]
        let answer = SolveResult(status: "answered", answer_index: 1, answer_label: "A", explanation: "제공 자료의 물 분자식과 일치합니다.", sources: [SolveResult.Source(file_id: "file-1", quote: "물의 분자식은 H₂O이다.")])
        try check("accept complete question and grounded answer") {
            try q.validate()
            try answer.validate(question: q, evidence: evidence)
        }
        try check("reject model index outside actual options") {
            var invalid = answer; invalid.answer_index = 3
            try rejects { try invalid.validate(question: q, evidence: evidence) }
        }
        try check("reject wrong original label") {
            var invalid = answer; invalid.answer_label = "B"
            try rejects { try invalid.validate(question: q, evidence: evidence) }
        }
        try check("reject invented source and quote") {
            var invalid = answer; invalid.sources = [.init(file_id: "other", quote: "물의 분자식은 H₂O이다.")]
            try rejects { try invalid.validate(question: q, evidence: evidence) }
            invalid.sources = [.init(file_id: "file-1", quote: "정답은 CO₂")]
            try rejects { try invalid.validate(question: q, evidence: evidence) }
        }
        try check("reject answered without evidence") {
            var invalid = answer; invalid.sources = []
            try rejects { try invalid.validate(question: q, evidence: evidence) }
        }
        try check("abstention must not contain an answer") {
            var invalid = answer; invalid.status = "no_evidence"
            try rejects { try invalid.validate(question: q, evidence: evidence) }
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
            try require(request.url?.path == "/v1/vector_stores/vs-test/search", "검색 주소가 잘못됨")
            return (200, Data("{\"data\":[{\"file_id\":\"file-1\",\"filename\":\"lecture.pdf\",\"score\":0.8,\"content\":[{\"type\":\"text\",\"text\":\"물의 분자식은 H₂O이다.\"}]},{\"file_id\":\"deleted-file\",\"filename\":\"old.pdf\",\"score\":0.9,\"content\":[{\"type\":\"text\",\"text\":\"old\"}]}]}".utf8))
        }
        let retrieved = try await api.search(query: q.searchQuery, storeID: "vs-test", allowedIDs: ["file-1"], timeout: 5)
        try check("search excludes deleted or unready material") { try require(retrieved.count == 1 && retrieved[0].file_id == "file-1", "자료 집합 밖의 근거가 포함됨") }
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
        let solved = try await api.solve(question: q, png: png(), evidence: retrieved, model: "gpt-4.1-mini", timeout: 5)
        try check("decode actual Responses envelope and validate evidence") { try require(solved.answer_index == 1 && api.usage["input_tokens"] == 10, "응답 또는 사용량 파싱 오류") }
        for status in [401, 429, 500] {
            var calls = 0
            StubProtocol.respond = { _ in calls += 1; return (status, Data("{\"error\":{\"message\":\"test\"}}".utf8)) }
            var rejected = false
            do { _ = try await api.search(query: "test", storeID: "vs-test", allowedIDs: ["file-1"], timeout: 5) } catch { rejected = true }
            try check("HTTP \(status) must fail once without retry") { try require(rejected && calls == 1, "오류를 성공으로 처리하거나 재시도함") }
        }
        var deletionPaths: [String] = []
        StubProtocol.respond = { request in
            let path = request.url!.path; deletionPaths.append(path)
            return path.contains("vector_stores") ? (404, Data("{}".utf8)) : (200, Data("{\"deleted\":true}".utf8))
        }
        var deletionWorked = true
        do { try await api.delete(fileID: "file-1", storeID: "vs-test") } catch { deletionWorked = false }
        try check("retry partial deletion cleans up the remaining Files object") {
            try require(deletionWorked && deletionPaths == ["/v1/vector_stores/vs-test/files/file-1", "/v1/files/file-1"], "연결이 이미 삭제된 파일의 정리를 재시도하지 못함")
        }
        StubProtocol.respond = { request in
            switch (request.httpMethod!, request.url!.path) {
            case ("POST", "/v1/vector_stores"): return (200, Data("{\"id\":\"vs-new\"}".utf8))
            case ("POST", "/v1/files"):
                let body = String(data: try StubProtocol.body(request), encoding: .utf8)!
                try require(body.contains("assistants") && body.contains("lecture text"), "multipart 내용 누락")
                return (200, Data("{\"id\":\"file-new\"}".utf8))
            case ("POST", "/v1/vector_stores/vs-new/files"): return (200, Data("{\"status\":\"in_progress\"}".utf8))
            case ("GET", "/v1/vector_stores/vs-new/files/file-new"): return (200, Data("{\"status\":\"completed\"}".utf8))
            default: throw SolverFailure(message: "잘못된 자료 관리 요청")
            }
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("lecture text".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let storeID = try await api.createStore(), fileID = try await api.upload(fileURL)
        try await api.attach(fileID: fileID, storeID: storeID)
        let ready = try await api.fileStatus(fileID: fileID, storeID: storeID)
        try check("multipart upload, store attachment and indexing status") { try require(storeID == "vs-new" && fileID == "file-new" && ready == "completed", "자료 등록 수명 오류") }
        StubProtocol.respond = { request in request.url!.path.contains("vector_stores") ? (200, Data("{\"deleted\":true}".utf8)) : (500, Data("{}".utf8)) }
        var partialFailed = false
        do { try await api.delete(fileID: "file-new", storeID: "vs-new") } catch { partialFailed = true }
        try check("partial remote deletion must remain a failure") { try require(partialFailed, "원격 파일 삭제 실패를 성공으로 표시함") }
        for envelope: [String: Any] in [
            ["status": "incomplete", "output": []],
            ["status": "completed", "output": [["content": [["type": "refusal", "refusal": "test"]]]]],
            ["status": "completed", "output": [["content": [["type": "output_text", "text": "not JSON"]]]]]
        ] {
            StubProtocol.respond = { _ in (200, try JSONSerialization.data(withJSONObject: envelope)) }
            var rejected = false
            do { _ = try await api.solve(question: q, png: png(), evidence: evidence, model: "test", timeout: 5) } catch { rejected = true }
            try check("incomplete, refusal or malformed model output has no answer") { try require(rejected, "잘못된 응답을 수락함") }
        }
        StubProtocol.respond = { _ in throw URLError(.timedOut) }
        var timedOut = false
        do { _ = try await api.search(query: "test", storeID: "vs-test", allowedIDs: ["file-1"], timeout: 0.1) } catch { timedOut = true }
        try check("network timeout cannot produce an answer") { try require(timedOut, "timeout 수락") }
        StubProtocol.respond = { _ in throw NSError(domain: "SelfCheck", code: 3) }
        let noEvidence = try await api.solve(question: q, png: png(), evidence: [], model: "test", timeout: 5)
        try check("empty evidence skips model HTTP call") { try require(noEvidence.status == "no_evidence" && noEvidence.answer_index == nil, "근거 없이 호출함") }
        try await checkLED()
        try await checkModes()
        try await checkJobs()
        print("Native self-checks passed: \(passed)")
    }
}
