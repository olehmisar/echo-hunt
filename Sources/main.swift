import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var view: GameView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        view = GameView(frame: frame)

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Echo Hunt"
        window.contentView = view
        window.delegate = self
        // Fullscreen isn't cosmetic here: AppKit routes indirect touch events
        // through window focus, so touches stop arriving the moment focus
        // leaves the window. Covering the screen keeps the pad ours.
        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)

        buildMenu()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // No capture at launch — we open on the main menu, which wants a
        // working pointer. Capture happens when play starts.
    }

    /// The fullscreen transition rebuilds the window's responder chain, so
    /// reclaim first responder or keystrokes and touches go nowhere.
    func windowDidEnterFullScreen(_ notification: Notification) {
        window.makeFirstResponder(view)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window.makeFirstResponder(view)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window.makeFirstResponder(view)
        restorePointerState()
    }

    /// Always hand the pointer back when we're not frontmost — a backgrounded
    /// Echo Hunt must never leave the rest of the system without a cursor.
    func windowDidResignKey(_ notification: Notification) { PointerCapture.shared.release() }
    func applicationDidResignActive(_ notification: Notification) { PointerCapture.shared.release() }
    func applicationWillTerminate(_ notification: Notification) { PointerCapture.shared.release() }

    /// Coming back from another app has to re-capture: resigning active always
    /// releases, so without this the cursor stays loose mid-game.
    func applicationDidBecomeActive(_ notification: Notification) { restorePointerState() }

    private func restorePointerState() {
        guard let view else { return }
        if view.wantsPointerCaptured {
            PointerCapture.shared.capture()
        } else {
            PointerCapture.shared.release()
        }
    }

    private func buildMenu() {
        let quit = NSMenuItem(
            title: "Quit Echo Hunt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenu = NSMenu()
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let bar = NSMenu()
        bar.addItem(appItem)
        NSApp.mainMenu = bar
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
