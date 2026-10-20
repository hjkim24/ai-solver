import AppKit
import Darwin

@main struct AppMain {
    static func main() {
        guard HostOrigin.valid(arguments: CommandLine.arguments, allowed: Bundle.main.object(forInfoDictionaryKey: "AllowedExtensionOrigin") as? String) else { exit(2) }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.mainMenu = makeApplicationMenu()
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
