import Testing
@testable import DesktopMask

@Test @MainActor func applicationAlreadyReadyDoesNotNeedRestoreRequests() async throws {
    let ready = try await ApplicationRestoreRecovery.perform(request: {
        Issue.record("不应重复发送恢复请求")
    }, state: { .ready }, fallback: {
        Issue.record("不应使用备用路径")
    }, pause: {})
    #expect(ready)
}

@Test @MainActor func rejectedUnhideCanStillRecoverThroughActivation() async throws {
    var state: ApplicationVisibilityState = .hidden
    let ready = try await ApplicationRestoreRecovery.perform(request: {
        // 即使 unhide 请求未发送成功，后续激活也可能让应用恢复。
        state = .inactive
    }, state: { state }, fallback: {
        Issue.record("激活成功后不应使用备用路径")
    }, pause: { state = .ready })
    #expect(ready)
}

@Test @MainActor func acceptedRequestsWithoutVisibleApplicationUseFallback() async throws {
    var state: ApplicationVisibilityState = .hidden
    var usedFallback = false
    let ready = try await ApplicationRestoreRecovery.perform(request: {
        // 请求已发送，但应用没有实际恢复。
    }, state: { state }, fallback: {
        usedFallback = true
        state = .ready
    }, pause: {})
    #expect(usedFallback)
    #expect(ready)
}

@Test @MainActor func terminatedApplicationCannotUseFallbackEvenIfRequestWasSent() async throws {
    var state: ApplicationVisibilityState = .hidden
    let ready = try await ApplicationRestoreRecovery.perform(request: {
        state = .terminated
    }, state: { state }, fallback: {
        Issue.record("已退出的应用不应重新启动")
    }, pause: {})
    #expect(!ready)
}

@Test @MainActor func applicationStillHiddenAfterFallbackIsNotSuccess() async throws {
    let ready = try await ApplicationRestoreRecovery.perform(request: {}, state: { .hidden }, fallback: {}, pause: {})
    #expect(!ready)
}
