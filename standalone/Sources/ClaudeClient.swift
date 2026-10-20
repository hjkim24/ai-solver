import Foundation
import ImageIO

final class ClaudeClient: ImageSolverClient {
    private let apiKey: String
    private let session: URLSession
    private let materials: ClaudeMaterials
    private(set) var usage: [String: Int] = [:]
    init(apiKey: String, session: URLSession = .shared, materials: ClaudeMaterials = ClaudeMaterials()) {
        self.apiKey = apiKey; self.session = session; self.materials = materials
    }
    func structured(model: String, instructions: String, input: [AIInput], name: String, schema: [String: Any], timeout: Double) async throws -> StructuredReply {
        try Task.checkCancellation()
        let content: [[String: Any]] = try input.map {
            switch $0 {
            case .text(let text): return ["type": "text", "text": text]
            case .image(let data):
                guard data.count <= 7_500_000,
                      let image = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width <= 8000, height <= 8000 else {
                    throw SolverFailure(message: "Claude 이미지는 한 변 8,000 px, PNG 7.5 MB 이하로 캡처하세요.", deferred: true)
                }
                return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]]
            case .file(let file): return try materials.input(file)
            }
        }
        let body: [String: Any] = ["model": model, "max_tokens": 8192, "system": instructions,
            "messages": [["role": "user", "content": content]], "output_config": ["format": ["type": "json_schema", "schema": schema]]]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"; request.timeoutInterval = max(0.001, timeout)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bytes = try JSONSerialization.data(withJSONObject: body)
        guard bytes.count <= 32_000_000 else { throw SolverFailure(message: "Claude 요청이 32 MB를 넘습니다. 스크린샷이나 첨부 선택을 줄이세요.") }
        request.httpBody = bytes
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SolverFailure(message: "Claude 응답을 확인하지 못했습니다.") }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "Anthropic API 키 또는 모델 접근 권한을 확인하세요."
            case 429: message = "Anthropic 사용 한도 또는 잔액을 확인하세요. 자동 재시도하지 않습니다."
            case 400: message = "Claude 요청을 처리하지 못했습니다. 모델의 이미지·문서·구조화 지원과 입력 크기를 확인하세요."
            default: message = "Claude 요청에 실패했습니다. HTTP \(http.statusCode)"
            }
            throw SolverFailure(message: message)
        }
        guard data.count <= 4 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["stop_reason"] as? String == "end_turn", let blocks = object["content"] as? [[String: Any]],
              blocks.allSatisfy({ ["text", "thinking", "redacted_thinking"].contains($0["type"] as? String ?? "") }) else {
            throw SolverFailure(message: "Claude 응답이 완료되지 않았거나 답변을 거절했습니다.", deferred: true)
        }
        usage = (object["usage"] as? [String: Any] ?? [:]).compactMapValues { $0 as? Int }
        return StructuredReply(text: blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(), usage: usage)
    }
    func answer(question: Question, png: Data, configuration: Configuration, timeout: Double, onStage: (String) -> Void) async throws -> (result: SolveResult, evidence: [Evidence], attachments: [ManagedFile]) {
        usage = [:]
        try question.validate()
        let end = ContinuousClock.now.advanced(by: .seconds(timeout))
        var evidence: [Evidence] = []
        let attachments = configuration.mode == .attachments ? configuration.attachmentFiles : []
        if configuration.mode == .rag {
            guard !configuration.readyIDs.isEmpty else { throw SolverFailure(message: "Claude RAG에 검색 가능한 자료를 추가하세요.", deferred: true) }
            onStage("searching")
            let store = materials; let files = configuration.activeFiles
            let search = Task.detached { try store.search(query: question.searchQuery, files: files) }
            evidence = try await withTaskCancellationHandler(operation: { try await search.value }, onCancel: { search.cancel() })
        }
        if !attachments.isEmpty {
            var total = 0
            for file in attachments { total += try materials.data(file.id).count }
            guard total <= 12_000_000 else { throw SolverFailure(message: "Claude 원본 첨부는 합계 12 MB 이하로 선택하세요.") }
        }
        try Task.checkCancellation()
        let duration = ContinuousClock.now.duration(to: end).components
        let remaining = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        guard remaining > 0 else { throw URLError(.timedOut) }
        onStage("solving")
        let result = try await solve(question: question, png: png, evidence: evidence, model: configuration.selectedModel, timeout: remaining, mode: configuration.mode, attachments: attachments)
        return (result, evidence, attachments)
    }
}
