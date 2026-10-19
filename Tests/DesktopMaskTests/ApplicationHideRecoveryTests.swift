import Testing
@testable import DesktopMask

@Test @MainActor func applicationAlreadyHiddenDoesNotNeedAnotherRequest() async throws {
    let hidden = try await ApplicationHideRecovery.perform(request: {
        Issue.record("已隐藏的应用不应重复请求")
    }, state: { .hidden }, fallback: {
        Issue.record("已隐藏的应用不应执行备用路径")
    }, pause: {})
    #expect(hidden)
}

@Test @MainActor func delayedHiddenStateDoesNotTriggerFalseFailure() async throws {
    var state: ApplicationVisibilityState = .ready
    let hidden = try await ApplicationHideRecovery.perform(request: {}, state: { state }, fallback: {
        Issue.record("隐藏状态已确认，不应执行备用路径")
    }, pause: { state = .hidden })
    #expect(hidden)
}

@Test @MainActor func rejectedHideRequestCanRecoverThroughFallback() async throws {
    var state: ApplicationVisibilityState = .ready
    var fallbackUsed = false
    let hidden = try await ApplicationHideRecovery.perform(request: {}, state: { state }, fallback: {
        fallbackUsed = true
        state = .hidden
    }, pause: {})
    #expect(hidden)
    #expect(fallbackUsed)
}

@Test @MainActor func inactiveApplicationIsNotTreatedAsHidden() async throws {
    let hidden = try await ApplicationHideRecovery.perform(request: {}, state: { .inactive }, fallback: {}, pause: {})
    #expect(!hidden)
}

@Test @MainActor func terminatedApplicationDoesNotRunHideFallback() async throws {
    var state: ApplicationVisibilityState = .ready
    let hidden = try await ApplicationHideRecovery.perform(request: { state = .terminated }, state: { state }, fallback: {
        Issue.record("应用已退出，不应继续请求隐藏")
    }, pause: {})
    #expect(!hidden)
}

@Test @MainActor func failedHideFallbackIsNotOverriddenByLaterHiddenState() async throws {
    enum FallbackFailure: Error { case unsupported }
    var state: ApplicationVisibilityState = .ready
    do {
        _ = try await ApplicationHideRecovery.perform(request: {}, state: { state }, fallback: {
            state = .hidden
            throw FallbackFailure.unsupported
        }, pause: {})
        Issue.record("备用请求的明确错误不应被忽略")
    } catch FallbackFailure.unsupported { }
}
