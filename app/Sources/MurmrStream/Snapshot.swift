import AppKit
import SwiftUI

/// Development tool: `MurmrStream --snapshot <appearance|general> <out.png> [dark]` draws the Settings
/// window offscreen into a PNG, so the design can be checked without opening a window or needing
/// the Screen Recording permission.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) {
        if arguments.first == "pills" {
            runPills(path: arguments.count > 1 ? arguments[1] : "pills.png", dark: arguments.contains("dark"))
            return
        }
        let tab = SettingsTab(rawValue: arguments.first ?? "") ?? .appearance
        let path = arguments.count > 1 ? arguments[1] : "snapshot.png"
        let dark = arguments.contains("dark")

        let state = AppState()
        state.engineReady = true
        state.engineStatus = "Sẵn sàng · giữ Option phải để nói"
        let actions = SettingsActions(preview: {}, restartEngine: {}, openConfig: {}, openLog: {}, openProject: {})

        let size = CGSize(width: 880, height: 760)
        let host = NSHostingView(rootView: SettingsView(state: state, actions: actions, tab: tab)
            .frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host

        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))  // let onAppear fill the demo signal and SwiftUI settle
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("snapshot failed: no bitmap")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("snapshot failed: no png")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(Int(size.width * 2))x\(Int(size.height * 2)) px)")
    }

    /// The real notch pill in each state, stacked on a paper background (it is black, so it needs one).
    private static func runPills(path: String, dark: Bool) {
        struct Row {
            let label: String
            let phase: Phase
        }
        let rows = [
            Row(label: "đang nói", phase: .recording),
            Row(label: "đang chép lời", phase: .transcribing),
            Row(label: "xong (câu dài)", phase: .done("Hôm nay tao push code lên main xong rồi review giúp tao nha")),
            Row(label: "lỗi", phase: .error("Không dán được, cần quyền Accessibility")),
        ]
        let layout = NotchLayout()
        layout.hasNotch = true
        layout.notchWidth = 220
        layout.topHeight = 38

        let stack = VStack(spacing: Theme.Space.l) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let state = AppState()
                state.phase = row.phase
                state.style = "casual"
                state.level = 0.5
                state.levels = (0..<AppState.historyCount).map { CGFloat(0.25 + 0.5 * abs(sin(Double($0) / 4))) }
                state.appIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
                return VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(row.label).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                    NotchView(state: state, layout: layout).frame(width: 560, height: 96)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 620)
        .background(Theme.paper)

        let host = NSHostingView(rootView: stack)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
