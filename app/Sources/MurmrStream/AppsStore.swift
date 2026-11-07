import AppKit
import Foundation

/// How pronouns are written when dictating into an app (see style.go in the engine).
enum PronounStyle: String, CaseIterable {
    case casual  // tao / mày: talking to a computer or an AI
    case neutral  // lịch sự: talking to people, the recognizer's pronouns are left alone

    var title: String { self == .casual ? "tao/mày" : "lịch sự" }
}

/// One line of ~/.config/murmr/apps.txt. Like the dictionary, the file is hand-written, so lines the app does
/// not understand are kept exactly as they were.
struct RuleEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case verbatim
        case app(bundle: String, style: PronounStyle)  // "com.google.Chrome casual"
        case title(text: String, style: PronounStyle)  // "title:- Gmail neutral"
    }

    let id = UUID()
    var kind: Kind
    var line: String
}

enum AppsFile {
    /// Overridden only by the development self-test, so it never touches the real file.
    nonisolated(unsafe) static var overridePath: String?

    static var path: String { overridePath ?? NSHomeDirectory() + "/.config/murmr/apps.txt" }

    /// Mirrors the engine's reader (styleFor in style.go), so both always agree on what a line means.
    static func parse(_ text: String) -> [RuleEntry] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            let fields = t.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !t.hasPrefix("#"), fields.count >= 2, let style = PronounStyle(rawValue: fields[fields.count - 1]) else {
                return RuleEntry(kind: .verbatim, line: line)
            }
            if t.hasPrefix("title:") {
                let text = String(t.dropFirst("title:".count).dropLast(style.rawValue.count)).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? RuleEntry(kind: .verbatim, line: line) : RuleEntry(kind: .title(text: text, style: style), line: line)
            }
            return fields.count == 2
                ? RuleEntry(kind: .app(bundle: fields[0], style: style), line: line)
                : RuleEntry(kind: .verbatim, line: line)
        }
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

/// The engine's built-in rules, from `murmr styles`.
struct StyleDefaults: Decodable, Equatable {
    struct TitleRule: Decodable, Equatable, Identifiable {
        let contains: String
        let style: String
        var id: String { contains }
    }

    var casual: [String]
    var titleRules: [TitleRule]
}

@MainActor
final class AppsStore: ObservableObject {
    @Published private(set) var entries: [RuleEntry] = []
    @Published private(set) var installed: [InstalledApp] = []
    @Published private(set) var defaults = StyleDefaults(casual: [], titleRules: [])
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
            if let output = await EngineCLI.run(["styles"]),
               let decoded = try? JSONDecoder().decode(StyleDefaults.self, from: Data(output.out.utf8)) {
                defaults = decoded
            }
        }
    }

    // MARK: reading

    func userStyle(for bundle: String) -> PronounStyle? {
        for entry in entries {
            if case .app(let b, let style) = entry.kind, b == bundle { return style }
        }
        return nil
    }

    func defaultStyle(for bundle: String) -> PronounStyle { defaults.casual.contains(bundle) ? .casual : .neutral }

    func effectiveStyle(for bundle: String) -> PronounStyle { userStyle(for: bundle) ?? defaultStyle(for: bundle) }

    func app(_ bundle: String) -> InstalledApp? { installed.first { $0.bundle == bundle } }

    /// Apps worth a row: those with a built-in rule or one of the user's, and installed (or user-ruled).
    var listed: [InstalledApp] {
        var bundles = Set(defaults.casual)
        for entry in entries {
            if case .app(let b, _) = entry.kind { bundles.insert(b) }
        }
        return bundles
            .compactMap { b in app(b) ?? (userStyle(for: b) != nil ? InstalledApp(bundle: b, name: b, path: "") : nil) }
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

    /// `nil` removes the user's rule, so the built-in default applies again.
    func setStyle(_ style: PronounStyle?, for bundle: String) {
        message = nil
        entries.removeAll { if case .app(let b, _) = $0.kind { return b == bundle } else { return false } }
        if let style {
            entries.append(RuleEntry(kind: .app(bundle: bundle, style: style), line: "\(bundle) \(style.rawValue)"))
        }
        save()
    }

    @discardableResult
    func addTitleRule(_ raw: String, style: PronounStyle) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let taken = titleRules.contains {
            if case .title(let t, _) = $0.kind { return t.lowercased() == text.lowercased() } else { return false }
        }
        guard !taken else {
            message = "Đã có quy tắc cho «\(text)»."
            return false
        }
        message = nil
        entries.append(RuleEntry(kind: .title(text: text, style: style), line: "title:\(text) \(style.rawValue)"))
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
            message = "Không lưu được: \(error.localizedDescription)"
        }
    }
}
