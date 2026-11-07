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
        if ProcessInfo.processInfo.environment["MURMR_SNAPSHOT_LOADING"] == "1" {  // show the startup bar
            state.engineReady = false
            state.loadStage = "whisper"
            state.loadProgress = 0.45
        }
        let actions = SettingsActions(preview: {}, restartEngine: {}, openConfig: {}, openLog: {}, openProject: {})

        let size = CGSize(width: 880, height: CGFloat(Double(ProcessInfo.processInfo.environment["MURMR_SNAPSHOT_HEIGHT"] ?? "") ?? 760))
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

    /// Development check: parse a dictionary file and write it back to a string. Never touches the file.
    static func dictCheck(path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("cannot read \(path)")
            return
        }
        let entries = DictFile.parse(text)
        let terms = entries.filter { if case .term = $0.kind { return true } else { return false } }.count
        let fixes = entries.filter { if case .fix = $0.kind { return true } else { return false } }.count
        let verbatim = entries.count - terms - fixes
        print("lines: \(entries.count)  terms: \(terms)  fixes: \(fixes)  comments/blank: \(verbatim)")
        print("round trip byte-identical: \(DictFile.serialize(entries) == text)")
    }

    /// Development check of the dictionary's write path, on a temporary file (never the real one).
    static func dictSelfTest() {
        let tmp = NSTemporaryDirectory() + "murmr-dict-selftest.txt"
        let original = "# note\n\nHuy\nboot -> push\n"
        try? original.write(toFile: tmp, atomically: true, encoding: .utf8)
        setenv("MURMR_DICT", tmp, 1)

        let store = DictionaryStore()
        store.load()
        var allOK = true
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(name)")
            if !condition { allOK = false }
        }
        check("loads one term and one fix", store.terms.count == 1 && store.fixes.count == 1)
        check("rejects an empty term", !store.addTerm("   "))
        check("rejects a duplicate (any case)", !store.addTerm("huy"))
        check("rejects an arrow inside a term", !store.addTerm("a -> b"))
        check("starts without a pending restart", !store.needsRestart)
        check("adds a term", store.addTerm("Kubernetes"))
        check("adds a fix", store.addFix(from: "push request", to: "pull request"))
        let afterAdd = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
        check("comments and order kept, new lines appended", afterAdd == original + "Kubernetes\npush request -> pull request\n")
        check("a restart is now pending", store.needsRestart)
        if let huy = store.terms.first(where: { $0.line == "Huy" }) { store.remove(huy) }
        let afterRemove = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
        check("removing deletes only that line", afterRemove == "# note\n\nboot -> push\nKubernetes\npush request -> pull request\n")
        try? FileManager.default.removeItem(atPath: tmp)
        print(allOK ? "ALL OK" : "FAILED")
    }
}
