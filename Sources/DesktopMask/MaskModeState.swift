enum MaskMode {
    case automatic
    case manual
}

enum AttachedWindowAvailability {
    case visible
    case hidden
    case unavailable
}

struct MaskModeState {
    private(set) var mode: MaskMode = .automatic
    private(set) var manualVisible = true

    mutating func select(_ mode: MaskMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        if mode == .manual { manualVisible = true }
    }

    mutating func toggleManualVisibility() {
        guard mode == .manual else { return }
        manualVisible.toggle()
    }

    mutating func showManualMask() {
        guard mode == .manual else { return }
        manualVisible = true
    }

    func canControlWindow(hasAttachment: Bool) -> Bool {
        mode == .automatic && hasAttachment
    }

    func shouldDisplay(hasAttachment: Bool, availability: AttachedWindowAvailability) -> Bool {
        switch mode {
        case .manual: manualVisible
        case .automatic: hasAttachment && availability == .visible
        }
    }
}
