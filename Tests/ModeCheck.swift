import Foundation

func checkModes() async throws {
    let data = Data(#"{"model":"kept-model","vectorStoreID":"vs-old","files":[],"mode":"general"}"#.utf8)
    let decoded = try JSONDecoder().decode(Configuration.self, from: data)
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
    try SelfCheck.check("mode selection survives configuration save") {
        try SelfCheck.require(saved["mode"] as? String == "general", "일반 AI 모드를 저장하지 못함")
    }
    let old = try JSONDecoder().decode(Configuration.self, from: Data(#"{"model":"kept-model","vectorStoreID":"vs-old","files":[{"id":"file-old","filename":"old.pdf","status":"준비됨"}]}"#.utf8))
    try SelfCheck.check("legacy settings preserve model and files without attaching them") {
        try SelfCheck.require(old.mode == .general && old.model == "kept-model" && old.files.map(\.id) == ["file-old"] && old.attachmentFiles.isEmpty && old.files[0].byteCount == nil, "이전 설정이 소실되거나 원본 첨부에 자동 포함됨")
    }
    var config = Configuration()
    config.files = [ManagedFile(id: "file-1", filename: "lecture.pdf", status: "준비됨", attached: true, byteCount: 100),
                    ManagedFile(id: "file-secret", filename: "unselected.txt", status: "준비됨", attached: false, byteCount: 100),
                    ManagedFile(id: "file-deleted", filename: "deleted.pdf", status: "삭제 실패", attached: true, byteCount: 100)]
    try SelfCheck.check("file status changes preserve selection and cancel deleting inputs") {
        var value = config; value.mode = .general
        try SelfCheck.require(!value.setFileStatus("file-1", "준비됨"), "일반 AI를 자료 상태로 취소함")
        value.mode = .attachments
        try SelfCheck.require(!value.setFileStatus("file-1", "준비됨") && value.inputFileIDs == ["file-1"], "첨부 선택이 소실됨")
        try SelfCheck.require(value.setFileStatus("file-1", "삭제 중") && value.inputFileIDs.isEmpty, "삭제 중인 첨부를 계속 사용함")
    }
    try SelfCheck.check("changing selected attachment invalidates its active answer") {
        var value = config; value.mode = .attachments
        try SelfCheck.require(value.setAttachment("file-1", false) && value.inputFileIDs.isEmpty, "첨부 해제를 무시함")
        try SelfCheck.require(value.setAttachment("file-secret", true) && value.inputFileIDs == ["file-secret"], "첨부 추가를 무시함")
        value.mode = .general
        try SelfCheck.require(!value.setAttachment("file-secret", false), "자료 선택이 일반 AI 입력을 바꿈")
    }
    let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [StubProtocol.self]
    let api = OpenAIClient(apiKey: "test-only", session: URLSession(configuration: session))
    let q = SelfCheck.question(), png = SelfCheck.png()
    func response(basis: String, sources: [[String: String]] = []) throws -> Data {
        let result: [String: Any] = ["status": "answered", "answer_index": 1, "answer_label": "A", "explanation": "물의 분자식은 H₂O입니다.", "sources": sources, "basis": basis]
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": String(data: JSONSerialization.data(withJSONObject: result), encoding: .utf8)!]]]], "usage": ["input_tokens": 10, "output_tokens": 5]])
    }
    var paths: [String] = []
    config.mode = .general
    StubProtocol.respond = { request in
        paths.append(request.url!.path)
        let body = try JSONSerialization.jsonObject(with: StubProtocol.body(request)) as! [String: Any]
        let serialized = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        try SelfCheck.require(request.url!.path == "/v1/responses" && !serialized.contains("file-1") && !serialized.contains("file-secret") && !serialized.contains("input_file"), "일반 AI에 자료를 전송함")
        return (200, try response(basis: "general"))
    }
    let general = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in })
    try SelfCheck.check("general AI answers without search or uploaded materials") {
        try SelfCheck.require(paths == ["/v1/responses"] && general.result.answer_index == 1 && general.result.basis == "general", "자료 없는 풀이를 보류함")
    }
    config.mode = .attachments; paths = []
    StubProtocol.respond = { request in
        paths.append(request.url!.path)
        let body = try JSONSerialization.jsonObject(with: StubProtocol.body(request)) as! [String: Any]
        let input = body["input"] as! [[String: Any]], content = input[0]["content"] as! [[String: Any]]
        let ids = content.filter { $0["type"] as? String == "input_file" }.compactMap { $0["file_id"] as? String }
        try SelfCheck.require(ids == ["file-1"], "체크한 원본 파일만 첨부하지 않음")
        return (200, try response(basis: "mixed", sources: [["file_id": "file-1", "quote": "물은 H₂O이다."]]))
    }
    let direct = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in })
    try SelfCheck.check("attachments use only the selected original files") {
        try SelfCheck.require(paths == ["/v1/responses"] && direct.result.basis == "mixed" && direct.attachments.map(\.id) == ["file-1"], "원본 첨부를 전송하지 않음")
    }
    StubProtocol.respond = { _ in (200, try response(basis: "general")) }
    let fallback = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in })
    config.files = []
    let empty = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in })
    try SelfCheck.check("attachments allow labeled model knowledge with missing material content or no files") {
        try SelfCheck.require(fallback.result.basis == "general" && empty.result.answer_index == 1 && empty.attachments.isEmpty, "자료 부족 시 AI 판단을 막음")
    }
    let materialAnswer = SolveResult(status: "answered", answer_index: 1, answer_label: "A", explanation: "자료에 따른 답", sources: [.init(file_id: "unselected", quote: "인용")])
    try SelfCheck.check("general and attachment modes reject invented attribution and invalid option indices") {
        try SelfCheck.rejects { try materialAnswer.validate(question: q, mode: .general) }
        try SelfCheck.rejects { try materialAnswer.validate(question: q, mode: .attachments, attachments: direct.attachments) }
        var invalid = fallback.result; invalid.answer_index = 3
        try SelfCheck.rejects { try invalid.validate(question: q, mode: .general) }
        invalid = fallback.result; invalid.basis = "mixed"
        try SelfCheck.rejects { try invalid.validate(question: q, mode: .attachments, attachments: direct.attachments) }
    }
    config.files = [ManagedFile(id: "file-old", filename: "old.pdf", status: "실패", attached: true)]
    paths = []
    StubProtocol.respond = { request in
        paths.append(request.url!.path)
        if request.url!.path == "/v1/files/file-old" { return (200, Data(#"{"id":"file-old","bytes":1234}"#.utf8)) }
        return (200, try response(basis: "general"))
    }
    _ = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in })
    try SelfCheck.check("legacy attachment size is checked using Files metadata") {
        try SelfCheck.require(paths == ["/v1/files/file-old", "/v1/responses"], "기존 파일 크기 확인을 생략함")
    }
    for sizes in [[50_000_000], [30_000_000, 20_000_001]] {
        config.files = sizes.enumerated().map { ManagedFile(id: "file-\($0.offset)", filename: "large.pdf", status: "준비됨", attached: true, byteCount: $0.element) }
        var calls = 0
        StubProtocol.respond = { _ in calls += 1; return (200, try response(basis: "general")) }
        var rejected = false
        do { _ = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in }) } catch { rejected = true }
        try SelfCheck.check("oversized attachments stop before model HTTP") { try SelfCheck.require(rejected && calls == 0, "용량 초과를 누락하거나 일반 AI로 자동 전환함") }
    }
    config.files = [ManagedFile(id: "file-old", filename: "old.pdf", status: "준비됨", attached: true)]
    var calls = 0
    StubProtocol.respond = { _ in calls += 1; return (404, Data("{}".utf8)) }
    var rejected = false
    do { _ = try await api.answer(question: q, png: png, configuration: config, timeout: 5, onStage: { _ in }) } catch { rejected = true }
    try SelfCheck.check("attachment metadata errors do not fall back to a general answer") { try SelfCheck.require(rejected && calls == 1, "파일 오류를 AI 지식 답으로 대체함") }
}
