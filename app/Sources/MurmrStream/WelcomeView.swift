import SwiftUI

/// The first-run window: say hello, get the three permissions, wait for the models, and say how to use it. It opens
/// once by itself and any time from the menu ("Hướng dẫn ban đầu…").
struct WelcomeView: View {
    enum Step: Int, CaseIterable { case hello, permissions, prepare, ready }

    @ObservedObject var state: AppState
    @ObservedObject var permissions: Permissions
    var openAISettings: () -> Void = {}
    var finish: () -> Void = {}
    @State private var step: Step

    init(state: AppState, permissions: Permissions, initialStep: Step = .hello, openAISettings: @escaping () -> Void = {}, finish: @escaping () -> Void = {}) {
        self.state = state
        self.permissions = permissions
        self.openAISettings = openAISettings
        self.finish = finish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Space.xl) {
                Mascot(mood: mood, size: 128)
                    .frame(height: 128)
                    .padding(.top, Theme.Space.xl)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Hairline()
            footer
        }
        .padding(.horizontal, Theme.Space.huge)
        .padding(.bottom, Theme.Space.xl)
        .frame(width: 560, height: 660)
        .background(Theme.paper)
        .animation(Theme.Motion.calm, value: step)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .onChange(of: permissions.allGranted) { _, granted in
            if granted { state.requestRestart() }  // the key listener cannot start until the permissions exist
        }
    }

    // MARK: mood

    private var mood: MascotMood {
        switch step {
        case .hello: return .idle
        case .permissions: return permissions.allGranted ? .done : .listening
        case .prepare: return state.engineReady ? .done : .sleeping
        case .ready: return .speaking
        }
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case .hello: hello
        case .permissions: permissionsStep
        case .prepare: prepare
        case .ready: ready
        }
    }

    private func heading(_ title: String, _ text: String) -> some View {
        VStack(spacing: Theme.Space.s) {
            Text(title).font(Theme.Typeface.display).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(text)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hello: some View {
        VStack(spacing: Theme.Space.xl) {
            heading("Xin chào", "Murmr Stream chép lời bạn nói và dán vào đúng app bạn đang dùng.")
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    KeyChip(text: "⌥ phải")
                    Text("Giữ phím này, nói, rồi thả ra.").font(Theme.Typeface.body).foregroundStyle(Theme.ink)
                }
                bullet("Giọng nói được xử lý ngay trên máy bạn.")
                bullet("Khoá AI (nếu bạn thêm) nằm trong Keychain, không gửi về máy chủ nào của chúng tôi.")
                bullet("Lần đầu mở, app tải thêm mô hình giọng nói. Chỉ một lần.")
            }
            .padding(.top, Theme.Space.s)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: Theme.Space.l) {
            heading("Cho phép ba quyền", "macOS sẽ hỏi từng quyền. Cả ba đều cần để dictation chạy được.")
            VStack(spacing: 0) {
                Hairline()
                ForEach(PermissionKind.allCases) { kind in
                    permissionRow(kind)
                    Hairline()
                }
            }
        }
    }

    private func permissionRow(_ kind: PermissionKind) -> some View {
        let state = permissions.state(kind)
        return HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: kind.symbol)
                .font(Theme.Typeface.body)
                .foregroundStyle(state == .granted ? Theme.sage : Theme.inkMuted)
                .frame(width: Theme.Space.xl)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(kind.title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                Text(kind.why).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.m)
            if state == .granted {
                HStack(spacing: Theme.Space.xs) {
                    Circle().fill(Theme.sage).frame(width: 6, height: 6)
                    Text("Đã cấp").font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
                }
            } else {
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    OutlineButton(title: "Cho phép") { permissions.request(kind) }
                    Button("Mở cài đặt") { permissions.openSettings(kind) }
                        .buttonStyle(.plain)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.signal)
                }
            }
        }
        .padding(.vertical, Theme.Space.m)
    }

    private var prepare: some View {
        VStack(spacing: Theme.Space.xl) {
            heading(state.engineReady ? "Đã chuẩn bị xong" : "Đang chuẩn bị",
                    "Lần đầu, app tải mô hình nhận dạng giọng nói (khoảng 574 MB). Chỉ cần có mạng một lần.")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ProgressBar(value: state.engineReady ? 1 : state.loadProgress)
                Text(state.engineReady ? "Sẵn sàng" : (state.loadDetail ?? AppState.loadText(state.loadStage)))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow("Không bắt buộc")
                Text("Thêm khoá AI để chữ được dọn sạch: bỏ từ đệm, thêm dấu câu, sửa chỗ nghe sai. Không có khoá, bạn vẫn nhận được văn bản thô.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OutlineButton(title: "Thêm khoá AI…", symbol: "key") { openAISettings() }
            }
        }
    }

    private var ready: some View {
        VStack(spacing: Theme.Space.xl) {
            heading("Sẵn sàng", "Mở một ô soạn thảo bất kỳ, giữ ⌥ phải và nói. Thả ra, chữ sẽ hiện ở đó.")
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                bullet("Biểu tượng sóng ở thanh menu mở Cài đặt: từ điển, app, AI.")
                bullet("Mở lại hướng dẫn này bất cứ lúc nào từ menu đó.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(Theme.inkFaint).frame(width: 4, height: 4)
            Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: footer

    private var canContinue: Bool {
        switch step {
        case .hello, .ready: return true
        case .permissions: return permissions.allGranted
        case .prepare: return state.engineReady
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle().fill(s == step ? Theme.ink : Theme.rule).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step != .hello && step != .ready {
                OutlineButton(title: "Quay lại") { move(-1) }
            }
            if step == .permissions && !permissions.allGranted {
                Button("Để sau") { move(1) }.buttonStyle(.plain).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            }
            if step == .prepare && !state.engineReady {
                Button("Tiếp tục ở nền") { finish() }.buttonStyle(.plain).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted)
            }
            InkButton(title: step == .hello ? "Bắt đầu" : (step == .ready ? "Xong" : "Tiếp tục")) {
                if step == .ready { finish() } else { move(1) }
            }
            .opacity(canContinue ? 1 : 0.4)
            .disabled(!canContinue)
        }
        .padding(.top, Theme.Space.l)
    }

    private func move(_ by: Int) {
        if let next = Step(rawValue: step.rawValue + by) { step = next }
    }
}
