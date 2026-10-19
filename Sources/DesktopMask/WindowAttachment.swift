import AppKit
import ApplicationServices

struct AttachmentGeometry {
    static func appKitRect(position: CGPoint, size: CGSize, primaryScreenTop: CGFloat) -> NSRect? {
        guard [position.x, position.y, size.width, size.height, primaryScreenTop].allSatisfy(\.isFinite),
              size.width > .zero, size.height > .zero else { return nil }
        return NSRect(x: position.x, y: primaryScreenTop - position.y - size.height,
                      width: size.width, height: size.height)
    }
}

private enum AccessibilitySettings {
    static let listingTimeout: Float = 0.15
    static let controlTimeout: Float = 0.4
    static let maximumConcurrentApplications = 4
    static let listingApplicationBudget: Duration = .seconds(1)
    static let singleRunningInstanceCount = 1
}

private struct AccessibilityFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private struct ApplicationCandidate: Sendable {
    let pid: pid_t
    let name: String
}

// AX 引用只作为不可变句柄跨线程传递；同一窗口的请求全部在独立串行队列上执行。
private final class AccessibilityWindow: @unchecked Sendable {
    let window: AXUIElement
    let appElement: AXUIElement
    let pid: pid_t
    let title: String
    private let queue: AccessibilityRequestQueue

    init(window: AXUIElement, appElement: AXUIElement, pid: pid_t, title: String) {
        self.window = window
        self.appElement = appElement
        self.pid = pid
        self.title = title
        queue = AccessibilityRequestQueue(label: "desktop-mask.ax.\(pid)")
        AXUIElementSetMessagingTimeout(window, AccessibilitySettings.controlTimeout)
        AXUIElementSetMessagingTimeout(appElement, AccessibilitySettings.controlTimeout)
    }

    func perform<T: Sendable>(_ operation: @escaping @Sendable (AccessibilityWindow) throws -> T) async throws -> T {
        try await queue.perform { try operation(self) }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func valueAttribute(_ element: AXUIElement, _ name: String, type: AXValueType) -> AXValue? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    func minimized() throws -> Bool {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value),
                  operation: L10n.text("Read minimized state"))
        guard let minimized = value as? Bool else {
            throw AccessibilityFailure(message: L10n.text("The target window state is unavailable. Please choose a window again."))
        }
        return minimized
    }

    func setMinimized(_ minimized: Bool) throws {
        try check(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                              minimized ? kCFBooleanTrue : kCFBooleanFalse),
                  operation: minimized ? L10n.text("Minimize window") : L10n.text("Restore window"))
    }

    func check(_ result: AXError, operation: String) throws {
        guard result != .success else { return }
        NSLog("窗口控制失败 pid=%d window=%@ operation=%@ AXError=%d", pid, title, operation, result.rawValue)
        throw AccessibilityFailure(message: L10n.format("%@ failed (%@). Check that the window still exists and supports this action, or grant Accessibility access again.", operation, String(describing: result)))
    }
}

// 观察器在后台完成注册，消息源仅在主 RunLoop 中安装和移除。
private final class AccessibilityObservation: @unchecked Sendable {
    let observer: AXObserver
    init(_ observer: AXObserver) { self.observer = observer }
}

@MainActor
final class WindowAttachment {
    static let changedNotification = Notification.Name("DesktopMaskAttachedWindowChanged")
    enum Snapshot: Sendable {
        case visible(NSRect)
        case hidden
        case unavailable
    }

    let application: NSRunningApplication
    let title: String
    private let handle: AccessibilityWindow
    private var observation: AccessibilityObservation?
    private var observationTask: Task<Void, Never>?

    private init(application: NSRunningApplication, handle: AccessibilityWindow) {
        self.application = application
        self.handle = handle
        title = handle.title
    }

    static func availableWindows() async -> [WindowAttachment] {
        guard AXIsProcessTrusted() else { return [] }
        let started = ContinuousClock.now
        let candidates = NSWorkspace.shared.runningApplications
            .filter {
                !$0.isTerminated && $0.activationPolicy == .regular
                    && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .map { ApplicationCandidate(pid: $0.processIdentifier, name: $0.localizedName ?? L10n.text("App")) }
            .sorted { $0.name < $1.name }
        let handles = await withTaskGroup(of: [AccessibilityWindow].self) { group in
            var results: [AccessibilityWindow] = []
            var iterator = candidates.makeIterator()
            for _ in .zero..<AccessibilitySettings.maximumConcurrentApplications {
                guard let candidate = iterator.next() else { break }
                group.addTask { enumerate(candidate) }
            }
            while let batch = await group.next() {
                results.append(contentsOf: batch)
                if !Task.isCancelled, let candidate = iterator.next() {
                    group.addTask { enumerate(candidate) }
                }
            }
            return results
        }
        guard !Task.isCancelled else { return [] }
        NSLog("窗口列表查询完成 apps=%d windows=%d elapsed=%@", candidates.count, handles.count,
              String(describing: started.duration(to: .now)))
        return handles.compactMap { handle in
            guard let application = NSRunningApplication(processIdentifier: handle.pid), !application.isTerminated else { return nil }
            return WindowAttachment(application: application, handle: handle)
        }.sorted {
            let lhs = "\($0.application.localizedName ?? "") · \($0.title)"
            let rhs = "\($1.application.localizedName ?? "") · \($1.title)"
            return lhs < rhs
        }
    }

    nonisolated private static func enumerate(_ candidate: ApplicationCandidate) -> [AccessibilityWindow] {
        guard !Task.isCancelled else { return [] }
        let started = ContinuousClock.now
        let appElement = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(appElement, AccessibilitySettings.listingTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            if result != .success {
                NSLog("窗口列表查询失败 pid=%d app=%@ AXError=%d", candidate.pid, candidate.name, result.rawValue)
            }
            return []
        }
        var handles: [AccessibilityWindow] = []
        for window in windows {
            guard !Task.isCancelled else { break }
            guard started.duration(to: .now) < AccessibilitySettings.listingApplicationBudget else {
                NSLog("窗口列表查询达到时间预算 pid=%d app=%@ loaded=%d", candidate.pid, candidate.name, handles.count)
                break
            }
            AXUIElementSetMessagingTimeout(window, AccessibilitySettings.listingTimeout)
            let title = AccessibilityWindow.attribute(window, kAXTitleAttribute) as? String ?? L10n.text("Untitled Window")
            // 列表只读取标题；几何和最小化状态在选定窗口后读取。
            handles.append(AccessibilityWindow(window: window, appElement: AXUIElementCreateApplication(candidate.pid),
                                               pid: candidate.pid, title: title))
        }
        return handles
    }

    private func validate() throws {
        guard !application.isTerminated, AXIsProcessTrusted() else {
            throw AccessibilityFailure(message: L10n.text("The target app has quit or Accessibility access is unavailable. Please choose a window again."))
        }
    }

    func bringToFront() async throws {
        try validate()
        try await handle.perform { handle in
            if try handle.minimized() { try handle.setMinimized(false) }
        }
        try Task.checkCancellation()
        try await activateAndRaise()
    }

    private func activateAndRaise() async throws {
        try Task.checkCancellation()
        try validate()
        let activated = try await ApplicationRestoreRecovery.perform(request: { [application, title] in
            let unhideSent = !application.isHidden || application.unhide()
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: application) }
            let activateSent = application.activate(options: [])
            if !unhideSent || !activateSent {
                NSLog("应用恢复请求响应 pid=%d window=%@ unhideSent=%d activateSent=%d",
                      application.processIdentifier, title, unhideSent, activateSent)
            }
        }, state: { [application] in
            if application.isTerminated { return .terminated }
            if application.isHidden { return .hidden }
            return application.isActive ? .ready : .inactive
        }, fallback: { [self] in
            try await reopenRunningApplication()
        })
        guard activated else {
            try validate()
            NSLog("应用恢复状态未确认 pid=%d window=%@ hidden=%d active=%d",
                  application.processIdentifier, title, application.isHidden, application.isActive)
            throw AccessibilityFailure(message: L10n.text("The app could not be confirmed in the foreground after restoring it. Please try again shortly."))
        }
        let result = try await WindowRaiseRecovery.perform(raise: { [handle] in
            try await handle.perform { handle in
                let result = AXUIElementPerformAction(handle.window, kAXRaiseAction as CFString)
                if result != .success {
                    NSLog("窗口置前响应 pid=%d window=%@ AXError=%d", handle.pid, handle.title, result.rawValue)
                }
                return result
            }
        }, isReady: { [weak self] in
            guard let self, self.isForeground, AXIsProcessTrusted() else { return false }
            let ready = try? await self.handle.perform { handle in
                guard let minimized = AccessibilityWindow.attribute(handle.window, kAXMinimizedAttribute) as? Bool,
                      !minimized,
                      let focused = AccessibilityWindow.elementAttribute(handle.appElement, kAXFocusedWindowAttribute) else { return false }
                return CFEqual(focused, handle.window)
            }
            return self.isForeground && AXIsProcessTrusted() && ready == true
        })
        try await handle.perform { handle in
            try handle.check(result, operation: L10n.text("Bring restored window to front"))
        }
    }

    private func reopenRunningApplication() async throws {
        try Task.checkCancellation()
        try validate()
        guard let url = application.bundleURL else {
            throw AccessibilityFailure(message: L10n.text("The target app location is unavailable. Please choose a window again."))
        }
        let instances = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL == url
        }
        guard instances.count == AccessibilitySettings.singleRunningInstanceCount,
              instances.first?.processIdentifier == application.processIdentifier else {
            throw AccessibilityFailure(message: L10n.text("Multiple instances of the target app are running. Restore it from the Dock, then attach again."))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        NSLog("尝试通过系统打开接口恢复应用 pid=%d window=%@", application.processIdentifier, title)
        let opened: NSRunningApplication
        do {
            opened = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            NSLog("系统恢复应用失败 pid=%d window=%@ error=%@", application.processIdentifier, title, error.localizedDescription)
            throw error
        }
        try Task.checkCancellation()
        guard opened.processIdentifier == application.processIdentifier, !application.isTerminated else {
            throw AccessibilityFailure(message: L10n.text("The target app process has changed. Please choose a window again."))
        }
    }

    func toggleApplicationVisibility() async throws {
        try Task.checkCancellation()
        try validate()
        let started = ContinuousClock.now
        defer {
            NSLog("应用显示控制完成 pid=%d window=%@ elapsed=%@", application.processIdentifier, title,
                  String(describing: started.duration(to: .now)))
        }
        // 读取系统真实隐藏状态，兼容用户通过 Cmd+H、Dock 等入口操作。
        if application.isHidden {
            try await bringToFront()
        } else {
            let hidden = try await ApplicationHideRecovery.perform(request: { [application, title] in
                let sent = application.hide()
                if !sent {
                    NSLog("应用隐藏请求未发送 pid=%d window=%@ hidden=%d active=%d",
                          application.processIdentifier, title, application.isHidden, application.isActive)
                }
            }, state: { [application] in
                if application.isTerminated { return .terminated }
                if application.isHidden { return .hidden }
                return application.isActive ? .ready : .inactive
            }, fallback: { [self] in
                try Task.checkCancellation()
                try validate()
                try await handle.perform { handle in
                    try handle.check(AXUIElementSetAttributeValue(handle.appElement, kAXHiddenAttribute as CFString, kCFBooleanTrue),
                                     operation: L10n.text("Hide app using Accessibility"))
                }
            })
            guard hidden else {
                NSLog("应用隐藏状态未确认 pid=%d window=%@ hidden=%d active=%d terminated=%d",
                      application.processIdentifier, title, application.isHidden, application.isActive, application.isTerminated)
                throw AccessibilityFailure(message: L10n.text("The app could not be hidden or has quit. Please try again or choose a window again."))
            }
        }
    }

    var isForeground: Bool { !application.isTerminated && application.isActive && !application.isHidden }

    func snapshot() async -> Snapshot {
        guard isForeground, AXIsProcessTrusted(), let primaryScreen = NSScreen.screens.first else { return .hidden }
        let primaryScreenTop = primaryScreen.frame.maxY
        let result = try? await handle.perform { handle -> Snapshot in
            guard let minimized = AccessibilityWindow.attribute(handle.window, kAXMinimizedAttribute) as? Bool else { return .unavailable }
            guard !minimized else { return .hidden }
            guard let focused = AccessibilityWindow.elementAttribute(handle.appElement, kAXFocusedWindowAttribute),
                  CFEqual(focused, handle.window) else { return .hidden }
            guard let positionValue = AccessibilityWindow.valueAttribute(handle.window, kAXPositionAttribute, type: .cgPoint),
                  let sizeValue = AccessibilityWindow.valueAttribute(handle.window, kAXSizeAttribute, type: .cgSize) else { return .unavailable }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size),
                  let rect = AttachmentGeometry.appKitRect(position: position, size: size, primaryScreenTop: primaryScreenTop) else { return .unavailable }
            return .visible(rect)
        }
        // 后台请求返回时重新验证应用生命周期，防止过期结果覆盖新前台窗口。
        guard isForeground, AXIsProcessTrusted() else { return .hidden }
        return result ?? .unavailable
    }

    func startObserving() {
        stopObserving()
        observationTask = Task { [weak self, handle] in
            let result = try? await handle.perform { handle -> AccessibilityObservation? in
                var observer: AXObserver?
                let status = AXObserverCreate(handle.pid, { _, _, notification, _ in
                    NotificationCenter.default.post(name: Notification.Name("DesktopMaskAttachedWindowChanged"),
                                                    object: notification as String)
                }, &observer)
                guard status == .success, let observer else { return nil }
                let windowNotifications = [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
                                           kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification]
                for name in windowNotifications {
                    let result = AXObserverAddNotification(observer, handle.window, name as CFString, nil)
                    if result != .success {
                        NSLog("窗口通知注册失败 pid=%d window=%@ notification=%@ AXError=%d", handle.pid, handle.title, name, result.rawValue)
                    }
                }
                let focusedResult = AXObserverAddNotification(observer, handle.appElement, kAXFocusedWindowChangedNotification as CFString, nil)
                if focusedResult != .success {
                    NSLog("窗口通知注册失败 pid=%d notification=%@ AXError=%d", handle.pid, kAXFocusedWindowChangedNotification, focusedResult.rawValue)
                }
                return AccessibilityObservation(observer)
            }
            guard !Task.isCancelled, let self, let result else { return }
            self.observation = result
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result.observer), .commonModes)
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        if let observation {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation.observer), .commonModes)
        }
        observation = nil
    }
}
