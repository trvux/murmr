import Foundation

/// Runs the Go engine's own subcommands (`hints`, `styles`, `clean`) and returns what they print. The
/// logic stays in the engine; the app only asks.
enum EngineCLI {
    struct Output {
        let out: String
        let err: String
        let status: Int32
    }

    /// `env` is added on top of the app's environment, for the keys a command needs.
    static func run(_ args: [String], env: [String: String] = [:]) async -> Output? {
        await Task.detached { () -> Output? in
            guard let exe = EngineController.locateEngine() else { return nil }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.currentDirectoryURL = URL(fileURLWithPath: EngineController.homeDirPath)
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            p.environment = environment
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch { return nil }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Output(out: String(decoding: outData, as: UTF8.self),
                          err: String(decoding: errData, as: UTF8.self),
                          status: p.terminationStatus)
        }.value
    }
}
