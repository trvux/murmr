import AppKit
import SwiftUI

/// Development tool: `MurmrStream --snapshot <dictionary|apps|ai|appearance|general|pills> <out.png> [dark]` draws the Settings
/// window offscreen into a PNG, so the design can be checked without opening a window or needing
/// the Screen Recording permission. Add `lang=en` or `lang=vi` to draw it in that language.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) {
        if arguments.first == "pills" {
            runPills(path: arguments.count > 1 ? arguments[1] : "pills.png", dark: arguments.contains("dark"))
            return
        }
        if let first = arguments.first, first.hasPrefix("welcome") {
            runWelcome(name: first, path: arguments.count > 1 ? arguments[1] : "welcome.png", dark: arguments.contains("dark"))
            return
        }
        if let sample = ProcessInfo.processInfo.environment["MURMR_SNAPSHOT_APPS"] { AppsFile.overridePath = sample }  // a sample rules file, so the page can be seen with data
        let tab = SettingsTab(rawValue: arguments.first ?? "") ?? .appearance
        let path = arguments.count > 1 ? arguments[1] : "snapshot.png"
        let dark = arguments.contains("dark")

        let state = AppState()
        state.engineReady = true
        state.status = Say("Sẵn sàng · giữ %@ để nói", state.holdKey.shown)
        if ProcessInfo.processInfo.environment["MURMR_SNAPSHOT_ENGINE"] == "stopped" {  // the failed state, for checking its look
            state.engineReady = false
            state.status = Say("Engine dừng: %@", tr("không tải được model giọng nói"))
        }
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

    /// The welcome window, one step per name (`welcome1` ... `welcome4`), with made-up permission and loading states.
    private static func runWelcome(name: String, path: String, dark: Bool) {
        let index = max(1, min(4, Int(name.dropFirst("welcome".count).prefix(1)) ?? 1)) - 1
        AppLocation.previewTemporary = name.hasSuffix("moved")
        let askKey = !name.hasSuffix("picked")  // `welcome1picked`: the first step after the person chose a key
        let step = WelcomeView.Step(rawValue: index) ?? .hello
        let state = AppState()
        if step == .prepare {
            state.loadStage = "models"
            state.loadProgress = 0.38
            state.loadDetail = Say("Đang tải model giọng nói · %@ / %@ MB", "218", "574")
        }
        if step == .ready { state.engineReady = true }
        let permissions = Permissions(preview: step == .permissions
            ? [.microphone: .granted, .inputMonitoring: .notAsked, .accessibility: .denied]
            : Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionState.granted) }))
        let size = CGSize(width: 560, height: 660)
        let host = NSHostingView(rootView: WelcomeView(state: state, permissions: permissions, initialStep: step, askKey: askKey).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let _ = Optional(host.cacheDisplay(in: host.bounds, to: rep)),
              let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed"); return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    /// The real notch pill in each state, stacked on a paper background (it is black, so it needs one).
    private static func runPills(path: String, dark: Bool) {
        struct Row {
            let label: String
            let phase: Phase
        }
        let rows = [
            Row(label: tr("đang nói"), phase: .recording),
            Row(label: tr("đang chép lời"), phase: .transcribing),
            Row(label: tr("xong (câu dài)"), phase: .done(tr("Chiều nay họp lúc ba giờ, nhớ gửi bản báo cáo trước nhé."))),
            Row(label: tr("lỗi"), phase: .error(tr("Không dán được, cần quyền Accessibility"))),
        ]
        let layout = NotchLayout()
        layout.hasNotch = true
        layout.notchWidth = 220
        layout.topHeight = 38

        let stack = VStack(spacing: Theme.Space.l) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let state = AppState()
                state.phase = row.phase
                state.style = "tôi / bạn"
                state.level = 0.5
                state.levels = (0..<AppState.historyCount).map { CGFloat(0.25 + 0.5 * abs(sin(Double($0) / 4))) }
                state.appIcon = NSApp.applicationIconImage  // our own icon: the snapshots are used in the README, which should not show other apps
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

    enum Brand { case icon, dmgBackground, banner, guide }

    /// The flock line at three levels on black, at the pill's real size (12 pt tall) and in the settings tile (24 pt),
    /// with the frame drawn, so a bird or a stroke cut off by the frame is visible.
    static func waveStrip(to path: String) {
        NSAppearance.current = NSAppearance(named: .aqua)
        let renderer = ImageRenderer(content: WaveStripArt())
        renderer.scale = 3
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

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
        case .guide:
            write(GuideArt(), scale: 2, to: path)
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
                print("\(p.id): \(list.count) models, error: \(settings.modelErrors[p.id]?.text ?? "none")")
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

        // --- apps.txt: the same sample the engine's own test uses (style_test.go)
        let sample = "# my rules\nprofile tao-may = tao / mày / tụi tao\nprofile toi-ban = tôi / bạn\ndefault toi-ban\n"
            + "com.mitchellh.ghostty tao-may\ncom.vng.zalo keep\ntitle:Team Chat tao-may\ncom.example.old casual\n"
            + "com.example.typo no-such-profile\nbogus line\n"
        let parsed = AppsFile.parse(sample)
        check("parses a profile", parsed[1].kind == .profile(PronounProfile(id: "tao-may", selfWord: "tao", you: "mày", we: "tụi tao")))
        check("a profile may leave out the 'we'", parsed[2].kind == .profile(PronounProfile(id: "toi-ban", selfWord: "tôi", you: "bạn", we: "")))
        check("parses the default", parsed[3].kind == .defaultRule("toi-ban"))
        check("parses an app rule", parsed[4].kind == .app(bundle: "com.mitchellh.ghostty", profile: "tao-may"))
        check("an explicit keep is a rule", parsed[5].kind == .app(bundle: "com.vng.zalo", profile: "keep"))
        check("parses a title rule with a space", parsed[6].kind == .title(text: "Team Chat", profile: "tao-may"))
        check("the old word casual still works", parsed[7].kind == .app(bundle: "com.example.old", profile: "casual"))
        check("a rule naming a profile nobody defined is kept as it was, not guessed at", parsed[8].kind == .verbatim)
        check("a line that is not a rule is kept as it was", parsed[9].kind == .verbatim && parsed[9].line == "bogus line")
        check("a comment is not a rule", parsed[0].kind == .verbatim)
        check("round trip is byte-identical", AppsFile.serialize(parsed) == sample)
        check("slug: ASCII ids from Vietnamese words", PronounProfile.slug(["tao", "mày"]) == "tao-may" && PronounProfile.slug(["đại", "ca"]) == "dai-ca")
        check("clean: no quotes, slashes or line breaks, at most 24 characters",
              PronounProfile.clean("ta\"; x/y\n") == "ta; xy" && PronounProfile.clean(String(repeating: "a", count: 60)).count == 24)

        let tmp = NSTemporaryDirectory() + "murmr-apps-selftest.txt"
        try? "# my rules\ncom.google.Chrome keep\n".write(toFile: tmp, atomically: true, encoding: .utf8)
        AppsFile.overridePath = tmp
        let store = AppsStore()
        store.loadFile()
        check("nothing is assumed: no profiles, default keep", store.profiles.isEmpty && store.defaultID == "keep")
        check("rejects an empty profile", store.addProfile(selfWord: " ", you: "", we: "x") == nil)
        let taoMay = store.addProfile(selfWord: "tao", you: "mày", we: "tụi tao")
        check("adds a profile and returns its id", taoMay == "tao-may" && store.profiles.count == 1)
        check("rejects the same profile twice", store.addProfile(selfWord: "tao", you: "mày", we: "tụi tao") == nil)
        let second = store.addProfile(selfWord: "tao", you: "mày", we: "")
        check("a different set with the same words gets its own id", second == "tao-may-2")
        store.setDefault("tao-may")
        check("sets the default", store.defaultID == "tao-may")
        store.setProfile("tao-may-2", for: "com.vng.zalo")
        store.setProfile("keep", for: "com.google.Chrome")
        check("adds and replaces app rules", store.userProfileID(for: "com.vng.zalo") == "tao-may-2" && store.userProfileID(for: "com.google.Chrome") == "keep")
        check("adds a title rule", store.addTitleRule("- Gmail", profile: "keep"))
        check("rejects a duplicate title rule (any case)", !store.addTitleRule("- gmail", profile: "tao-may"))
        store.removeProfile("tao-may-2")
        check("removing a profile removes the rules that named it", store.userProfileID(for: "com.vng.zalo") == nil && store.profiles.count == 1)
        store.setDefault("keep")
        store.setProfile(nil, for: "com.vng.zalo")
        let written = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
        check("only the touched lines changed, the comment is kept",
              written == "# my rules\ncom.google.Chrome keep\nprofile tao-may = tao / mày / tụi tao\ntitle:- Gmail keep\n")
        check("changing a rule keeps its place in the file", {
            store.setProfile("tao-may", for: "com.google.Chrome")
            let text = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
            return text.hasPrefix("# my rules\ncom.google.Chrome tao-may\nprofile tao-may")
        }())
        try? FileManager.default.removeItem(atPath: tmp)
        AppsFile.overridePath = nil

        // --- the app and the engine agree: what the store writes is what the engine resolves (`murmr pronouns --for`)
        let home = NSTemporaryDirectory() + "murmr-home-selftest"
        try? FileManager.default.removeItem(atPath: home)
        AppsFile.overridePath = home + "/.config/murmr/apps.txt"
        let written2 = AppsStore()
        written2.loadFile()
        _ = written2.addProfile(selfWord: "mình", you: "cậu", we: "tụi mình")
        _ = written2.addProfile(selfWord: "tôi", you: "bạn", we: "")
        written2.setDefault("toi-ban")
        written2.setProfile("minh-cau", for: "com.example.chat")
        _ = written2.addTitleRule("- Gmail", profile: "keep")
        func resolved(_ args: [String]) -> String {
            guard let out = EngineCLI.runSync(["pronouns"] + args, env: ["HOME": home]), out.status == 0 else { return "no engine" }
            return out.out
        }
        if resolved(["--for", "x"]) == "no engine" {
            print("info the engine was not found next to the app: the app-and-engine agreement check was skipped")
        } else {
            check("engine: an app rule written by the app", resolved(["--for", "com.example.chat"]).contains("\"label\":\"mình / cậu\""))
            check("engine: the default written by the app", resolved(["--for", "com.example.other"]).contains("\"label\":\"tôi / bạn\""))
            check("engine: a title rule beats the app rule", resolved(["--for", "com.example.chat", "--title", "Inbox - Gmail"]).contains("\"id\":\"keep\""))
        }
        try? FileManager.default.removeItem(atPath: home)
        AppsFile.overridePath = nil

        // --- the dictation key: what a person's presses become
        func run(_ inputs: [KeyInput]) -> [HoldKeyRecognizer.Outcome] {
            var r = HoldKeyRecognizer()
            return inputs.map { r.feed($0) }
        }
        func flagsEvent(_ code: Int, _ flags: UInt) -> KeyInput { KeyInput(kind: .flags, keyCode: code, flags: flags, characters: "") }
        func downEvent(_ code: Int, _ flags: UInt, _ chars: String = "") -> KeyInput { KeyInput(kind: .down, keyCode: code, flags: flags, characters: chars) }
        let ctrl: UInt = 0x40000, opt: UInt = 0x80000, cmd: UInt = 0x100000, shift: UInt = 0x20000
        let rightOption = run([flagsEvent(61, opt | 0x40), flagsEvent(61, 0)])
        check("right Option held and let go alone is a modifier key", rightOption.last == .commit(HoldKey(spec: "mod:61", label: "⌥ phải")))
        check("left Command alone is a modifier key, named left",
              run([flagsEvent(55, cmd | 0x8), flagsEvent(55, 0)]).last == .commit(HoldKey(spec: "mod:55", label: "⌘ trái")))
        check("fn alone", run([flagsEvent(63, 0x800000), flagsEvent(63, 0)]).last == .commit(HoldKey(spec: "mod:63", label: "fn")))
        check("Control then Option then Space is the combination, in ⌃⌥ order",
              run([flagsEvent(59, ctrl | 0x1), flagsEvent(58, ctrl | opt | 0x21), downEvent(49, ctrl | opt | 0x21, " ")]).last
              == .commit(HoldKey(spec: "combo:49:c0000", label: "⌃⌥ Space")))
        check("two modifiers let go without a key choose nothing",
              !run([flagsEvent(59, ctrl | 0x1), flagsEvent(58, ctrl | opt | 0x21), flagsEvent(58, ctrl | 0x1), flagsEvent(59, 0)]).contains { if case .commit = $0 { return true } else { return false } })
        check("a function key alone is allowed", run([downEvent(105, 0)]).last == .commit(HoldKey(spec: "combo:105:0", label: "F13")))
        check("a letter with Command and Shift", run([downEvent(16, cmd | shift, "y")]).last == .commit(HoldKey(spec: "combo:16:120000", label: "⇧⌘ Y")))
        check("a plain letter is refused (it would type)", { if case .reject = run([downEvent(0, 0, "a")]).last! { return true } else { return false } }())
        check("Command+C is refused (copy)", { if case .reject = run([downEvent(8, cmd, "c")]).last! { return true } else { return false } }())
        check("Esc cancels", run([downEvent(53, 0)]).last == .cancel)

        // what the app produces, the engine must accept (murmr holdkey <spec>)
        let specs = ["mod:61", "mod:55", "mod:63", "combo:49:c0000", "combo:105:0", "combo:16:120000"]
        let engineAgrees = specs.map { spec -> Bool? in
            EngineCLI.runSync(["holdkey", spec]).map { $0.status == 0 }
        }
        if engineAgrees.contains(where: { $0 == nil }) {
            print("info the engine was not found next to the app: the key-spec agreement check was skipped")
        } else {
            check("the engine accepts every key spec the app can produce", engineAgrees.allSatisfy { $0 == true })
            check("the engine refuses a spec that is not a key", EngineCLI.runSync(["holdkey", "mod:12"])?.status != 0)
        }
        check("no key note names another company's app",
              [HoldKey.standard, HoldKey(spec: "mod:55", label: "x"), HoldKey(spec: "mod:63", label: "x"), HoldKey(spec: "combo:49:c0000", label: "x")]
                .compactMap(\.note).allSatisfy { !$0.lowercased().contains("raycast") })
        check("choosing ignores the first moments, so the click that began it cannot be taken as the key", HoldKeyCapture.settle >= 0.2)
        // --- the interface languages
        check("a Vietnamese Mac gets Vietnamese, any other gets English",
              UILanguage.resolve(.auto, preferred: ["vi-VN", "en-US"]) == .vi
              && UILanguage.resolve(.auto, preferred: ["en-US", "vi-VN"]) == .en
              && UILanguage.resolve(.auto, preferred: ["fr-FR"]) == .en
              && UILanguage.resolve(.auto, preferred: []) == .en)
        check("a fixed choice stays fixed", UILanguage.resolve(.vi, preferred: ["en-US"]) == .vi && UILanguage.resolve(.en, preferred: ["vi"]) == .en)
        check("Vietnamese words are their own keys", L10n.tr("Lưu", in: .vi) == "Lưu")
        if L10n.tr("Lưu", in: .en) == "Lưu" {
            print("info the language files are not next to the app: the English lookup checks were skipped")
        } else {
            check("English comes from the language file", L10n.tr("Lưu", in: .en) == "Save")
            check("values go where %@ is", L10n.tr("Sẵn sàng · giữ %@ để nói", "Right ⌥", in: .en) == "Ready · hold Right ⌥ to talk")
            check("a modifier key is named in the language", {
                let saved = L10n.choice
                defer { L10n.choice = saved }
                L10n.choice = .en
                let english = HoldKey.standard.shown
                L10n.choice = .vi
                return english == "Right ⌥" && HoldKey.standard.shown == "⌥ phải"
            }())
            check("a combination reads the same in both", {
                let saved = L10n.choice
                defer { L10n.choice = saved }
                let combo = HoldKey(spec: "combo:49:c0000", label: "⌃⌥ Space")
                L10n.choice = .en
                let a = combo.shown
                L10n.choice = .vi
                return a == "⌃⌥ Space" && combo.shown == "⌃⌥ Space"
            }())
            check("a status keeps its words apart from its values and follows the language", {
                let saved = L10n.choice
                defer { L10n.choice = saved }
                let say = Say("Đang tải model giọng nói · %@ / %@ MB", "218", "574")
                L10n.choice = .en
                let a = say.text
                L10n.choice = .vi
                return a == "Downloading the speech model · 218 / 574 MB" && say.text == "Đang tải model giọng nói · 218 / 574 MB"
            }())
        }

        let watched = Permissions()
        watched.startPolling()
        watched.startPolling()  // a second window opens before the first one has closed
        watched.stopPolling()
        check("the live status keeps running while any window still shows it", watched.isWatching)
        watched.stopPolling()
        check("and stops when the last one closes", !watched.isWatching)
        check("a mounted installer or a temporary copy is not a place to keep permissions",
              AppLocation.isTemporary("/Volumes/Murmr Stream 0.1.0/Murmr Stream.app")
              && AppLocation.isTemporary("/private/var/folders/3f/T/AppTranslocation/84D7/d/Murmr Stream.app"))
        check("Applications and a build folder are fine",
              !AppLocation.isTemporary("/Applications/Murmr Stream.app") && !AppLocation.isTemporary("/Users/x/murmr/app/build/Murmr Stream.app"))
        check("macOS shows its dialog only while it has not decided",
              Permissions.dialogWillShow(.notAsked) && !Permissions.dialogWillShow(.denied) && !Permissions.dialogWillShow(.granted))
        check("every key has a note or none, never an empty one", [HoldKey.standard, HoldKey(spec: "mod:55", label: "⌘ trái"), HoldKey(spec: "combo:49:c0000", label: "x")].allSatisfy { $0.note?.isEmpty != true })

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
