import Testing
@testable import DesktopMask

@Test func startupDefaultsToAutomaticWithoutDisplayingMask() {
    let state = MaskModeState()
    #expect(state.mode == .automatic)
    #expect(!state.shouldDisplay(hasAttachment: false, availability: .visible))
    #expect(!state.shouldDisplay(hasAttachment: false, availability: .unavailable))
    #expect(!state.canControlWindow(hasAttachment: false))
}

@Test func manualModeDefaultsToVisibleWithoutAttachment() {
    var state = MaskModeState()
    state.select(.manual)
    #expect(state.mode == .manual)
    #expect(state.shouldDisplay(hasAttachment: false, availability: .unavailable))
    #expect(!state.canControlWindow(hasAttachment: true))
}

@Test func manualVisibilityDoesNotDependOnWindowAvailability() {
    var state = MaskModeState()
    state.select(.manual)
    state.toggleManualVisibility()
    #expect(!state.shouldDisplay(hasAttachment: false, availability: .visible))
    state.showManualMask()
    #expect(state.shouldDisplay(hasAttachment: false, availability: .hidden))
}

@Test func automaticModeRequiresAttachmentEvenWithVisibleWindowResult() {
    var state = MaskModeState()
    state.select(.automatic)
    #expect(!state.shouldDisplay(hasAttachment: false, availability: .visible))
    #expect(!state.canControlWindow(hasAttachment: false))
    #expect(state.shouldDisplay(hasAttachment: true, availability: .visible))
    #expect(state.canControlWindow(hasAttachment: true))
    #expect(!state.shouldDisplay(hasAttachment: true, availability: .hidden))
    #expect(!state.shouldDisplay(hasAttachment: true, availability: .unavailable))
}

@Test func manualControlsCannotOverrideAutomaticWindowState() {
    var state = MaskModeState()
    state.select(.automatic)
    state.toggleManualVisibility()
    state.showManualMask()
    #expect(!state.shouldDisplay(hasAttachment: true, availability: .hidden))
    #expect(!state.shouldDisplay(hasAttachment: false, availability: .visible))
}

@Test func returningToManualModeShowsMaskAndDisablesWindowControl() {
    var state = MaskModeState()
    state.select(.manual)
    state.toggleManualVisibility()
    state.select(.automatic)
    state.select(.manual)
    #expect(state.shouldDisplay(hasAttachment: false, availability: .unavailable))
    #expect(!state.canControlWindow(hasAttachment: true))
}
