import Foundation

/// The two hosted services the engine can use to clean up a transcript.
enum AIProvider: String, CaseIterable {
    case deepseek
    case claude

    var title: String { self == .deepseek ? "DeepSeek" : "Claude (Anthropic)" }
    var keyName: String { self == .deepseek ? "DEEPSEEK_API_KEY" : "ANTHROPIC_API_KEY" }
    var getKeyURL: String { self == .deepseek ? "https://platform.deepseek.com" : "https://console.anthropic.com" }
    var blurb: String {
        self == .deepseek ? "Rẻ và nhanh. Tắt chế độ suy luận để trả lời trong vài giây." : "Dọn văn cần trả lời nhanh, nên model nhỏ thường hợp nhất."
    }
    var defaultModel: String { self == .deepseek ? "deepseek-flash" : "claude-haiku-4-5-20251001" }
    var modelEnvName: String { self == .deepseek ? "DEEPSEEK_MODEL" : "ANTHROPIC_MODEL" }
    var modelDefaultsKey: String { self == .deepseek ? "deepseekModel" : "claudeModel" }
}

/// One model a provider says it serves (the engine's `murmr models` prints these as JSON).
struct ModelOption: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let deprecated: Bool
}

/// Which service cleans the text. `auto` is what the engine did before this setting existed: DeepSeek
/// if it has a key, else Claude.
enum CleanupChoice: String {
    case auto, deepseek, claude, none
}

enum KeyStatus: Equatable {
    case keychain(last4: String)
    case envFile  // present in ~/.config/murmr/env but not yet in the Keychain
    case missing
}

/// API keys and the cleanup provider. Keys live in the Keychain; the app hands them to the engine when it
/// starts. A key already in the old env file keeps working until the user moves it.
@MainActor
final class AISettings: ObservableObject {
    @Published var choice: CleanupChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "cleanupChoice") }
    }
    /// Use the other service when the chosen one fails. Off unless asked: it sends the text somewhere the user
    /// did not pick, so it is the user's call.
    @Published var fallback: Bool {
        didSet { UserDefaults.standard.set(fallback, forKey: "cleanupFallback"); onChanged() }
    }
    /// The model picked for each provider (the provider's default until the user picks another).
    @Published private(set) var selectedModels: [AIProvider: String] = [:]
    /// The lists the providers returned, newest first, once fetched with a key.
    @Published private(set) var models: [AIProvider: [ModelOption]] = [:]
    @Published private(set) var loadingModels: Set<AIProvider> = []
    @Published private(set) var modelErrors: [AIProvider: String] = [:]
    @Published private(set) var statuses: [AIProvider: KeyStatus] = [:]
    @Published private(set) var testing: AIProvider?
    @Published private(set) var testResults: [AIProvider: String] = [:]
    @Published var message: String?

    /// Called after anything the engine only reads at startup changes.
    var onChanged: () -> Void = {}

    init() {
        choice = CleanupChoice(rawValue: UserDefaults.standard.string(forKey: "cleanupChoice") ?? "") ?? .auto
        fallback = UserDefaults.standard.bool(forKey: "cleanupFallback")
        for provider in AIProvider.allCases { selectedModels[provider] = Self.storedModel(for: provider) }
        refresh()
    }

    func refresh() {
        for provider in AIProvider.allCases { statuses[provider] = Self.status(for: provider) }
    }

    /// What the segmented control shows: `auto` is displayed as the provider it would pick.
    var shownChoice: CleanupChoice {
        guard choice == .auto else { return choice }
        if statuses[.deepseek] != .missing { return .deepseek }
        if statuses[.claude] != .missing { return .claude }
        return .deepseek
    }

    // MARK: reading (usable off the main actor, by the engine launcher too)

    nonisolated static func envFileKey(for provider: AIProvider) -> String? {
        let value = EnvFile.load(NSHomeDirectory() + "/.config/murmr/env")[provider.keyName]
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated static func status(for provider: AIProvider) -> KeyStatus {
        if let key = KeychainStore.read(provider.keyName), !key.isEmpty { return .keychain(last4: String(key.suffix(4))) }
        return envFileKey(for: provider) != nil ? .envFile : .missing
    }

    nonisolated static func activeKey(for provider: AIProvider) -> String? {
        if let key = KeychainStore.read(provider.keyName), !key.isEmpty { return key }
        return envFileKey(for: provider)
    }

    /// What the engine needs in its environment: keys from the Keychain and the chosen provider and model.
    nonisolated static func engineEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for provider in AIProvider.allCases {
            if let key = KeychainStore.read(provider.keyName), !key.isEmpty { env[provider.keyName] = key }
        }
        let choice = UserDefaults.standard.string(forKey: "cleanupChoice") ?? CleanupChoice.auto.rawValue
        if choice != CleanupChoice.auto.rawValue { env["MURMR_CLEANUP"] = choice }
        if UserDefaults.standard.bool(forKey: "cleanupFallback") { env["MURMR_FALLBACK"] = "on" }
        for provider in AIProvider.allCases {
            let model = storedModel(for: provider)
            if model != provider.defaultModel { env[provider.modelEnvName] = model }
        }
        return env
    }

    nonisolated static func storedModel(for provider: AIProvider) -> String {
        let value = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? provider.defaultModel : value
    }

    /// Both services have a key, so a backup is possible.
    var canFallBack: Bool { AIProvider.allCases.allSatisfy { statuses[$0] != .missing } }

    func model(for provider: AIProvider) -> String { selectedModels[provider] ?? provider.defaultModel }

    // MARK: changing

    func setModel(_ id: String, for provider: AIProvider) {
        let clean = id.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != model(for: provider) else { return }
        selectedModels[provider] = clean
        UserDefaults.standard.set(clean, forKey: provider.modelDefaultsKey)
        testResults[provider] = nil
        onChanged()
    }

    /// Asks the provider which models this key can use (through the engine, so all networking stays in Go).
    func loadModels(_ provider: AIProvider) async {
        guard let key = Self.activeKey(for: provider), !loadingModels.contains(provider) else { return }
        loadingModels.insert(provider)
        modelErrors[provider] = nil
        defer { loadingModels.remove(provider) }
        guard let output = await EngineCLI.run(["models", provider.rawValue], env: [provider.keyName: key]) else {
            modelErrors[provider] = "Không tìm thấy engine."
            return
        }
        guard output.status == 0, let data = output.out.data(using: .utf8),
              let list = try? JSONDecoder().decode([ModelOption].self, from: data)
        else {
            modelErrors[provider] = "Chưa tải được danh sách model. Kiểm tra mạng hoặc thử lại."
            return
        }
        models[provider] = list
    }

    @discardableResult
    func save(_ raw: String, for provider: AIProvider) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard KeychainStore.write(key, account: provider.keyName) else {
            message = "Không lưu được khoá vào Keychain."
            return false
        }
        message = nil
        testResults[provider] = nil
        refresh()
        onChanged()
        Task { await loadModels(provider) }
        return true
    }

    func remove(for provider: AIProvider) {
        KeychainStore.delete(provider.keyName)
        models[provider] = nil
        modelErrors[provider] = nil
        testResults[provider] = nil
        refresh()
        onChanged()
    }

    func moveEnvKeyToKeychain(for provider: AIProvider) {
        if let key = Self.envFileKey(for: provider) { save(key, for: provider) }
    }

    /// Asks the engine itself to clean one short sentence with this provider (`murmr clean`), so the test
    /// uses exactly the code path dictation uses.
    func test(_ provider: AIProvider) async {
        testing = provider
        testResults[provider] = nil
        defer { testing = nil }
        guard let key = Self.activeKey(for: provider) else {
            testResults[provider] = "Chưa có khoá để thử."
            return
        }
        let env = [provider.keyName: key, "MURMR_CLEANUP": provider.rawValue, provider.modelEnvName: model(for: provider)]
        guard let output = await EngineCLI.run(["clean", "xin chào"], env: env) else {
            testResults[provider] = "Không tìm thấy engine."
            return
        }
        if output.status == 0 {
            testResults[provider] = "Khoá hoạt động."
        } else {
            let line = output.err.split(whereSeparator: \.isNewline).last(where: { $0.contains("murmr:") }) ?? output.err.split(whereSeparator: \.isNewline).last ?? "lỗi không rõ"
            testResults[provider] = "Không dùng được: " + String(line).replacingOccurrences(of: "murmr: ", with: "").prefix(140)
        }
    }
}
