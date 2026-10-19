import AppKit

private enum PickerLayout {
    static let size = NSSize(width: 600, height: 180)
    static let inset: CGFloat = 20
    static let spacing: CGFloat = 16
}

@MainActor
final class WindowPickerController: NSWindowController, NSWindowDelegate {
    private let picker = NSPopUpButton()
    private let message = NSTextField(labelWithString: "正在读取窗口列表…")
    private let confirm = NSButton(title: "附着", target: nil, action: nil)
    private let refresh = NSButton(title: "刷新列表", target: nil, action: nil)
    private var windows: [WindowAttachment] = []
    private var loadTask: Task<Void, Never>?
    private let onSelect: (WindowAttachment) -> Void
    private let onClose: () -> Void

    init(onSelect: @escaping (WindowAttachment) -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: PickerLayout.size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "选择附着窗口"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        confirm.target = self
        confirm.action = #selector(selectWindow)
        confirm.keyEquivalent = "\r"
        refresh.target = self
        refresh.action = #selector(loadWindows)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSelection))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [refresh, cancel, confirm])
        buttons.spacing = PickerLayout.spacing
        let stack = NSStackView(views: [message, picker, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PickerLayout.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: PickerLayout.inset),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -PickerLayout.inset),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: PickerLayout.inset),
                picker.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadWindows()
    }

    @objc private func loadWindows() {
        loadTask?.cancel()
        message.stringValue = "正在读取窗口列表…（可以取消）"
        confirm.isEnabled = false
        picker.isEnabled = false
        refresh.isEnabled = false
        loadTask = Task { [weak self] in
            let windows = await WindowAttachment.availableWindows()
            guard !Task.isCancelled, let self else { return }
            self.windows = windows
            self.picker.removeAllItems()
            for window in windows {
                self.picker.menu?.addItem(NSMenuItem(
                    title: "\(window.application.localizedName ?? "应用") · \(window.title)", action: nil, keyEquivalent: ""
                ))
            }
            if !windows.isEmpty { self.picker.selectItem(at: windows.startIndex) }
            self.confirm.isEnabled = !windows.isEmpty
            self.picker.isEnabled = !windows.isEmpty
            self.refresh.isEnabled = true
            self.message.stringValue = windows.isEmpty
                ? "暂无可用窗口，请打开目标应用后刷新。"
                : "请选择目标窗口，附着后会激活该窗口。"
        }
    }

    @objc private func selectWindow() {
        guard windows.indices.contains(picker.indexOfSelectedItem) else { return }
        let target = windows[picker.indexOfSelectedItem]
        close()
        onSelect(target)
    }

    @objc private func cancelSelection() { close() }

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        loadTask = nil
        onClose()
    }
}
