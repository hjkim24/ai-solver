import Foundation

@main struct ProviderConfigurationCheck {
    static func main() throws {
        let data = Data(#"{"model":"gpt-existing","mode":"attachments","provider":"anthropic","claudeModel":"claude-existing","files":[{"id":"file-openai","filename":"openai.pdf","status":"준비됨","attached":true}],"claudeFiles":[{"id":"local-test","filename":"claude.pdf","status":"준비됨","attached":true}]}"#.utf8)
        var config = try JSONDecoder().decode(Configuration.self, from: data)
        precondition(config.inputFileIDs == ["local-test"], "Claude must use only its own materials")
        config.selectedModel = "claude-changed"
        config.setAttachment("local-test", false)
        precondition(config.inputFileIDs.isEmpty && config.model == "gpt-existing")
        config.provider = .openai
        precondition(config.inputFileIDs == ["file-openai"] && config.selectedModel == "gpt-existing")
        let roundTrip = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        precondition(roundTrip.claudeModel == "claude-changed" && roundTrip.claudeFiles.first?.attached == false)
        let legacy = try JSONDecoder().decode(Configuration.self, from: Data(#"{"model":"gpt-legacy","mode":"general","vectorStoreID":"vs-existing","capsLockBlink":true,"files":[]}"#.utf8))
        precondition(legacy.provider == .openai && legacy.selectedModel == "gpt-legacy" && legacy.capsLockBlink && legacy.vectorStoreID == "vs-existing")
        print("Provider configuration: migration, round trip and isolated materials passed")
    }
}
