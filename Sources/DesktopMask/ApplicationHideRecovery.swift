import Foundation

private enum ApplicationHideSettings {
    static let initialConfirmationAttempts = 5
    static let fallbackConfirmationAttempts = 50
    static let confirmationInterval: Duration = .milliseconds(20)
}

@MainActor
enum ApplicationHideRecovery {
    static func perform(
        request: () -> Void,
        state: () -> ApplicationVisibilityState,
        fallback: () async throws -> Void,
        pause: () async throws -> Void = { try await Task.sleep(for: ApplicationHideSettings.confirmationInterval) }
    ) async throws -> Bool {
        try Task.checkCancellation()
        switch state() {
        case .hidden: return true
        case .terminated: return false
        case .ready, .inactive: break
        }
        request()
        for _ in .zero..<ApplicationHideSettings.initialConfirmationAttempts {
            try Task.checkCancellation()
            switch state() {
            case .hidden: return true
            case .terminated: return false
            case .ready, .inactive: try await pause()
            }
        }
        try Task.checkCancellation()
        switch state() {
        case .hidden: return true
        case .terminated: return false
        case .ready, .inactive: break
        }
        try await fallback()
        for _ in .zero..<ApplicationHideSettings.fallbackConfirmationAttempts {
            try Task.checkCancellation()
            switch state() {
            case .hidden: return true
            case .terminated: return false
            case .ready, .inactive: try await pause()
            }
        }
        return state() == .hidden
    }
}
