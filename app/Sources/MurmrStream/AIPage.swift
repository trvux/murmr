import SwiftUI

/// "AI và khoá API": one flow, top to bottom. Pick the service, give it a key, pick its model, optionally pick a
/// backup. The list of services comes from the engine; this page only draws what it is given.
struct AIPage: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var settings = AISettings()
    @State private var drafts: [String: String] = [:]
    @State private var urlDrafts: [String: String] = [:]
    @State private var replacing: Set<String> = []
    @State private var customModel = ""
    @State private var showCustom = false

    private static let privacyURL = "https://github.com/trvux/murmr/blob/main/PRIVACY.md"

    var body: some View {
        PageScaffold(title: "AI và khoá API", subtitle: "AI chỉ làm một việc: dọn văn sau khi Whisper chép lời. Khoá của bạn nằm trong Keychain, trên máy này.") {
            serviceChoice
            if let provider = settings.provider(settings.shownChoice) {
                Hairline()
                providerBlock(provider)
                Hairline()
                backupRow(primary: provider)
            }
            Hairline()
            privacyBlock
        }
        .onAppear {
            settings.onChanged = { state.needsRestart = true }
            settings.refresh()
            loadModelsIfNeeded()
        }
    }

    private func loadModelsIfNeeded() {
        guard let p = settings.provider(settings.shownChoice), settings.isReady(p), settings.models[p.id] == nil else { return }
        Task { await settings.loadModels(p) }
    }

    // MARK: 1. service

    private var serviceChoice: some View {
        let shown = settings.shownChoice
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Dịch vụ dọn văn")
            MenuField(label: settings.provider(shown)?.title ?? "Không dùng AI") {
                Picker("Dịch vụ", selection: Binding(
                    get: { shown },
                    set: {
                        settings.choice = $0
                        showCustom = false
                        state.needsRestart = true
                        loadModelsIfNeeded()
                    }
                )) {
                    ForEach(settings.providers) { p in
                        Text(menuTitle(p)).tag(p.id)
                    }
                    Text("Không dùng AI").tag(AISettings.off)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Text(shown == AISettings.off
                 ? "Đang dán nguyên văn Whisper chép, không gửi gì đi đâu. Chọn một dịch vụ để bật AI."
                 : "Chỉ dịch vụ đang chọn được gọi, trừ khi bạn chọn một dịch vụ dự phòng ở dưới. Khoá của các bên khác vẫn được giữ, không tốn tiền.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A menu line: the name, and what is worth knowing before picking it.
    private func menuTitle(_ p: ProviderInfo) -> String {
        if p.local { return "\(p.title)  ·  chữ không rời máy" }
        if p.needsKey && settings.status(p) == .missing { return "\(p.title)  ·  chưa có khoá" }
        return p.title
    }

    // MARK: 2. address and key, 3. model

    private func providerBlock(_ p: ProviderInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.title).font(Theme.Typeface.title).foregroundStyle(Theme.ink)
                Spacer()
                statusLabel(p)
            }
            Text(p.blurb).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            if p.editableURL { addressSection(p) }
            if p.takesKey { keySection(p) }
            if settings.isReady(p) {
                modelSection(p)
                if let result = settings.testResults[p.id] {
                    let ok = result.hasPrefix("Khoá hoạt động") || result.hasPrefix("Dịch vụ trên máy")
                    MascotNote(mood: ok ? .done : .oops, text: result, size: 44, tone: ok ? Theme.sage : Theme.signal)
                }
                HStack(spacing: Theme.Space.s) {
                    OutlineButton(title: settings.testing == p.id ? "Đang thử…" : (p.takesKey ? "Thử khoá" : "Thử kết nối"), symbol: "checkmark.seal") {
                        Task { await settings.test(p) }
                    }
                    .disabled(settings.testing != nil)
                    Spacer()
                }
            }
            if !p.tested {
                Text("Chưa được kiểm với khoá thật. Nếu \"Thử\" báo lỗi, hãy báo lại để sửa.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func addressSection(_ p: ProviderInfo) -> some View {
        let binding = Binding(get: { urlDrafts[p.id] ?? settings.baseURL(p) }, set: { urlDrafts[p.id] = $0 })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow("Địa chỉ")
            InputField(placeholder: p.baseURL.isEmpty ? "https://…/v1" : p.baseURL, text: binding) {
                settings.setBaseURL(binding.wrappedValue, for: p)
            }
            Text("Nhấn Return để lưu. Địa chỉ http chỉ được dùng cho chính máy này (localhost); máy khác phải là https.")
                .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func keySection(_ p: ProviderInfo) -> some View {
        let status = settings.status(p)
        let draft = Binding(get: { drafts[p.id] ?? "" }, set: { drafts[p.id] = $0 })
        let draftEmpty = draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        let entering = status == .missing || replacing.contains(p.id)

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !p.needsKey { Eyebrow("Khoá (nếu dịch vụ cần)") }
            if entering {
                HStack(spacing: Theme.Space.s) {
                    SecureInputField(placeholder: "Dán khoá API", text: draft) { saveDraft(p) }
                    InkButton(title: "Lưu") { saveDraft(p) }
                        .opacity(draftEmpty ? 0.4 : 1)
                        .disabled(draftEmpty)
                }
                HStack(spacing: Theme.Space.m) {
                    if !p.keyURL.isEmpty { ExternalLink(title: "Lấy khoá \(p.title.split(separator: " ").first.map(String.init) ?? p.title)", url: p.keyURL) }
                    if status == .envFile {
                        OutlineButton(title: "Chuyển khoá từ file env vào Keychain", symbol: "lock") { settings.moveEnvKeyToKeychain(for: p) }
                    }
                    if replacing.contains(p.id) {
                        Button("Huỷ") { replacing.remove(p.id); drafts[p.id] = "" }
                            .buttonStyle(.plain).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: Theme.Space.s) {
                    OutlineButton(title: "Thay khoá", symbol: "arrow.triangle.2.circlepath") { replacing.insert(p.id) }
                    OutlineButton(title: "Xoá khoá", symbol: "trash") { settings.remove(for: p) }
                    Spacer()
                }
            }
            if status == .envFile && !entering {
                OutlineButton(title: "Chuyển khoá từ file env vào Keychain", symbol: "lock") { settings.moveEnvKeyToKeychain(for: p) }
            }
        }
    }

    private func modelSection(_ p: ProviderInfo) -> some View {
        let selected = settings.model(for: p)
        let all = settings.models[p.id] ?? []
        let fresh = all.filter { !$0.deprecated }
        let old = all.filter(\.deprecated)
        let listed = all.contains { $0.id == selected }
        let binding = Binding(get: { selected }, set: { settings.setModel($0, for: p) })

        func label(_ id: String, _ name: String) -> String { id == p.defaultModel ? "\(name)  ·  mặc định" : name }

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow("Model")
            MenuField(
                label: selected.isEmpty ? "Chọn model…" : (all.first { $0.id == selected }?.name ?? selected),
                detail: settings.loadingModels.contains(p.id) ? "Đang tải danh sách…" : nil
            ) {
                Picker("Model", selection: binding) {
                    if !listed && !selected.isEmpty { Text(label(selected, selected)).tag(selected) }
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
                Button("Tải lại danh sách") { Task { await settings.loadModels(p) } }
            }

            if showCustom {
                InputField(placeholder: "Tên model", text: $customModel) {
                    settings.setModel(customModel, for: p)
                    customModel = ""
                    showCustom = false
                }
            }
            if let error = settings.modelErrors[p.id] {
                Text(error).font(Theme.Typeface.caption).foregroundStyle(Theme.signal)
            } else if selected.isEmpty {
                Text("Chọn một model ở trên. Dọn văn cần trả lời trong vài giây, nên model nhỏ và nhanh thường hợp nhất.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            } else {
                Text("Dọn văn cần trả lời trong vài giây, nên model nhỏ và nhanh thường hợp nhất.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func statusLabel(_ p: ProviderInfo) -> some View {
        HStack(spacing: Theme.Space.xs) {
            if !p.takesKey {
                Circle().fill(Theme.sage).frame(width: 6, height: 6)
                Text("Không cần khoá").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            } else {
                switch settings.status(p) {
                case .keychain(let last4):
                    Circle().fill(Theme.sage).frame(width: 6, height: 6)
                    Text("Đã lưu trong Keychain  ••••\(last4)").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                case .envFile:
                    Circle().fill(Theme.signal).frame(width: 6, height: 6)
                    Text("Đang ở file env").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                case .missing:
                    Circle().fill(Theme.inkFaint).frame(width: 6, height: 6)
                    Text(p.needsKey ? "Chưa có khoá" : "Chưa đặt khoá").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    private func saveDraft(_ p: ProviderInfo) {
        if settings.save(drafts[p.id] ?? "", for: p) {
            drafts[p.id] = ""
            replacing.remove(p.id)
        }
    }

    // MARK: 4. backup

    @ViewBuilder
    private func backupRow(primary: ProviderInfo) -> some View {
        let candidates = settings.backupCandidates(excluding: primary.id)
        let current = candidates.contains { $0.id == settings.backup } ? settings.backup : ""
        if candidates.isEmpty {
            if settings.shownChoice != AISettings.off {
                Text("Muốn có dự phòng khi \(primary.title) lỗi? Thêm khoá của một dịch vụ khác để chọn nó làm dự phòng.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow("Dự phòng")
                MenuField(label: settings.provider(current)?.title ?? "Tắt") {
                    Picker("Dự phòng", selection: Binding(get: { current }, set: { settings.backup = $0 })) {
                        Text("Tắt").tag("")
                        ForEach(candidates) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Text("Nếu \(primary.title) không trả lời, chữ sẽ được gửi sang dịch vụ dự phòng thay vì dán nguyên văn, và notch báo cho bạn biết. Để Tắt thì chữ chỉ đi tới dịch vụ bạn đã chọn.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: privacy

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Riêng tư")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note("Khoá nằm trong Keychain của macOS trên máy này, không đồng bộ qua iCloud. Murmr Stream không có máy chủ: không nhận khoá, giọng nói hay chữ của bạn.")
                note("Giọng nói không rời máy. Khi dọn văn, chỉ phần chữ đã chép (cùng từ điển và gợi ý đã học) được gửi thẳng tới dịch vụ bạn chọn (hoặc dịch vụ dự phòng, nếu bạn bật), kèm khoá của bạn; dịch vụ đó có chính sách dữ liệu riêng.")
                note("Tắt AI, hoặc dùng dịch vụ chạy trên máy bạn như Ollama, thì không có chữ nào rời máy.")
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
