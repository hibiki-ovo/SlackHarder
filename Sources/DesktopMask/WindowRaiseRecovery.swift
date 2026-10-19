import ApplicationServices

private enum WindowRaiseSettings {
    static let confirmationAttempts = 3
    static let confirmationInterval: Duration = .milliseconds(100)
}

@MainActor
enum WindowRaiseRecovery {
    static func perform(
        raise: () async throws -> AXError,
        isReady: () async -> Bool,
        pause: () async throws -> Void = { try await Task.sleep(for: WindowRaiseSettings.confirmationInterval) }
    ) async throws -> AXError {
        try Task.checkCancellation()
        if await isReady() { return .success }
        let result = try await raise()
        // 只有协议明确允许结果不确定的 cannotComplete 才用实际状态确认，其他错误直接保留。
        guard result == .cannotComplete else { return result }
        for attempt in .zero..<WindowRaiseSettings.confirmationAttempts {
            try Task.checkCancellation()
            if await isReady() { return .success }
            if attempt < WindowRaiseSettings.confirmationAttempts - 1 { try await pause() }
        }
        return result
    }
}
