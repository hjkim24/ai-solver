import Foundation

private final class FakeLight: CapsLockLight {
    let initialState: Bool
    var writes: [Bool] = []
    var restored = false
    var failAt: Int?
    var failRestore = false
    init(_ initial: Bool = false) { initialState = initial }
    func set(_ on: Bool) throws {
        if writes.count == failAt { throw SolverFailure(message: "test output error") }
        writes.append(on)
    }
    func restore() throws {
        restored = true
        if failRestore { throw SolverFailure(message: "test restore error") }
        writes.append(initialState)
    }
}

@MainActor
func checkLED() async throws {
    let input = Data(#"{"model":"kept-model","mode":"general","capsLockBlink":true}"#.utf8)
    let config = try JSONDecoder().decode(Configuration.self, from: input)
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
    try SelfCheck.check("Caps Lock LED setting persists without dropping model or mode") {
        try SelfCheck.require(saved["capsLockBlink"] as? Bool == true && config.model == "kept-model" && config.mode == .general, "LED 설정 저장 실패")
    }
    let legacy = try JSONDecoder().decode(Configuration.self, from: Data(#"{"model":"legacy"}"#.utf8))
    try SelfCheck.check("legacy LED preference is off") { try SelfCheck.require(!legacy.capsLockBlink, "이전 설치에서 LED를 자동 실행함") }
    try SelfCheck.check("restoration respects a user lock-state change") {
        try SelfCheck.require(InternalCapsLockLight.restorationValue(initialLED: false, initialLock: false, currentLock: true), "사용자가 켠 잠금 상태를 무시함")
        try SelfCheck.require(!InternalCapsLockLight.restorationValue(initialLED: true, initialLock: true, currentLock: false), "사용자가 끈 잠금 상태를 무시함")
        try SelfCheck.require(InternalCapsLockLight.restorationValue(initialLED: true, initialLock: false, currentLock: false), "잠금 상태가 같을 때 원래 LED 상태를 잃음")
    }
    for initial in [false, true] {
        let light = FakeLight(initial)
        var waits: [Duration] = []
        try await blinkCapsLockLED(count: 3, light: light, pause: { waits.append($0) })
        try SelfCheck.check("three flashes preserve initial \(initial ? "on" : "off") state") {
            try SelfCheck.require(light.writes == [!initial, initial, !initial, initial, !initial, initial, initial] && light.restored, "점멸 횟수 또는 원복 오류")
            try SelfCheck.require(waits == [.milliseconds(250), .milliseconds(350), .milliseconds(250), .milliseconds(350), .milliseconds(250)], "점멸 간격 오류")
        }
    }
    for count in [0, 11] {
        let light = FakeLight(); var rejected = false
        do { try await blinkCapsLockLED(count: count, light: light, pause: { _ in }) } catch { rejected = true }
        try SelfCheck.check("invalid answer number never changes LED") { try SelfCheck.require(rejected && light.writes.isEmpty, "보기 범위 밖 LED 출력") }
    }
    for (count, writes) in [(1, 3), (10, 21)] {
        let light = FakeLight()
        try await blinkCapsLockLED(count: count, light: light, pause: { _ in })
        try SelfCheck.check("valid boundary \(count) flashes completes and restores") { try SelfCheck.require(light.writes.count == writes && light.writes.last == false && light.restored, "유효한 보기 경계 점멸 실패") }
    }
    let broken = FakeLight(); broken.failAt = 1
    var failed = false
    do { try await blinkCapsLockLED(count: 3, light: broken, pause: { _ in }) } catch { failed = true }
    try SelfCheck.check("device write failure still restores initial LED") { try SelfCheck.require(failed && broken.restored && broken.writes.last == false, "출력 실패 후 원복 누락") }
    let restoreBroken = FakeLight(); restoreBroken.failRestore = true
    failed = false
    do { try await blinkCapsLockLED(count: 1, light: restoreBroken, pause: { _ in }) } catch { failed = true }
    try SelfCheck.check("restore failure is reported") { try SelfCheck.require(failed, "원복 실패를 성공으로 처리함") }

    let canceled = FakeLight()
    var resume: CheckedContinuation<Void, Never>?
    let task = Task {
        try await blinkCapsLockLED(count: 3, light: canceled, pause: { _ in
            await withCheckedContinuation { resume = $0 }
        })
    }
    while resume == nil { await Task.yield() }
    task.cancel(); resume?.resume()
    _ = try? await task.value
    try SelfCheck.check("cancellation during flash restores without more flashes") { try SelfCheck.require(canceled.writes == [true, false] && canceled.restored, "취소 이후 계속 점멸함") }

    var pulses: [Int] = []
    let notifier = CapsLockNotifier(flash: { pulses.append($0) })
    let answer = JobOutput(state: "answered", message: "정답", number: 3)
    notifier.update(enabled: true, requestID: "A", output: answer)
    await notifier.waitUntilIdle()
    notifier.update(enabled: true, requestID: "A", output: answer)
    await notifier.waitUntilIdle()
    for state in ["ready", "solving", "deferred", "error", "disabled"] {
        notifier.update(enabled: true, requestID: "B", output: JobOutput(state: state, message: "검사", number: 2))
    }
    notifier.update(enabled: false, requestID: "C", output: answer)
    notifier.update(enabled: true, requestID: "D", output: JobOutput(state: "answered", message: "검사", number: 11))
    await notifier.waitUntilIdle()
    try SelfCheck.check("only one valid completed answer triggers one LED pattern") { try SelfCheck.require(pulses == [3], "중복·보류·비활성 응답으로 점멸함") }

    var order: [String] = [], oldResume: CheckedContinuation<Void, Never>?
    let serial = CapsLockNotifier(flash: { number in
        order.append("start\(number)")
        if number == 1 { await withCheckedContinuation { oldResume = $0 } }
        order.append("restore\(number)")
    })
    serial.update(enabled: true, requestID: "old", output: JobOutput(state: "answered", message: "", number: 1))
    while oldResume == nil { await Task.yield() }
    serial.update(enabled: true, requestID: "new", output: JobOutput(state: "answered", message: "", number: 2))
    await Task.yield()
    try SelfCheck.require(order == ["start1"], "이전 원복 전에 새 점멸을 실행함")
    oldResume?.resume(); await serial.waitUntilIdle()
    try SelfCheck.check("replacement waits for old LED restoration") { try SelfCheck.require(order == ["start1", "restore1", "start2", "restore2"], "새 점멸과 이전 원복이 경합함") }

    var ledError = ""
    let denied = CapsLockNotifier(flash: { _ in throw SolverFailure(message: "permission denied") })
    denied.onStatus = { ledError = $0 }
    let jobs = JobController()
    jobs.onChange = { denied.update(enabled: true, requestID: jobs.requestID, output: jobs.output) }
    jobs.setEnabled(true); jobs.begin("denied")
    jobs.run("denied", remainingMS: 1000) { _ in answer }
    for _ in 0..<20 { await Task.yield() }
    await denied.waitUntilIdle()
    try SelfCheck.check("LED access error preserves the published job answer") { try SelfCheck.require(ledError.contains("permission denied") && jobs.output.state == "answered" && jobs.output.number == 3, "LED 오류를 숨기거나 답을 바꿈") }
    jobs.onChange = nil; jobs.setEnabled(false)

    let stuck = FakeLight(); stuck.failRestore = true
    var blockedResume: CheckedContinuation<Void, Never>?, attempts = 0, blockedStatus = ""
    let blocked = CapsLockNotifier(flash: { _ in
        attempts += 1
        if attempts == 1 {
            try await blinkCapsLockLED(count: 1, light: stuck, pause: { _ in
                await withCheckedContinuation { blockedResume = $0 }
            })
        }
    })
    blocked.onStatus = { blockedStatus = $0 }
    blocked.update(enabled: true, requestID: "restore-old", output: JobOutput(state: "answered", message: "", number: 1))
    while blockedResume == nil { await Task.yield() }
    blocked.update(enabled: true, requestID: "restore-new", output: JobOutput(state: "answered", message: "", number: 2))
    blockedResume?.resume(); await blocked.waitUntilIdle()
    blocked.test(); await blocked.waitUntilIdle()
    try SelfCheck.check("restore failure blocks queued and manual flashes while preserving its diagnostic") {
        try SelfCheck.require(attempts == 1 && blockedStatus.contains("원복 실패"), "원복 실패 뒤 새 점멸을 실행하거나 오류를 덮음")
    }
}
