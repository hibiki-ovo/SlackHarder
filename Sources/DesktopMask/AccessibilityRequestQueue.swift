import Foundation

private final class RequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

// 隔离同步 AX 请求；每个窗口独立串行，慢应用不阻塞主线程。
final class AccessibilityRequestQueue: Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    continuation.resume(with: Result { try operation() })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
