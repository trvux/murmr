import Foundation

/// One line of ~/.config/murmr/dictionary.txt. The file is hand-written (comments, blank lines,
/// sections), so the app keeps every line it does not understand exactly as it was and only adds or
/// removes the entries the user touches.
struct DictEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case verbatim  // a comment or a blank line, kept untouched
        case term(String)  // "Kubernetes": a spelling to prefer
        case fix(from: String, to: String)  // "boot lên -> push lên": a hard replacement
    }

    let id = UUID()
    var kind: Kind
    var line: String  // the original text of the line, written back as is
}

enum DictFile {
    static var path: String {
        ProcessInfo.processInfo.environment["MURMR_DICT"] ?? NSHomeDirectory() + "/.config/murmr/dictionary.txt"
    }

    static func parse(_ text: String) -> [DictEntry] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }  // the newline that ends the file is not a blank entry
        return lines.map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return DictEntry(kind: .verbatim, line: line) }
            if let arrow = t.range(of: "->") {
                let from = t[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let to = t[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                if !from.isEmpty, !to.isEmpty { return DictEntry(kind: .fix(from: from, to: to), line: line) }
                return DictEntry(kind: .verbatim, line: line)  // malformed: leave it alone
            }
            return DictEntry(kind: .term(t), line: line)
        }
    }

    static func serialize(_ entries: [DictEntry]) -> String {
        entries.isEmpty ? "" : entries.map(\.line).joined(separator: "\n") + "\n"
    }
}

/// What the Dictionary page edits. Changes are written to disk at once, but the engine only reads the
/// file at startup, so `needsRestart` stays true until the user applies them.
@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictEntry] = []
    @Published private(set) var needsRestart = false
    @Published var message: String?
    /// Called after the file was written, so the page can ask for an engine restart.
    var onSaved: () -> Void = {}

    var terms: [DictEntry] { entries.filter { if case .term = $0.kind { return true } else { return false } } }
    var fixes: [DictEntry] { entries.filter { if case .fix = $0.kind { return true } else { return false } } }

    func load() {
        let text = (try? String(contentsOfFile: DictFile.path, encoding: .utf8)) ?? ""
        entries = DictFile.parse(text)
    }

    func addTerm(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard !t.contains("->") else {
            message = "Từ khoá không được chứa ký hiệu ->. Dùng mục Sửa cứng cho cặp nghe sai và đúng."
            return false
        }
        guard !terms.contains(where: { if case .term(let x) = $0.kind { return x.lowercased() == t.lowercased() } else { return false } }) else {
            message = "\(t) đã có trong từ điển."
            return false
        }
        append(DictEntry(kind: .term(t), line: t))
        return true
    }

    func addFix(from rawFrom: String, to rawTo: String) -> Bool {
        let from = rawFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = rawTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return false }
        guard !from.contains("->"), !to.contains("->") else {
            message = "Không dùng ký hiệu -> trong nội dung."
            return false
        }
        append(DictEntry(kind: .fix(from: from, to: to), line: "\(from) -> \(to)"))
        return true
    }

    func remove(_ entry: DictEntry) {
        message = nil
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func markApplied() { needsRestart = false }

    private func append(_ entry: DictEntry) {
        message = nil
        entries.append(entry)
        save()
    }

    private func save() {
        do {
            let dir = (DictFile.path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try DictFile.serialize(entries).write(toFile: DictFile.path, atomically: true, encoding: .utf8)
            needsRestart = true
            onSaved()
        } catch {
            message = "Không lưu được từ điển: \(error.localizedDescription)"
        }
    }
}

/// A "heard => meant" pair learned from past dictations (`murmr hints`).
struct Hint: Identifiable, Decodable, Equatable {
    let from: String
    let to: String
    let count: Int
    let active: Bool
    var id: String { from }
}

/// Asks the Go engine for what it has learned, and tells it to forget a pair. Both are the engine's own
/// subcommands, so the learning logic lives in one place.
@MainActor
final class HintsStore: ObservableObject {
    @Published private(set) var hints: [Hint] = []
    @Published private(set) var loaded = false

    func refresh() {
        Task {
            let output = await EngineCLI.run(["hints"])
            if let data = output?.out.data(using: .utf8), let decoded = try? JSONDecoder().decode([Hint].self, from: data) {
                hints = decoded
            }
            loaded = true
        }
    }

    func forget(_ hint: Hint) {
        Task {
            _ = await EngineCLI.run(["forget", hint.from])
            refresh()
        }
    }
}
