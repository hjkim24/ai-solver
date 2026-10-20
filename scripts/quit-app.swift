import AppKit
import Foundation

// Wait for the app's normal quit handler, including pending LED restoration.
let identifiers = Set(CommandLine.arguments.dropFirst())
for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier.map(identifiers.contains) == true {
    guard app.terminate() else { throw NSError(domain: "AppQuit", code: 1, userInfo: [NSLocalizedDescriptionKey: "앱을 종료하지 못했습니다. 메뉴에서 종료한 뒤 다시 실행하세요."]) }
    let deadline = Date().addingTimeInterval(12)
    while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard app.isTerminated else { throw NSError(domain: "AppQuit", code: 2, userInfo: [NSLocalizedDescriptionKey: "앱의 정상 종료를 기다리는 중입니다. 상태를 확인하세요."]) }
}
