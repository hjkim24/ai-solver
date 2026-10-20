import Foundation

struct JobOutput {
    var state: String
    var message: String
    var detail = ""
    var number: Int?
}

@MainActor final class JobController {
    private(set) var enabled = false
    private(set) var requestID: String?
    private(set) var output = JobOutput(state: "disabled", message: "메뉴에서 사용 시작을 선택하세요.")
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var deadline = ContinuousClock.now
    private var running = false
    private var started = false

    private func stop() { task?.cancel(); timer?.cancel(); task = nil; timer = nil; running = false }
    private func publish(_ value: JobOutput) { output = value; onChange?() }
    func setEnabled(_ value: Bool) {
        stop(); enabled = value; requestID = nil
        publish(JobOutput(state: value ? "ready" : "disabled", message: value ? "단축키로 문항을 선택하세요." : "사용 중지"))
    }
    func invalidate(_ reason: String) {
        stop(); requestID = nil
        publish(JobOutput(state: enabled ? "ready" : "disabled", message: reason))
    }
    @discardableResult func begin(_ id: String) -> Bool {
        stop(); requestID = id; started = false
        guard enabled else { publish(JobOutput(state: "disabled", message: "메뉴에서 사용 시작을 선택하세요.")); return false }
        deadline = .now.advanced(by: .seconds(45)); running = true
        publish(JobOutput(state: "locating", message: "문항 범위 확인 중"))
        armTimer(id)
        return true
    }
    func cancel(_ id: String, reason: String) {
        guard id == requestID else { return }
        stop()
        publish(JobOutput(state: enabled ? "deferred" : "disabled", message: reason))
    }
    private func armTimer(_ id: String) {
        timer?.cancel()
        let end = deadline
        timer = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: end) } catch { return }
            guard let self, self.requestID == id, self.running else { return }
            self.stop()
            self.publish(JobOutput(state: "error", message: "45초 처리 제한 시간을 넘었습니다. 다시 선택하세요."))
        }
    }
    private func current(_ id: String) -> Bool { enabled && running && requestID == id && ContinuousClock.now < deadline }
    func run(_ id: String, remainingMS: Int, operation: @escaping (@escaping (String, String) -> Void) async throws -> JobOutput) {
        guard current(id), !started else { return }
        started = true
        deadline = min(deadline, .now.advanced(by: .milliseconds(remainingMS)))
        armTimer(id)
        task = Task { [weak self] in
            do {
                let result = try await operation { [weak self] state, message in
                    guard let self, self.current(id) else { return }
                    self.publish(JobOutput(state: state, message: message))
                }
                guard let self, self.current(id) else { return }
                self.stop(); self.publish(result)
            } catch {
                guard let self, self.current(id) else { return }
                self.stop()
                let failure = error as? SolverFailure
                self.publish(JobOutput(state: failure?.deferred == true ? "deferred" : "error", message: failure?.message ?? "네트워크 또는 처리 오류입니다. 연결 상태를 확인하세요."))
            }
        }
    }
}
