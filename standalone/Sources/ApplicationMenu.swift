import AppKit

@MainActor func makeApplicationMenu() -> NSMenu {
    let menu = NSMenu()
    let application = NSMenuItem(title: "Clipboard AI Solver", action: nil, keyEquivalent: "")
    application.submenu = NSMenu(title: application.title)
    application.submenu?.addItem(withTitle: "설정…", action: NSSelectorFromString("settings"), keyEquivalent: ",")
    application.submenu?.addItem(.separator())
    application.submenu?.addItem(withTitle: "Clipboard AI Solver 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(application)

    let edit = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu(title: edit.title)
    for (title, action, key) in [("실행 취소", "undo:", "z"), ("다시 실행", "redo:", "z"),
                                 ("잘라내기", "cut:", "x"), ("복사", "copy:", "c"),
                                 ("붙여넣기", "paste:", "v"), ("전체 선택", "selectAll:", "a")] {
        let item = edit.submenu!.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = action == "redo:" ? [.command, .shift] : .command
    }
    menu.addItem(edit)
    return menu
}
