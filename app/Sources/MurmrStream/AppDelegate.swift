import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = AppState()
    private lazy var engine = EngineController(state: state)
    private var panel: NotchPanel!
    private var statusItem: NSStatusItem!
    private var statusLine = NSMenuItem()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private let permissions = Permissions()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["notchEars": true, "waveStyle": WaveStyle.flock.rawValue])
        state.restartHandler = { [weak self] in self?.engine.restart() }
        state.holdKeyHandler = { [weak self] spec in self?.engine.sendHoldKey(spec) }
        state.keyCaptureHandler = { [weak self] on in self?.engine.setKeyCapturing(on) }
        panel = NotchPanel(state: state)
        panel.orderFrontRegardless()
        buildMenu()
        buildMainMenu()

        state.$phase
            .sink { [weak self] phase in
                if phase == .recording { self?.panel.reposition() }  // the screen under the pointer may have changed
                self?.updateIcon(for: phase)
            }
            .store(in: &cancellables)

        engine.start()

        // First launch: say hello and walk through the permissions. Any time after, from the menu.
        if !UserDefaults.standard.bool(forKey: "welcomeDone") { openWelcome() }

        // Development hook: open Settings right away (used to smoke-test the window without clicking).
        if ProcessInfo.processInfo.environment["MURMR_OPEN_SETTINGS"] == "1" { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: menu bar

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)

        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Murmr Stream", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(item("Xem thử hiệu ứng notch", #selector(runDemo)))
        menu.addItem(item("Cài đặt…", #selector(openSettings), key: ","))
        menu.addItem(item("Khởi động lại engine", #selector(restartEngine)))
        menu.addItem(item("Hướng dẫn ban đầu…", #selector(openWelcome)))
        menu.addItem(.separator())
        menu.addItem(item("Thoát", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    /// An accessory app has no menu bar of its own, so Cmd+V, Cmd+C and friends have no menu item to reach
    /// and text fields cannot paste. A main menu with a standard Edit menu fixes that; it is never shown.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ẩn cửa sổ", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Sửa")
        edit.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func updateIcon(for phase: Phase) {
        let name = phase == .recording ? "waveform.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Murmr Stream")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusLine.title = state.engineStatus
    }

    // MARK: actions

    @objc private func runDemo() {
        panel.reposition()
        state.runDemo()
    }

    @objc private func restartEngine() { engine.restart() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                preview: { [weak self] in self?.runDemo() },
                restartEngine: { [weak self] in self?.engine.restart() },
                openConfig: { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.config/murmr")) },
                openLog: { NSWorkspace.shared.open(URL(fileURLWithPath: EngineController.logPath)) },
                openProject: { NSWorkspace.shared.open(URL(fileURLWithPath: EngineController.homeDir)) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state, actions: actions)))
            window.title = "Murmr Stream"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true  // the content runs up under the traffic lights
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 880, height: 760))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)  // an accessory app has no Dock icon to click
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openWelcome() {
        welcomeWindow?.close()  // always start from the first step
        let view = WelcomeView(
            state: state, permissions: permissions,
            openAISettings: { [weak self] in self?.openSettings() },
            finish: { [weak self] in
                UserDefaults.standard.set(true, forKey: "welcomeDone")
                self?.welcomeWindow?.close()
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Murmr Stream"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
