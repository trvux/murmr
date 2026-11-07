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
        state.languageHandler = { [weak self] language in
            self?.engine.sendLanguage(language)
            self?.buildMenus()  // the menu words are plain strings, so they are made again in the new language
        }
        panel = NotchPanel(state: state)
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)
        buildMenus()

        state.$phase
            .sink { [weak self] phase in
                if phase == .recording { self?.panel.reposition() }  // the screen under the pointer may have changed
                self?.updateIcon(for: phase)
            }
            .store(in: &cancellables)

        engine.start()

        // First launch: say hello and walk through the permissions. Any time after, from the menu.
        if !UserDefaults.standard.bool(forKey: "welcomeDone") {
            openWelcome()
        } else {
            // After an update macOS can have forgotten the permissions (a new build is a new app to it) and nothing would
            // say why dictation does nothing. Show the permissions step, once per build.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.guideIfPermissionsMissing() }
        }

        // Development hook: open Settings right away (used to smoke-test the window without clicking).
        if ProcessInfo.processInfo.environment["MURMR_OPEN_SETTINGS"] == "1" { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: menu bar

    private func buildMenus() {
        buildMenu()
        buildMainMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Murmr Stream", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(item(tr("Xem thử hiệu ứng notch"), #selector(runDemo)))
        menu.addItem(item(tr("Cài đặt…"), #selector(openSettings), key: ","))
        menu.addItem(item(tr("Khởi động lại engine"), #selector(restartEngine)))
        menu.addItem(item(tr("Hướng dẫn ban đầu…"), #selector(openWelcome)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Thoát"), #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    /// An accessory app has no menu bar of its own, so Cmd+V, Cmd+C and friends have no menu item to reach
    /// and text fields cannot paste. A main menu with a standard Edit menu fixes that; it is never shown.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Ẩn cửa sổ"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: tr("Sửa"))
        edit.addItem(withTitle: tr("Hoàn tác"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: tr("Làm lại"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Cắt"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Sao chép"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Dán"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Chọn tất cả"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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

    private func guideIfPermissionsMissing() {
        permissions.refresh()
        guard !permissions.allGranted else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard UserDefaults.standard.string(forKey: "permissionsGuideBuild") != build else { return }
        UserDefaults.standard.set(build, forKey: "permissionsGuideBuild")
        showWelcome(at: .permissions)
    }

    @objc private func openWelcome() { showWelcome(at: .hello) }

    private func showWelcome(at step: WelcomeView.Step) {
        welcomeWindow?.close()  // always start from the first step
        let view = WelcomeView(
            state: state, permissions: permissions, initialStep: step,
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
