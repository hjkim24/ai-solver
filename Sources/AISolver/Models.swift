import Foundation

struct SolverFailure: Error, LocalizedError {
    let message: String
    var deferred = false
    var errorDescription: String? { message }
}

func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Question: Codable, Equatable {
    struct Option: Codable, Equatable { var index: Int; var label: String; var text: String }
    var page_session_id: String
    var question_key: String
    var question_number: String?
    var stem_text: String
    var options: [Option]
    func validate() throws {
        guard !page_session_id.isEmpty, !question_key.isEmpty, !normalized(stem_text).isEmpty,
              (2...10).contains(options.count), options.enumerated().allSatisfy({ i, o in o.index == i + 1 && !normalized(o.label).isEmpty && !normalized(o.text).isEmpty }),
              (stem_text + options.map(\.text).joined()).utf8.count <= 65536 else {
            throw SolverFailure(message: "문제 본문과 보기 형식을 확인할 수 없습니다.")
        }
    }
}

enum SolveMode: String, Codable, CaseIterable {
    case general, attachments
    var title: String {
        switch self {
        case .general: return "일반 AI"
        case .attachments: return "첨부자료 우선 AI"
        }
    }
}

enum AIProvider: String, Codable, CaseIterable {
    case openai, anthropic
    var title: String { self == .openai ? "OpenAI · GPT" : "Anthropic · Claude" }
    var keyAccount: String { self == .openai ? "openai-api-key" : "anthropic-api-key" }
}

struct SolveResult: Codable {
    struct Source: Codable { let file_id: String; let quote: String }
    var status: String
    var answer_index: Int?
    var answer_label: String?
    var explanation: String
    var sources: [Source]
    var basis = "materials"
    var basisLabel: String {
        ["materials": "자료 기반", "general": "AI 지식으로 판단", "mixed": "자료 + AI 지식", "none": "답변 보류"][basis] ?? "답변 보류"
    }
    func validate(question: Question, mode: SolveMode = .general, attachments: [ManagedFile] = []) throws {
        let statuses = ["answered", "uncertain", "unreadable", "unsupported"]
        guard statuses.contains(status), ["materials", "general", "mixed", "none"].contains(basis), (1...300).contains(explanation.count), !normalized(explanation).isEmpty, sources.count <= 5 else {
            throw SolverFailure(message: "AI 응답 형식이 올바르지 않습니다.")
        }
        if status == "answered" {
            guard let index = answer_index, (1...question.options.count).contains(index), answer_label == question.options[index - 1].label, basis != "none" else {
                throw SolverFailure(message: "답 번호·보기 라벨·근거를 확인할 수 없습니다.")
            }
            switch mode {
            case .general:
                guard basis == "general", sources.isEmpty else { throw SolverFailure(message: "일반 AI 답변에 자료 출처가 포함되어 있습니다.") }
            case .attachments:
                guard basis == "general" ? sources.isEmpty : !sources.isEmpty else { throw SolverFailure(message: "첨부자료와 답변 근거 구분이 일치하지 않습니다.") }
            }
        } else if answer_index != nil || answer_label != nil || basis != "none" || !sources.isEmpty {
            throw SolverFailure(message: "보류된 응답에 답 번호가 포함되어 있습니다.")
        }
        for source in sources {
            let quote = normalized(source.quote)
            // shortcut: 원본 첨부는 파일 ID만 검증한다. 인용 원문 검증이 필요하면 별도 텍스트 추출을 추가한다.
            let validSource = mode == .attachments && attachments.contains(where: { $0.id == source.file_id })
            guard (1...500).contains(source.quote.count), !quote.isEmpty, validSource else {
                throw SolverFailure(message: "AI가 제시한 출처나 인용문이 첨부 자료와 일치하지 않습니다.")
            }
        }
    }
}

struct ManagedFile: Codable, Identifiable {
    var id: String
    var filename: String
    var status: String
    var attached: Bool? = nil
    var byteCount: Int? = nil
}

struct Configuration: Codable {
    var provider: AIProvider = .openai
    var claudeModel = ""
    var claudeFiles: [ManagedFile] = []
    var model = "gpt-4.1-mini"
    var files: [ManagedFile] = []
    var mode: SolveMode = .general
    var capsLockBlink = false
    init() {}
    private enum CodingKeys: String, CodingKey { case model, files, mode, capsLockBlink, provider, claudeModel, claudeFiles }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openai
        claudeModel = try values.decodeIfPresent(String.self, forKey: .claudeModel) ?? ""
        claudeFiles = try values.decodeIfPresent([ManagedFile].self, forKey: .claudeFiles) ?? []
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? model
        files = try values.decodeIfPresent([ManagedFile].self, forKey: .files) ?? files
        let savedMode = try values.decodeIfPresent(String.self, forKey: .mode) ?? ""
        mode = savedMode == "rag" ? .attachments : SolveMode(rawValue: savedMode) ?? .general
        capsLockBlink = try values.decodeIfPresent(Bool.self, forKey: .capsLockBlink) ?? false
    }
    var selectedModel: String {
        get { provider == .openai ? model : claudeModel }
        set { if provider == .openai { model = newValue } else { claudeModel = newValue } }
    }
    var activeFiles: [ManagedFile] {
        get { provider == .openai ? files : claudeFiles }
        set { if provider == .openai { files = newValue } else { claudeFiles = newValue } }
    }
    var attachmentFiles: [ManagedFile] { activeFiles.filter { $0.attached == true && !["삭제 중", "삭제 실패"].contains($0.status) } }
    var inputFileIDs: Set<String> {
        switch mode {
        case .general: return []
        case .attachments: return Set(attachmentFiles.map(\.id))
        }
    }
    mutating func invalidateCachedStatuses() {
        for i in files.indices where files[i].status == "삭제 중" { files[i].status = "삭제 실패" }
        for i in claudeFiles.indices where claudeFiles[i].status == "삭제 중" { claudeFiles[i].status = "삭제 실패" }
    }
    @discardableResult mutating func setFileStatus(_ id: String, _ status: String) -> Bool {
        let previous = inputFileIDs
        if let index = activeFiles.firstIndex(where: { $0.id == id }) { activeFiles[index].status = status }
        return inputFileIDs != previous
    }
    @discardableResult mutating func setAttachment(_ id: String, _ selected: Bool) -> Bool {
        let previous = inputFileIDs
        if let index = activeFiles.firstIndex(where: { $0.id == id }) { activeFiles[index].attached = selected }
        return inputFileIDs != previous
    }
    static func load() -> Configuration {
        guard let data = UserDefaults.standard.data(forKey: "solver.configuration"), let value = try? JSONDecoder().decode(Configuration.self, from: data) else { return Configuration() }
        return value
    }
    func save() throws { UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "solver.configuration") }
}
