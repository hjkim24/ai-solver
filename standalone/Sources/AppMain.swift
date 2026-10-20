import AppKit

@main struct AppMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.mainMenu = makeApplicationMenu()
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
