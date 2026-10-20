import Foundation

struct AIModel: Equatable {
    let id: String
    let name: String
}
struct ModelCatalogResult { let models: [AIModel]; let message: String }

struct ModelCatalog {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    private func get(_ url: URL, provider: AIProvider? = nil, key: String = "") async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url); request.timeoutInterval = 15
        if provider == .openai { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SolverFailure(message: "모델 목록 응답을 확인하지 못했습니다.") }
        guard (200..<300).contains(http.statusCode) else {
            throw SolverFailure(message: [401, 403].contains(http.statusCode) ? "API 키와 모델 조회 권한을 확인하세요." : "모델 정보를 불러오지 못했습니다. HTTP \(http.statusCode)")
        }
        guard data.count <= 4 * 1024 * 1024 else { throw SolverFailure(message: "모델 목록 응답이 너무 큽니다.") }
        return data
    }
    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["data"] is [[String: Any]] else { throw SolverFailure(message: "모델 목록 형식이 올바르지 않습니다.") }
        return value
    }
    private func captures(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }
    func load(provider: AIProvider, apiKey: String) async throws -> ModelCatalogResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SolverFailure(message: "선택한 공급자의 API 키를 먼저 입력하세요.") }
        let result = try await provider == .openai ? openai(apiKey) : anthropic(apiKey)
        guard !result.models.isEmpty else { throw SolverFailure(message: "이 키로 사용할 수 있는 이미지·구조화 출력 지원 모델을 찾지 못했습니다. 키 권한과 연결을 확인하세요.") }
        return result
    }
    private func anthropic(_ key: String) async throws -> ModelCatalogResult {
        var cursor = ""; var seen: Set<String> = []; var models: [AIModel] = []
        for _ in 0..<30 {
            var url = URLComponents(string: "https://api.anthropic.com/v1/models")!
            url.queryItems = [URLQueryItem(name: "limit", value: "100")]
            if !cursor.isEmpty { url.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
            let page = try object(await get(url.url!, provider: .anthropic, key: key))
            for row in page["data"] as! [[String: Any]] {
                guard let id = row["id"] as? String, !id.isEmpty,
                      let capabilities = row["capabilities"] as? [String: Any],
                      (capabilities["image_input"] as? [String: Any])?["supported"] as? Bool == true,
                      (capabilities["structured_outputs"] as? [String: Any])?["supported"] as? Bool == true,
                      row["lifecycle"] as? String != "retired" else { continue }
                models.append(AIModel(id: id, name: row["display_name"] as? String ?? id))
            }
            guard let more = page["has_more"] as? Bool else { throw SolverFailure(message: "모델 페이지 정보를 확인하지 못했습니다.") }
            if !more { return ModelCatalogResult(models: unique(models), message: "\(unique(models).count)개 모델 · Anthropic의 이미지·구조화 지원 확인") }
            guard let last = page["last_id"] as? String, !last.isEmpty, seen.insert(last).inserted else { throw SolverFailure(message: "모델 페이지 정보가 반복되거나 누락되었습니다.") }
            cursor = last
        }
        throw SolverFailure(message: "모델 목록이 너무 길어 완료하지 못했습니다.")
    }
    private func openai(_ key: String) async throws -> ModelCatalogResult {
        let page = try object(await get(URL(string: "https://api.openai.com/v1/models")!, provider: .openai, key: key))
        let available = Set((page["data"] as! [[String: Any]]).compactMap { $0["id"] as? String })
        let index = String(decoding: try await get(URL(string: "https://developers.openai.com/api/docs/models/all.md")!), as: UTF8.self)
        let pages = Set(captures("/api/docs/models/([a-zA-Z0-9._-]+)\\.md", index)).filter { id in
            available.contains(id) || available.contains { $0.hasPrefix(id + "-20") }
        }.sorted()
        guard !pages.isEmpty else { throw SolverFailure(message: "OpenAI 공식 카탈로그와 사용 가능한 모델 목록을 대조하지 못했습니다.") }
        var models: [AIModel] = []; var failures = 0
        for start in stride(from: 0, to: pages.count, by: 4) {
            try Task.checkCancellation()
            let values = await withTaskGroup(of: ([AIModel], Bool).self) { group in
                for id in pages[start..<min(start + 4, pages.count)] {
                    group.addTask {
                        do {
                            let doc = String(decoding: try await get(URL(string: "https://developers.openai.com/api/docs/models/\(id).md")!), as: UTF8.self)
                            return (documentedModels(doc, available: available), false)
                        } catch { return ([], true) }
                    }
                }
                var found: [AIModel] = []; var failed = false
                for await (items, error) in group { found += items; failed = failed || error }
                return (found, failed)
            }
            models += values.0; if values.1 { failures += 1 }
        }
        try Task.checkCancellation()
        return ModelCatalogResult(models: unique(models), message: "\(unique(models).count)개 모델 · OpenAI 공식 문서의 이미지·구조화·Responses 지원 확인" + (failures > 0 ? " · 일부 문서 조회 실패: 확인된 모델만 표시" : ""))
    }
    private func documentedModels(_ doc: String, available: Set<String>) -> [AIModel] {
        let features = doc.components(separatedBy: "## Supported features\n").dropFirst().first?.components(separatedBy: "\n## ").first ?? ""
        let supported = Set(features.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard supported.contains("- image_input"), supported.contains("- structured_outputs"),
              doc.range(of: #"\|\s*Responses\s*\|\s*`v1/responses`\s*\|\s*Supported\s*\|"#, options: .regularExpression) != nil else { return [] }
        let title = doc.components(separatedBy: "\n").first?.replacingOccurrences(of: "# ", with: "") ?? "OpenAI"
        // Historical snapshots can have different capabilities; only the alias and its explicit default inherit this page's support.
        let ids = captures("Model ID: `([A-Za-z0-9._-]+)`", doc) + captures("Default snapshot: `([A-Za-z0-9._-]+)`", doc)
        return Set(ids).filter { available.contains($0) }.map { AIModel(id: $0, name: title) }
    }
    private func unique(_ models: [AIModel]) -> [AIModel] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
