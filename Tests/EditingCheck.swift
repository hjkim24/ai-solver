import AppKit

@MainActor final class EditingResponder: NSObject, NSApplicationDelegate {
    var received: [String] = []
    @objc func paste(_ sender: Any?) { received.append("paste") }
    @objc func selectAll(_ sender: Any?) { received.append("selectAll") }
}

@main struct EditingCheck {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let responder = EditingResponder()
        app.delegate = responder
        app.mainMenu = makeApplicationMenu()
        for (key, expected) in [("v", "paste"), ("a", "selectAll")] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: key == "v" ? 9 : 0)!
            guard app.mainMenu?.performKeyEquivalent(with: event) == true, responder.received.last == expected else {
                throw NSError(domain: "EditingCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Command-\(key) did not reach \(expected): through the app menu"])
            }
        }
        print("Editing shortcut checks passed: 2 (paste, select all; system clipboard untouched)")
    }
}
