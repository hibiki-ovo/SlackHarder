import Foundation

private enum ApplicationRestoreSettings {
    static let initialConfirmationAttempts = 5
    static let fallbackConfirmationAttempts = 25
    static let confirmationInterval: Duration = .milliseconds(20)
}

@MainActor
enum ApplicationRestoreRecovery {
    static func perform(
        request: () -> Void,
        state: () -> ApplicationVisibilityState,
        fallback: () async throws -> Void,
        pause: () async throws -> Void = { try await Task.sleep(for: ApplicationRestoreSettings.confirmationInterval) }
    ) async throws -> Bool {
        try Task.checkCancellation()
        switch state() {
        case .ready: return true
        case .terminated: return false
        case .hidden, .inactive: break
        }
        request()
        for _ in .zero..<ApplicationRestoreSettings.initialConfirmationAttempts {
            try Task.checkCancellation()
            switch state() {
            case .ready: return true
            case .terminated: return false
            case .hidden, .inactive: try await pause()
            }
        }
        // 请求结果不等于最终状态；给主 RunLoop 更新状态的机会后才使用备用路径。
        try Task.checkCancellation()
        switch state() {
        case .ready: return true
        case .terminated: return false
        case .hidden, .inactive: break
        }
        try await fallback()
        for _ in .zero..<ApplicationRestoreSettings.fallbackConfirmationAttempts {
            try Task.checkCancellation()
            switch state() {
            case .ready: return true
            case .terminated: return false
            case .hidden, .inactive: try await pause()
            }
        }
        return state() == .ready
    }
}
