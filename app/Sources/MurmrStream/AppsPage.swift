import SwiftUI

/// "Xưng hô": how you address yourself and the listener, and where. The app offers the mechanism and a few starting
/// points; it never assumes how anyone speaks. Everything is written to apps.txt, which the engine re-reads at every
/// dictation, so a change applies to the very next thing you say.
struct AppsPage: View {
    @StateObject private var store = AppsStore()
    @State private var showPicker = false
    @State private var newSelf = ""
    @State private var newYou = ""
    @State private var newWe = ""
    @State private var ruleText = ""
    @State private var ruleProfile = PronounProfile.keepID

    var body: some View {
        PageScaffold(
            title: "Xưng hô",
            subtitle: "Máy chép lời hay đổi «tao» thành «tôi», «mày» thành «bạn». Cho Murmr Stream biết bạn xưng hô thế nào, AI sẽ viết lại đúng như vậy. Mặc định nó giữ nguyên những gì nghe được."
        ) {
            profilesSection
            Hairline()
            defaultSection
            Hairline()
            appsSection
            Hairline()
            titlesSection
        }
        .onAppear { store.load() }
        .onChange(of: newSelf) { store.message = nil }
        .onChange(of: ruleText) { store.message = nil }
    }

    // MARK: your ways of addressing

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Cách xưng hô của bạn")
            if store.profiles.isEmpty {
                MascotNote(mood: .idle, text: "Chưa có cách xưng hô nào. Chọn một gợi ý bên dưới, hoặc tự nhập.")
            } else {
                RuledList(items: store.profiles) { profile in
                    HStack {
                        Text(profile.detail).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                        Spacer()
                        RemoveButton(label: "Xoá cách xưng hô") { store.removeProfile(profile.id) }
                    }
                }
            }

            if !store.presets.isEmpty {
                Text("Gợi ý (bấm để điền vào ô bên dưới, rồi bấm Thêm):")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.s)], alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(store.presets) { preset in
                        OutlineButton(title: preset.label) {
                            newSelf = preset.selfWord
                            newYou = preset.you
                            newWe = preset.we
                        }
                    }
                }
            }

            HStack(spacing: Theme.Space.s) {
                InputField(placeholder: "Tôi nói là…", text: $newSelf, onSubmit: addProfile)
                InputField(placeholder: "Gọi người nghe là…", text: $newYou, onSubmit: addProfile)
                InputField(placeholder: "Chúng tôi (tuỳ chọn)", text: $newWe, onSubmit: addProfile)
                InkButton(title: "Thêm", action: addProfile)
                    .opacity(canAddProfile ? 1 : 0.4)
                    .disabled(!canAddProfile)
            }
            if let message = store.message {
                Text(message).font(Theme.Typeface.caption).foregroundStyle(Theme.signal)
            }
        }
    }

    private var canAddProfile: Bool {
        !newSelf.trimmingCharacters(in: .whitespaces).isEmpty || !newYou.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addProfile() {
        guard store.addProfile(selfWord: newSelf, you: newYou, we: newWe) != nil else { return }
        newSelf = ""
        newYou = ""
        newWe = ""
    }

    // MARK: the default

    private var defaultSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Mặc định")
            Text("Dùng khi không có quy tắc nào khác bên dưới.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
            MenuField(label: store.defaultID == PronounProfile.keepID ? "Giữ nguyên như máy nghe được" : store.name(for: store.defaultID)) {
                Picker("Mặc định", selection: Binding(get: { store.defaultID }, set: { store.setDefault($0) })) {
                    Text("Giữ nguyên như máy nghe được").tag(PronounProfile.keepID)
                    ForEach(store.profiles) { Text($0.detail).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }

    // MARK: apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Theo ứng dụng")
            Text("Chỉ cần thêm app mà bạn xưng hô khác mặc định, ví dụ nói «tao/mày» với AI trong terminal nhưng «tôi/bạn» khi viết email.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !store.listed.isEmpty {
                RuledList(items: store.listed) { app in
                    AppRow(app: app, store: store)
                }
            }

            OutlineButton(title: "Thêm ứng dụng", symbol: "plus") { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    AppPicker(apps: store.notListed) { app in
                        // start from a profile other than the default if there is one, so the new row already means something
                        let other = store.profiles.first { $0.id != store.defaultID }?.id ?? PronounProfile.keepID
                        store.setProfile(store.defaultID == PronounProfile.keepID ? other : PronounProfile.keepID, for: app.bundle)
                        showPicker = false
                    }
                }
        }
    }

    // MARK: titles

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Theo tiêu đề cửa sổ")
            Text("Trình duyệt dùng chung cho cả chat với AI lẫn email, nên có thể quyết theo tiêu đề tab. Quy tắc theo tiêu đề thắng quy tắc theo app.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !store.titleRules.isEmpty {
                RuledList(items: store.titleRules) { entry in
                    HStack(spacing: Theme.Space.m) {
                        if case .title(let text, let id) = entry.kind {
                            Text("chứa").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                            KeyChip(text: text)
                            Image(systemName: "arrow.right").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                            Text(store.name(for: id)).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        RemoveButton(label: "Xoá quy tắc tiêu đề") { store.remove(entry) }
                    }
                }
            }

            HStack(spacing: Theme.Space.s) {
                InputField(placeholder: "Tiêu đề chứa…, ví dụ: - Gmail", text: $ruleText, onSubmit: addRule)
                MenuField(label: store.name(for: ruleProfile)) {
                    Picker("Xưng hô", selection: $ruleProfile) {
                        Text("Giữ nguyên").tag(PronounProfile.keepID)
                        ForEach(store.profiles) { Text($0.detail).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .frame(width: 170)
                InkButton(title: "Thêm", action: addRule)
                    .opacity(ruleText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .disabled(ruleText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addRule() {
        if store.addTitleRule(ruleText, profile: ruleProfile) { ruleText = "" }
    }
}

/// One app with a rule: its icon and name, and a menu to choose how you address in it.
private struct AppRow: View {
    let app: InstalledApp
    @ObservedObject var store: AppsStore

    private var icon: NSImage {
        app.path.isEmpty
            ? (NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
            : NSWorkspace.shared.icon(forFile: app.path)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(nsImage: icon).resizable().frame(width: Theme.Space.xxl - Theme.Space.xs, height: Theme.Space.xxl - Theme.Space.xs)
            Text(app.name).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
            Spacer()
            MenuField(label: store.name(for: store.userProfileID(for: app.bundle) ?? PronounProfile.keepID)) {
                Picker("Xưng hô", selection: Binding(
                    get: { store.userProfileID(for: app.bundle) ?? PronounProfile.keepID },
                    set: { store.setProfile($0, for: app.bundle) }
                )) {
                    Text("Giữ nguyên").tag(PronounProfile.keepID)
                    ForEach(store.profiles) { Text($0.detail).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("Bỏ quy tắc: dùng mặc định") { store.setProfile(nil, for: app.bundle) }
            }
            .frame(width: 200)
        }
    }
}

/// Pick an installed app that is not listed yet.
private struct AppPicker: View {
    let apps: [InstalledApp]
    let onPick: (InstalledApp) -> Void

    @State private var query = ""

    private var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            InputField(placeholder: "Tìm ứng dụng", text: $query)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { app in
                        Button { onPick(app) } label: {
                            HStack(spacing: Theme.Space.m) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: Theme.Space.xl, height: Theme.Space.xl)
                                Text(app.name).font(Theme.Typeface.body).foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Space.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        MascotNote(mood: .oops, text: "Không thấy ứng dụng nào.", size: 44)
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 340, height: 380)
        .background(Theme.paper)
    }
}
