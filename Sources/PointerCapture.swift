import AppKit

/// Game-style pointer capture. Disassociating the mouse from the cursor stops
/// trackpad movement from dragging the pointer around — without it, hunting
/// sends the cursor skating across the screen, lighting up whatever it passes
/// over. The pointer parks in the middle of the screen and stays there.
///
/// Every acquire must be balanced by a release: leaving the system
/// disassociated (or the cursor hidden) after we exit would strand the user
/// with an unusable pointer.
final class PointerCapture {
    static let shared = PointerCapture()

    private(set) var isCaptured = false

    func capture() {
        guard !isCaptured else { return }
        isCaptured = true

        centerPointer()
        // 0 = mouse input no longer moves the cursor.
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
    }

    func release() {
        guard isCaptured else { return }
        isCaptured = false

        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }

    private func centerPointer() {
        guard let screen = NSScreen.main else { return }
        // CGWarpMouseCursorPosition uses global display coordinates, whose
        // origin is top-left — the opposite of NSScreen's bottom-left.
        let frame = screen.frame
        let center = CGPoint(x: frame.midX, y: frame.height - frame.midY)
        CGWarpMouseCursorPosition(center)
    }
}
