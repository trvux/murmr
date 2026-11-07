import SwiftUI

/// "Từ điển": names, jargon and known mis-hearings, edited here instead of in a text file. The file stays
/// the source of truth (the terminal workflow reads the same one), and comments in it are preserved.
struct DictionaryPage: View {
    let actions: SettingsActions

    @EnvironmentObject private var state: AppState
    @StateObject private var store = DictionaryStore()
    @StateObject private var hints = HintsStore()
    @State private var newTerm = ""
    @State private var fixFrom = ""
    @State private var fixTo = ""

    var body: some View {
        PageScaffold(title: "Từ điển", subtitle: "Tên người, thuật ngữ và những từ hay bị nghe sai. Thêm ở đây, không cần mở file.") {
            termsSection
            Hairline()
            fixesSection
            Hairline()
            learnedSection
        }
        .onAppear {
            store.onSaved = { state.needsRestart = true }
            store.load()
            hints.refresh()
        }
        // an old error must not outlive what caused it
        .onChange(of: newTerm) { store.message = nil }
        .onChange(of: fixFrom) { store.message = nil }
        .onChange(of: fixTo) { store.message = nil }
    }

    // MARK: terms

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Từ khoá")
            Text("Whisper và AI sẽ ưu tiên viết đúng những từ này: tên người, tên sản phẩm, thuật ngữ.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)

            if store.terms.isEmpty {
                emptyNote("Chưa có từ khoá nào. Thêm tên người hay thuật ngữ bạn hay nói.")
            } else {
                RuledList(items: store.terms) { entry in
                    HStack {
                        Text(entry.line.trimmingCharacters(in: .whitespaces)).font(Theme.Typeface.body).foregroundStyle(Theme.ink)
                        Spacer()
                        RemoveButton(label: "Xoá từ khoá") { store.remove(entry) }
                    }
                }
            }

            HStack(spacing: Theme.Space.s) {
                InputField(placeholder: "Thêm tên hoặc thuật ngữ", text: $newTerm, onSubmit: addTerm)
                InkButton(title: "Thêm", action: addTerm)
                    .opacity(newTerm.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = store.message {
                Text(message).font(Theme.Typeface.caption).foregroundStyle(Theme.signal)
            }
        }
    }

    private func addTerm() {
        if store.addTerm(newTerm) { newTerm = "" }
    }

    // MARK: fixes

    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Sửa cứng")
            Text("Thay thẳng bằng code, không qua AI, ở mọi chỗ khớp. Chỉ nên dùng cho cụm nhiều từ, hoặc từ không bao giờ là thật (ví dụ **push request** thành **pull request**). Đừng dùng cho từ có thể đúng, như tên một người thật.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if store.fixes.isEmpty {
                emptyNote("Chưa có cặp nào.", mood: nil)
            } else {
                RuledList(items: store.fixes) { entry in
                    HStack(spacing: Theme.Space.m) {
                        if case .fix(let from, let to) = entry.kind {
                            Text(from).font(Theme.Typeface.body).foregroundStyle(Theme.inkMuted)
                            Image(systemName: "arrow.right").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                            Text(to).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        RemoveButton(label: "Xoá cặp sửa cứng") { store.remove(entry) }
                    }
                }
            }

            HStack(spacing: Theme.Space.s) {
                InputField(placeholder: "Nghe sai", text: $fixFrom, onSubmit: addFix)
                Image(systemName: "arrow.right").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                InputField(placeholder: "Đúng là", text: $fixTo, onSubmit: addFix)
                InkButton(title: "Thêm", action: addFix)
                    .opacity(fixCanAdd ? 1 : 0.4)
                    .disabled(!fixCanAdd)
            }
        }
    }

    private var fixCanAdd: Bool {
        !fixFrom.trimmingCharacters(in: .whitespaces).isEmpty && !fixTo.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addFix() {
        if store.addFix(from: fixFrom, to: fixTo) {
            fixFrom = ""
            fixTo = ""
        }
    }

    // MARK: learned

    private var learnedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Đã học từ lịch sử")
            Text("Cặp nghe sai lặp từ 3 lần trở lên được gửi cho AI như một gợi ý (không thay cứng). Bỏ cặp nào học nhầm.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !hints.loaded {
                emptyNote("Đang đọc lịch sử…", mood: .sleeping)
            } else if hints.hints.isEmpty {
                emptyNote("Chưa có cặp nào. Dùng thêm vài ngày, các lỗi lặp lại sẽ hiện ở đây.", mood: .sleeping)
            } else {
                RuledList(items: hints.hints) { hint in
                    HStack(spacing: Theme.Space.m) {
                        Text(hint.from).font(Theme.Typeface.body).foregroundStyle(Theme.inkMuted)
                        Image(systemName: "arrow.right").font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
                        Text(hint.to).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                        Spacer()
                        HStack(spacing: Theme.Space.xs) {
                            if hint.active { Circle().fill(Theme.signal).frame(width: 6, height: 6) }
                            Text(hint.active ? "Đang dùng" : "\(hint.count)/3 lần")
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        OutlineButton(title: "Bỏ") { hints.forget(hint) }
                    }
                }
            }
        }
    }

    /// An empty list says so; where the page has more than one, only the first and the last carry the mascot.
    @ViewBuilder private func emptyNote(_ text: String, mood: MascotMood? = .idle) -> some View {
        if let mood {
            MascotNote(mood: mood, text: text, size: 48)
        } else {
            Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
        }
    }
}
