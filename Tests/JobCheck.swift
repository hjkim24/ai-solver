import Foundation

@MainActor func checkJobs() async throws {
    let jobs = JobController()
    try SelfCheck.check("new connection starts disabled") { try SelfCheck.require(!jobs.enabled && jobs.output.state == "disabled", "새 연결이 자동 활성화됨") }
    jobs.setEnabled(true)
    let answer = JobOutput(state: "answered", message: "새 결과", detail: "근거", number: 2)
    for oldThrows in [false, true] {
        var oldCompletion: CheckedContinuation<JobOutput, Error>?
        jobs.begin("A")
        jobs.run("A", remainingMS: 1000) { _ in
            try await withCheckedThrowingContinuation { oldCompletion = $0 }
        }
        await Task.yield()
        jobs.begin("B")
        jobs.run("B", remainingMS: 1000) { _ in answer }
        await Task.yield()
        if oldThrows { oldCompletion?.resume(throwing: SolverFailure(message: "이전 오류")) }
        else { oldCompletion?.resume(returning: JobOutput(state: "answered", message: "이전 결과", detail: "", number: 1)) }
        await Task.yield()
        try SelfCheck.check("late \(oldThrows ? "error" : "success") cannot replace a newer answer") {
            try SelfCheck.require(jobs.output.number == 2 && jobs.requestID == "B", "오래된 응답이 최신 결과를 변경함")
        }
        jobs.cancel("A", reason: "오래된 취소")
        try SelfCheck.check("old cancel cannot clear a newer answer") { try SelfCheck.require(jobs.output.number == 2, "오래된 취소를 수락함") }
    }
    jobs.begin("timeout")
    jobs.run("timeout", remainingMS: 20) { _ in
        try? await Task.sleep(nanoseconds: 100_000_000)
        return answer
    }
    try await Task.sleep(nanoseconds: 60_000_000)
    try SelfCheck.check("deadline clears an answer even when work ignores cancellation") { try SelfCheck.require(jobs.output.state == "error" && jobs.output.number == nil, "제한 시간 이후 답을 표시함") }
    jobs.begin("disabled")
    jobs.run("disabled", remainingMS: 1000) { stage in stage("solving", "풀이 중"); return answer }
    jobs.setEnabled(false)
    await Task.yield()
    try SelfCheck.check("stop invalidates work and recent answer") { try SelfCheck.require(jobs.output.state == "disabled" && jobs.output.number == nil, "중지 뒤 답이 표시됨") }
}
