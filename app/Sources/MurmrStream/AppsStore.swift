import AppKit
import Foundation

/// A way of addressing: how you refer to yourself, to the listener and to your own group. The id is what apps.txt refers
/// to. The app offers the mechanism and a few starting points; it never decides how anyone speaks (see style.go).
struct PronounProfile: Identifiable, Equatable, Hashable {
    static let keepID = "keep"

    var id: String
    var selfWord: String
    var you: String
    var we: String

    /// "tao / mày": what the notch and the menus show.
    var label: String { [selfWord, you].filter { !$0.isEmpty }.joined(separator: " / ") }
    /// "tao / mày / tụi tao": the whole set, for the list.
    var detail: String { [selfWord, you, we].filter { !$0.isEmpty }.joined(separator: " / ") }

    /// The apps.txt line that defines it. Trailing empty parts are left out.
    var line: String {
        var parts: [String] = [selfWord]
        if !we.isEmpty { parts.append(contentsOf: [you, we]) } else if !you.isEmpty { parts.append(you) }
        return "profile \(id) = " + parts.joined(separator: " / ")
    }

    /// Same rules as cleanWord in style.go: a short plain word, no quotes, slashes or line breaks.
    static func clean(_ raw: String) -> String {
        let banned: Set<Character> = ["\"", "'", "`", "“", "”", "/", "\\"]
        var kept = ""
        for ch in raw {
            if banned.contains(ch) { continue }
            kept.append(ch.isNewline || ch.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) ? " " : ch)
        }
        let words = kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.prefix(24))
    }

    /// "tao-may" from "tao", "mày": ASCII, so the file stays easy to type and read.
    static func slug(_ parts: [String]) -> String {
        let folded = parts.joined(separator: " ")
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
            .lowercased()
        let words = folded.split(whereSeparator: { !($0.isLetter && $0.isASCII) && !$0.isNumber }).map(String.init)
        return words.isEmpty ? "mine" : words.joined(separator: "-")
    }
}

/// A starting point offered in Settings, from `murmr pronouns`. Nothing is applied until the user adds it.
struct PronounPreset: Decodable, Identifiable, Equatable {
    let label: String
    let selfWord: String
    let you: String
    let we: String
    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, you, we
        case selfWord = "self"
    }
}

/// One line of ~/.config/murmr/apps.txt. Like the dictionary, the file is hand-written, so lines the app does not
/// understand are kept exactly as they were.
struct RuleEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case verbatim
        case profile(PronounProfile)  // "profile tao-may = tao / mày / tụi tao"
        case defaultRule(String)  // "default tao-may"
        case app(bundle: String, profile: String)  // "com.google.Chrome tao-may"
        case title(text: String, profile: String)  // "title:- Gmail keep"
    }

    let id = UUID()
    var kind: Kind
    var line: String
}

enum AppsFile {
    /// Overridden only by the development self-test, so it never touches the real file.
    nonisolated(unsafe) static var overridePath: String?

    static var path: String { overridePath ?? NSHomeDirectory() + "/.config/murmr/apps.txt" }

    /// The label of the profile the user set as default ("tao / mày"), or "" when pronouns are left alone. The notch
    /// preview and the demo show it, so they never show a way of speaking the user did not choose.
    static func defaultProfileLabel() -> String {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let entries = parse(text)
        var defaultID: String?
        var profiles: [String: PronounProfile] = [:]
        for entry in entries {
            switch entry.kind {
            case .defaultRule(let id): defaultID = id
            case .profile(let p): profiles[p.id] = p
            default: break
            }
        }
        guard let id = defaultID, let profile = profiles[id] else { return "" }
        return profile.label
    }

    static func parseProfile(_ line: String) -> PronounProfile? {
        let t = line.trimmingCharacters(in: .whitespaces)
        let fields = t.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !t.hasPrefix("#"), fields.count >= 2, fields[0] == "profile" else { return nil }
        let id = fields[1]
        guard id != PronounProfile.keepID, !id.contains("/"), !id.contains("=") else { return nil }
        var rest = String(t.dropFirst("profile".count)).trimmingCharacters(in: .whitespaces)
        rest = String(rest.dropFirst(id.count)).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("=") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
        let parts = rest.components(separatedBy: "/")
        let selfWord = PronounProfile.clean(parts[0])
        let you = parts.count > 1 ? PronounProfile.clean(parts[1]) : ""
        let we = parts.count > 2 ? PronounProfile.clean(parts[2]) : ""
        guard !selfWord.isEmpty || !you.isEmpty else { return nil }
        return PronounProfile(id: id, selfWord: selfWord, you: you, we: we)
    }

    /// Mirrors the engine's reader (ParsePronouns in style.go), so both always agree on what a line means: definitions
    /// first, so a rule may come before the profile it names; a rule naming nothing known is left as it was.
    static func parse(_ text: String) -> [RuleEntry] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var defined = Set<String>()
        var profileAt: [Int: PronounProfile] = [:]
        for (index, line) in lines.enumerated() {
            if let profile = parseProfile(line) {
                defined.insert(profile.id)
                profileAt[index] = profile
            }
        }
        func known(_ id: String) -> Bool { defined.contains(id) || id == PronounProfile.keepID || id == "neutral" || id == "casual" }

        var entries: [RuleEntry] = []
        for (index, line) in lines.enumerated() {
            if let profile = profileAt[index] {
                entries.append(RuleEntry(kind: .profile(profile), line: line))
                continue
            }
            let t = line.trimmingCharacters(in: .whitespaces)
            let fields = t.split(whereSeparator: \.isWhitespace).map(String.init)
            var kind: RuleEntry.Kind = .verbatim
            if !t.hasPrefix("#"), fields.count >= 2, fields[0] != "profile" {
                let id = fields[fields.count - 1]
                if fields[0] == "default" {
                    kind = .defaultRule(fields[1])
                } else if known(id) {
                    if t.hasPrefix("title:") {
                        let text = String(t.dropFirst("title:".count).dropLast(id.count)).trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty { kind = .title(text: text, profile: id) }
                    } else if fields.count == 2 {
                        kind = .app(bundle: fields[0], profile: id)
                    }
                }
            }
            entries.append(RuleEntry(kind: kind, line: line))
        }
        return entries
    }

    static func serialize(_ entries: [RuleEntry]) -> String {
        entries.isEmpty ? "" : entries.map(\.line).joined(separator: "\n") + "\n"
    }
}

struct InstalledApp: Identifiable, Hashable {
    let bundle: String
    let name: String
    let path: String
    var id: String { bundle }
}

enum AppScanner {
    /// Looks for .app bundles in the usual places. A few hundred apps take well under a second.
    static func scan() -> [InstalledApp] {
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var found: [String: InstalledApp] = [:]
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let path = folder + "/" + name
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { continue }
                let display = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? String(name.dropLast(4))
                found[id] = InstalledApp(bundle: id, name: display, path: path)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class AppsStore: ObservableObject {
    @Published private(set) var entries: [RuleEntry] = []
    @Published private(set) var installed: [InstalledApp] = []
    @Published private(set) var presets: [PronounPreset] = []
    @Published var message: String?

    /// Reads the rules file only (what the development self-test uses).
    func loadFile() {
        let text = (try? String(contentsOfFile: AppsFile.path, encoding: .utf8)) ?? ""
        entries = AppsFile.parse(text)
    }

    func load() {
        loadFile()
        Task {
            installed = await Task.detached { AppScanner.scan() }.value
            struct Presets: Decodable { let presets: [PronounPreset] }
            if let output = await EngineCLI.run(["pronouns"]),
               let decoded = try? JSONDecoder().decode(Presets.self, from: Data(output.out.utf8)) {
                presets = decoded.presets
            }
        }
    }

    // MARK: reading

    var profiles: [PronounProfile] {
        entries.compactMap { if case .profile(let p) = $0.kind { return p } else { return nil } }
    }

    /// "keep" (leave pronouns as recognised) when the user has not chosen a default.
    var defaultID: String {
        for entry in entries.reversed() {
            if case .defaultRule(let id) = entry.kind { return id }
        }
        return PronounProfile.keepID
    }

    /// What to call a profile id in a menu. Unknown ids read as "keep", which is also what the engine does.
    func name(for id: String) -> String {
        if let p = profiles.first(where: { $0.id == id }) { return p.label }
        if id == "casual" { return "tao / mày" }  // l10n-ok: the words themselves, not interface text
        return tr("Giữ nguyên")
    }

    func userProfileID(for bundle: String) -> String? {
        for entry in entries {
            if case .app(let b, let id) = entry.kind, b == bundle { return id }
        }
        return nil
    }

    func app(_ bundle: String) -> InstalledApp? { installed.first { $0.bundle == bundle } }

    /// Apps with a rule of the user's; the ones not installed (any more) still show, by their id.
    var listed: [InstalledApp] {
        var bundles = Set<String>()
        for entry in entries {
            if case .app(let b, _) = entry.kind { bundles.insert(b) }
        }
        return bundles
            .map { app($0) ?? InstalledApp(bundle: $0, name: $0, path: "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var notListed: [InstalledApp] {
        let shown = Set(listed.map(\.bundle))
        return installed.filter { !shown.contains($0.bundle) }
    }

    var titleRules: [RuleEntry] {
        entries.filter { if case .title = $0.kind { return true } else { return false } }
    }

    // MARK: changing (the engine re-reads the file at every dictation, so no restart is needed)

    /// Adds a profile and returns its id, or nil (with a message) when there is nothing to add.
    @discardableResult
    func addProfile(selfWord rawSelf: String, you rawYou: String, we rawWe: String) -> String? {
        let selfWord = PronounProfile.clean(rawSelf), you = PronounProfile.clean(rawYou), we = PronounProfile.clean(rawWe)
        guard !selfWord.isEmpty || !you.isEmpty else {
            message = tr("Nhập ít nhất một từ: bạn gọi bản thân, hoặc gọi người nghe.")
            return nil
        }
        if let same = profiles.first(where: { $0.selfWord == selfWord && $0.you == you && $0.we == we }) {
            message = tr("Đã có cách xưng hô này rồi.")
            return nil
        }
        message = nil
        let base = PronounProfile.slug([selfWord, you])
        var id = base, n = 2
        let taken = Set(profiles.map(\.id)).union([PronounProfile.keepID, "casual", "neutral", "default", "profile"])
        while taken.contains(id) { id = "\(base)-\(n)"; n += 1 }
        let profile = PronounProfile(id: id, selfWord: selfWord, you: you, we: we)
        entries.append(RuleEntry(kind: .profile(profile), line: profile.line))
        save()
        return id
    }

    /// Removes the profile and every rule that named it, so nothing is left pointing at nothing.
    func removeProfile(_ id: String) {
        message = nil
        entries.removeAll {
            switch $0.kind {
            case .profile(let p): return p.id == id
            case .defaultRule(let d): return d == id
            case .app(_, let p): return p == id
            case .title(_, let p): return p == id
            case .verbatim: return false
            }
        }
        save()
    }

    /// Puts `entry` where `matching` finds an existing line (so a file the user has arranged keeps its order), else at the
    /// end. `nil` removes that line.
    private func put(_ entry: RuleEntry?, replacing matching: (RuleEntry.Kind) -> Bool) {
        let index = entries.firstIndex { matching($0.kind) }
        entries.removeAll { matching($0.kind) }
        guard let entry else { return }
        entries.insert(entry, at: min(index ?? entries.count, entries.count))
    }

    func setDefault(_ id: String) {
        message = nil
        let entry: RuleEntry? = id == PronounProfile.keepID ? nil : RuleEntry(kind: .defaultRule(id), line: "default \(id)")
        put(entry) { if case .defaultRule = $0 { return true } else { return false } }
        save()
    }

    /// `nil` removes the user's rule for the app, so the default applies again.
    func setProfile(_ id: String?, for bundle: String) {
        message = nil
        let entry: RuleEntry? = id.map { RuleEntry(kind: .app(bundle: bundle, profile: $0), line: "\(bundle) \($0)") }
        put(entry) { if case .app(let b, _) = $0 { return b == bundle } else { return false } }
        save()
    }

    @discardableResult
    func addTitleRule(_ raw: String, profile id: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let taken = titleRules.contains {
            if case .title(let t, _) = $0.kind { return t.lowercased() == text.lowercased() } else { return false }
        }
        guard !taken else {
            message = tr("Đã có quy tắc cho tiêu đề này.")
            return false
        }
        message = nil
        entries.append(RuleEntry(kind: .title(text: text, profile: id), line: "title:\(text) \(id)"))
        save()
        return true
    }

    func remove(_ entry: RuleEntry) {
        message = nil
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func save() {
        do {
            let dir = (AppsFile.path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try AppsFile.serialize(entries).write(toFile: AppsFile.path, atomically: true, encoding: .utf8)
        } catch {
            message = tr("Không lưu được: %@", "\(error.localizedDescription)")
        }
    }
}
