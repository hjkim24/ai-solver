import AppKit
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let jobs = JobController()
    private let led = CapsLockNotifier()
    private let clipboard = ClipboardMonitor()
    private var config: Configuration = {
        if let data = UserDefaults.standard.data(forKey: "solver.configuration"),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) { return saved }
        var value = Configuration(); value.mode = .general; return value
    }()
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var toggle: NSMenuItem!
    private var menuStatus: NSMenuItem!
    private var footer: NSStackView?
    private var resultSummary: NSTextField?
    private var window: NSWindow?
    private var recentLabel: NSTextField?
    private var materialStack: NSStackView?
    private var keyField: NSSecureTextField?
    private var modelField: NSPopUpButton?
    private var providerField: NSPopUpButton?
    private var modelStatus: NSTextField?
    private var modelButton: NSButton?
    private var settingsProvider: AIProvider = .openai
    private var keyDrafts: [AIProvider: String] = [:]
    private var originalKeys: [AIProvider: String] = [:]
    private var modelDrafts: [AIProvider: String] = [:]
    private var modelLists: [AIProvider: [AIModel]] = [:]
    private var modelKeys: [AIProvider: String] = [:]
    private var modelTask: Task<Void, Never>?
    private var modelRequest = UUID()
    private let catalog: ModelCatalog
    private let session: URLSession
    init(catalog: ModelCatalog = ModelCatalog(), session: URLSession = .shared) { self.catalog = catalog; self.session = session; super.init() }
    private var modeField: NSPopUpButton?
    private var ledField: NSButton?
    private var ledStatusLabel: NSTextField?
    private var ledMessage = "Caps Lock LED: 아직 테스트하지 않았습니다."
    private var terminating = false
    private var terminationReady = false
    private var materialTask: Task<Void, Never>?
    private var busy = false
    private var materialMessage = "자료를 추가하거나 상태를 새로 고치세요."

    func applicationDidFinishLaunching(_ notification: Notification) {
        config.invalidateCachedStatuses()
        try? config.save()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let name = menu.addItem(withTitle: "Clipboard AI Solver", action: nil, keyEquivalent: "")
        name.isEnabled = false
        menuStatus = menu.addItem(withTitle: "사용 중지", action: nil, keyEquivalent: "")
        menuStatus.isEnabled = false
        menu.addItem(.separator())
        toggle = menu.addItem(withTitle: "사용 시작", action: #selector(toggleUse), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "최근 결과", action: #selector(recent), keyEquivalent: "")
        menu.addItem(withTitle: "자료 관리", action: #selector(materials), keyEquivalent: "")
        menu.addItem(withTitle: "설정…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clipboard AI Solver 종료", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        led.onStatus = { [weak self] message in
            guard let self else { return }
            let message = message.replacingOccurrences(of: "Aside 또는 Canvas RAG Solver", with: "Clipboard AI Solver")
                .replacingOccurrences(of: "메뉴 앱을 다시 연결하세요", with: "Clipboard AI Solver를 종료하고 다시 실행하세요")
            self.ledMessage = message; self.ledStatusLabel?.stringValue = message
            self.item.button?.toolTip = self.jobs.output.message + "\n" + message
            self.showRecentResult()
        }
        jobs.onChange = { [weak self] in self?.update() }
        update()
        clipboard.onImage = { [weak self] in self?.solveImage($0) }
        clipboard.onError = { [weak self] in self?.jobs.invalidate($0) }
        refreshFiles()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return terminationReady ? .terminateNow : .terminateCancel }
        terminating = true; clipboard.setEnabled(false); jobs.setEnabled(false); led.cancel()
        // terminateLater enters a modal loop that does not run the main-actor cleanup task.
        Task { await led.waitUntilIdle(); terminationReady = true; sender.terminate(nil) }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { clipboard.setEnabled(false); jobs.setEnabled(false); materialTask?.cancel(); modelTask?.cancel() }
    private func showRecentResult() {
        let output = jobs.output
        resultSummary?.stringValue = output.message
        recentLabel?.stringValue = (output.detail.isEmpty ? output.message : output.detail) + "\n\n" + ledMessage
    }
    private func update() {
        guard !terminating else { return }
        let output = jobs.output
        led.update(enabled: config.capsLockBlink, requestID: jobs.requestID, output: output)
        showRecentResult()
        item.button?.image = nil
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        item.button?.title = output.number.map(String.init) ?? (["ready": "·", "disabled": "—", "deferred": "?", "error": "!"][output.state] ?? "…")
        menuStatus.title = String(output.message.prefix(72))
        item.button?.toolTip = output.message + (config.capsLockBlink ? "\n" + ledMessage : "")
        item.button?.setAccessibilityLabel("Clipboard AI Solver: \(output.message)")
        toggle.title = jobs.enabled ? "사용 중지" : "사용 시작"
    }
    private func client(provider: AIProvider) throws -> any ImageSolverClient {
        let key = try KeychainStore.load(provider: provider)
        guard !key.isEmpty else { throw SolverFailure(message: "설정에서 API 키를 저장하세요.") }
        return provider == .openai ? OpenAIClient(apiKey: key, session: session) : ClaudeClient(apiKey: key, session: session)
    }
    private func solveImage(_ image: Data) {
        guard !terminating, jobs.enabled else { return }
        let id = UUID().uuidString
        guard jobs.begin(id) else { return }
        let configuration = config
        jobs.run(id, remainingMS: 45_000) { [weak self] stage in
            guard let self else { throw CancellationError() }
            guard !configuration.selectedModel.isEmpty else { throw SolverFailure(message: "설정에서 모델 목록을 불러와 선택하세요.") }
            let api = try self.client(provider: configuration.provider)
            let started = ContinuousClock.now
            let response = try await api.answerScreenshot(image: image, configuration: configuration, timeout: 45) { state in
                let text = ["preparing": "이미지 확인 중", "reading": "문항 인식 중", "solving": "풀이 중"][state] ?? state
                stage(state, "\(configuration.mode.title) · \(text)")
            }
            try Task.checkCancellation()
            let question = response.question; let result = response.result
            let number = result.answer_index
            let message = number.map { "문항 \(question.question_number ?? "선택") · 보기 \($0) (\(result.answer_label ?? "")) · \(result.basisLabel)" } ?? result.explanation
            let citations = result.sources.map { source in
                let filename = response.attachments.first(where: { $0.id == source.file_id })?.filename ?? source.file_id
                return "\(filename): “\(source.quote)”"
            }.joined(separator: "\n\n")
            let sourceNote: String
            if configuration.mode == .attachments && !result.sources.isEmpty {
                sourceNote = "AI가 제시한 첨부자료 인용 · 원문 확인 필요"
            } else if configuration.mode == .attachments && result.basis == "general" && !response.attachments.isEmpty {
                sourceNote = "첨부자료에서 근거가 부족해 AI 지식으로 판단했습니다."
            } else { sourceNote = "" }
            let duration = started.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let recognized = question.stem_text + "\n" + question.options.map { "\($0.index). [\($0.label)] \($0.text)" }.joined(separator: "\n")
            let detail = "\(message)\n\(configuration.provider.title) · \(configuration.selectedModel)\n모드: \(configuration.mode.title) · \(result.basisLabel)\n\n\(result.explanation)\n\n\(sourceNote)\n\(citations)\n\n인식한 문항 (원본과 대조하세요)\n\(recognized)\n\n\(Date().formatted()) · 처리 \(String(format: "%.1f", seconds))초\n인식+풀이 입력 \(response.usage["input_tokens"] ?? 0) / 출력 \(response.usage["output_tokens"] ?? 0) 토큰"
            return JobOutput(state: result.status == "answered" ? "answered" : "deferred", message: message, detail: detail, number: number)
        }
    }
    @objc private func toggleUse() {
        guard !terminating else { return }
        jobs.setEnabled(!jobs.enabled); clipboard.setEnabled(jobs.enabled)
        if jobs.enabled { jobs.invalidate("문제 하나와 모든 보기를 화면에 놓고 Control–Shift–Command–3으로 복사하세요.") }
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    private func openWindow(_ title: String, height: Double = 520) -> NSStackView {
        modelTask?.cancel(); modelRequest = UUID()
        window?.close(); materialStack = nil; recentLabel = nil; resultSummary = nil; ledStatusLabel = nil
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 600, height: 420)
        panel.backgroundColor = .windowBackgroundColor
        let root = NSView(); panel.contentView = root
        let stack = AppInterface.column(spacing: 20)
        let document = FlippedDocumentView(); document.addSubview(stack)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = document
        let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 8; actions.alignment = .centerY
        let line = AppInterface.separator()
        for view in [scroll, line, actions] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        document.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor), line.trailingAnchor.constraint(equalTo: root.trailingAnchor), line.heightAnchor.constraint(equalToConstant: 1),
            actions.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 12), actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            actions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), actions.heightAnchor.constraint(equalToConstant: 28),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8)
        ])
        footer = actions
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
        return stack
    }
    private func label(_ text: String) -> NSTextField { AppInterface.text(text) }
    @objc private func recent() {
        let stack = openWindow("최근 결과")
        let summary = label(jobs.output.message); summary.font = .systemFont(ofSize: 17, weight: .semibold)
        resultSummary = summary; AppInterface.fill(stack, summary)
        AppInterface.fill(stack, AppInterface.separator())
        let text = label(""); recentLabel = text; AppInterface.fill(stack, text)
        footer?.addArrangedSubview(AppInterface.text("새 스크린샷을 복사하면 결과가 갱신됩니다.", secondary: true))
        showRecentResult()
    }
    @objc private func settings() {
        let stack = openWindow("설정", height: 650)
        do {
            settingsProvider = config.provider; keyDrafts = [:]; originalKeys = [:]
            modelDrafts = [.openai: config.model, .anthropic: config.claudeModel]
            let key = try KeychainStore.load(provider: settingsProvider)
            keyDrafts[settingsProvider] = key; originalKeys[settingsProvider] = key
            let provider = NSPopUpButton(frame: .zero, pullsDown: false)
            provider.addItems(withTitles: AIProvider.allCases.map(\.title)); provider.selectItem(at: AIProvider.allCases.firstIndex(of: settingsProvider)!)
            provider.target = self; provider.action = #selector(selectProvider); providerField = provider; provider.identifier = .init("provider")
            let field = NSSecureTextField(string: key); field.placeholderString = "선택한 공급자의 API 키"; field.delegate = self; keyField = field
            let model = NSPopUpButton(frame: .zero, pullsDown: false); model.identifier = .init("model"); modelField = model
            let load = AppInterface.button("모델 불러오기", target: self, action: #selector(refreshModels)); modelButton = load
            let selection = NSStackView(views: [model, load]); selection.orientation = .horizontal; selection.spacing = 8
            model.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let status = AppInterface.text("", secondary: true); modelStatus = status
            populateModels()
            let mode = NSPopUpButton(frame: .zero, pullsDown: false)
            mode.addItems(withTitles: SolveMode.allCases.map(\.title))
            mode.selectItem(at: SolveMode.allCases.firstIndex(of: config.mode)!)
            modeField = mode
            let connection = AppInterface.column(spacing: 22)
            AppInterface.fill(connection, AppInterface.section("AI 연결", views: [
                AppInterface.row("공급자", control: provider), AppInterface.row("API 키", control: field), AppInterface.row("모델", control: selection), status,
                AppInterface.text("API 키로 조회한 모델 중 이미지 입력·구조화 출력을 지원하는 모델만 표시합니다. 새 모델은 다시 불러와 갱신하세요.", secondary: true)
            ]))
            AppInterface.fill(connection, AppInterface.separator())
            AppInterface.fill(connection, AppInterface.text("키는 공급자별로 macOS 키체인에 저장합니다. 비우고 저장하면 해당 키를 삭제합니다. ChatGPT·Claude 구독과 API 사용료는 별개입니다.", secondary: true))
            AppInterface.fill(connection, AppInterface.text("자료는 공급자별로 관리합니다. OpenAI 자료는 원격 저장하며, Claude 자료는 Mac에 보관하고 선택한 원본을 풀이할 때 전송합니다.", secondary: true))
            let general = AppInterface.column(spacing: 22)
            AppInterface.fill(general, AppInterface.section("풀이 방식", views: [
                AppInterface.row("모드", control: mode),
                AppInterface.text("일반 AI: 자료 없이 판단\n첨부자료 우선 AI: 선택한 자료를 먼저 참고하고 AI 지식으로 보완", secondary: true)
            ]))
            AppInterface.fill(general, AppInterface.separator())
            AppInterface.fill(general, AppInterface.section("스크린샷 입력", views: [
                label("전체 화면 복사  ⌃⇧⌘3     ·     영역 복사  ⌃⇧⌘4"),
                AppInterface.text("사용 시작 후 복사한 이미지만 처리합니다. 문제 하나와 모든 보기가 보이도록 캡처하세요. 텍스트 복사는 무시합니다.", secondary: true),
                AppInterface.text("이미지는 선택한 AI 공급자로 전송됩니다. 문항 인식·풀이에 같은 모델로 API를 각각 호출합니다.", secondary: true)
            ]))
            let notifications = AppInterface.column(spacing: 22)
            let blink = NSButton(checkboxWithTitle: "정답 번호만큼 Caps Lock LED 깜빡이기", target: nil, action: nil)
            blink.state = config.capsLockBlink ? .on : .off; ledField = blink
            let test = AppInterface.button("LED 3회 테스트", target: self, action: #selector(testLED))
            let ledStatus = AppInterface.text(ledMessage, secondary: true); ledStatusLabel = ledStatus
            AppInterface.fill(notifications, AppInterface.section("키보드 알림", views: [
                blink, AppInterface.text("MacBook 내장 키보드 전용입니다. Caps Lock 입력 상태는 유지하며, 새 문항·사용 중지·종료 시 점멸을 취소하고 원복합니다.", secondary: true)
            ]))
            notifications.addArrangedSubview(test)
            AppInterface.fill(notifications, ledStatus)
            AppInterface.fill(notifications, AppInterface.separator())
            AppInterface.fill(notifications, AppInterface.section("접근 권한", views: [
                AppInterface.text("처음 켜거나 테스트할 때 macOS 입력 모니터링 권한이 필요할 수 있습니다. 요청에 표시된 Clipboard AI Solver를 허용한 뒤 앱을 다시 실행하세요.", secondary: true)
            ]))
            let tabs = NSTabView(); tabs.addTabViewItem(AppInterface.tab("AI 연결", body: connection)); tabs.addTabViewItem(AppInterface.tab("일반", body: general)); tabs.addTabViewItem(AppInterface.tab("알림", body: notifications))
            tabs.heightAnchor.constraint(equalToConstant: 520).isActive = true
            AppInterface.fill(stack, tabs)
            footer?.addArrangedSubview(AppInterface.text("변경한 설정은 저장 후 적용됩니다.", secondary: true))
            footer?.addArrangedSubview(NSView())
            let save = AppInterface.button("저장", target: self, action: #selector(saveSettings)); save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
            footer?.addArrangedSubview(save)
        } catch { AppInterface.fill(stack, AppInterface.text(error.localizedDescription)) }
    }
    @objc private func saveSettings() {
        do {
            guard !busy else { throw SolverFailure(message: "자료 처리가 끝난 뒤 설정을 저장하세요.") }
            rememberDraft()
            for provider in AIProvider.allCases {
                guard let key = keyDrafts[provider] else { continue }
                let model = modelDrafts[provider] ?? ""
                if !key.isEmpty && (provider == settingsProvider || key != originalKeys[provider]) {
                    guard !model.isEmpty else { throw SolverFailure(message: "\(provider.title): 모델 목록을 불러와 선택하세요.") }
                    if key != originalKeys[provider] {
                        guard modelKeys[provider] == key, modelLists[provider]?.contains(where: { $0.id == model }) == true else {
                            throw SolverFailure(message: "\(provider.title): 새 API 키로 모델 목록을 불러와 선택한 뒤 저장하세요.")
                        }
                    }
                }
            }
            for provider in AIProvider.allCases {
                if let key = keyDrafts[provider], key != originalKeys[provider] { try KeychainStore.save(key, provider: provider) }
            }
            config.provider = settingsProvider
            config.model = modelDrafts[.openai] ?? config.model
            config.claudeModel = modelDrafts[.anthropic] ?? config.claudeModel
            keyField?.stringValue = ""; keyDrafts = [:]; originalKeys = [:]
            if let index = modeField?.indexOfSelectedItem, SolveMode.allCases.indices.contains(index) { config.mode = SolveMode.allCases[index] }
            let enableLED = ledField?.state == .on
            let requestLEDPermission = enableLED && !config.capsLockBlink
            config.capsLockBlink = enableLED
            try config.save()
            jobs.invalidate("설정을 저장했습니다. 스크린샷을 다시 복사하세요.")
            if requestLEDPermission { InternalCapsLockLight.requestAccess() }
            modelTask?.cancel(); modelRequest = UUID(); window?.close(); refreshFiles()
        } catch { alert(error.localizedDescription) }
    }
    private func rememberDraft() {
        keyDrafts[settingsProvider] = keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let model = modelField?.selectedItem?.representedObject as? String { modelDrafts[settingsProvider] = model }
    }
    private func populateModels() {
        guard let field = modelField else { return }
        field.removeAllItems()
        let key = keyDrafts[settingsProvider] ?? ""
        let models = modelKeys[settingsProvider] == key ? modelLists[settingsProvider] ?? [] : []
        let saved = modelDrafts[settingsProvider] ?? ""
        for model in models {
            field.addItem(withTitle: "\(model.name) · \(model.id)")
            field.lastItem?.representedObject = model.id
        }
        if models.isEmpty {
            field.addItem(withTitle: saved.isEmpty ? "모델 목록을 불러오세요" : "\(saved) · 저장된 모델")
            field.lastItem?.representedObject = saved.isEmpty ? nil : saved
        }
        if let selected = field.itemArray.first(where: { $0.representedObject as? String == saved }) { field.select(selected) }
        field.isEnabled = !models.isEmpty
        modelStatus?.stringValue = models.isEmpty ? "키를 입력하고 ‘모델 불러오기’를 누르세요. 저장된 모델은 그대로 유지됩니다." : "\(models.count)개 지원 모델"
    }
    @objc private func selectProvider() {
        guard let index = providerField?.indexOfSelectedItem, AIProvider.allCases.indices.contains(index) else { return }
        rememberDraft()
        let next = AIProvider.allCases[index]
        do {
            if keyDrafts[next] == nil { let key = try KeychainStore.load(provider: next); keyDrafts[next] = key; originalKeys[next] = key }
            settingsProvider = next
            modelTask?.cancel(); modelRequest = UUID(); modelButton?.isEnabled = true
            keyField?.stringValue = keyDrafts[next] ?? ""; populateModels()
        } catch {
            providerField?.selectItem(at: AIProvider.allCases.firstIndex(of: settingsProvider)!)
            alert(error.localizedDescription)
        }
    }
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSecureTextField === keyField else { return }
        rememberDraft(); modelTask?.cancel(); modelRequest = UUID(); modelButton?.isEnabled = true; populateModels()
    }
    @objc private func refreshModels() {
        rememberDraft(); modelTask?.cancel()
        let provider = settingsProvider; let key = keyDrafts[provider] ?? ""; let request = UUID(); modelRequest = request
        guard !key.isEmpty else { modelStatus?.stringValue = "선택한 공급자의 API 키를 먼저 입력하세요."; return }
        modelButton?.isEnabled = false; modelStatus?.stringValue = "모델 목록과 지원 기능을 확인하고 있습니다…"
        modelTask = Task { [weak self] in
            guard let self else { return }
            defer { if modelRequest == request { modelButton?.isEnabled = true } }
            do {
                let result = try await catalog.load(provider: provider, apiKey: key)
                guard !Task.isCancelled, modelRequest == request, settingsProvider == provider,
                      keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == key else { return }
                modelLists[provider] = result.models; modelKeys[provider] = key
                populateModels(); modelStatus?.stringValue = result.message
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, modelRequest == request else { return }
                modelStatus?.stringValue = error is SolverFailure ? error.localizedDescription : "목록을 불러오지 못했습니다. 인터넷 연결을 확인하고 다시 시도하세요. 저장된 선택은 유지됩니다."
            }
        }
    }
    @objc private func testLED() {
        guard !terminating else { return }
        jobs.invalidate("LED 3회 테스트 중입니다. 끝난 뒤 스크린샷을 다시 복사하세요.")
        InternalCapsLockLight.requestAccess()
        led.test()
    }
    private func alert(_ message: String) { let alert = NSAlert(); alert.messageText = message; alert.runModal() }
    @objc private func materials() { materialStack = openWindow("자료 관리", height: 560); renderFiles() }
    private func renderFiles() {
        guard let stack = materialStack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        footer?.arrangedSubviews.forEach { footer?.removeArrangedSubview($0); $0.removeFromSuperview() }
        let title = label("등록 자료"); title.font = .systemFont(ofSize: 17, weight: .semibold)
        AppInterface.fill(stack, title)
        AppInterface.fill(stack, AppInterface.text("\(config.provider.title) · \(config.mode.title) · \(config.activeFiles.count)개 파일", secondary: true))
        AppInterface.fill(stack, AppInterface.text("‘첨부’ 체크는 첨부자료 우선 AI에서만 사용합니다. 일반 AI는 자료를 보내지 않습니다.", secondary: true))
        AppInterface.fill(stack, AppInterface.separator())
        if config.activeFiles.isEmpty {
            let empty = AppInterface.column(spacing: 8)
            AppInterface.fill(empty, label("등록된 자료가 없습니다."))
            AppInterface.fill(empty, AppInterface.text("PDF, TXT, MD 파일을 추가하세요. 일반 AI는 자료 없이 사용할 수 있습니다.", secondary: true))
            AppInterface.fill(stack, empty)
        }
        for file in config.activeFiles {
            let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
            let selected = NSButton(checkboxWithTitle: "첨부", target: self, action: #selector(selectAttachment(_:)))
            selected.state = file.attached == true ? .on : .off
            selected.identifier = NSUserInterfaceItemIdentifier(file.id)
            selected.isEnabled = !busy && !["삭제 중", "삭제 실패"].contains(file.status)
            selected.setAccessibilityLabel("\(file.filename) 첨부 선택")
            row.addArrangedSubview(selected)
            let names = AppInterface.column(spacing: 3)
            let filename = NSTextField(labelWithString: file.filename); filename.lineBreakMode = .byTruncatingMiddle; filename.toolTip = file.filename
            filename.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            AppInterface.fill(names, filename)
            AppInterface.fill(names, AppInterface.text(file.status, secondary: true))
            names.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(names)
            let button = AppInterface.button(file.status == "삭제 실패" ? "삭제 재시도" : "제거", target: self, action: #selector(removeFile(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(file.id); button.isEnabled = !busy
            row.addArrangedSubview(button); AppInterface.fill(stack, row)
            AppInterface.fill(stack, AppInterface.separator())
        }
        AppInterface.fill(stack, AppInterface.text(materialMessage, secondary: true))
        let description = config.provider == .openai
            ? "원본 첨부: 파일당 50 MB 미만 · 합계 50 MB 이하. 파일은 OpenAI 서버에 저장되며 제거하면 원격 파일도 삭제합니다."
            : "Claude 자료는 이 Mac에 별도 보관합니다(파일당·첨부 합계 12 MB 이하). 첨부자료 우선 AI는 선택한 원본을 전송합니다."
        AppInterface.fill(stack, AppInterface.text(description, secondary: true))
        for (title, action) in [("자료 추가…", #selector(addFiles)), ("상태 새로 고침", #selector(refreshFiles))] {
            let button = AppInterface.button(title, target: self, action: action); button.isEnabled = !busy; footer?.addArrangedSubview(button)
        }
        footer?.addArrangedSubview(NSView())
    }
    private func saveFiles() throws { try config.save(); renderFiles() }
    @objc private func selectAttachment(_ sender: NSButton) {
        guard !busy, let id = sender.identifier?.rawValue else { return }
        let changed = config.setAttachment(id, sender.state == .on)
        if changed { jobs.invalidate("첨부 선택이 바뀌었습니다. 스크린샷을 다시 복사하세요.") }
        do { try saveFiles() } catch { alert(error.localizedDescription) }
    }
    private func changeFile(_ id: String, _ status: String) throws {
        guard config.activeFiles.contains(where: { $0.id == id && $0.status != status }) else { return }
        let changed = config.setFileStatus(id, status)
        try saveFiles()
        if changed { jobs.invalidate("사용 자료가 바뀌었습니다. 스크린샷을 다시 복사하세요.") }
    }
    private func performMaterials(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; renderFiles()
        materialTask = Task {
            defer { busy = false; renderFiles() }
            do { try await operation() }
            catch is CancellationError { return }
            catch { materialMessage = error is SolverFailure ? error.localizedDescription : "자료 요청에 실패했습니다. 연결을 확인하고 다시 시도하세요." }
        }
    }
    @objc private func addFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText, UTType(filenameExtension: "md")!]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        performMaterials { [self] in
            if config.provider == .anthropic {
                let store = ClaudeMaterials()
                for url in urls {
                    materialMessage = "자료 복사 중: \(url.lastPathComponent)"; renderFiles()
                    let copy = Task.detached { try store.add(url) }
                    let file = try await withTaskCancellationHandler(operation: { try await copy.value }, onCancel: { copy.cancel() })
                    config.activeFiles.append(file)
                    do { try saveFiles() }
                    catch { config.activeFiles.removeAll { $0.id == file.id }; try? store.remove(file.id); throw error }
                    jobs.invalidate("자료를 추가했습니다. 스크린샷을 다시 복사하세요.")
                }
                materialMessage = "Mac에 자료 사본을 보관했습니다."
                return
            }
            guard let api = try client(provider: .openai) as? OpenAIClient else { return }
            for url in urls {
                materialMessage = "업로드 중: \(url.lastPathComponent)"; renderFiles()
                let id = try await api.upload(url)
                config.activeFiles.append(ManagedFile(id: id, filename: url.lastPathComponent, status: "준비됨", attached: true, byteCount: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize))
                if config.mode == .attachments { jobs.invalidate("첨부 자료를 추가했습니다. 스크린샷을 다시 복사하세요.") }
                try saveFiles()
            }
            materialMessage = "원본 파일을 업로드했습니다."
        }
    }
    @objc private func refreshFiles() {
        guard !config.activeFiles.isEmpty else { return }
        performMaterials { [self] in
            if config.provider == .anthropic {
                let store = ClaudeMaterials(); let files = config.activeFiles.filter { !["삭제 중", "삭제 실패"].contains($0.status) }
                let check = Task.detached { files.map { ($0.id, (try? store.status($0)) ?? "실패") } }
                let statuses = await check.value
                try Task.checkCancellation()
                for (id, status) in statuses { try changeFile(id, status) }
                materialMessage = "로컬 자료 확인을 완료했습니다."
                return
            }
            guard let api = try client(provider: .openai) as? OpenAIClient else { return }
            for file in config.activeFiles where !["삭제 중", "삭제 실패"].contains(file.status) {
                do {
                    try await changeFile(file.id, api.fileStatus(fileID: file.id))
                } catch { try changeFile(file.id, "실패"); throw error }
            }
            materialMessage = "상태 확인 완료. 첨부자료 우선 AI는 체크한 원본 파일을 사용합니다."
        }
    }
    @objc private func removeFile(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        performMaterials { [self] in
            try changeFile(id, "삭제 중")
            do {
                if config.provider == .anthropic { try ClaudeMaterials().remove(id) }
                else if let api = try client(provider: .openai) as? OpenAIClient { try await api.delete(fileID: id) }
                config.activeFiles.removeAll { $0.id == id }; try saveFiles()
                materialMessage = config.provider == .anthropic ? "Mac에 보관한 자료 사본을 삭제했습니다." : "원격 파일을 삭제했습니다."
            } catch { try changeFile(id, "삭제 실패"); throw error }
        }
    }
}
