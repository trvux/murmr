import AppKit
import Foundation

/// Runs the Go engine as a child process and turns its JSON-line events into UI state.
@MainActor
final class EngineController {
    private let state: AppState
    private var process: Process?
    private var stdinPipe: Pipe?  // kept open on purpose: the engine exits when this closes
    private var buffer = Data()
    private var lastStderr = ""
    private var quitting = false
    private var restarting = false
    private var failures = 0
    private var startedAt = Date()

    init(state: AppState) {
        self.state = state
        log("app started")
    }

    // MARK: log file

    /// ~/Library/Logs/Murmr Stream/engine.log. It records what the engine reports, but never the
    /// dictated text: the engine's "raw:" / "final:" lines and the text inside "done" events are dropped.
    private lazy var logHandle: FileHandle? = {
        let dir = NSHomeDirectory() + "/Library/Logs/Murmr Stream"
        let path = dir + "/engine.log"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(atPath: path)  // our own log, kept small
        }
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let h = FileHandle(forWritingAtPath: path)
        _ = try? h?.seekToEnd()
        return h
    }()

    static var logPath: String { NSHomeDirectory() + "/Library/Logs/Murmr Stream/engine.log" }

    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? logHandle?.write(contentsOf: Data("\(stamp) \(message)\n".utf8))
    }

    /// Where the models and the project live. The engine runs with this as its working directory.
    static var homeDir: String { homeDirPath }

    /// The same path without main-actor isolation, for background work (running `murmr hints`).
    nonisolated static var homeDirPath: String {
        ProcessInfo.processInfo.environment["MURMR_HOME"] ?? NSHomeDirectory() + "/Documents/murmr"
    }

    nonisolated static func locateEngine() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["MURMR_ENGINE"],
            Bundle.main.resourceURL?.appendingPathComponent("murmr").path,
            homeDirPath + "/murmr",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func enginePath() -> String? { Self.locateEngine() }

    func start() {
        guard let exe = enginePath() else {
            state.engineStatus = "Không tìm thấy engine murmr (build bằng go build -o murmr .)"
            state.setPhase(.error("Không tìm thấy engine"), resetAfter: 5)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.currentDirectoryURL = URL(fileURLWithPath: Self.homeDir)

        var env = ProcessInfo.processInfo.environment
        env.merge(EnvFile.load(NSHomeDirectory() + "/.config/murmr/env")) { _, new in new }
        env["MURMR_EVENTS"] = "1"
        // A GUI app does not inherit the shell PATH; whisper-server lives in Homebrew's bin.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env

        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp

        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            Task { @MainActor in self?.ingest(data) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.noteStderr(text) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.exited(code: proc.terminationStatus) }
        }

        log("starting engine \(exe) in \(Self.homeDir)")
        do {
            try p.run()
        } catch {
            log("could not start engine: \(error.localizedDescription)")
            state.engineStatus = "Không chạy được engine: \(error.localizedDescription)"
            return
        }
        process = p
        stdinPipe = inp
        startedAt = Date()
        buffer.removeAll()
        lastStderr = ""
        state.beginLoading()
    }

    func stop() {
        quitting = true
        stdinPipe?.fileHandleForWriting.closeFile()  // engine notices and shuts down cleanly
        process?.terminate()
    }

    func restart() {
        failures = 0
        if process == nil {
            start()
        } else {
            restarting = true
            process?.terminate()
        }
    }

    // MARK: output

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty else { continue }
            guard let ev = try? JSONDecoder().decode(EngineEvent.self, from: line) else {
                log("undecodable event line (\(line.count) bytes)")  // contents omitted: it may hold dictated text
                continue
            }
            if ev.e != "level" && ev.e != "partial" { log("event \(ev.e)" + (ev.stage.map { " \($0)" } ?? "")) }
            state.apply(ev)
        }
    }

    private func noteStderr(_ text: String) {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("  raw:") || line.hasPrefix("  final:") { continue }  // dictated text
            log("engine: " + line)
        }
        // Keep the last meaningful line, without the engine's "15:04:05 " timestamp.
        for raw in text.split(whereSeparator: \.isNewline).reversed() {
            var line = String(raw)
            if line.count > 9, Array(line)[2] == ":" { line = String(line.dropFirst(9)) }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lastStderr = line
                return
            }
        }
    }

    private func exited(code: Int32) {
        process = nil
        stdinPipe = nil
        log("engine exited with code \(code)")
        if quitting { return }
        if restarting {
            restarting = false
            start()
            return
        }
        state.failLoading()
        failures = Date().timeIntervalSince(startedAt) > 20 ? 1 : failures + 1
        let why = lastStderr.isEmpty ? "mã thoát \(code)" : lastStderr
        state.engineReady = false
        state.engineStatus = "Engine dừng: \(why)"
        state.setPhase(.error(String(why.prefix(70))), resetAfter: 6)
        if failures >= 4 {
            state.engineStatus += " (đã thử lại \(failures - 1) lần; chọn «Khởi động lại engine» sau khi sửa)"
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if !quitting, process == nil { start() }
        }
    }
}
