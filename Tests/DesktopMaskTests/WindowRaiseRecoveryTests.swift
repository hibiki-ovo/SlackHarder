import ApplicationServices
import Testing
@testable import DesktopMask

@Test @MainActor func alreadyRestoredForegroundWindowDoesNotNeedRaise() async throws {
    var raised = false
    let result = try await WindowRaiseRecovery.perform(raise: {
        raised = true
        return .cannotComplete
    }, isReady: { true }, pause: {})
    #expect(result == .success)
    #expect(!raised)
}

@Test @MainActor func timeoutIsAcceptedOnlyAfterWindowStateConfirmsRestoration() async throws {
    var restored = false
    let result = try await WindowRaiseRecovery.perform(raise: {
        restored = true
        return .cannotComplete
    }, isReady: { restored }, pause: {})
    #expect(result == .success)
}

@Test @MainActor func delayedRestorationCanCompleteWithoutRepeatingRaise() async throws {
    var restored = false
    var raised = false
    let result = try await WindowRaiseRecovery.perform(raise: {
        #expect(!raised)
        raised = true
        return .cannotComplete
    }, isReady: { restored }, pause: { restored = true })
    #expect(result == .success)
}

@Test @MainActor func timeoutWithoutRestoredWindowRemainsFailure() async throws {
    let result = try await WindowRaiseRecovery.perform(raise: { .cannotComplete }, isReady: { false }, pause: {})
    #expect(result == .cannotComplete)
}

@Test @MainActor func invalidWindowErrorCannotBeOverriddenByLaterReadyState() async throws {
    var restored = false
    let result = try await WindowRaiseRecovery.perform(raise: {
        restored = true
        return .invalidUIElement
    }, isReady: { restored }, pause: {})
    #expect(result == .invalidUIElement)
}
