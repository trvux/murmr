import SwiftUI

/// "Ứng dụng": how pronouns are written when dictating into each app. Edits apps.txt; the engine re-reads it at
/// every dictation, so a change applies to the very next thing you say.
struct AppsPage: View {
    @StateObject private var store = AppsStore()
    @State private var showPicker = false
    @State private var ruleText = ""
    @State private var ruleStyle: PronounStyle = .neutral

    var body: some View {
        PageScaffold(
            title: "Ứng dụng",
            subtitle: "Chọn cách xưng hô khi nói vào từng app: «tao/mày» khi nói với máy và AI, «lịch sự» khi nói với người. Áp dụng ở lần nói kế tiếp, không cần khởi động lại."
        ) {
            appsSection
            Hairline()
            titlesSection
        }
        .onAppear { store.load() }
        .onChange(of: ruleText) { store.message = nil }
    }

    // MARK: apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Theo ứng dụng")
            Text("App không có trong danh sách dùng «lịch sự»: giữ nguyên xưng hô Whisper chép. Chỉ cần thêm những app bạn nói với máy.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if store.listed.isEmpty {
                MascotNote(mood: .sleeping, text: "Đang tìm các ứng dụng…")
            } else {
                RuledList(items: store.listed) { app in
                    AppRow(app: app, store: store)
                }
            }

            OutlineButton(title: "Thêm ứng dụng", symbol: "plus") { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    AppPicker(apps: store.notListed) { app in
                        store.setStyle(.casual, for: app.bundle)  // an app worth listing is usually one you talk to
                        showPicker = false
                    }
                }
        }
    }

    // MARK: titles

    private struct TitleRow: Identifiable {
        let id: String
        let text: String
        let style: PronounStyle
        let entry: RuleEntry?  // nil for a built-in rule
    }

    private var titleRows: [TitleRow] {
        let mine = store.titleRules.compactMap { entry -> TitleRow? in
            if case .title(let text, let style) = entry.kind { return TitleRow(id: "u-" + entry.id.uuidString, text: text, style: style, entry: entry) }
            return nil
        }
        let builtIn = store.defaults.titleRules.map {
            TitleRow(id: "d-" + $0.contains, text: $0.contains.trimmingCharacters(in: .whitespaces),
                     style: PronounStyle(rawValue: $0.style) ?? .neutral, entry: nil)
        }
        return mine + builtIn
    }

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Theo tiêu đề cửa sổ")
            Text("Trình duyệt dùng chung cho cả chat với AI lẫn email, nên có thể quyết theo tiêu đề tab. Quy tắc theo tiêu đề thắng quy tắc theo app.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            RuledList(items: titleRows) { row in
                HStack(spacing: Theme.Space.m) {
                    Text("chứa").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                    KeyChip(text: row.text)
                    Image(systemName: "arrow.right").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                    Text(row.style.title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                    Spacer()
                    if let entry = row.entry {
                        RemoveButton(label: "Xoá quy tắc tiêu đề") { store.remove(entry) }
                    } else {
                        Text("Mặc định").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                    }
                }
            }

            HStack(spacing: Theme.Space.s) {
                InputField(placeholder: "Tiêu đề chứa…, ví dụ: - Gmail", text: $ruleText, onSubmit: addRule)
                SegmentedChoice(options: [(PronounStyle.casual, "tao/mày"), (.neutral, "lịch sự")], selection: $ruleStyle)
                InkButton(title: "Thêm", action: addRule)
                    .opacity(ruleText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .disabled(ruleText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = store.message {
                Text(message).font(Theme.Typeface.caption).foregroundStyle(Theme.signal)
            }
        }
    }

    private func addRule() {
        if store.addTitleRule(ruleText, style: ruleStyle) { ruleText = "" }
    }
}

/// One app: its icon and name, and the three-way choice (the built-in default, tao/mày, lịch sự).
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
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(app.name).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                Text("mặc định: \(store.defaultStyle(for: app.bundle).title)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            SegmentedChoice(
                options: [(PronounStyle?.none, "Mặc định"), (.casual, "tao/mày"), (.neutral, "lịch sự")],
                selection: Binding(
                    get: { store.userStyle(for: app.bundle) },
                    set: { store.setStyle($0, for: app.bundle) }
                )
            )
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
