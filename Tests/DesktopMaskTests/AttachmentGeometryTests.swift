import Foundation
import Testing
@testable import DesktopMask

@Test func convertsTopLeftCoordinatesToAppKit() {
    let rect = AttachmentGeometry.appKitRect(
        position: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 360), primaryScreenTop: 1080
    )
    #expect(rect == CGRect(x: 120, y: 640, width: 640, height: 360))
}

@Test func supportsScreensLeftOfAndAbovePrimaryScreen() {
    let rect = AttachmentGeometry.appKitRect(
        position: CGPoint(x: -900, y: -700), size: CGSize(width: 800, height: 600), primaryScreenTop: 1080
    )
    #expect(rect == CGRect(x: -900, y: 1180, width: 800, height: 600))
}

@Test func rejectsInvalidWindowGeometry() {
    #expect(AttachmentGeometry.appKitRect(
        position: .zero, size: .zero, primaryScreenTop: 1080
    ) == nil)
    #expect(AttachmentGeometry.appKitRect(
        position: CGPoint(x: CGFloat.nan, y: 80), size: CGSize(width: 640, height: 360), primaryScreenTop: 1080
    ) == nil)
}
