import AppKit
import Darwin
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let jobs = JobController()
    private let led = CapsLockNotifier()
    private var config = Configuration.load()
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var toggle: NSMenuItem!
    private var window: NSWindow?
    private var recentLabel: NSTextField?
    private var materialStack: NSStackView?
    private var keyField: NSSecureTextField?
    private var modelField: NSTextField?
    private var modeField: NSPopUpButton?
    private var ledField: NSButton?
    private var ledStatusLabel: NSTextField?
    private var ledMessage = "Caps Lock LED: 아직 테스트하지 않았습니다."
    private var terminating = false
    private var terminationReady = false
    private var materialTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var busy = false
    private var materialMessage = "등록 자료는 OpenAI 서버에 저장됩니다. 제거는 원격 파일도 삭제합니다."

    func applicationDidFinishLaunching(_ notification: Notification) {
        config.invalidateCachedStatuses()
        try? config.save()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle = menu.addItem(withTitle: "사용 중지", action: #selector(toggleUse), keyEquivalent: "")
        for (title, action) in [("최근 결과", #selector(recent)), ("자료 관리", #selector(materials)), ("설정", #selector(settings)), ("종료", #selector(quit))] { menu.addItem(withTitle: title, action: action, keyEquivalent: "") }
        for entry in menu.items { entry.target = self }
        item.menu = menu
        led.onStatus = { [weak self] message in
            guard let self else { return }
            self.ledMessage = message; self.ledStatusLabel?.stringValue = message
            self.item.button?.toolTip = self.jobs.output.message + "\n" + message
            self.showRecentResult()
        }
        jobs.onChange = { [weak self] in self?.update() }
        update()
        startInput()
        refreshFiles()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return terminationReady ? .terminateNow : .terminateCancel }
        terminating = true; jobs.setEnabled(false); led.cancel()
        // terminateLater enters a modal loop that does not run the main-actor cleanup task.
        Task { await led.waitUntilIdle(); terminationReady = true; sender.terminate(nil) }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { jobs.setEnabled(false); materialTask?.cancel(); pollTask?.cancel() }
    private func showRecentResult() {
        let output = jobs.output
        recentLabel?.stringValue = (output.detail.isEmpty ? output.message : output.detail) + "\n\n" + ledMessage
    }
    private func update() {
        guard !terminating else { return }
        let output = jobs.output
        led.update(enabled: config.capsLockBlink, requestID: jobs.requestID, output: output)
        showRecentResult()
        item.button?.title = output.number.map(String.init) ?? (["ready": "·", "disabled": "—", "deferred": "?", "error": "!"][output.state] ?? "…")
        item.button?.toolTip = output.message + (config.capsLockBlink ? "\n" + ledMessage : "")
        item.button?.setAccessibilityLabel("Canvas RAG Solver: \(output.message)")
        toggle.title = jobs.enabled ? "사용 중지" : "사용 시작"
        do {
            let object: [String: Any] = ["version": 1, "type": "state", "request_id": jobs.requestID as Any? ?? NSNull(), "state": output.state, "message": output.message]
            let frame = try NativeFrameParser.encode(JSONSerialization.data(withJSONObject: object))
            try frame.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(STDOUT_FILENO, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw SolverFailure(message: "Native 연결이 종료되었습니다.") }
                    offset += count
                }
            }
        } catch { NSApplication.shared.terminate(nil) }
    }
    private func startInput() {
        signal(SIGPIPE, SIG_IGN)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var parser = NativeFrameParser()
            var bytes = [UInt8](repeating: 0, count: 65536)
            do {
                while true {
                    let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw SolverFailure(message: "Native 입력 오류") }
                    if count == 0 { break }
                    for packet in try parser.append(Data(bytes.prefix(count))) {
                        let request = try NativeRequest.decode(packet)
                        DispatchQueue.main.async { self?.receive(request) }
                    }
                }
                try parser.finish()
            } catch { /* Malformed input closes the connection without logging content. */ }
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
    private func client() throws -> OpenAIClient {
        let key = try KeychainStore.load()
        guard !key.isEmpty else { throw SolverFailure(message: "설정에서 API 키를 저장하세요.") }
        return OpenAIClient(apiKey: key)
    }
    private func receive(_ request: NativeRequest) {
        guard !terminating else { return }
        switch request.type {
        case "begin": jobs.begin(request.request_id)
        case "cancel": jobs.cancel(request.request_id, reason: request.reason ?? "요청을 취소했습니다.")
        case "solve":
            guard request.request_id == jobs.requestID, let question = request.question, let ms = request.remaining_ms else { return }
            let configuration = config
            jobs.run(request.request_id, remainingMS: ms) { [weak self] stage in
                guard let self else { throw CancellationError() }
                let png = try request.image()
                let api = try self.client()
                let started = ContinuousClock.now
                let response = try await api.answer(question: question, png: png, configuration: configuration, timeout: Double(ms) / 1000) { state in
                    stage(state, "문항 \(question.question_number ?? "선택"): \(configuration.mode.title) · \(state == "searching" ? "자료 검색 중" : "풀이 중")")
                }
                try Task.checkCancellation()
                let result = response.result
                let number = result.answer_index
                let message = number.map { "문항 \(question.question_number ?? "선택") · 보기 \($0) (\(result.answer_label ?? "")) · \(result.basisLabel)" } ?? result.explanation
                let citations = result.sources.map { source in
                    let filename = response.evidence.first(where: { $0.file_id == source.file_id })?.filename ?? response.attachments.first(where: { $0.id == source.file_id })?.filename ?? source.file_id
                    return "\(filename): “\(source.quote)”"
                }.joined(separator: "\n\n")
                let sourceNote: String
                if configuration.mode == .attachments && !result.sources.isEmpty {
                    sourceNote = "AI가 제시한 첨부자료 인용 · 원문 확인 필요"
                } else if configuration.mode == .attachments && result.basis == "general" && !response.attachments.isEmpty {
                    sourceNote = "첨부자료에서 근거가 부족해 AI 지식으로 판단했습니다."
                } else if configuration.mode == .rag && !result.sources.isEmpty {
                    sourceNote = "검색 구절과 인용문 일치 확인"
                } else { sourceNote = "" }
                let duration = started.duration(to: .now).components
                let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                let detail = "\(message)\n모드: \(configuration.mode.title) · \(result.basisLabel)\n\n\(result.explanation)\n\n\(sourceNote)\n\(citations)\n\n\(Date().formatted()) · 처리 \(String(format: "%.1f", seconds))초\n모델 입력 \(api.usage["input_tokens"] ?? 0) / 출력 \(api.usage["output_tokens"] ?? 0) 토큰"
                return JobOutput(state: result.status == "answered" ? "answered" : "deferred", message: message, detail: detail, number: number)
            }
        default: break
        }
    }
    @objc private func toggleUse() { if !terminating { jobs.setEnabled(!jobs.enabled) } }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    private func openWindow(_ title: String, height: Double = 380) -> NSStackView {
        window?.close(); materialStack = nil; recentLabel = nil; ledStatusLabel = nil
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = stack
        panel.contentView = scroll
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor)])
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
        return stack
    }
    private func label(_ text: String) -> NSTextField { let value = NSTextField(wrappingLabelWithString: text); value.isSelectable = true; return value }
    @objc private func recent() {
        let stack = openWindow("최근 결과")
        let text = label(jobs.output.detail.isEmpty ? jobs.output.message : jobs.output.detail)
        recentLabel = text; stack.addArrangedSubview(text); showRecentResult()
    }
    @objc private func settings() {
        let stack = openWindow("설정", height: 700)
        do {
            let field = NSSecureTextField(string: try KeychainStore.load()); field.placeholderString = "API 키 (Keychain에 저장)"; keyField = field
            stack.addArrangedSubview(label("OpenAI API 키")); stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
            let model = NSTextField(string: config.model); modelField = model
            stack.addArrangedSubview(label("이미지·구조화 출력 지원 모델 ID")); stack.addArrangedSubview(model)
            model.widthAnchor.constraint(equalTo: field.widthAnchor).isActive = true
            let mode = NSPopUpButton(frame: .zero, pullsDown: false)
            mode.addItems(withTitles: SolveMode.allCases.map(\.title))
            mode.selectItem(at: SolveMode.allCases.firstIndex(of: config.mode)!)
            mode.setAccessibilityLabel("풀이 모드"); modeField = mode
            stack.addArrangedSubview(label("풀이 모드")); stack.addArrangedSubview(mode)
            stack.addArrangedSubview(label("일반 AI: 자료 없이 판단\n첨부자료 우선 AI: 자료 관리에서 체크한 원본 파일을 참고하고, 없거나 부족하면 AI 지식으로 판단\nRAG: 준비된 자료의 검색 근거만 사용하며 근거가 없으면 보류"))
            let blink = NSButton(checkboxWithTitle: "정답 번호만큼 Caps Lock LED 깜빡이기", target: nil, action: nil)
            blink.state = config.capsLockBlink ? .on : .off; ledField = blink; stack.addArrangedSubview(blink)
            stack.addArrangedSubview(label("MacBook 내장 키보드 전용 · Caps Lock 입력 상태는 유지합니다. 새 문항·중지·종료 시 점멸을 취소하고 원복합니다. 처음 켜거나 테스트할 때 macOS 입력 모니터링 권한이 필요할 수 있습니다."))
            stack.addArrangedSubview(NSButton(title: "LED 3회 테스트", target: self, action: #selector(testLED)))
            let ledStatus = label(ledMessage); ledStatusLabel = ledStatus; stack.addArrangedSubview(ledStatus)
            stack.addArrangedSubview(label("키를 비우고 저장하면 Keychain에서 제거합니다. 등록 자료와 선택 문항은 OpenAI로 전송됩니다."))
            stack.addArrangedSubview(NSButton(title: "저장", target: self, action: #selector(saveSettings)))
        } catch { stack.addArrangedSubview(label(error.localizedDescription)) }
    }
    @objc private func saveSettings() {
        do {
            guard !busy else { throw SolverFailure(message: "자료 처리가 끝난 뒤 설정을 저장하세요.") }
            let model = modelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard model.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else { throw SolverFailure(message: "모델 ID를 확인하세요.") }
            try KeychainStore.save(keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            keyField?.stringValue = ""; config.model = model
            if let index = modeField?.indexOfSelectedItem, SolveMode.allCases.indices.contains(index) { config.mode = SolveMode.allCases[index] }
            let enableLED = ledField?.state == .on
            let requestLEDPermission = enableLED && !config.capsLockBlink
            config.capsLockBlink = enableLED
            try config.save()
            jobs.invalidate("설정을 저장했습니다. 문항을 다시 선택하세요.")
            if requestLEDPermission { InternalCapsLockLight.requestAccess() }
            window?.close(); refreshFiles()
        } catch { alert(error.localizedDescription) }
    }
    @objc private func testLED() {
        guard !terminating else { return }
        jobs.invalidate("LED 3회 테스트 중입니다. 끝난 뒤 문항을 다시 선택하세요.")
        InternalCapsLockLight.requestAccess()
        led.test()
    }
    private func alert(_ message: String) { let alert = NSAlert(); alert.messageText = message; alert.runModal() }
    @objc private func materials() { materialStack = openWindow("자료 관리", height: 500); renderFiles() }
    private func renderFiles() {
        guard let stack = materialStack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        stack.addArrangedSubview(label(materialMessage))
        stack.addArrangedSubview(label("현재 모드: \(config.mode.title)\n‘첨부’ 체크는 첨부자료 우선 AI에서만 사용합니다. 새 파일은 자동 체크되며, 기존 파일은 직접 체크하세요. 일반 AI는 자료를 보내지 않고, RAG는 준비된 자료 전체를 검색합니다.\n원본 첨부는 파일당 50 MB 미만·합계 50 MB 이하입니다. 매 요청 파일 입력 비용이 발생할 수 있습니다. 등록 파일은 RAG 인덱싱도 수행합니다."))
        for file in config.files {
            let row = NSStackView(); row.orientation = .horizontal
            let selected = NSButton(checkboxWithTitle: "첨부", target: self, action: #selector(selectAttachment(_:)))
            selected.state = file.attached == true ? .on : .off
            selected.identifier = NSUserInterfaceItemIdentifier(file.id)
            selected.isEnabled = !busy && !["삭제 중", "삭제 실패"].contains(file.status)
            selected.setAccessibilityLabel("\(file.filename) 첨부 선택")
            row.addArrangedSubview(selected)
            row.addArrangedSubview(label("\(file.filename) — \(file.status)"))
            let button = NSButton(title: file.status == "삭제 실패" ? "삭제 재시도" : "제거", target: self, action: #selector(removeFile(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(file.id); button.isEnabled = !busy
            row.addArrangedSubview(button); stack.addArrangedSubview(row)
        }
        for (title, action) in [("자료 추가…", #selector(addFiles)), ("상태 새로 고침", #selector(refreshFiles))] {
            let button = NSButton(title: title, target: self, action: action); button.isEnabled = !busy; stack.addArrangedSubview(button)
        }
    }
    private func saveFiles() throws { try config.save(); renderFiles() }
    @objc private func selectAttachment(_ sender: NSButton) {
        guard !busy, let id = sender.identifier?.rawValue else { return }
        let changed = config.setAttachment(id, sender.state == .on)
        if changed { jobs.invalidate("첨부 선택이 바뀌었습니다. 문항을 다시 선택하세요.") }
        do { try saveFiles() } catch { alert(error.localizedDescription) }
    }
    private func changeFile(_ id: String, _ status: String) throws {
        guard config.files.contains(where: { $0.id == id && $0.status != status }) else { return }
        let changed = config.setFileStatus(id, status)
        try saveFiles()
        if changed { jobs.invalidate("사용 자료가 바뀌었습니다. 문항을 다시 선택하세요.") }
    }
    private func performMaterials(_ operation: @escaping (OpenAIClient) async throws -> Void) {
        guard !busy else { return }
        pollTask?.cancel(); busy = true; renderFiles()
        materialTask = Task {
            defer { busy = false; renderFiles(); schedulePoll() }
            do { try await operation(client()) }
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
        performMaterials { [self] api in
            if config.vectorStoreID.isEmpty { config.vectorStoreID = try await api.createStore(); try config.save() }
            for url in urls {
                materialMessage = "업로드 중: \(url.lastPathComponent)"; renderFiles()
                let id = try await api.upload(url)
                config.files.append(ManagedFile(id: id, filename: url.lastPathComponent, status: "인덱싱 중", attached: true, byteCount: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize))
                if config.mode == .attachments { jobs.invalidate("첨부 자료를 추가했습니다. 문항을 다시 선택하세요.") }
                try saveFiles()
                do { try await api.attach(fileID: id, storeID: config.vectorStoreID) }
                catch { try changeFile(id, "실패"); throw error }
            }
            materialMessage = "업로드 완료. 인덱싱 상태를 확인하고 있습니다."
        }
    }
    @objc private func refreshFiles() {
        guard !config.files.isEmpty, !config.vectorStoreID.isEmpty else { return }
        performMaterials { [self] api in
            for file in config.files where !["삭제 중", "삭제 실패"].contains(file.status) {
                do {
                    let state = try await api.fileStatus(fileID: file.id, storeID: config.vectorStoreID)
                    try changeFile(file.id, state == "completed" ? "준비됨" : state == "in_progress" ? "인덱싱 중" : "실패")
                } catch { try changeFile(file.id, "실패"); throw error }
            }
            materialMessage = "상태 확인 완료. RAG는 준비된 자료를, 첨부자료 우선 AI는 체크한 원본 파일을 사용합니다."
        }
    }
    private func schedulePoll() {
        guard config.files.contains(where: { $0.status == "인덱싱 중" }) else { return }
        pollTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            self?.refreshFiles()
        }
    }
    @objc private func removeFile(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        performMaterials { [self] api in
            try changeFile(id, "삭제 중")
            do {
                try await api.delete(fileID: id, storeID: config.vectorStoreID)
                config.files.removeAll { $0.id == id }; try saveFiles(); materialMessage = "원격 파일과 자료 연결을 삭제했습니다."
            } catch { try changeFile(id, "삭제 실패"); throw error }
        }
    }
}
