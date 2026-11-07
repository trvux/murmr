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
        case .microphone: return "Micro"
        case .inputMonitoring: return "Giám sát đầu vào"
        case .accessibility: return "Trợ năng"
        }
    }

    /// Why it is needed, in the plainest true words (the engine listens only to modifier-key changes, listen-only).
    var why: String {
        switch self {
        case .microphone: return "Để nghe bạn nói. Chỉ thu âm khi bạn đang giữ phím."
        case .inputMonitoring: return "Để biết lúc phím ⌥ phải được giữ hoặc thả. App không đọc bạn gõ chữ gì."
        case .accessibility: return "Để dán chữ vào app bạn đang dùng."
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

enum PermissionState: Equatable {
    case granted
    case notAsked  // macOS has not asked yet: asking shows its own dialog
    case denied  // asked and refused (or switched off): only System Settings can change it now
}

@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    private var timer: Timer?
    private let preview: [PermissionKind: PermissionState]?

    /// `preview` fixes the states, for the offscreen snapshots; it never touches the real permissions.
    init(preview: [PermissionKind: PermissionState]? = nil) {
        self.preview = preview
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

    /// Shows macOS's own dialog for this permission (it appears once; afterwards use `openSettings`).
    func request(_ kind: PermissionKind) {
        guard preview == nil else { return }
        switch kind {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        refresh()
    }

    func openSettings(_ kind: PermissionKind) {
        guard preview == nil, let url = URL(string: kind.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The person grants these in another window, so look again every second while the welcome window is open.
    func startPolling() {
        guard preview == nil, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
