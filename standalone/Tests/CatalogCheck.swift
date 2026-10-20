import Foundation

final class CatalogStub: URLProtocol {
    static var respond: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request); let (status, data) = Self.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CatalogCheck {
    static var passed = 0
    static func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); passed += 1 }
    static func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    static var supportedDoc: String { "# GPT Future\n\nModel ID: `gpt-future`\n\n## Model details\n- Default snapshot: `gpt-future-2026-10-01`\n\n## Endpoints\n| Responses | `v1/responses` | Supported |\n\n## Supported features\n- image_input\n- structured_outputs\n\n## Snapshots\n- `gpt-future-2026-10-01`\n- `gpt-future-2024-05-13`\n\n## Rate limits\n" }
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CatalogStub.self]
        let catalog = ModelCatalog(session: URLSession(configuration: config))
        CatalogStub.respond = { request in
            if request.url!.host == "api.openai.com" { return (200, json(["data": [["id": "gpt-future"], ["id": "gpt-future-2026-10-01"], ["id": "gpt-future-2024-05-13"], ["id": "audio-fixture"], ["id": "gpt-unavailable-doc"]]])) }
            if request.url!.path.hasSuffix("all.md") { return (200, Data("[Future](/api/docs/models/gpt-future.md)\n[Audio](/api/docs/models/audio-fixture.md)\n[Not on account](/api/docs/models/gpt-other.md)".utf8)) }
            if request.url!.path.hasSuffix("gpt-future.md") { return (200, Data(supportedDoc.utf8)) }
            return (200, Data("# Audio\nModel ID: `audio-fixture`\n## Supported features\n- structured_outputs\n".utf8))
        }
        let openai = try await catalog.load(provider: .openai, apiKey: "fixture-openai")
        check(Set(openai.models.map(\.id)) == ["gpt-future", "gpt-future-2026-10-01"], "only available documented image and schema models including snapshots")
        check(CatalogStub.requests.filter { $0.url!.host == "developers.openai.com" }.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "x-api-key") == nil }, "public docs never receive keys")
        CatalogStub.requests = []
        CatalogStub.respond = { request in
            let capability: [String: Any] = ["image_input": ["supported": true], "structured_outputs": ["supported": true]]
            if request.url!.query?.contains("after_id=") == true {
                return (200, json(["data": [["id": "claude-future", "display_name": "Claude Future", "capabilities": capability, "lifecycle": "active"]], "has_more": false]))
            }
            return (200, json(["data": [["id": "claude-text-only", "display_name": "Text", "capabilities": ["image_input": ["supported": false], "structured_outputs": ["supported": true]]]], "has_more": true, "last_id": "claude-text-only"]))
        }
        let claude = try await catalog.load(provider: .anthropic, apiKey: "fixture-claude")
        check(claude.models.map(\.id) == ["claude-future"], "Claude capability filtering and pagination")
        check(CatalogStub.requests.count == 2 && CatalogStub.requests.allSatisfy { $0.url!.host == "api.anthropic.com" && $0.value(forHTTPHeaderField: "x-api-key") == "fixture-claude" && $0.value(forHTTPHeaderField: "Authorization") == nil }, "Claude list uses only Claude credentials")
        for (status, data) in [(401, Data()), (200, Data("invalid".utf8)), (200, json(["data": [], "has_more": true]))] {
            CatalogStub.respond = { _ in (status, data) }
            do { _ = try await catalog.load(provider: .anthropic, apiKey: "fixture"); fatalError("bad catalog accepted") } catch { passed += 1 }
        }
        print("Model catalog checks: \(passed) passed; fixture HTTP only")
    }
}
