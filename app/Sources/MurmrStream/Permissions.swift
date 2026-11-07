import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid

/// The three things macOS makes a person allow before dictation can work. They are granted to the app, and the engine
/// (started by the app) uses them.
enum PermissionKind: CaseIterable, Identifiable {
    case microphone, inputMonitoring, accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: return tr("Micro")
        case .inputMonitoring: return tr("Giám sát đầu vào")
        case .accessibility: return tr("Trợ năng")
        }
    }

    /// Why it is needed, in the plainest true words (the engine listens only to modifier-key changes, listen-only).
    var why: String {
        switch self {
        case .microphone: return tr("Để nghe bạn nói. Chỉ thu âm khi bạn đang giữ phím.")
        case .inputMonitoring: return tr("Để biết lúc bạn giữ hoặc thả phím nói. App chỉ so với phím bạn đã chọn, không ghi lại và không đọc bạn gõ gì.")
        case .accessibility: return tr("Để dán chữ vào app bạn đang dùng.")
        }
    }

    var symbol: String {
        switch self {
        case .microphone: return "mic"
        case .inputMonitoring: return "keyboard"
        case .accessibility: return "hand.point.up.left"
        }
    }

    /// The page in System Settings where this permission is switched on.
    var settingsURL: String {
        switch self {
        case .microphone: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .inputMonitoring: return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

/// Where the app is running from. macOS ties a permission to one app in one place: from a mounted installer or a
/// temporary copy it makes for a downloaded app (AppTranslocation), what the person grants does not stick.
enum AppLocation {
    static func isTemporary(_ path: String) -> Bool { path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") }
    nonisolated(unsafe) static var previewTemporary = false  // the offscreen snapshots show the notice
    static var isTemporary: Bool { previewTemporary || isTemporary(Bundle.main.bundlePath) }
}

enum PermissionState: Equatable {
    case granted
    case notAsked  // macOS has not asked yet: asking shows its own dialog
    case denied  // asked and refused (or switched off): only System Settings can change it now
}

@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    /// Permissions the person was sent to System Settings for: the welcome window then explains what to do if the switch
    /// is already on and the app still says "not granted" (an old entry, from another build of the app).
    @Published private(set) var needHelp: Set<PermissionKind> = []
    private var timer: Timer?
    private var watchers = 0  // windows that need the live status; the timer runs while there is one
    private var napBlock: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var askingInTurn = false
    private let preview: [PermissionKind: PermissionState]?

    /// `preview` fixes the states, for the offscreen snapshots; it never touches the real permissions.
    init(preview: [PermissionKind: PermissionState]? = nil) {
        self.preview = preview
        needHelp = Set((preview ?? [:]).filter { $0.value == .denied }.keys)  // previews show the hint a stuck row gets
        refresh()
    }

    var allGranted: Bool { PermissionKind.allCases.allSatisfy { states[$0] == .granted } }

    func state(_ kind: PermissionKind) -> PermissionState { states[kind] ?? .notAsked }

    func refresh() {
        if let preview { states = preview; return }
        var now: [PermissionKind: PermissionState] = [:]
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: now[.microphone] = .granted
        case .notDetermined: now[.microphone] = .notAsked
        default: now[.microphone] = .denied
        }
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: now[.inputMonitoring] = .granted
        case kIOHIDAccessTypeUnknown: now[.inputMonitoring] = .notAsked
        default: now[.inputMonitoring] = .denied
        }
        now[.accessibility] = AXIsProcessTrusted() ? .granted : .notAsked  // macOS does not say "denied" here
        if now != states { states = now }
    }

    /// macOS asks only while it has not decided; afterwards asking does nothing at all.
    static func dialogWillShow(_ state: PermissionState) -> Bool { state == .notAsked }

    /// Shows macOS's own dialog for this permission. When macOS has already decided, a dialog would never come (the
    /// button would look dead), so the person goes straight to the page in System Settings. `fallbackToSettings`: if the
    /// dialog does not appear either (this app is still in front a moment later), open that page too.
    func request(_ kind: PermissionKind, fallbackToSettings: Bool = true) {
        guard preview == nil else { return }
        refresh()
        if kind != .accessibility && !Self.dialogWillShow(state(kind)) {
            if fallbackToSettings { openSettings(kind) }
            return
        }
        switch kind {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        refresh()
        guard fallbackToSettings, kind != .accessibility else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.refresh()
            // a dialog from macOS takes the focus; still in front and still not granted means none came
            if self.state(kind) != .granted && NSApp.isActive { self.openSettings(kind) }
        }
    }

    /// The microphone dialog comes by itself, so do the same for the others: ask for each missing permission in turn,
    /// waiting for the answer before the next dialog. Only what macOS has not decided yet (a decided one would be silent).
    func askInTurn() {
        guard preview == nil, !askingInTurn else { return }
        askingInTurn = true
        Task { @MainActor in
            defer { askingInTurn = false }
            for kind in PermissionKind.allCases {
                refresh()
                guard state(kind) == .notAsked else { continue }
                request(kind, fallbackToSettings: false)
                var wasAway = false
                for _ in 0..<240 {  // up to two minutes for the person to answer
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    refresh()
                    if state(kind) != .notAsked { break }
                    if !NSApp.isActive { wasAway = true } else if wasAway { break }  // the dialog was dismissed
                }
            }
        }
    }

    func openSettings(_ kind: PermissionKind) {
        guard preview == nil, let url = URL(string: kind.settingsURL) else { return }
        needHelp.insert(kind)
        NSWorkspace.shared.open(url)
    }

    /// The person grants these in another window, so keep looking while a window that shows them is open. Looking happens
    /// on a timer, when the app comes to the front, and when macOS says the accessibility list changed; and App Nap is
    /// held off, because it stretches a one-second timer of an app that is in the background to many seconds.
    var isWatching: Bool { watchers > 0 }

    func startPolling() {
        guard preview == nil else { return }
        watchers += 1
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        napBlock = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Showing which permissions are granted")
        let again: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                try? await Task.sleep(nanoseconds: 600_000_000)  // the list is written a moment after the notice
                self?.refresh()
            }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: again),
            DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main, using: again),
        ]
    }

    func stopPolling() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        if let napBlock { ProcessInfo.processInfo.endActivity(napBlock) }
        napBlock = nil
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
        }
        observers = []
    }
}
