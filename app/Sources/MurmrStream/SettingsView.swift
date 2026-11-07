import SwiftUI

/// What the Settings window can ask the app to do (kept as closures so the views stay dumb).
struct SettingsActions {
    var preview: () -> Void
    var restartEngine: () -> Void
    var openConfig: () -> Void
    var openLog: () -> Void
    var openProject: () -> Void
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case dictionary
    case apps
    case ai
    case appearance
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionary: return "Từ điển"
        case .apps: return "Ứng dụng"
        case .ai: return "AI và khoá API"
        case .appearance: return "Giao diện"
        case .general: return "Chung"
        }
    }

    var symbol: String {
        switch self {
        case .dictionary: return "book"
        case .apps: return "square.grid.2x2"
        case .ai: return "key"
        case .appearance: return "waveform"
        case .general: return "slider.horizontal.3"
        }
    }
}

/// The Settings window: a quiet sidebar on the left, a page on the right. Structure comes from
/// whitespace and hairlines, not boxes (see DESIGN.md). New pages are added as further tabs.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @State var tab: SettingsTab = .appearance

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state, tab: $tab)
                .frame(width: 224)
                .background(Theme.paperSunken)
            Rectangle().fill(Theme.rule).frame(width: 1)
            Group {
                switch tab {
                case .dictionary: DictionaryPage(actions: actions)
                case .apps: AppsPage()
                case .ai: AIPage()
                case .appearance: AppearancePage(actions: actions)
                case .general: GeneralPage(state: state, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
        }
        .frame(minWidth: 840, minHeight: 640)
        .ignoresSafeArea()
        .environmentObject(state)
    }
}

// MARK: - sidebar

struct Sidebar: View {
    @ObservedObject var state: AppState
    @Binding var tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Wordmark()
                .padding(.top, Theme.Space.huge)  // clears the window's traffic-light buttons
                .padding(.bottom, Theme.Space.xl)
                .padding(.horizontal, Theme.Space.m)

            ForEach(SettingsTab.allCases) { t in
                NavItem(tab: t, selected: tab == t) { tab = t }
            }

            Spacer()

            EngineStatus(state: state)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The engine's state at the foot of the sidebar: a progress bar with the current step while it starts,
/// then a dot and "Sẵn sàng".
struct EngineStatus: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.isLoading {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ProgressBar(value: state.loadProgress)
                Text(state.loadDetail ?? AppState.loadText(state.loadStage))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        } else {
            HStack(spacing: Theme.Space.s) {
                Circle().fill(state.engineReady ? Theme.sage : Theme.signal).frame(width: 6, height: 6)
                Text(state.engineReady ? "Sẵn sàng" : "Engine chưa chạy")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

struct NavItem: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: tab.symbol)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                    .frame(width: Theme.Space.xl)
                Text(tab.title)
                    .font(selected ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.ink.opacity(selected ? 0.07 : (hover ? 0.035 : 0)))
            )
            .overlay(alignment: .leading) {
                // a short clay bar marks the selected page
                if selected {
                    Capsule().fill(Theme.signal).frame(width: 2, height: Theme.Space.l)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.Motion.quick, value: hover)
        .animation(Theme.Motion.quick, value: selected)
    }
}

// MARK: - page chrome

/// "Saved, but the engine reads this at startup": shown on every page while a restart is pending.
struct RestartBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Circle().fill(Theme.signal).frame(width: 6, height: 6)
            Text("Đã lưu. Engine đọc phần này lúc khởi động, nên cần khởi động lại để dùng thay đổi.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.m)
            OutlineButton(title: "Áp dụng ngay", symbol: "arrow.clockwise") { state.requestRestart() }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.rule))
    }
}

struct PageScaffold<Content: View>: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(title).font(Theme.Typeface.display).foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state.needsRestart { RestartBar() }
                content()
            }
            .frame(maxWidth: 680, alignment: .leading)  // a reading measure, not the full window
            .padding(.horizontal, Theme.Space.huge)
            .padding(.top, Theme.Space.huge + Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Giao diện

struct AppearancePage: View {
    let actions: SettingsActions

    @AppStorage("notchEars") private var ears = true
    @AppStorage("waveStyle") private var selected = WaveStyle.flock.rawValue
    @StateObject private var signal = DemoSignal()
    private let columns = [GridItem(.adaptive(minimum: 170), spacing: Theme.Space.l)]

    private var style: WaveStyle { WaveStyle(rawValue: selected) ?? .flock }

    var body: some View {
        PageScaffold(title: "Giao diện", subtitle: "Viên thuốc trên notch hiện lên khi bạn nói. Chọn kiểu sóng và hình dạng của nó.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Eyebrow("Xem trước")
                LivePreview(style: style, ears: ears, signal: signal)
            }

            Hairline()

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Eyebrow("Kiểu sóng âm")
                LazyVGrid(columns: columns, spacing: Theme.Space.l) {
                    ForEach(WaveStyle.allCases, id: \.self) { s in
                        WaveTile(style: s, chosen: s == style, signal: signal) { selected = s.rawValue }
                    }
                }
            }

            Hairline()

            SettingRow(title: "Góc tai cong", detail: "Viên thuốc hoà vào notch thay vì có góc vuông.") {
                Toggle("", isOn: $ears).labelsHidden().toggleStyle(.switch).tint(Theme.signal)
            }

            InkButton(title: "Xem thử trên notch", symbol: "play.fill", action: actions.preview)
        }
        .onAppear { signal.start() }
        .onDisappear { signal.stop() }
    }
}

/// One selectable wave: a black tile (it is the pill in miniature) with the wave moving.
struct WaveTile: View {
    let style: WaveStyle
    let chosen: Bool
    @ObservedObject var signal: DemoSignal
    let onTap: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                WaveView(style: style, level: signal.level, levels: signal.levels)
                    .frame(height: 24)
                    .padding(.horizontal, Theme.Space.xl)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.pillBody))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(chosen ? Theme.signal : Theme.rule.opacity(hover ? 2 : 1), lineWidth: chosen ? 2 : 1)
                    )
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(Theme.signal).frame(width: 6, height: 6).opacity(chosen ? 1 : 0)
                    Text(style.title)
                        .font(chosen ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
                        .foregroundStyle(chosen ? Theme.ink : Theme.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.Motion.quick, value: hover)
        .animation(Theme.Motion.quick, value: chosen)
    }
}

/// A quiet mock desktop with the real pill on it, so a choice can be judged in context.
struct LivePreview: View {
    let style: WaveStyle
    let ears: Bool
    @ObservedObject var signal: DemoSignal

    private let notchWidth: CGFloat = 200
    private let menuBar: CGFloat = 34

    var body: some View {
        ZStack(alignment: .top) {
            // the desktop: warm stone, not a wallpaper
            LinearGradient(colors: [Theme.paperSunken, Theme.ink.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                .background(Theme.paperSunken)

            HStack(spacing: Theme.Space.l) {
                Image(systemName: "apple.logo").font(Theme.Typeface.caption)
                Text("Ghostty").font(Theme.Typeface.captionStrong)
                Spacer()
                Text("9:41").font(Theme.Typeface.captionStrong)
            }
            .foregroundStyle(Theme.ink.opacity(0.8))
            .padding(.horizontal, Theme.Space.l)
            .frame(height: menuBar)
            .frame(maxWidth: .infinity)
            .background(Theme.paper.opacity(0.6))

            targetWindow
            pill
        }
        .frame(height: 134)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.rule))
    }

    /// A faint stand-in for the app being dictated into: the text lands here, not on the notch.
    private var targetWindow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Capsule().fill(Theme.inkFaint.opacity(0.7)).frame(width: 190, height: 5)
            Capsule().fill(Theme.inkFaint.opacity(0.5)).frame(width: 130, height: 5)
            HStack(spacing: Theme.Space.xs) {
                Capsule().fill(Theme.inkFaint.opacity(0.5)).frame(width: 70, height: 5)
                Rectangle().fill(Theme.signal).frame(width: 2, height: 11)  // the caret
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.rule))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, Theme.Space.m)
    }

    private var pill: some View {
        let width = notchWidth + Theme.Pill.wing * 2
        let height = menuBar + Theme.Pill.recordingExtra
        let shape = ears
            ? AnyShape(EarShape(ear: Theme.Pill.ear, bottom: Theme.Radius.lg))
            : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: Theme.Radius.lg,
                                              bottomTrailingRadius: Theme.Radius.lg, topTrailingRadius: 0))
        return shape
            .fill(Theme.pillBody)
            .frame(width: width + (ears ? Theme.Pill.ear * 2 : 0), height: height)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "terminal.fill")
                            .font(Theme.Typeface.body)
                            .foregroundStyle(Theme.pillInk.opacity(0.9))
                            .frame(width: Theme.Pill.wing)
                        Spacer(minLength: notchWidth)
                        HStack(spacing: Theme.Space.xs) {
                            RecordingDot()
                            Text("tao/mày")
                                .font(Theme.Typeface.label)
                                .foregroundStyle(Theme.pillInk.opacity(0.65))
                        }
                        .frame(width: Theme.Pill.wing)
                    }
                    .frame(height: menuBar)
                    WaveView(style: style, level: signal.level, levels: signal.levels)
                        .frame(height: Theme.Pill.waveRow)
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.xs)
                }
                .frame(width: width)
            }
    }
}

/// A speech-like fake signal, so waves move the way they will while you talk. It never goes fully
/// quiet, so every preview always shows something.
@MainActor
final class DemoSignal: ObservableObject {
    @Published var level: CGFloat = 0
    @Published var levels: [CGFloat] = Array(repeating: 0, count: AppState.historyCount)
    private var timer: Timer?
    private var tick = 0

    func start() {
        guard timer == nil else { return }
        for _ in 0..<(AppState.historyCount * 2) { step() }  // start with a filled history, not a flat line
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        tick += 1
        let swell = 0.55 + 0.35 * sin(Double(tick) / 7)
        let raw = CGFloat(min(1, max(0.1, swell * Double.random(in: 0.55...1.0))))
        level = raw > level ? level * 0.35 + raw * 0.65 : level * 0.8 + raw * 0.2
        levels.removeFirst()
        levels.append(level)
    }
}

// MARK: - Chung

struct GeneralPage: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        PageScaffold(title: "Chung", subtitle: "Trạng thái của engine và nơi lưu dữ liệu.") {
            if state.isLoading { ProgressBar(value: state.loadProgress) }
            if !state.engineReady && !state.isLoading {
                MascotNote(mood: .oops, text: "Engine đang dừng. Bấm «Khởi động lại»; nếu vẫn không được, mở nhật ký engine ở dưới.", size: 64)
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingRow(title: state.engineReady ? "Engine đang chạy" : "Engine chưa sẵn sàng", detail: state.engineStatus) {
                    OutlineButton(title: "Khởi động lại", symbol: "arrow.clockwise", action: actions.restartEngine)
                }
                Hairline()
                SettingRow(title: "Phím nói", detail: "Giữ để nói, thả ra để dán.") {
                    KeyChip(text: "⌥ phải")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow("Dữ liệu")
                VStack(alignment: .leading, spacing: 0) {
                    DataRow(title: "Thư mục cấu hình", path: "~/.config/murmr", action: actions.openConfig)
                    Hairline()
                    DataRow(title: "Nhật ký engine", path: "~/Library/Logs/Murmr Stream", action: actions.openLog)
                    Hairline()
                    DataRow(title: "Thư mục dự án (model Whisper)", path: EngineController.homeDir, action: actions.openProject)
                }
            }

            Text("Murmr Stream \(version)")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkFaint)
        }
    }
}

struct DataRow: View {
    let title: String
    let path: String
    let action: () -> Void

    var body: some View {
        SettingRow(title: title) {
            HStack(spacing: Theme.Space.m) {
                Text(path)
                    .font(Theme.Typeface.mono)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                OutlineButton(title: "Mở", symbol: "arrow.up.right", action: action)
            }
        }
    }
}
