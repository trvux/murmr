import AppKit

// An "accessory" app: no Dock icon and no main window, just the menu bar item and the notch pill.
// run() blocks, so `delegate` stays alive for the whole session (NSApplication only holds it weakly).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    if let i = CommandLine.arguments.firstIndex(of: "--app-icon"), CommandLine.arguments.count > i + 1 {
        Snapshot.renderBrand(.icon, to: CommandLine.arguments[i + 1])
        return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--brand-banner"), CommandLine.arguments.count > i + 1 {
        Snapshot.renderBrand(.banner, to: CommandLine.arguments[i + 1], dark: CommandLine.arguments.contains("dark"))
        return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--dmg-background"), CommandLine.arguments.count > i + 1 {
        Snapshot.renderBrand(.dmgBackground, to: CommandLine.arguments[i + 1])
        return
    }
    if CommandLine.arguments.contains("--models-check") {
        Snapshot.modelsCheck()
        return
    }
    if CommandLine.arguments.contains("--keychain-selftest") {
        Snapshot.keychainSelfTest()
        return
    }
    if CommandLine.arguments.contains("--settings-selftest") {
        Snapshot.settingsSelfTest()
        return
    }
    if CommandLine.arguments.contains("--dict-selftest") {
        Snapshot.dictSelfTest()
        return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--dict-check") {
        Snapshot.dictCheck(path: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : DictFile.path)
        return
    }
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
        Snapshot.run(arguments: Array(CommandLine.arguments.dropFirst(i + 1)))
        return
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
