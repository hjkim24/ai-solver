import AppKit

// The UI harness links this fake instead of the production Keychain implementation.
enum KeychainStore {
    static var saved = ""
    static var keys: [AIProvider: String] = [.openai: "fixture-key", .anthropic: "fixture-claude-key"]
    static func load(provider: AIProvider = .openai) throws -> String { keys[provider] ?? "" }
    static func save(_ value: String, provider: AIProvider = .openai) throws { saved = value; keys[provider] = value }
}

final class ModelFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let data: Data
        if url.host == "api.anthropic.com" {
            data = try! JSONSerialization.data(withJSONObject: ["data": [["id": "claude-fixture", "display_name": "Claude Fixture", "capabilities": ["image_input": ["supported": true], "structured_outputs": ["supported": true]]]], "has_more": false])
        } else if url.host == "api.openai.com" {
            data = try! JSONSerialization.data(withJSONObject: ["data": [["id": "gpt-4.1-mini"]]])
        } else if url.path.hasSuffix("all.md") {
            data = Data("[Mini](/api/docs/models/gpt-4.1-mini.md)".utf8)
        } else {
            data = Data("# GPT Fixture\nModel ID: `gpt-4.1-mini`\n| Responses | `v1/responses` | Supported |\n## Supported features\n- image_input\n- structured_outputs\n".utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct InterfaceCheck {
    static var passed = 0
    static func check(_ value: @autoclosure () -> Bool, _ name: String) {
        precondition(value(), name); passed += 1
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor static func image(_ window: NSWindow, name: String) throws {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let context = NSGraphicsContext(bitmapImageRep: output)!.cgContext
            let rect = CGRect(x: 0, y: 0, width: output.pixelsWide, height: output.pixelsHigh)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor); context.fill(rect)
            context.draw(bitmap.cgImage!, in: rect)
        }
        try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/interface-\(name).png"))
    }
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("com.hjkim24.clipboard-interface-fixture.") == true)
        var fixture = Configuration(); fixture.mode = .attachments
        fixture.files = [ManagedFile(id: "fixture-file", filename: "나노신소재실험_아주_긴_이름의_강의자료_2026_최종_수정_참고문서.pdf", status: "실패", attached: true, byteCount: 10)]
        // Empty vector store prevents startup refresh from making any HTTP request.
        try fixture.save()
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--preview") { app.setActivationPolicy(.regular) }
        let network = URLSessionConfiguration.ephemeral; network.protocolClasses = [ModelFixture.self]
        let delegate = AppDelegate(catalog: ModelCatalog(session: URLSession(configuration: network))); app.delegate = delegate; app.mainMenu = makeApplicationMenu()
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: app, queue: .main) { _ in
            DispatchQueue.main.async {
                if CommandLine.arguments.contains("--preview") {
                    _ = delegate.perform(NSSelectorFromString("settings"))
                    app.windows.first { $0.title == "설정" }?.appearance = NSAppearance(named: .aqua)
                    print("UI_FIXTURE_BUNDLE=\(Bundle.main.bundleIdentifier!) PID=\(ProcessInfo.processInfo.processIdentifier)"); fflush(stdout)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 45) { finishChecks(app: app, delegate: delegate, fixture: fixture) }
                } else { finishChecks(app: app, delegate: delegate, fixture: fixture) }
            }
        }
        app.run()
        NotificationCenter.default.removeObserver(observer)
        withExtendedLifetime(delegate) {}
    }
    @MainActor static func finishChecks(app: NSApplication, delegate: AppDelegate, fixture: Configuration) {
        Task {
            do { try await runChecks(app: app, delegate: delegate, fixture: fixture) }
            catch { fputs("Interface check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            UserDefaults.standard.removeObject(forKey: "solver.configuration")
            app.terminate(nil)
        }
    }
    @MainActor static func runChecks(app: NSApplication, delegate: AppDelegate, fixture: Configuration) async throws {
        let status = Mirror(reflecting: delegate).children.first { $0.label == "item" }!.value as! NSStatusItem
        check(status.button?.title == "—" && status.button?.image == nil, "status item contains no clipboard icon")
        check(status.menu!.items.filter(\.isSeparatorItem).count == 3, "native menu command groups")
        let settingsCommand = status.menu!.items.first { $0.action == NSSelectorFromString("settings") }!
        check(settingsCommand.keyEquivalent == ",", "settings command shortcut")
        _ = delegate.perform(NSSelectorFromString("settings"))
        let window = app.windows.first { $0.isVisible && $0.title == "설정" }!
        let tabs = descendants(window.contentView!).compactMap { $0 as? NSTabView }.first!
        check(tabs.tabViewItems.map(\.label) == ["AI 연결", "일반", "알림"], "native settings panes")
        let general = descendants(tabs.tabViewItems[0].view!)
        let key = general.compactMap { $0 as? NSSecureTextField }.first!
        guard let model = general.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.identifier?.rawValue == "model" }) else { fatalError("model picker missing; model must not require typing") }
        let mode = descendants(tabs.tabViewItems[1].view!).compactMap { $0 as? NSPopUpButton }.first!
        check(key.stringValue == "fixture-key" && model.selectedItem?.representedObject as? String == fixture.model && mode.indexOfSelectedItem == 1, "existing settings populate fields")
        key.stringValue = "fixture-updated"
        let provider = general.compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "provider" }!
        check(provider.itemTitles == ["OpenAI · GPT", "Anthropic · Claude"], "both providers available")
        provider.selectItem(at: 1); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        check(key.stringValue == "fixture-claude-key" && model.selectedItem?.representedObject == nil, "Claude draft has own key and no invented model")
        provider.selectItem(at: 0); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        check(key.stringValue == "fixture-updated", "key draft retained when switching provider")
        _ = delegate.perform(NSSelectorFromString("refreshModels"))
        for _ in 0..<100 where !model.isEnabled { try await Task.sleep(nanoseconds: 10_000_000) }
        check(model.isEnabled && model.selectedItem?.representedObject as? String == "gpt-4.1-mini", "model picker loads verified API list")
        _ = delegate.perform(NSSelectorFromString("refreshModels"))
        provider.selectItem(at: 1); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        try await Task.sleep(nanoseconds: 50_000_000)
        check(model.selectedItem?.representedObject == nil && !model.isEnabled, "late OpenAI list does not populate Claude picker")
        provider.selectItem(at: 0); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        tabs.selectTabViewItem(at: 1); tabs.selectTabViewItem(at: 0)
        check(key.stringValue == "fixture-updated" && mode.indexOfSelectedItem == 1, "draft retained across tabs")
        for (appearance, name) in [(NSAppearance.Name.aqua, "settings-light"), (.darkAqua, "settings-dark")] {
            window.appearance = NSAppearance(named: appearance)
            try image(window, name: name)
            let body = tabs.tabViewItems[0].view!.subviews.first!
            check(body.frame.minY >= -1 && body.frame.maxY <= tabs.tabViewItems[0].view!.bounds.height + 1, "general pane fits")
        }
        tabs.selectTabViewItem(at: 2); window.appearance = NSAppearance(named: .aqua)
        try image(window, name: "notifications")
        let save = descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "저장" }!
        check(save.action == NSSelectorFromString("saveSettings") && save.keyEquivalent == "s", "save action preserved")
        _ = delegate.perform(NSSelectorFromString("saveSettings"))
        check(KeychainStore.saved == "fixture-updated" && Configuration.load().mode == .attachments, "save still writes form values")
        _ = delegate.perform(NSSelectorFromString("settings"))
        let second = app.windows.first { $0.isVisible && $0.title == "설정" }!
        let controls2 = descendants(second.contentView!)
        let provider2 = controls2.compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "provider" }!
        let model2 = controls2.compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "model" }!
        controls2.compactMap { $0 as? NSSecureTextField }.first!.stringValue = "fixture-second"
        _ = delegate.perform(NSSelectorFromString("refreshModels"))
        for _ in 0..<100 where !model2.isEnabled { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 50_000_000)
        provider2.selectItem(at: 1); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        _ = delegate.perform(NSSelectorFromString("refreshModels"))
        for _ in 0..<100 where !model2.isEnabled { try await Task.sleep(nanoseconds: 10_000_000) }
        _ = delegate.perform(NSSelectorFromString("saveSettings"))
        check(Configuration.load().provider == .anthropic && Configuration.load().claudeModel == "claude-fixture" && Configuration.load().model == fixture.model, "Claude selection saves without losing OpenAI model")
        check(KeychainStore.keys[.openai] == "fixture-second", "save retains edited key from the other provider draft")
        _ = delegate.perform(NSSelectorFromString("settings"))
        let third = app.windows.first { $0.isVisible && $0.title == "설정" }!
        let provider3 = descendants(third.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "provider" }!
        provider3.selectItem(at: 0); _ = delegate.perform(NSSelectorFromString("selectProvider"))
        _ = delegate.perform(NSSelectorFromString("saveSettings"))
        _ = delegate.perform(NSSelectorFromString("materials"))
        let materials = app.windows.first { $0.isVisible && $0.title == "자료 관리" }!
        try image(materials, name: "materials")
        let controls = descendants(materials.contentView!)
        check(controls.compactMap { $0 as? NSButton }.contains { $0.title == "첨부" && $0.state == .on && $0.identifier?.rawValue == "fixture-file" }, "attachment selection preserved")
        check(controls.compactMap { $0 as? NSButton }.contains { $0.title == "제거" && $0.action == NSSelectorFromString("removeFile:") }, "remove action preserved")
        check(controls.compactMap { $0 as? NSTextField }.contains { $0.stringValue == fixture.files[0].filename && $0.lineBreakMode == .byTruncatingMiddle }, "long filenames truncate")
        _ = delegate.perform(NSSelectorFromString("recent"))
        let recent = app.windows.first { $0.isVisible && $0.title == "최근 결과" }!
        try image(recent, name: "recent")
        check(descendants(recent.contentView!).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Caps Lock LED") }, "recent result includes LED status")
        for window in app.windows { window.close() }
        print("Native interface checks: \(passed) passed; fixture previews rendered, no real key/clipboard/API/LED access")
    }
}
