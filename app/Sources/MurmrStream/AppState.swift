import AppKit
import SwiftUI

/// What the notch is currently showing.
enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    case cleaning
    case done(String)
    case notice(String)
    case error(String)
}

/// One JSON line from the Go engine (see events.go for the full list). Fields the UI does
/// not use are simply not declared; unknown keys (such as live-caption ones) are ignored.
struct EngineEvent: Decodable {
    let e: String
    var v: Double?
    var bundle: String?
    var style: String?
    var stage: String?
    var text: String?
    var reason: String?
    var msg: String?
}

@MainActor
final class AppState: ObservableObject {
    static let historyCount = 44  // samples kept for the waveform, ~2 s at 20 per second

    @Published var phase: Phase = .idle
    @Published var level: CGFloat = 0  // smoothed microphone level, 0...1
    @Published var levels: [CGFloat] = Array(repeating: 0, count: AppState.historyCount)
    @Published var appIcon: NSImage?  // icon of the app the text will be pasted into
    @Published var style = ""  // "casual", "neutral" or "" while unknown
    @Published var engineStatus = "Đang khởi động…"
    @Published var engineReady = false
    /// Startup progress: which step the engine reports, and an estimated 0...1 for the bar. The bar is an
    /// estimate (the engine does not know how long Whisper takes to load), so it creeps during that step.
    @Published var loadStage = ""  // "" when not loading
    @Published var loadProgress: Double = 0

    var isLoading: Bool { !loadStage.isEmpty }

    private var loadTask: Task<Void, Never>?
    private var stageStartedAt = Date()
    private var resetTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?

    func apply(_ ev: EngineEvent) {
        switch ev.e {
        case "loading":
            loadStage = ev.stage ?? ""
            stageStartedAt = Date()
            engineStatus = Self.loadText(loadStage) + "…"
        case "ready":
            engineReady = true
            engineStatus = "Sẵn sàng · giữ Option phải để nói"
            setPhase(.idle)
            finishLoading()
        case "recording":
            demoTask?.cancel()
            clearLevels()
            appIcon = nil
            style = ""
            setPhase(.recording)
        case "app":
            if let bundle = ev.bundle { resolveIcon(bundle) }
            style = ev.style ?? ""
        case "level":
            push(CGFloat(ev.v ?? 0))
        case "processing":
            setPhase(ev.stage == "cleanup" ? .cleaning : .transcribing)
        case "done":
            setPhase(.done(ev.text ?? ""), resetAfter: 2.2)
        case "skipped":
            setPhase(.notice(ev.reason == "silent" ? "Giữ phím hơi ngắn" : "Không nghe thấy gì"), resetAfter: 1.3)
        case "error":
            setPhase(.error(ev.msg ?? "Có lỗi"), resetAfter: 4)
        default:
            break
        }
    }

    static func loadText(_ stage: String) -> String {
        switch stage {
        case "starting": return "Đang khởi động"
        case "dictionary": return "Đang nạp từ điển"
        case "whisper": return "Đang nạp model Whisper"
        case "audio": return "Đang mở micro"
        case "keys": return "Đang bật phím nói"
        case "ready": return "Sẵn sàng"
        default: return ""
        }
    }

    /// The engine process has just been (re)started.
    func beginLoading() {
        engineReady = false
        loadStage = "starting"
        loadProgress = 0
        stageStartedAt = Date()
        engineStatus = Self.loadText("starting") + "…"
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.loadProgress += (self.loadTarget() - self.loadProgress) * 0.12  // ease toward the target
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// The engine stopped before it was ready.
    func failLoading() {
        loadTask?.cancel()
        loadStage = ""
        loadProgress = 0
    }

    private func finishLoading() {
        loadStage = "ready"  // the bar runs to the end and says "Sẵn sàng" for a moment
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, self.loadStage == "ready" else { return }
            self.loadTask?.cancel()
            self.loadStage = ""
            self.loadProgress = 0
        }
    }

    private func loadTarget() -> Double {
        switch loadStage {
        case "starting": return 0.04
        case "dictionary": return 0.08
        case "whisper":  // about 8 s on a cold start: creep from 10% to 88% over that time, never past it
            return min(0.88, 0.10 + 0.78 * Date().timeIntervalSince(stageStartedAt) / 8)
        case "audio": return 0.92
        case "keys": return 0.96
        default: return loadStage.isEmpty ? 0 : 1
        }
    }

    /// Changes the phase, and optionally returns to idle after a delay.
    func setPhase(_ p: Phase, resetAfter: Double? = nil) {
        resetTask?.cancel()
        phase = p
        if p == .idle { clearLevels() }
        guard let delay = resetAfter else { return }
        resetTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { phase = .idle }
        }
    }

    private func clearLevels() {
        level = 0
        levels = Array(repeating: 0, count: Self.historyCount)
    }

    /// Fast attack, slow release: the wave jumps up with the voice and falls back gently.
    func push(_ raw: CGFloat) {
        let v = min(1, max(0, raw))
        level = v > level ? level * 0.35 + v * 0.65 : level * 0.8 + v * 0.2
        levels.removeFirst()
        levels.append(level)
    }

    private func resolveIcon(_ bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            appIcon = nil
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Plays a fake dictation so the animation can be previewed without the engine
    /// (menu: "Xem thử hiệu ứng notch").
    func runDemo() {
        demoTask?.cancel()
        resetTask?.cancel()
        demoTask = Task {
            resolveIcon("com.mitchellh.ghostty")
            style = "casual"
            clearLevels()
            setPhase(.recording)
            for i in 0..<56 {
                if Task.isCancelled { return }
                let envelope = sin(Double(i) / 56 * .pi)
                push(CGFloat(max(0.05, envelope * Double.random(in: 0.25...0.95))))
                try? await Task.sleep(for: .milliseconds(50))
            }
            setPhase(.transcribing)
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled { return }
            setPhase(.cleaning)
            try? await Task.sleep(for: .seconds(0.9))
            if Task.isCancelled { return }
            setPhase(.done("Hôm nay tao push code lên main xong rồi review giúp tao nha"), resetAfter: 2.4)
        }
    }
}
