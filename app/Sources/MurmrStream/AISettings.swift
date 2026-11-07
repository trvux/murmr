import Foundation

/// One cleanup service, as the engine describes it (`murmr providers`). The app has no list of its own.
struct ProviderInfo: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let baseURL: String
    let keyEnv: String  // "" when the service takes no key
    let baseURLEnv: String  // set when the user may change the address
    let defaultModel: String  // "" until verified: the user picks from the provider's list
    let keyURL: String
    let needsKey: Bool
    let local: Bool  // runs on this machine
    let tested: Bool  // checked by the author with a real key

    var takesKey: Bool { !keyEnv.isEmpty }
    var editableURL: Bool { !baseURLEnv.isEmpty }
}

/// One model a provider says it serves (the engine's `murmr models` prints these as JSON).
struct ModelOption: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let deprecated: Bool
}

enum KeyStatus: Equatable {
    case keychain(last4: String)
    case envFile  // present in ~/.config/murmr/env but not yet in the Keychain
    case missing
}

/// Providers, keys, models and the backup choice. The engine owns what exists; this stores what the user chose
/// (UserDefaults) and the keys (Keychain), and hands both to the engine as environment when it starts.
@MainActor
final class AISettings: ObservableObject {
    nonisolated static let auto = "auto"
    nonisolated static let off = "none"

    @Published private(set) var providers: [ProviderInfo]
    /// "auto" (first service with a key), "none", or a provider id.
    @Published var choice: String {
        didSet { UserDefaults.standard.set(choice, forKey: "cleanupChoice") }
    }
    /// A second service to try when the chosen one fails; "" is off. Off unless asked: it sends the text somewhere
    /// the user did not pick as the main service.
    @Published var backup: String {
        didSet { UserDefaults.standard.set(backup, forKey: "cleanupBackup"); onChanged() }
    }
    @Published private(set) var statuses: [String: KeyStatus] = [:]
    @Published private(set) var selectedModels: [String: String] = [:]
    @Published private(set) var baseURLs: [String: String] = [:]
    /// The lists the providers returned, newest first, once fetched.
    @Published private(set) var models: [String: [ModelOption]] = [:]
    @Published private(set) var loadingModels: Set<String> = []
    @Published private(set) var modelErrors: [String: String] = [:]
    @Published private(set) var testing: String?
    @Published private(set) var testResults: [String: String] = [:]
    @Published var message: String?

    /// Called after anything the engine only reads at startup changes.
    var onChanged: () -> Void = {}

    init() {
        providers = Self.loadCatalog()
        choice = UserDefaults.standard.string(forKey: "cleanupChoice") ?? Self.auto
        backup = UserDefaults.standard.string(forKey: "cleanupBackup") ?? ""
        for p in providers {
            selectedModels[p.id] = Self.storedModel(for: p.id)
            baseURLs[p.id] = Self.storedBaseURL(for: p.id)
        }
        refresh()
    }

    func provider(_ id: String) -> ProviderInfo? { providers.first { $0.id == id } }

    func refresh() {
        for p in providers where p.takesKey { statuses[p.id] = Self.status(for: p) }
    }

    // MARK: what is usable

    func status(_ p: ProviderInfo) -> KeyStatus { statuses[p.id] ?? .missing }

    func baseURL(_ p: ProviderInfo) -> String { baseURLs[p.id].flatMap { $0.isEmpty ? nil : $0 } ?? p.baseURL }

    func model(for p: ProviderInfo) -> String { selectedModels[p.id].flatMap { $0.isEmpty ? nil : $0 } ?? p.defaultModel }

    /// Can be called now: it has a key if it needs one, and an address.
    func isReady(_ p: ProviderInfo) -> Bool {
        (!p.needsKey || status(p) != .missing) && !baseURL(p).isEmpty
    }

    /// What the service menu shows: "auto" is displayed as the provider it would pick.
    var shownChoice: String {
        guard choice == Self.auto else { return choice }
        return providers.first { $0.needsKey && status($0) != .missing }?.id ?? providers.first?.id ?? Self.off
    }

    /// Services that could back up `primary`: ready, and not the main one.
    func backupCandidates(excluding primary: String) -> [ProviderInfo] {
        providers.filter { $0.id != primary && isReady($0) }
    }

    // MARK: reading (usable off the main actor, by the engine launcher too)

    nonisolated static func loadCatalog() -> [ProviderInfo] {
        let decoder = JSONDecoder()
        if let out = EngineCLI.runSync(["providers"]), out.status == 0, let data = out.out.data(using: .utf8),
           let list = try? decoder.decode([ProviderInfo].self, from: data), !list.isEmpty {
            UserDefaults.standard.set(data, forKey: "providerCatalog")  // so the page still draws if the engine is missing
            return list
        }
        if let data = UserDefaults.standard.data(forKey: "providerCatalog"),
           let list = try? decoder.decode([ProviderInfo].self, from: data) { return list }
        return []
    }

    nonisolated static func envFileKey(for p: ProviderInfo) -> String? {
        let value = EnvFile.load(NSHomeDirectory() + "/.config/murmr/env")[p.keyEnv]
        return (value?.isEmpty == false) ? value : nil
    }

    nonisolated static func status(for p: ProviderInfo) -> KeyStatus {
        if let key = KeychainStore.read(p.keyEnv), !key.isEmpty { return .keychain(last4: String(key.suffix(4))) }
        return envFileKey(for: p) != nil ? .envFile : .missing
    }

    nonisolated static func activeKey(for p: ProviderInfo) -> String? {
        if let key = KeychainStore.read(p.keyEnv), !key.isEmpty { return key }
        return envFileKey(for: p)
    }

    nonisolated static func storedModel(for id: String) -> String {
        let defaults = UserDefaults.standard
        let legacy = ["deepseek": "deepseekModel", "claude": "claudeModel"][id]
        let value = defaults.string(forKey: "model.\(id)") ?? legacy.flatMap { defaults.string(forKey: $0) } ?? ""
        return value.trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func storedBaseURL(for id: String) -> String {
        (UserDefaults.standard.string(forKey: "baseURL.\(id)") ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// {"openai": {"model": "...", "baseURL": "..."}}: what the user picked, as the engine's MURMR_PROVIDER_CONFIG.
    nonisolated static func configJSON(only id: String? = nil) -> String? {
        var ids = Set<String>()
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.hasPrefix("model.") { ids.insert(String(key.dropFirst(6))) }
            if key.hasPrefix("baseURL.") { ids.insert(String(key.dropFirst(8))) }
        }
        ids.formUnion(["deepseek", "claude"])  // models stored under their old names
        var config: [String: [String: String]] = [:]
        for pid in ids where id == nil || id == pid {
            var entry: [String: String] = [:]
            if !storedModel(for: pid).isEmpty { entry["model"] = storedModel(for: pid) }
            if !storedBaseURL(for: pid).isEmpty { entry["baseURL"] = storedBaseURL(for: pid) }
            if !entry.isEmpty { config[pid] = entry }
        }
        guard !config.isEmpty, let data = try? JSONSerialization.data(withJSONObject: config) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// What the engine needs in its environment: every key in the Keychain (their account names are the variable
    /// names), the chosen service and backup, and the models and addresses the user picked.
    nonisolated static func engineEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for account in KeychainStore.allAccounts() where account.range(of: "^[A-Z][A-Z0-9_]*$", options: .regularExpression) != nil {
            if let key = KeychainStore.read(account), !key.isEmpty { env[account] = key }
        }
        let defaults = UserDefaults.standard
        let choice = defaults.string(forKey: "cleanupChoice") ?? auto
        if choice != auto { env["MURMR_CLEANUP"] = choice }
        if let backup = defaults.string(forKey: "cleanupBackup"), !backup.isEmpty { env["MURMR_FALLBACK"] = backup }
        if let config = configJSON() { env["MURMR_PROVIDER_CONFIG"] = config }
        return env
    }

    // MARK: changing

    @discardableResult
    func save(_ raw: String, for p: ProviderInfo) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard KeychainStore.write(key, account: p.keyEnv) else {
            message = "Không lưu được khoá vào Keychain."
            return false
        }
        message = nil
        testResults[p.id] = nil
        refresh()
        onChanged()
        Task { await loadModels(p) }
        return true
    }

    func remove(for p: ProviderInfo) {
        KeychainStore.delete(p.keyEnv)
        models[p.id] = nil
        modelErrors[p.id] = nil
        testResults[p.id] = nil
        refresh()
        onChanged()
    }

    func moveEnvKeyToKeychain(for p: ProviderInfo) {
        if let key = Self.envFileKey(for: p) { save(key, for: p) }
    }

    func setModel(_ id: String, for p: ProviderInfo) {
        let clean = id.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != model(for: p) else { return }
        selectedModels[p.id] = clean
        UserDefaults.standard.set(clean, forKey: "model.\(p.id)")
        testResults[p.id] = nil
        onChanged()
    }

    func setBaseURL(_ raw: String, for p: ProviderInfo) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != baseURL(p) else { return }
        baseURLs[p.id] = clean == p.baseURL ? "" : clean
        UserDefaults.standard.set(baseURLs[p.id] ?? "", forKey: "baseURL.\(p.id)")
        models[p.id] = nil
        modelErrors[p.id] = nil
        testResults[p.id] = nil
        onChanged()
        Task { await loadModels(p) }
    }

    /// Asks the provider which models are available (through the engine, so all networking stays in Go).
    func loadModels(_ p: ProviderInfo) async {
        guard isReady(p), !loadingModels.contains(p.id) else { return }
        loadingModels.insert(p.id)
        modelErrors[p.id] = nil
        defer { loadingModels.remove(p.id) }
        var env: [String: String] = [:]
        if p.takesKey, let key = Self.activeKey(for: p) { env[p.keyEnv] = key }
        if let config = Self.configJSON(only: p.id) { env["MURMR_PROVIDER_CONFIG"] = config }
        guard let output = await EngineCLI.run(["models", p.id], env: env) else {
            modelErrors[p.id] = "Không tìm thấy engine."
            return
        }
        guard output.status == 0, let data = output.out.data(using: .utf8),
              let list = try? JSONDecoder().decode([ModelOption].self, from: data)
        else {
            modelErrors[p.id] = p.local
                ? "Không kết nối được tới \(baseURL(p)). Dịch vụ đã chạy chưa?"
                : "Chưa tải được danh sách model. Kiểm tra mạng hoặc thử lại."
            return
        }
        models[p.id] = list
    }

    /// Asks the engine itself to clean one short sentence with this provider (`murmr clean`), so the test uses
    /// exactly the code path dictation uses.
    func test(_ p: ProviderInfo) async {
        testing = p.id
        testResults[p.id] = nil
        defer { testing = nil }
        guard model(for: p) != "" else {
            testResults[p.id] = "Chưa chọn model."
            return
        }
        var env = ["MURMR_CLEANUP": p.id]
        if p.takesKey, let key = Self.activeKey(for: p) { env[p.keyEnv] = key }
        if let config = Self.configJSON(only: p.id) { env["MURMR_PROVIDER_CONFIG"] = config }
        guard let output = await EngineCLI.run(["clean", "xin chào"], env: env) else {
            testResults[p.id] = "Không tìm thấy engine."
            return
        }
        if output.status == 0 {
            testResults[p.id] = p.local ? "Dịch vụ trên máy đang chạy tốt." : "Khoá hoạt động."
        } else {
            let line = output.err.split(whereSeparator: \.isNewline).last(where: { $0.contains("murmr:") }) ?? output.err.split(whereSeparator: \.isNewline).last ?? "lỗi không rõ"
            testResults[p.id] = "Không dùng được: " + String(line).replacingOccurrences(of: "murmr: ", with: "").prefix(140)
        }
    }
}
