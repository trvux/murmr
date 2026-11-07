import AppKit
import SwiftUI

// The single source of every visual decision. See DESIGN.md for the reasoning.
// Views use only what is defined here; scripts/design-lint.sh fails the build of a design that does not.

extension NSColor {
    fileprivate convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// A colour that follows the system appearance.
private func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
    }))
}

enum Theme {
    // MARK: palette: paper, ink, and one accent

    static let paper = dynamic(light: 0xF6F2E9, dark: 0x161412)
    static let paperRaised = dynamic(light: 0xFBF9F4, dark: 0x1E1B18)
    static let paperSunken = dynamic(light: 0xEEE9DD, dark: 0x121110)

    static let ink = dynamic(light: 0x1D1A15, dark: 0xEFE9DC)
    static let inkMuted = dynamic(light: 0x6E675B, dark: 0xA59E90)
    static let inkFaint = dynamic(light: 0xA39C8E, dark: 0x6B655A)
    static let rule = dynamic(light: 0x1D1A15, dark: 0xEFE9DC, lightAlpha: 0.12, darkAlpha: 0.14)

    /// The single accent (clay). Selection, recording, the one warm voice of the product.
    static let signal = dynamic(light: 0xB5532F, dark: 0xE0825C)
    static let sage = dynamic(light: 0x4F7A5E, dark: 0x7FB08D)  // success only

    /// The notch pill: the body must be true black to merge with the hardware notch.
    static let pillBody = Color.black
    static let pillInk = Color(nsColor: NSColor(hex: 0xF6F2E9))

    // MARK: space (4pt scale)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let huge: CGFloat = 48
    }

    // MARK: radius

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 18
    }

    // MARK: type: New York, SF Pro, SF Mono; five sizes

    enum Typeface {
        static let display = Font.system(size: 30, weight: .regular, design: .serif)
        static let title = Font.system(size: 17, weight: .semibold, design: .serif)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 12)
        static let captionStrong = Font.system(size: 12, weight: .medium)
        static let label = Font.system(size: 11, weight: .semibold)  // used uppercase and tracked
        static let mono = Font.system(size: 12, design: .monospaced)
    }

    // MARK: motion: calm, no overshoot

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let calm = Animation.easeOut(duration: 0.28)
        static let settle = Animation.spring(response: 0.45, dampingFraction: 0.92)
    }

    // MARK: the notch pill

    enum Pill {
        static let wing: CGFloat = 64  // width of each side beside the notch
        static let ear: CGFloat = 10  // the concave corner flare
        static let waveRow: CGFloat = 12  // height of the wave while recording
        static let recordingExtra: CGFloat = 20  // pill height below the notch while recording
        static let statusExtra: CGFloat = 24
        static let resultExtra: CGFloat = 28
        static let resultExtraTall: CGFloat = 46
        static let resultWidening: CGFloat = 40
        static let iconSize: CGFloat = 20
        static let floatingWidth: CGFloat = 150  // on a screen without a notch
    }
}

// MARK: - shared pieces

/// A one-point rule: structure without boxes.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 1)
    }
}

/// A small uppercase, tracked heading above a group.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.label)
            .tracking(1.0)
            .foregroundStyle(Theme.inkMuted)
    }
}

/// The mark: "Murmr" in the serif, with a small tracked "STREAM" beneath.
struct Wordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Murmr").font(Theme.Typeface.title).foregroundStyle(Theme.ink)
            Text("STREAM").font(Theme.Typeface.label).tracking(2.4).foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Primary action: solid ink on paper.
struct InkButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                if let symbol { Image(systemName: symbol).font(Theme.Typeface.captionStrong) }
                Text(title).font(Theme.Typeface.bodyStrong)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .foregroundStyle(Theme.paper)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.ink.opacity(hover ? 0.86 : 1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.Motion.quick, value: hover)
    }
}

/// Secondary action: a hairline outline.
struct OutlineButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                if let symbol { Image(systemName: symbol).font(Theme.Typeface.captionStrong) }
                Text(title).font(Theme.Typeface.body)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .foregroundStyle(Theme.ink)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.ink.opacity(hover ? 0.06 : 0)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.rule))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.Motion.quick, value: hover)
    }
}

/// A key or a path, set in mono inside a hairline box.
struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.mono)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.paperRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.rule))
    }
}

/// One line of a settings list: title and description on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.l)
            control()
        }
        .padding(.vertical, Theme.Space.m)
    }
}

/// A single-line text field: raised paper, hairline border, and the accent on focus.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.paperRaised))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(focused ? Theme.ink : Theme.rule, lineWidth: focused ? 1.5 : 1)
            )
            .animation(Theme.Motion.quick, value: focused)
    }
}

/// A quiet "x" that removes a list row. It carries a label for VoiceOver and a tooltip.
struct RemoveButton: View {
    let label: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Theme.Typeface.captionStrong)
                .foregroundStyle(hover ? Theme.ink : Theme.inkFaint)
                .frame(width: Theme.Space.xl, height: Theme.Space.xl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
        .animation(Theme.Motion.quick, value: hover)
    }
}

/// Rows of a list separated by hairlines (none above the first or below the last).
struct RuledList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Hairline() }
                row(item).padding(.vertical, Theme.Space.s)
            }
        }
    }
}

/// A thin progress bar: hairline track, accent fill.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule)
                Capsule().fill(Theme.signal).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: Theme.Space.xs)
        .animation(Theme.Motion.quick, value: value)
        .accessibilityValue("\(Int(max(0, min(1, value)) * 100)) phần trăm")
    }
}

/// Like `InputField`, but the text is hidden: for API keys.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typeface.mono)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.paperRaised))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(focused ? Theme.ink : Theme.rule, lineWidth: focused ? 1.5 : 1)
            )
            .animation(Theme.Motion.quick, value: focused)
    }
}

/// Choose one of a few options: the chosen one is solid ink, the rest are hairline outlines.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(chosen ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
                        .foregroundStyle(chosen ? Theme.paper : Theme.ink)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.s)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .fill(chosen ? Theme.ink : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(chosen ? Color.clear : Theme.rule)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Theme.Motion.quick, value: selection)
    }
}

/// A text link in the accent colour, with an arrow that says it leaves the app.
struct ExternalLink: View {
    let title: String
    let url: String

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: Theme.Space.xs) {
                    Text(title).font(Theme.Typeface.caption)
                    Image(systemName: "arrow.up.right").font(Theme.Typeface.label)
                }
                .foregroundStyle(Theme.signal)
            }
        }
    }
}

/// A closed field that opens a menu: the one control for "pick one of many" (a service, a model, a backup).
struct MenuField<Content: View>: View {
    let label: String
    var detail: String?  // quiet text before the chevron, such as "Đang tải danh sách…"
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(label).font(Theme.Typeface.body).foregroundStyle(Theme.ink)
                Spacer()
                if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.inkMuted) }
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
    }
}

// MARK: - Brand artwork (rendered to files by `MurmrStream --app-icon` and `--dmg-background`)

/// The app icon: the typographic mark ("Murmr" is set in the serif) reduced to its initial, in paper on ink, with a
/// small clay pill beneath it, the same pill the notch grows. macOS icons are an 824 pt body inside a 1024 pt canvas.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)
                .fill(Theme.ink)
                .frame(width: 824, height: 824)
            VStack(spacing: 34) {
                Text("M")
                    .font(.system(size: 560, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.paper)
                    .frame(height: 430)
                Capsule()
                    .fill(Theme.signal)
                    .frame(width: 176, height: 46)
            }
            .offset(y: -6)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// The picture behind the two icons in the disk image: where to drag, and the one extra step the first launch needs.
struct DmgBackgroundArt: View {
    static let size = CGSize(width: 660, height: 400)

    var body: some View {
        ZStack {
            Theme.paper
            VStack(spacing: 0) {
                Text("Kéo Murmr Stream vào Applications")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 38)
                Spacer()
                Text("Lần đầu mở, macOS sẽ chặn vì app chưa được Apple công chứng.\nVào System Settings → Privacy & Security → Open Anyway.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.bottom, 30)
            }
            // a thin arrow from where the app sits (x 180) to where Applications sits (x 480), on the icons' centre line
            Path { p in
                p.move(to: CGPoint(x: 262, y: 190))
                p.addLine(to: CGPoint(x: 398, y: 190))
                p.move(to: CGPoint(x: 386, y: 180))
                p.addLine(to: CGPoint(x: 398, y: 190))
                p.addLine(to: CGPoint(x: 386, y: 200))
            }
            .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
