import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

protocol CapsLockLight: AnyObject {
    var initialState: Bool { get }
    func set(_ on: Bool) throws
    func restore() throws
}

struct CapsLockRestoreFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func blinkCapsLockLED(count: Int, light: CapsLockLight,
                     pause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws {
    guard (1...10).contains(count) else { throw SolverFailure(message: "LED 점멸 횟수는 보기 번호 1~10이어야 합니다.") }
    var failure: Error?
    do {
        for index in 0..<count {
            try Task.checkCancellation()
            try light.set(!light.initialState)
            try await pause(.milliseconds(250))
            try Task.checkCancellation()
            try light.set(light.initialState)
            if index + 1 < count { try await pause(.milliseconds(350)) }
        }
    } catch { failure = error }
    do { try light.restore() }
    catch { throw CapsLockRestoreFailure(message: "Caps Lock LED 원복 실패: \(error.localizedDescription)") }
    if let failure { throw failure }
}

final class InternalCapsLockLight: CapsLockLight {
    private let device: IOHIDDevice
    private let element: IOHIDElement
    let initialState: Bool
    private let initialLock: Bool
    private static var lockState: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) }
    static let permissionHint = "시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링에서 권한 요청에 표시된 실행 앱(Aside 또는 Canvas RAG Solver)을 허용한 뒤 메뉴 앱을 다시 연결하세요."

    static func requestAccess() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }
    init() throws {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else {
            throw SolverFailure(message: "내장 키보드를 찾을 수 없습니다.")
        }
        defer { IOObjectRelease(iterator) }
        var keyboard: IOHIDDevice?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            if property(kIOHIDPrimaryUsagePageKey) as? Int == kHIDPage_GenericDesktop,
               property(kIOHIDPrimaryUsageKey) as? Int == kHIDUsage_GD_Keyboard,
               property("Built-In") as? Bool == true {
                keyboard = IOHIDDeviceCreate(kCFAllocatorDefault, service)
                break
            }
        }
        guard let keyboard else { throw SolverFailure(message: "MacBook 내장 키보드에 접근할 수 없습니다.") }
        let status = IOHIDDeviceOpen(keyboard, 0)
        guard status == kIOReturnSuccess else {
            throw SolverFailure(message: "내장 LED 접근 실패 (\(status)). \(Self.permissionHint)")
        }
        do {
            guard let elements = IOHIDDeviceCopyMatchingElements(keyboard, nil, 0) as? [IOHIDElement],
                  let caps = elements.first(where: { IOHIDElementGetType($0) == kIOHIDElementTypeOutput && IOHIDElementGetUsagePage($0) == kHIDPage_LEDs && IOHIDElementGetUsage($0) == kHIDUsage_LED_CapsLock }) else {
                throw SolverFailure(message: "이 내장 키보드에서 Caps Lock LED 출력 항목을 찾지 못했습니다.")
            }
            let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, caps, 0, 0)
            var value = Unmanaged.passUnretained(placeholder)
            let result = IOHIDDeviceGetValue(keyboard, caps, &value)
            guard result == kIOReturnSuccess else { throw SolverFailure(message: "원래 LED 상태를 읽지 못했습니다 (\(result)).") }
            let initial = IOHIDValueGetIntegerValue(value.takeUnretainedValue())
            guard initial == 0 || initial == 1 else { throw SolverFailure(message: "Caps Lock LED 상태가 0/1 형식이 아닙니다.") }
            device = keyboard; element = caps; initialState = initial == 1; initialLock = Self.lockState
        } catch { IOHIDDeviceClose(keyboard, 0); throw error }
    }
    deinit { IOHIDDeviceClose(device, 0) }
    func set(_ on: Bool) throws {
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
        let status = IOHIDDeviceSetValue(device, element, value)
        guard status == kIOReturnSuccess else { throw SolverFailure(message: "Caps Lock LED 출력 실패 (\(status)).") }
    }
    static func restorationValue(initialLED: Bool, initialLock: Bool, currentLock: Bool) -> Bool {
        initialLock == currentLock ? initialLED : currentLock
    }
    func restore() throws { try set(Self.restorationValue(initialLED: initialState, initialLock: initialLock, currentLock: Self.lockState)) }

    static func flash(_ count: Int) async throws {
        // IOHIDDeviceSetValue blocks; keep all device access off the main actor.
        let work = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let light = try InternalCapsLockLight()
            try await blinkCapsLockLED(count: count, light: light)
        }
        try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }
}

@MainActor final class CapsLockNotifier {
    private var task: Task<Void, Never>?
    private var key: String?
    private var restoreFailure: String?
    private let flash: (Int) async throws -> Void
    var onStatus: ((String) -> Void)?
    init(flash: @escaping (Int) async throws -> Void = InternalCapsLockLight.flash) { self.flash = flash }
    func update(enabled: Bool, requestID: String?, output: JobOutput) {
        guard enabled, output.state == "answered", let id = requestID,
              let number = output.number, (1...10).contains(number) else { cancel(); return }
        guard key != id else { return }
        start(number, id: id)
    }
    func test() { start(3, id: "led-test-" + UUID().uuidString) }
    private func start(_ number: Int, id: String) {
        let previous = task; previous?.cancel(); key = id
        let flash = self.flash
        task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            if let failure = self?.restoreFailure { self?.onStatus?(failure); return }
            self?.onStatus?("Caps Lock LED: \(number)회 점멸 중")
            do {
                try await flash(number)
                guard !Task.isCancelled else { return }
                self?.onStatus?("Caps Lock LED: \(number)회 출력 완료")
            } catch let failure as CapsLockRestoreFailure {
                let message = "\(failure.localizedDescription) LED 점멸을 중단했습니다. 표시등 상태를 확인하고 메뉴 앱을 다시 연결하세요."
                self?.restoreFailure = message
                self?.onStatus?(message)
            } catch is CancellationError { return }
            catch { self?.onStatus?("LED 알림 실패: \(error.localizedDescription)") }
        }
    }
    func cancel() { task?.cancel(); key = nil }
    func waitUntilIdle() async { await task?.value }
}
