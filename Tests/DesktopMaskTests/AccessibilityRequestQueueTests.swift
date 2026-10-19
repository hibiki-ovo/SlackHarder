import Foundation
import Testing
@testable import DesktopMask

@Test @MainActor func accessibilityRequestsDoNotRunOnMainThread() async throws {
    let queue = AccessibilityRequestQueue(label: "test.ax.background")
    let ranOnMainThread = try await queue.perform { Thread.isMainThread }
    #expect(!ranOnMainThread)
}

@Test func failedRequestDoesNotBlockNextRequest() async throws {
    enum RequestFailure: Error { case unavailable }
    let queue = AccessibilityRequestQueue(label: "test.ax.failure")
    do {
        try await queue.perform { throw RequestFailure.unavailable }
        Issue.record("预期失败请求抛出错误")
    } catch RequestFailure.unavailable {
        let nextResult = try await queue.perform { "completed" }
        #expect(nextResult == "completed")
    }
}

@Test func cancelledRequestDoesNotExecute() async throws {
    let queue = AccessibilityRequestQueue(label: "test.ax.cancelled")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await queue.perform { "unexpected" }
    }
    do {
        _ = try await task.value
        Issue.record("取消的请求不应继续执行")
    } catch is CancellationError { }
}
