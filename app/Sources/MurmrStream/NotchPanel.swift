import AppKit
import SwiftUI

/// Notch geometry of the screen the pill is shown on, measured from the macOS APIs
/// (on this machine: 220 x 38 pt).
@MainActor
final class NotchLayout: ObservableObject {
    @Published var hasNotch = false
    @Published var notchWidth: CGFloat = 0
    @Published var topHeight: CGFloat = 32

    func update(for screen: NSScreen) {
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            topHeight = inset
            notchWidth = screen.frame.width - left.width - right.width
        } else {
            hasNotch = false  // external display: the pill floats just below the top edge
            topHeight = 32
            notchWidth = 0
        }
    }
}

/// A transparent, click-through panel pinned to the top centre of the screen. It never
/// takes focus, so the app you are dictating into stays active. The SwiftUI view inside
/// draws (and animates) the actual pill; the panel itself never changes size.
@MainActor
final class NotchPanel: NSPanel {
    static let size = CGSize(width: 560, height: 160)
    let layout = NotchLayout()

    init(state: AppState) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        level = .statusBar  // above the menu bar, so the pill can cover the notch strip
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: NotchView(state: state, layout: layout))
        reposition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Re-centres on the screen under the mouse pointer. NSScreen.main asks which window has
    /// focus, which touches other apps' windows; it is the suspected (not confirmed) cause of
    /// a Screen Recording request macOS raised for this app, so it is avoided here.
    func reposition() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.screens.first else { return }
        layout.update(for: screen)
        let f = screen.frame
        setFrame(
            NSRect(x: f.midX - Self.size.width / 2, y: f.maxY - Self.size.height,
                   width: Self.size.width, height: Self.size.height),
            display: true
        )
    }
}
