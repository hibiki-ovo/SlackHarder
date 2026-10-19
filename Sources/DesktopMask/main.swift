import AppKit
@preconcurrency import ApplicationServices

private enum MaskSettings {
    static let initialSize = NSSize(width: 640, height: 360)
    static let minimumSize = NSSize(width: 80, height: 60)
    static let initialOpacity = 0.4
    static let opacityRange = 0.0...1.0
    static let percentScale = 100.0
    static let preferencesDomain = "local.desktop-mask"
    static let frameKey = "maskContentFrame"
    static let opacityKey = "maskOpacity"
    static let controlsWidth: CGFloat = 260
    static let controlsHeight: CGFloat = 68
    static let controlsInset: CGFloat = 16
    static let labelY: CGFloat = 40
    static let labelHeight: CGFloat = 20
    static let sliderY: CGFloat = 12
    static let sliderHeight: CGFloat = 24
    static let attachmentRefreshInterval: TimeInterval = 0.5
}

private enum MouseSideButton: Int {
    case back = 3
    case forward = 4
}

private enum InteractionMode {
    case passthrough
    case editing
}

private struct SavedFrame: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && width >= MaskSettings.minimumSize.width
            && height >= MaskSettings.minimumSize.height
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = UserDefaults(suiteName: MaskSettings.preferencesDomain)!
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var interactionMode: InteractionMode = .passthrough
    private var state = MaskModeState()
    private var automaticItem: NSMenuItem!
    private var manualItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var recenterItem: NSMenuItem!
    private var opacity = MaskSettings.initialOpacity
    private var editItem: NSMenuItem!
    private var opacityLabel: NSTextField!
    private var opacitySlider: NSSlider!
    private var mouseSideButtonItem: NSMenuItem!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isChangingStyle = false
    private var attachment: WindowAttachment?
    private var attachmentTimer: Timer?
    private var attachmentItem: NSMenuItem!
    private var detachItem: NSMenuItem!
    private var windowPicker: WindowPickerController?
    private var attachmentTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var refreshRevision = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let saved = preferences.object(forKey: MaskSettings.opacityKey) as? Double,
           saved.isFinite, MaskSettings.opacityRange.contains(saved) {
            opacity = saved
        }
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: MaskSettings.initialSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("Overlay · Drag the title bar to move, drag edges to resize")
        panel.contentMinSize = MaskSettings.minimumSize
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        restoreFrame()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let fish = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: L10n.text("Overlay Controls"))
            fish?.isTemplate = true
            button.image = fish
            button.title = fish == nil ? "🐟" : ""
            button.toolTip = L10n.text("Overlay Controls")
            button.setAccessibilityLabel(L10n.text("Overlay Controls"))
        }
        let menu = NSMenu()
        automaticItem = addItem(L10n.text("Automatic Mode"), action: #selector(selectAutomatic), to: menu)
        manualItem = addItem(L10n.text("Manual Mode"), action: #selector(selectManual), to: menu)
        menu.addItem(.separator())
        visibilityItem = addItem(L10n.text("Hide Overlay"), action: #selector(toggleManualVisibility), to: menu)
        editItem = addItem(L10n.text("Edit Overlay (Move / Resize)"), action: #selector(toggleEditing), to: menu)
        mouseSideButtonItem = addItem(L10n.text("Mouse Side Button: Hide"), action: #selector(toggleAttachedApplication), to: menu)
        menu.addItem(.separator())
        attachmentItem = addItem(L10n.text("Attach to an App Window"), action: #selector(chooseAttachmentWindow), to: menu)
        detachItem = addItem(L10n.text("Detach"), action: #selector(detachWindow), to: menu)
        detachItem.isEnabled = false
        addItem(L10n.text("Grant Accessibility Access…"), action: #selector(requestAccessibility), to: menu)
        menu.addItem(.separator())
        addOpacitySlider(to: menu)
        menu.addItem(.separator())
        recenterItem = addItem(L10n.text("Move Overlay to Current Screen"), action: #selector(recenter), to: menu)
        addItem(L10n.text("Quit"), action: #selector(quit), to: menu)
        statusItem.menu = menu
        applyAppearance()
        updateModeMenu()
        refreshMask()
        panel.delegate = self
        installMouseMonitors()
        menu.autoenablesItems = false
        NotificationCenter.default.addObserver(self, selector: #selector(attachedWindowChanged(_:)),
                                               name: WindowAttachment.changedNotification, object: nil)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.chooseAttachmentWindow()
        }
    }

    private func addOpacitySlider(to menu: NSMenu) {
        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(
            width: MaskSettings.controlsWidth, height: MaskSettings.controlsHeight
        )))
        let controlWidth = MaskSettings.controlsWidth - MaskSettings.controlsInset - MaskSettings.controlsInset
        opacityLabel = NSTextField(labelWithString: "")
        opacityLabel.frame = NSRect(x: MaskSettings.controlsInset, y: MaskSettings.labelY,
                                   width: controlWidth, height: MaskSettings.labelHeight)
        let slider = NSSlider(value: opacity, minValue: MaskSettings.opacityRange.lowerBound,
                              maxValue: MaskSettings.opacityRange.upperBound,
                              target: self, action: #selector(opacityChanged(_:)))
        slider.frame = NSRect(x: MaskSettings.controlsInset, y: MaskSettings.sliderY,
                             width: controlWidth, height: MaskSettings.sliderHeight)
        slider.isContinuous = true
        opacitySlider = slider
        slider.setAccessibilityLabel(L10n.text("Overlay Opacity"))
        view.addSubview(opacityLabel)
        view.addSubview(slider)
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func applyAppearance() {
        panel.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(opacity))
        opacityLabel.stringValue = L10n.format("Overlay Opacity: %@%%", String(Int((opacity * MaskSettings.percentScale).rounded())))
        opacitySlider.doubleValue = opacity
        panel.ignoresMouseEvents = interactionMode == .passthrough
        editItem.state = interactionMode == .editing ? .on : .off
    }

    private func setInteractionMode(_ newMode: InteractionMode) {
        guard interactionMode != newMode else { return }
        let contentRect = panel.contentRect(forFrameRect: panel.frame)
        isChangingStyle = true
        interactionMode = newMode
        if interactionMode == .editing {
            panel.styleMask.insert(.titled)
        } else {
            panel.styleMask.remove(.titled)
        }
        panel.setFrame(panel.frameRect(forContentRect: contentRect), display: true)
        isChangingStyle = false
        applyAppearance()
    }

    @objc private func toggleEditing() {
        guard state.mode == .manual else { return }
        setInteractionMode(interactionMode == .passthrough ? .editing : .passthrough)
        state.showManualMask()
        saveFrame()
        refreshMask()
        updateModeMenu()
    }

    @objc private func toggleManualVisibility() {
        guard state.mode == .manual else { return }
        state.toggleManualVisibility()
        if state.manualVisible { setInteractionMode(.passthrough) }
        refreshMask()
        updateModeMenu()
    }

    @objc private func selectAutomatic() {
        selectMode(.automatic)
        chooseAttachmentWindow()
    }
    @objc private func selectManual() { selectMode(.manual) }

    private func selectMode(_ mode: MaskMode) {
        guard state.mode != mode else { return }
        windowPicker?.close()
        saveFrame()
        setInteractionMode(.passthrough)
        clearAttachment()
        state.select(mode)
        panel.orderOut(nil)
        if mode == .manual {
            isChangingStyle = true
            panel.contentMinSize = MaskSettings.minimumSize
            restoreFrame()
            isChangingStyle = false
        }
        refreshMask()
        updateModeMenu()
    }

    private func updateModeMenu() {
        let automatic = state.mode == .automatic
        automaticItem.state = automatic ? .on : .off
        manualItem.state = automatic ? .off : .on
        visibilityItem.isHidden = automatic
        visibilityItem.title = state.manualVisible ? L10n.text("Hide Overlay") : L10n.text("Show Overlay")
        editItem.isHidden = automatic
        recenterItem.isHidden = automatic
        attachmentItem.isHidden = !automatic
        detachItem.isHidden = !automatic
        detachItem.isEnabled = attachment != nil
        mouseSideButtonItem.isHidden = !automatic
        mouseSideButtonItem.title = attachment?.application.isHidden == true ? L10n.text("Mouse Side Button: Restore") : L10n.text("Mouse Side Button: Hide")
        mouseSideButtonItem.isEnabled = state.canControlWindow(hasAttachment: attachment != nil) && controlTask == nil
        attachmentItem.title = attachment.map {
            L10n.format("Attached: %@ · %@ (click to change)", $0.application.localizedName ?? L10n.text("App"), $0.title)
        } ?? L10n.text("Choose a Window…")
    }

    @objc private func toggleAttachedApplication() {
        guard state.canControlWindow(hasAttachment: attachment != nil), let attachment, controlTask == nil else { return }
        // 在发送可能等待目标应用动画的请求前隐藏遮罩，避免留在原位置。
        invalidateRefresh()
        panel.orderOut(nil)
        controlTask = Task { [weak self] in
            do {
                try await attachment.toggleApplicationVisibility()
            } catch {
                guard !Task.isCancelled, let self, self.attachment === attachment else { return }
                let alert = NSAlert()
                alert.messageText = L10n.text("Unable to Hide / Restore the Attached App")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            guard !Task.isCancelled, let self, self.attachment === attachment else { return }
            self.controlTask = nil
            self.updateModeMenu()
            self.refreshMask()
        }
        updateModeMenu()
    }

    @objc private func opacityChanged(_ slider: NSSlider) {
        opacity = slider.doubleValue
        preferences.set(opacity, forKey: MaskSettings.opacityKey)
        applyAppearance()
    }

    private func installMouseMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard MouseSideButton(rawValue: event.buttonNumber) != nil else { return }
            Task { @MainActor [weak self] in self?.toggleAttachedApplication() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard MouseSideButton(rawValue: event.buttonNumber) != nil else { return event }
            guard let self, self.state.canControlWindow(hasAttachment: self.attachment != nil) else { return event }
            self.toggleAttachedApplication()
            return nil
        }
    }

    private func restoreFrame() {
        if let data = preferences.data(forKey: MaskSettings.frameKey),
           let saved = try? JSONDecoder().decode(SavedFrame.self, from: data), saved.isValid {
            panel.setFrame(panel.frameRect(forContentRect: saved.rect), display: false)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { return }
        } else {
            panel.setContentSize(MaskSettings.initialSize)
        }
        panel.center()
    }

    private func saveFrame() {
        guard !isChangingStyle, state.mode == .manual else { return }
        let saved = SavedFrame(panel.contentRect(forFrameRect: panel.frame))
        guard saved.isValid, let data = try? JSONEncoder().encode(saved) else { return }
        preferences.set(data, forKey: MaskSettings.frameKey)
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    func applicationWillTerminate(_ notification: Notification) {
        windowPicker?.close()
        clearAttachment()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        saveFrame()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func chooseAttachmentWindow() {
        guard state.mode == .automatic else { return }
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            showAttachmentError(L10n.text("Allow Accessibility access in System Settings, then select Automatic Mode or choose a window again. Restart the app if needed."))
            return
        }
        if let windowPicker {
            windowPicker.window?.makeKeyAndOrderFront(nil)
            return
        }
        let picker = WindowPickerController(onSelect: { [weak self] target in
            self?.attach(target)
        }, onClose: { [weak self] in
            self?.windowPicker = nil
        })
        windowPicker = picker
        picker.present()
    }

    private func attach(_ target: WindowAttachment) {
        attachmentTask?.cancel()
        attachmentTask = Task { [weak self] in
            do {
                try await target.bringToFront()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.showAttachmentError(error.localizedDescription)
                return
            }
            guard !Task.isCancelled, let self, self.state.mode == .automatic else { return }
            self.attachmentTask = nil
            self.clearAttachment()
            self.setInteractionMode(.passthrough)
            self.attachment = target
            self.updateModeMenu()
            self.panel.contentMinSize = .zero
            target.startObserving()
            self.attachmentTimer = Timer(timeInterval: MaskSettings.attachmentRefreshInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMask() }
            }
            if let timer = self.attachmentTimer { RunLoop.main.add(timer, forMode: .common) }
            self.refreshMask()
        }
    }

    @objc private func attachedWindowChanged(_ notification: Notification) {
        guard state.mode == .automatic, attachment != nil else { return }
        invalidateRefresh()
        if let name = notification.object as? String,
           name == kAXWindowMiniaturizedNotification || name == kAXUIElementDestroyedNotification || name == kAXFocusedWindowChangedNotification {
            panel.orderOut(nil)
        }
        refreshMask()
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        guard state.mode == .automatic, let attachment else { return }
        invalidateRefresh()
        if !attachment.isForeground { panel.orderOut(nil) }
        updateModeMenu()
        refreshMask()
    }

    private func invalidateRefresh() {
        refreshRevision = UUID()
    }

    private func refreshMask() {
        if state.mode == .manual {
            if state.manualVisible {
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else { panel.orderOut(nil) }
            return
        }
        guard let attachment, attachment.isForeground else {
            panel.orderOut(nil)
            return
        }
        // 控制请求优先；同一时刻最多一个状态读取，避免慢应用造成队列堆积。
        guard controlTask == nil, refreshTask == nil else { return }
        let revision = refreshRevision
        refreshTask = Task { [weak self] in
            let snapshot = await attachment.snapshot()
            guard !Task.isCancelled, let self,
                  self.state.mode == .automatic, self.attachment === attachment else { return }
            self.refreshTask = nil
            guard self.controlTask == nil else { return }
            guard self.refreshRevision == revision else {
                self.refreshMask()
                return
            }
            switch snapshot {
            case .visible(let rect):
                if self.panel.frame != rect { self.panel.setFrame(rect, display: true) }
                if !self.panel.isVisible { self.panel.orderFrontRegardless() }
            case .hidden, .unavailable:
                self.panel.orderOut(nil)
            }
        }
    }

    private func clearAttachment() {
        attachmentTask?.cancel()
        attachmentTask = nil
        controlTask?.cancel()
        controlTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        invalidateRefresh()
        attachmentTimer?.invalidate()
        attachmentTimer = nil
        attachment?.stopObserving()
        attachment = nil
    }

    @objc private func detachWindow() {
        guard state.mode == .automatic else { return }
        clearAttachment()
        panel.orderOut(nil)
        updateModeMenu()
    }

    private func showAttachmentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Unable to Attach to the Window")
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func recenter() {
        guard state.mode == .manual else { return }
        panel.center()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
