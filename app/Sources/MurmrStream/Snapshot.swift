import AppKit
import SwiftUI

/// Development tool: `MurmrStream --snapshot <dictionary|apps|ai|appearance|general|pills> <out.png> [dark]` draws the Settings
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
        if ProcessInfo.processInfo.environment["MURMR_SNAPSHOT_PENDING"] == "1" { state.needsRestart = true }
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

    enum Brand { case icon, dmgBackground, banner }

    /// Draws brand artwork to a PNG at 1x, and at 2x next to it (`name@2x.png`) for the disk-image background.
    /// Always in the light appearance, whatever the Mac is set to.
    static func renderBrand(_ brand: Brand, to path: String, dark: Bool = false) {
        NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)
        func write<V: View>(_ view: V, scale: CGFloat, to file: String) {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = scale
            renderer.isOpaque = false
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("render failed: \(file)")
                return
            }
            try? png.write(to: URL(fileURLWithPath: file))
            print("wrote \(file) (\(rep.pixelsWide)x\(rep.pixelsHigh) px)")
        }
        switch brand {
        case .icon:
            write(AppIconArt(), scale: 1, to: path)
        case .banner:
            write(BannerArt(), scale: 2, to: path)
        case .dmgBackground:
            write(DmgBackgroundArt(), scale: 1, to: path)
            write(DmgBackgroundArt(), scale: 2, to: path.replacingOccurrences(of: ".png", with: "@2x.png"))
        }
    }

    /// Development check: fetch each provider's model list with the stored key and print ids (never the key).
    static func modelsCheck() {
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let settings = AISettings()
            for p in settings.providers where settings.isReady(p) && p.needsKey {
                await settings.loadModels(p)
                let list = settings.models[p.id] ?? []
                print("\(p.id): \(list.count) models, error: \(settings.modelErrors[p.id] ?? "none")")
                for m in list.prefix(8) { print("  \(m.deprecated ? "old" : "new") \(m.id)  (\(m.name))") }
            }
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    }

    /// Development check of the Keychain claims made in PRIVACY.md, on a throwaway item that is deleted at the end.
    static func keychainSelfTest() {
        let service = "dev.trvux.murmr-stream.selftest", account = "SELFTEST_KEY"
        var allOK = true
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(name)")
            if !condition { allOK = false }
        }
        KeychainStore.delete(account, service: service)
        check("writes", KeychainStore.write("sk-test-123", account: account, service: service))
        check("reads back", KeychainStore.read(account, service: service) == "sk-test-123")
        check("updates in place", KeychainStore.write("sk-test-456", account: account, service: service)
            && KeychainStore.read(account, service: service) == "sk-test-456")

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,  // also match a synced copy, if there were one
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let attrs = item as? [String: Any] ?? [:]
        print("info raw attributes: synchronizable=\(attrs[kSecAttrSynchronizable as String] ?? "nil")")
        check("attributes readable", status == errSecSuccess)
        let sync = attrs[kSecAttrSynchronizable as String]
        check("not synchronizable (not synced through iCloud)", sync == nil || (sync as? NSNumber)?.boolValue == false)

        check("deletes", KeychainStore.delete(account, service: service) && KeychainStore.read(account, service: service) == nil)
        print(allOK ? "ALL OK" : "SOME CHECKS FAILED")
    }

    /// Development check of the Apps rules file, the Keychain wrapper and the provider catalog, on temporary data
    /// only: a temp rules file and a throw-away Keychain service. It prints whether keys exist, never the keys.
    static func settingsSelfTest() {
        var allOK = true
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(name)")
            if !condition { allOK = false }
        }

        // --- apps.txt: the same sample the engine's own test uses
        let sample = "com.vng.zalo casual\ntitle:Team Chat neutral\nbogus line\n# note casual\n"
        let parsed = AppsFile.parse(sample)
        check("parses an app rule", parsed[0].kind == .app(bundle: "com.vng.zalo", style: .casual))
        check("parses a title rule with a space", parsed[1].kind == .title(text: "Team Chat", style: .neutral))
        check("a line that is not a rule is kept as it was", parsed[2].kind == .verbatim && parsed[2].line == "bogus line")
        check("a comment ending in a style word is not a rule", parsed[3].kind == .verbatim)
        check("round trip is byte-identical", AppsFile.serialize(parsed) == sample)

        let tmp = NSTemporaryDirectory() + "murmr-apps-selftest.txt"
        try? "# my rules\ncom.google.Chrome casual\n".write(toFile: tmp, atomically: true, encoding: .utf8)
        AppsFile.overridePath = tmp
        let store = AppsStore()
        store.loadFile()
        check("reads the user's rule", store.userStyle(for: "com.google.Chrome") == .casual)
        store.setStyle(.neutral, for: "com.google.Chrome")
        store.setStyle(.casual, for: "com.vng.zalo")
        check("replaces and adds rules", store.userStyle(for: "com.google.Chrome") == .neutral && store.userStyle(for: "com.vng.zalo") == .casual)
        check("adds a title rule", store.addTitleRule("- Gmail", style: .neutral))
        check("rejects a duplicate title rule (any case)", !store.addTitleRule("- gmail", style: .casual))
        store.setStyle(nil, for: "com.vng.zalo")
        let written = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
        check("removing a rule deletes only that line, comment kept",
              written == "# my rules\ncom.google.Chrome neutral\ntitle:- Gmail neutral\n")
        try? FileManager.default.removeItem(atPath: tmp)
        AppsFile.overridePath = nil

        // --- Keychain wrapper on a throw-away service
        let service = "dev.trvux.murmr-stream.selftest"
        KeychainStore.delete("probe", service: service)
        check("nothing stored before the test", KeychainStore.read("probe", service: service) == nil)
        check("writes a secret", KeychainStore.write("sk-test-123456", account: "probe", service: service))
        check("reads it back", KeychainStore.read("probe", service: service) == "sk-test-123456")
        check("overwrites it", KeychainStore.write("sk-test-654321", account: "probe", service: service)
              && KeychainStore.read("probe", service: service) == "sk-test-654321")
        check("deletes it", KeychainStore.delete("probe", service: service) && KeychainStore.read("probe", service: service) == nil)
        check("deleting a missing item is not an error", KeychainStore.delete("probe", service: service))

        // --- key status (existence only)
        let t0 = Date()
        let env = AISettings.engineEnvironment()
        print("info engine environment: \(env.count) variables in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        let catalog = AISettings.loadCatalog()
        check("the engine lists its providers", catalog.count >= 2 && catalog.contains { $0.id == "deepseek" } && catalog.contains { $0.id == "claude" })
        check("a provider with a fixed address cannot be edited, ollama can",
              catalog.first { $0.id == "deepseek" }?.editableURL == false && catalog.first { $0.id == "ollama" }?.editableURL == true)
        check("ollama needs no key and is local", catalog.first { $0.id == "ollama" }.map { !$0.needsKey && !$0.takesKey && $0.local } ?? false)
        for p in catalog where p.takesKey {
            print("info \(p.keyEnv): \(AISettings.status(for: p))".replacingOccurrences(of: "last4: ", with: "last4: …"))
        }
        print(allOK ? "ALL OK" : "FAILED")
    }
}
