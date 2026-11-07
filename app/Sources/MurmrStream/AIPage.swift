import SwiftUI

/// "AI và khoá API": one flow, top to bottom. Pick the service, give it a key, pick its model. Only the chosen
/// service's details are shown; the other one's key stays stored and untouched until it is chosen.
struct AIPage: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var settings = AISettings()
    @State private var drafts: [AIProvider: String] = [:]
    @State private var replacing: Set<AIProvider> = []
    @State private var customModel = ""
    @State private var showCustom = false

    private static let privacyURL = "https://github.com/trvux/murmr/blob/main/PRIVACY.md"

    var body: some View {
        PageScaffold(title: "AI và khoá API", subtitle: "AI chỉ làm một việc: dọn văn sau khi Whisper chép lời. Khoá của bạn nằm trong Keychain, trên máy này.") {
            serviceChoice
            if let provider = AIProvider(rawValue: settings.shownChoice.rawValue) {
                Hairline()
                providerBlock(provider)
                Hairline()
                fallbackRow(provider)
            }
            Hairline()
            privacyBlock
        }
        .onAppear {
            settings.onChanged = { state.needsRestart = true }
            settings.refresh()
            for provider in AIProvider.allCases where settings.statuses[provider] != .missing && settings.models[provider] == nil {
                Task { await settings.loadModels(provider) }
            }
        }
    }

    // MARK: 1. service

    private var serviceChoice: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Dịch vụ dọn văn")
            SegmentedChoice(
                options: [(CleanupChoice.deepseek, "DeepSeek"), (.claude, "Claude"), (.none, "Không dùng AI")],
                selection: Binding(
                    get: { settings.shownChoice },
                    set: {
                        settings.choice = $0
                        showCustom = false
                        state.needsRestart = true
                    }
                )
            )
            Text(settings.shownChoice == .none
                 ? "Đang dán nguyên văn Whisper chép, không gửi gì đi đâu. Chọn một dịch vụ để bật AI."
                 : "Chỉ dịch vụ đang chọn được gọi, trừ khi bạn bật tự chuyển ở dưới. Khoá của bên còn lại vẫn được giữ, không tốn tiền.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 4. backup

    @ViewBuilder
    private func fallbackRow(_ provider: AIProvider) -> some View {
        let other = provider == .deepseek ? AIProvider.claude : .deepseek
        if settings.canFallBack {
            SettingRow(
                title: "Tự chuyển sang \(other == .claude ? "Claude" : "DeepSeek") khi bị lỗi",
                detail: "Nếu \(provider == .claude ? "Claude" : "DeepSeek") không trả lời, chữ sẽ được gửi sang \(other == .claude ? "Claude" : "DeepSeek") thay vì dán nguyên văn. Bạn sẽ thấy thông báo ở notch. Tắt thì chữ chỉ đi tới dịch vụ bạn chọn."
            ) {
                Toggle("", isOn: $settings.fallback).labelsHidden().toggleStyle(.switch).tint(Theme.signal)
            }
        } else if settings.shownChoice != .none {
            Text("Muốn có dự phòng khi dịch vụ lỗi? Thêm khoá của \(other == .claude ? "Claude" : "DeepSeek") để bật tuỳ chọn tự chuyển.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 2. key, 3. model

    private func providerBlock(_ provider: AIProvider) -> some View {
        let status = settings.statuses[provider] ?? .missing
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.title).font(Theme.Typeface.title).foregroundStyle(Theme.ink)
                Spacer()
                statusLabel(status)
            }
            keySection(provider, status: status)
            if status != .missing {
                modelSection(provider)
            }
        }
    }

    @ViewBuilder
    private func keySection(_ provider: AIProvider, status: KeyStatus) -> some View {
        let draft = Binding(get: { drafts[provider] ?? "" }, set: { drafts[provider] = $0 })
        let draftEmpty = draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        let entering = status == .missing || replacing.contains(provider)

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if entering {
                HStack(spacing: Theme.Space.s) {
                    SecureInputField(placeholder: "Dán khoá API", text: draft) { saveDraft(provider) }
                    InkButton(title: "Lưu") { saveDraft(provider) }
                        .opacity(draftEmpty ? 0.4 : 1)
                        .disabled(draftEmpty)
                }
                HStack(spacing: Theme.Space.m) {
                    ExternalLink(title: "Lấy khoá \(provider == .deepseek ? "DeepSeek" : "Anthropic")", url: provider.getKeyURL)
                    if status == .envFile {
                        OutlineButton(title: "Chuyển khoá từ file env vào Keychain", symbol: "lock") { settings.moveEnvKeyToKeychain(for: provider) }
                    }
                    if replacing.contains(provider) {
                        Button("Huỷ") { replacing.remove(provider); drafts[provider] = "" }
                            .buttonStyle(.plain).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: Theme.Space.s) {
                    OutlineButton(title: settings.testing == provider ? "Đang thử…" : "Thử khoá", symbol: "checkmark.seal") {
                        Task { await settings.test(provider) }
                    }
                    .disabled(settings.testing != nil)
                    OutlineButton(title: "Thay khoá", symbol: "arrow.triangle.2.circlepath") { replacing.insert(provider) }
                    OutlineButton(title: "Xoá khoá", symbol: "trash") { settings.remove(for: provider) }
                    Spacer()
                }
            }
            if status == .envFile && !entering {
                OutlineButton(title: "Chuyển khoá từ file env vào Keychain", symbol: "lock") { settings.moveEnvKeyToKeychain(for: provider) }
            }
            if let result = settings.testResults[provider] {
                Text(result)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(result.hasPrefix("Khoá hoạt động") ? Theme.sage : Theme.signal)
            }
        }
    }

    private func modelSection(_ provider: AIProvider) -> some View {
        let selected = settings.model(for: provider)
        let all = settings.models[provider] ?? []
        let fresh = all.filter { !$0.deprecated }
        let old = all.filter(\.deprecated)
        let listed = all.contains { $0.id == selected }
        let binding = Binding(get: { selected }, set: { settings.setModel($0, for: provider) })

        func label(_ id: String, _ name: String) -> String { id == provider.defaultModel ? "\(name)  ·  mặc định" : name }

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow("Model")
            Menu {
                Picker("Model", selection: binding) {
                    if !listed { Text(label(selected, selected)).tag(selected) }
                    ForEach(fresh) { Text(label($0.id, $0.name)).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if !old.isEmpty {
                    Divider()
                    Menu("Model cũ") {
                        Picker("Model cũ", selection: binding) { ForEach(old) { Text($0.name).tag($0.id) } }
                            .pickerStyle(.inline)
                            .labelsHidden()
                    }
                }
                Divider()
                Button("Nhập tên model khác…") { showCustom = true }
                Button("Tải lại danh sách") { Task { await settings.loadModels(provider) } }
            } label: {
                HStack {
                    Text(all.first { $0.id == selected }?.name ?? selected).font(Theme.Typeface.body).foregroundStyle(Theme.ink)
                    Spacer()
                    if settings.loadingModels.contains(provider) {
                        Text("Đang tải danh sách…").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.paperRaised))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.rule))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            if showCustom {
                InputField(placeholder: "Tên model, ví dụ \(provider.defaultModel)", text: $customModel) {
                    settings.setModel(customModel, for: provider)
                    customModel = ""
                    showCustom = false
                }
            }
            if let error = settings.modelErrors[provider] {
                Text(error).font(Theme.Typeface.caption).foregroundStyle(Theme.signal)
            } else {
                Text("Dọn văn cần trả lời trong vài giây, nên model nhỏ và nhanh thường hợp nhất.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func statusLabel(_ status: KeyStatus) -> some View {
        HStack(spacing: Theme.Space.xs) {
            switch status {
            case .keychain(let last4):
                Circle().fill(Theme.sage).frame(width: 6, height: 6)
                Text("Đã lưu trong Keychain  ••••\(last4)").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            case .envFile:
                Circle().fill(Theme.signal).frame(width: 6, height: 6)
                Text("Đang ở file env").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            case .missing:
                Circle().fill(Theme.inkFaint).frame(width: 6, height: 6)
                Text("Chưa có khoá").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func saveDraft(_ provider: AIProvider) {
        if settings.save(drafts[provider] ?? "", for: provider) {
            drafts[provider] = ""
            replacing.remove(provider)
        }
    }

    // MARK: privacy

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Riêng tư")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note("Khoá nằm trong Keychain của macOS trên máy này, không đồng bộ qua iCloud. Murmr Stream không có máy chủ: không nhận khoá, giọng nói hay chữ của bạn.")
                note("Giọng nói không rời máy. Khi dọn văn, chỉ phần chữ đã chép (cùng từ điển và gợi ý đã học) được gửi thẳng tới dịch vụ bạn chọn (hoặc dịch vụ dự phòng, nếu bạn bật), kèm khoá của bạn; dịch vụ đó có chính sách dữ liệu riêng.")
                note("Tắt AI thì không có gì rời máy.")
            }
            ExternalLink(title: "Xem chính sách riêng tư", url: Self.privacyURL)
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(Theme.inkFaint).frame(width: 4, height: 4)
            Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
