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
    static let pillAccent = Color(nsColor: NSColor(hex: 0xE0825C))  // the clay, lifted to read on black

    /// A colour on the way from the pill's paper to its clay: 0 is paper, 1 is clay. Blended in sRGB by hand because
    /// Color.mix needs macOS 15 and the app runs on 14. The wave uses it so that louder speech is richer in colour, not darker
    /// (darker would fade into the black pill).
    static func pillBlend(_ amount: Double) -> Color {
        let t = min(1, max(0, amount))
        let paper: (Double, Double, Double) = (0xF6, 0xF2, 0xE9)
        let clay: (Double, Double, Double) = (0xE0, 0x82, 0x5C)
        let r: Double = (paper.0 + (clay.0 - paper.0) * t) / 255
        let g: Double = (paper.1 + (clay.1 - paper.1) * t) / 255
        let b: Double = (paper.2 + (clay.2 - paper.2) * t) / 255
        return Color(.sRGB, red: r, green: g, blue: b)
    }

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

/// One wing-beat: two curved arms that meet at the body, like a bird seen from a distance. The brand's mark is a
/// flock of these (a murmuration: "Murmr" is its first syllables), one of them in the accent colour.
struct WingBeat: Shape {
    /// 1 is the brand's resting "v" (the flock in the logo); 0 flattens the arms into a line, so a bird can flap.
    var amp: CGFloat = 1

    func path(in r: CGRect) -> Path {
        let w = r.width
        let arm = 0.40 * w - 0.08 * w * amp, control = 0.40 * w - 0.36 * w * amp, dip = 0.40 * w + 0.10 * w * amp
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + arm))
        p.addQuadCurve(to: CGPoint(x: r.minX + 0.5 * w, y: r.minY + dip), control: CGPoint(x: r.minX + 0.25 * w, y: r.minY + control))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + arm), control: CGPoint(x: r.minX + 0.75 * w, y: r.minY + control))
        return p
    }
}

/// A flock drawn on a canvas: each bird has a centre (x, y as fractions of the canvas) and a width (a fraction of the
/// canvas width). `weight` is the stroke as a fraction of a bird's width: thin for large art, heavier for small icons.
struct Murmuration: View {
    struct Bird {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var accent = false
    }

    var birds: [Bird]
    var weight: CGFloat = 0.175
    var tone: Color = Theme.ink
    var accent: Color = Theme.signal

    var body: some View {
        GeometryReader { g in
            ForEach(Array(birds.enumerated()), id: \.offset) { _, b in
                let w = b.size * g.size.width
                WingBeat()
                    .stroke(b.accent ? accent : tone, style: StrokeStyle(lineWidth: max(1.4, w * weight), lineCap: .round, lineJoin: .round))
                    .frame(width: w, height: w * 0.56)
                    .position(x: b.x * g.size.width, y: b.y * g.size.height)
            }
        }
    }

    /// The brand's flock, exactly as drawn in the chosen concept "D": eight birds flowing up and to the right, big and
    /// near at the lower left, small and far at the upper right, the fifth in the accent colour. Positions are fractions
    /// of a square canvas; the stroke is 17.5% of a bird's width.
    static let d: [Bird] = [
        Bird(x: 0.1933, y: 0.6733, size: 0.1333), Bird(x: 0.3267, y: 0.5467, size: 0.12), Bird(x: 0.4733, y: 0.4667, size: 0.104),
        Bird(x: 0.62, y: 0.4267, size: 0.088), Bird(x: 0.74, y: 0.3533, size: 0.072, accent: true), Bird(x: 0.2667, y: 0.4, size: 0.08),
        Bird(x: 0.4333, y: 0.6333, size: 0.0933), Bird(x: 0.5867, y: 0.5333, size: 0.0733),
    ]

    /// The same flock, scaled up about its own centre so it spans `width` of the canvas, and centred on it. Nothing
    /// about the arrangement changes: it is the whole picture made bigger.
    static func centered(_ birds: [Bird], width: CGFloat) -> [Bird] {
        let left = birds.map { $0.x - $0.size / 2 }.min() ?? 0, right = birds.map { $0.x + $0.size / 2 }.max() ?? 1
        let top = birds.map { $0.y - $0.size * 0.28 }.min() ?? 0, bottom = birds.map { $0.y + $0.size * 0.28 }.max() ?? 1
        let k = width / (right - left)
        let cx = (left + right) / 2, cy = (top + bottom) / 2
        return birds.map { Bird(x: 0.5 + ($0.x - cx) * k, y: 0.5 + ($0.y - cy) * k, size: $0.size * k, accent: $0.accent) }
    }
}

/// The app icon: the flock on paper, in the same ink and clay as the rest of the app. macOS icons are an 824 pt body
/// inside a 1024 pt canvas.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)
                .fill(Theme.paper)
                .frame(width: 824, height: 824)
            RoundedRectangle(cornerRadius: 184, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.14), lineWidth: 3)  // so a paper icon still has an edge on a light desktop
                .frame(width: 824, height: 824)
            Murmuration(birds: Murmuration.centered(Murmuration.d, width: 0.8))
                .frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// The wide banner at the top of the README: the name on the left and a flock streaming away to the right.
struct BannerArt: View {
    static let size = CGSize(width: 1600, height: 420)

    var body: some View {
        ZStack {
            Theme.paper
            Murmuration(birds: Murmuration.centered(Murmuration.d, width: 0.9))
                .frame(width: 400, height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 150)
            VStack(alignment: .leading, spacing: 14) {
                Text("Murmr")
                    .font(.system(size: 92, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("STREAM")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(9)
                    .foregroundStyle(Theme.inkMuted)
                Text("Giữ phím, nói, thả ra: chữ hiện ra ở app đang dùng.")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 96)
        }
        .frame(width: Self.size.width, height: Self.size.height)
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
                VStack(spacing: 10) {
                    Text("Lần đầu mở bị chặn? Vào System Settings → Privacy & Security, kéo xuống mục Security, rồi bấm:")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                    // what that row looks like in macOS, so it is recognised when it appears
                    HStack {
                        Text("“Murmr Stream” was blocked to protect your Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Open Anyway")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.paperSunken))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.signal, lineWidth: 1.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(width: 480)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.paperRaised))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.rule))
                }
                .padding(.bottom, 22)
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

// MARK: - Mascot

enum MascotMood { case idle, listening, speaking, done, oops, sleeping }

extension Theme {
    /// The mascot keeps its own colours in both appearances: dark body, pale belly. In the dark appearance the body is
    /// lifted a little so its outline does not vanish into the window.
    static let mascotBody = dynamic(light: 0x1D1A15, dark: 0x3A342C)
    static let mascotPale = dynamic(light: 0xF6F2E9, dark: 0xF6F2E9)
    static let mascotPupil = dynamic(light: 0x1D1A15, dark: 0x1D1A15)
}

/// The mascot, a plump bird from the flock (chosen: round body, pale belly, small wings, one tuft, clay beak and feet).
/// Its face is two eyes and a beak; the mood changes the eyes, the beak, and a few marks around it.
struct Mascot: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 120

    var body: some View {
        let u = size / 100
        ZStack(alignment: .topLeading) {
            ForEach([39.0, 61.0], id: \.self) { x in
                Capsule().fill(Theme.signal).frame(width: 10 * u, height: 5 * u).offset(x: (x - 5) * u, y: 91 * u)
            }
            Ellipse().fill(Theme.mascotBody).frame(width: 15 * u, height: 28 * u)
                .rotationEffect(.degrees(mood == .done ? 40 : 16)).offset(x: 7 * u, y: (mood == .done ? 44 : 50) * u)
            Ellipse().fill(Theme.mascotBody).frame(width: 15 * u, height: 28 * u)
                .rotationEffect(.degrees(mood == .done ? -40 : -16)).offset(x: 78 * u, y: (mood == .done ? 44 : 50) * u)
            Path { p in
                p.move(to: CGPoint(x: 50 * u, y: 21 * u))
                p.addQuadCurve(to: CGPoint(x: 55 * u, y: 8 * u), control: CGPoint(x: 49 * u, y: 13 * u))
            }.stroke(Theme.mascotBody, style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))
            Ellipse().fill(Theme.mascotBody).frame(width: 82 * u, height: 76 * u).offset(x: 9 * u, y: 18 * u)
            Ellipse().fill(Theme.mascotPale).frame(width: 48 * u, height: 40 * u).offset(x: 26 * u, y: 52 * u)
            eyes(u)
            beak(u)
            marks(u)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .rotationEffect(.degrees(mood == .listening ? 5 : 0), anchor: .bottom)
        .animation(Theme.Motion.calm, value: mood)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func eyes(_ u: CGFloat) -> some View {
        ForEach([35.0, 65.0], id: \.self) { cx in
            switch mood {
            case .done:  // happy: an arch
                Path { p in
                    p.move(to: CGPoint(x: (cx - 7) * u, y: 51 * u))
                    p.addQuadCurve(to: CGPoint(x: (cx + 7) * u, y: 51 * u), control: CGPoint(x: cx * u, y: 38 * u))
                }.stroke(Theme.mascotPale, style: StrokeStyle(lineWidth: 3.4 * u, lineCap: .round))
            case .sleeping:  // closed: a smile-shaped line
                Path { p in
                    p.move(to: CGPoint(x: (cx - 7) * u, y: 46 * u))
                    p.addQuadCurve(to: CGPoint(x: (cx + 7) * u, y: 46 * u), control: CGPoint(x: cx * u, y: 55 * u))
                }.stroke(Theme.mascotPale, style: StrokeStyle(lineWidth: 3.4 * u, lineCap: .round))
            default:
                let big: CGFloat = mood == .listening ? 21 : 19
                let pupil: CGFloat = mood == .oops ? 5 : (mood == .listening ? 12 : 10)
                let look: CGPoint = mood == .listening ? CGPoint(x: -1.5, y: -2) : (mood == .oops ? .zero : CGPoint(x: 1.5, y: 1))
                Circle().fill(Theme.mascotPale).frame(width: big * u, height: big * u).offset(x: (cx - big / 2) * u, y: (47 - big / 2) * u)
                Circle().fill(Theme.mascotPupil).frame(width: pupil * u, height: pupil * u)
                    .offset(x: (cx - pupil / 2 + look.x) * u, y: (47 - pupil / 2 + look.y) * u)
            }
        }
    }

    @ViewBuilder private func beak(_ u: CGFloat) -> some View {
        if mood == .speaking {  // open: the upper beak, a dark mouth, a small lower beak
            Ellipse().fill(Theme.mascotPupil).frame(width: 12 * u, height: 8 * u).offset(x: 44 * u, y: 59.5 * u)
            Poly(points: [(43, 52), (57, 52), (50, 59)]).fill(Theme.signal).frame(width: size, height: size)
            Capsule().fill(Theme.signal).frame(width: 11 * u, height: 3.2 * u).offset(x: 44.5 * u, y: 66.5 * u)
        } else {
            Poly(points: [(43, 53), (57, 53), (50, 63)]).fill(Theme.signal).frame(width: size, height: size)
        }
    }

    @ViewBuilder private func marks(_ u: CGFloat) -> some View {
        switch mood {
        case .listening:  // sound arriving from the left
            ForEach(0..<2) { i in
                Path { p in
                    p.addArc(center: CGPoint(x: 30 * u, y: 42 * u), radius: CGFloat(30 + i * 9) * u, startAngle: .degrees(158), endAngle: .degrees(202), clockwise: false)
                }.stroke(Theme.signal, style: StrokeStyle(lineWidth: 3 * u, lineCap: .round)).opacity(1 - Double(i) * 0.45)
            }
        case .speaking:  // sound leaving to the right, outside the body (the mirror of "listening")
            ForEach(0..<2) { i in
                Path { p in
                    p.addArc(center: CGPoint(x: 70 * u, y: 42 * u), radius: CGFloat(30 + i * 9) * u, startAngle: .degrees(-22), endAngle: .degrees(22), clockwise: false)
                }.stroke(Theme.signal, style: StrokeStyle(lineWidth: 3 * u, lineCap: .round)).opacity(1 - Double(i) * 0.45)
            }
        case .oops:  // a drop of worry
            Path { p in
                p.move(to: CGPoint(x: 84 * u, y: 20 * u))
                p.addQuadCurve(to: CGPoint(x: 90 * u, y: 32 * u), control: CGPoint(x: 90 * u, y: 24 * u))
                p.addQuadCurve(to: CGPoint(x: 78 * u, y: 32 * u), control: CGPoint(x: 84 * u, y: 38 * u))
                p.addQuadCurve(to: CGPoint(x: 84 * u, y: 20 * u), control: CGPoint(x: 78 * u, y: 24 * u))
            }.fill(Theme.signal)
        case .sleeping:  // z z
            Text("z").font(.system(size: 16 * u, weight: .semibold, design: .serif)).foregroundStyle(Theme.inkMuted).offset(x: 80 * u, y: 8 * u)
            Text("z").font(.system(size: 11 * u, weight: .semibold, design: .serif)).foregroundStyle(Theme.inkFaint).offset(x: 92 * u, y: -2 * u)
        default:
            EmptyView()
        }
    }
}

/// A filled polygon from points in a 100 x 100 box (used for the beak).
struct Poly: Shape {
    var points: [(CGFloat, CGFloat)]
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = r.width / 100
        p.move(to: CGPoint(x: points[0].0 * s, y: points[0].1 * s))
        for q in points.dropFirst() { p.addLine(to: CGPoint(x: q.0 * s, y: q.1 * s)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - First-launch guide (README and release page)

/// The three steps for the one-time "Open Anyway", drawn in the app's own style with small copies of what macOS shows at
/// each step, so each is recognised when it appears. Rendered by `MurmrStream --brand-guide`.
struct GuideArt: View {
    static let size = CGSize(width: 1200, height: 820)

    var body: some View {
        ZStack {
            Theme.paper
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 28) {
                    Mascot(mood: .oops, size: 124)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Lần đầu mở, macOS sẽ chặn")
                            .font(.system(size: 40, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("Vì app chưa được Apple công chứng. Chỉ cần làm một lần, ba bước.")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    step(1, "Mở Murmr Stream. Khi macOS báo không xác minh được, bấm Done.") { dialog }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    step(2, "Mở System Settings, chọn Privacy & Security, kéo xuống mục Security.") { sidebar }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    step(3, "Bấm Open Anyway cạnh dòng “Murmr Stream was blocked”, rồi xác nhận bằng mật khẩu hoặc Touch ID.") { blockedRow }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                }
            }
            .padding(.horizontal, 56)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func step<M: View>(_ n: Int, _ text: String, @ViewBuilder _ mock: () -> M) -> some View {
        HStack(alignment: .center, spacing: 24) {
            Text("\(n)")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.paper)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.ink))
            Text(text)
                .font(.system(size: 21))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 440, alignment: .leading)
            Spacer(minLength: 0)
            mock()
        }
        .padding(.vertical, 24)
    }

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    private var dialog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.shield").font(.system(size: 30)).foregroundStyle(Theme.signal)
            Text("“Murmr Stream” Not Opened").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Apple could not verify “Murmr Stream” is free of malware that may harm your Mac.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            Text("Done")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(Capsule().fill(Theme.ink))
        }
        .padding(16)
        .frame(width: 330)
        .background(card.fill(Theme.paperRaised))
        .overlay(card.strokeBorder(Theme.rule))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([("Appearance", false), ("Privacy & Security", true), ("Desktop & Dock", false)], id: \.0) { name, selected in
                HStack(spacing: 10) {
                    Image(systemName: selected ? "hand.raised.fill" : "circle.grid.2x2").font(.system(size: 14)).foregroundStyle(selected ? Theme.paper : Theme.inkMuted)
                    Text(name).font(.system(size: 14, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.paper : Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.ink : Color.clear))
            }
            Text("Security").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).padding(.top, 8).padding(.horizontal, 12)
        }
        .padding(12)
        .frame(width: 330)
        .background(card.fill(Theme.paperRaised))
        .overlay(card.strokeBorder(Theme.rule))
    }

    private var blockedRow: some View {
        HStack {
            Text("“Murmr Stream” was blocked\nto protect your Mac.").font(.system(size: 14)).foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Text("Open Anyway")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paperSunken))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.signal, lineWidth: 2))
        }
        .padding(16)
        .frame(width: 330)
        .background(card.fill(Theme.paperRaised))
        .overlay(card.strokeBorder(Theme.rule))
    }
}

/// The mascot with one short line beside it: the app's voice in empty, waiting and failed states.
struct MascotNote: View {
    var mood: MascotMood
    var text: String
    var size: CGFloat = 56
    var tone: Color = Theme.inkMuted

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Mascot(mood: mood, size: size).frame(width: size, height: size)
            Text(text)
                .font(Theme.Typeface.caption)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// The flock line at silence, soft and loud on black, at the pill's real height (12 pt) and the settings tile's (24 pt),
/// with the frame outlined so a stroke cut off by it shows. Rendered by `MurmrStream --wave-strip`.
struct WaveStripArt: View {
    private func row(_ label: String, _ base: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 14) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.inkMuted).frame(width: 70, alignment: .leading)
            FlockWave(level: base)
                .frame(width: 280, height: height)
                .overlay(Rectangle().strokeBorder(Color.red.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.pillBody)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("im lặng", 0.02, height: 12)
            row("nói thường", 0.3, height: 12)
            row("nói to", 0.9, height: 12)
            row("to (tile)", 0.3, height: 24)
        }
        .padding(16)
        .background(Theme.paper)
    }
}
