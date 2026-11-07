import SwiftUI

/// The pill that grows out of the notch. It is the one dark object in the product; everything on it
/// is drawn in warm paper (`pillInk`) and the single accent (`signal`). See DESIGN.md.
///
///   idle        invisible (same size as the notch)
///   recording   wings beside the notch (app icon | recording dot and pronoun style), a slim wave underneath
///   processing  spinner and what it is doing ("Đang chép lời" / "Đang dọn văn")
///   done        check mark and the text that was pasted
struct NotchView: View {
    @ObservedObject var state: AppState
    @ObservedObject var layout: NotchLayout

    /// Concave "ears" where the pill meets the top edge, so it melts into the notch.
    /// Chosen in Settings; stored in UserDefaults.
    @AppStorage("notchEars") private var ears = true
    /// Which wave is drawn while recording; chosen in Settings.
    @AppStorage("waveStyle") private var waveStyleRaw = WaveStyle.flock.rawValue

    private var waveStyle: WaveStyle { WaveStyle(rawValue: waveStyleRaw) ?? .flock }
    private var usesEars: Bool { layout.hasNotch && ears }

    private func size(for phase: Phase) -> CGSize {
        let base = layout.hasNotch ? layout.notchWidth : Theme.Pill.floatingWidth
        let top = layout.topHeight
        let wing = Theme.Pill.wing
        switch phase {
        case .idle:
            return CGSize(width: base, height: top)
        case .recording:
            return CGSize(width: base + wing * 2, height: top + Theme.Pill.recordingExtra)
        case .transcribing, .cleaning:
            return CGSize(width: base + wing * 2, height: top + Theme.Pill.statusExtra)
        case .done(let text):
            return CGSize(width: base + wing * 2 + Theme.Pill.resultWidening,
                          height: top + (text.count > 50 ? Theme.Pill.resultExtraTall : Theme.Pill.resultExtra))
        case .notice, .error:
            return CGSize(width: base + wing * 2 + Theme.Pill.resultWidening, height: top + Theme.Pill.resultExtra)
        }
    }

    private var pillShape: AnyShape {
        guard layout.hasNotch else { return AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.lg)) }
        return ears
            ? AnyShape(EarShape(ear: Theme.Pill.ear, bottom: Theme.Radius.lg))
            : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: Theme.Radius.lg,
                                              bottomTrailingRadius: Theme.Radius.lg, topTrailingRadius: 0))
    }

    var body: some View {
        let s = size(for: state.phase)
        let visible = state.phase != .idle
        ZStack(alignment: .top) {
            pillShape
                .fill(Theme.pillBody)
                .frame(width: s.width + (usesEars ? Theme.Pill.ear * 2 : 0), height: s.height)
                .overlay(alignment: .top) { content(width: s.width) }
                .opacity(visible ? 1 : 0)
                .offset(y: layout.hasNotch ? 0 : Theme.Space.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(Theme.Motion.settle, value: state.phase)
        .animation(Theme.Motion.calm, value: visible)
    }

    // MARK: content

    private func content(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            topRow
            bottomRow
        }
        .frame(width: width)
        .clipped()
    }

    /// The strip level with the notch: only the two wings are visible, the middle is the notch.
    private var topRow: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: Theme.Pill.wing)
            Spacer(minLength: layout.hasNotch ? layout.notchWidth : 0)
            rightWing.frame(width: Theme.Pill.wing)
        }
        .frame(height: layout.topHeight)
    }

    private var leftWing: some View {
        Group {
            if let icon = state.appIcon {
                Image(nsImage: icon).resizable().frame(width: Theme.Pill.iconSize, height: Theme.Pill.iconSize)
            } else {
                Image(systemName: "mic.fill").font(Theme.Typeface.body).foregroundStyle(Theme.pillInk.opacity(0.8))
            }
        }
    }

    private var rightWing: some View {
        HStack(spacing: Theme.Space.xs) {
            if state.phase == .recording { RecordingDot() }
            if !styleLabel.isEmpty {
                Text(styleLabel)
                    .font(Theme.Typeface.label)
                    .foregroundStyle(Theme.pillInk.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    /// How pronouns will be written for this app (see style.go).
    private var styleLabel: String {
        switch state.style {
        case "casual": return "tao/mày"
        case "neutral": return "lịch sự"
        default: return ""
        }
    }

    @ViewBuilder private var bottomRow: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .recording:
            WaveView(style: waveStyle, level: state.level, levels: state.levels)
                .frame(height: Theme.Pill.waveRow)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.xs)
        case .transcribing:
            StatusLine(text: "Đang chép lời")
        case .cleaning:
            StatusLine(text: "Đang dọn văn")
        case .done(let text):
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "checkmark").foregroundStyle(Theme.pillInk)
                Text(text)
                    .foregroundStyle(Theme.pillInk)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typeface.captionStrong)
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)
        case .notice(let msg):
            Text(msg)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.pillInk.opacity(0.7))
                .padding(.top, Theme.Space.xs)
        case .error(let msg):
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.signal)
                Text(msg).foregroundStyle(Theme.pillInk).lineLimit(1).truncationMode(.tail)
            }
            .font(Theme.Typeface.captionStrong)
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)
        }
    }
}

// MARK: - waves

/// The wave shown while recording. All of them are short and tapered or faded at the ends,
/// drawn in `pillInk`; pick one in Settings.
enum WaveStyle: String, CaseIterable {
    case flock, line, bars, dots, ribbon, pulse

    var title: String {
        switch self {
        case .flock: return "Nét vẽ Murmr"
        case .line: return "Đường sóng mượt"
        case .bars: return "Vạch đối xứng mảnh"
        case .dots: return "Chuỗi chấm"
        case .ribbon: return "Dải lụa đặc"
        case .pulse: return "Chấm nhịp thở"
        }
    }
}

struct WaveView: View {
    let style: WaveStyle
    let level: CGFloat
    let levels: [CGFloat]

    var body: some View {
        switch style {
        case .flock: FlockWave(level: level)
        case .line: LineWave(level: level)
        case .bars: MirrorBars(levels: levels)
        case .dots: DotWave(levels: levels)
        case .ribbon: RibbonWave(levels: levels)
        case .pulse: PulseDots(level: level)
        }
    }
}

/// The brand's mark as a wave, behaving like the smooth-line style (three layers running at different speeds, tapering to
/// nothing at both ends, an amplitude that follows the voice and reaches most of the row) but drawn in the logo's hand:
/// instead of a sine, a chain of wing-beats, each a rounded arch that falls into a point (1 - 2|sin|). The main layer
/// fades in from the left and ends in clay. The swing is capped inside the frame, so no arch is ever cut off.
struct FlockWave: View {
    let level: CGFloat

    struct Layer {
        let arches: Double  // how many beats fit across (twice this many arches)
        let speed: Double
        let opacity: Double
        let lineWidth: CGFloat
        let share: Double  // of the full swing
    }

    static let layers: [Layer] = [
        Layer(arches: 4.4, speed: 2.6, opacity: 1.0, lineWidth: 1.7, share: 1.0),
        Layer(arches: 3.2, speed: -3.4, opacity: 0.5, lineWidth: 1.3, share: 0.7),
        Layer(arches: 5.6, speed: 4.2, opacity: 0.28, lineWidth: 1.0, share: 0.5),
    ]

    /// One layer's line at time `t`. Pure, so it can be checked without a window. Short typed steps on purpose: the older
    /// Swift compiler on GitHub's runner gives up on long mixed expressions.
    static func path(layer: Layer, level: CGFloat, size: CGSize, t: Double) -> Path {
        let midY: Double = Double(size.height) / 2
        let limit: Double = midY - 1.5  // the most a point may move from the middle and still stay inside the frame
        let amplitude: Double = 1.2 + pow(Double(level), 0.6) * (limit - 1.2)
        let steps: Int = max(2, Int(size.width / 2))
        var path = Path()
        for s in 0...steps {
            let x: Double = Double(s) / Double(steps)
            let taper: Double = sin(x * Double.pi)  // zero at both ends
            let phase: Double = x * 2 * Double.pi * layer.arches + t * layer.speed
            let beat: Double = 1 - 2 * abs(sin(phase))  // +1 at the point (down), -1 at the top of the arch
            let y: Double = midY + beat * amplitude * layer.share * taper
            let point = CGPoint(x: x * Double(size.width), y: y)
            if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                for (index, layer) in Self.layers.enumerated() {
                    let path = Self.path(layer: layer, level: level, size: size, t: t)
                    let style = StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round)
                    if index == 0 {
                        let stops: [Gradient.Stop] = [
                            Gradient.Stop(color: Theme.pillInk.opacity(0.35), location: 0),
                            Gradient.Stop(color: Theme.pillInk, location: 0.3),
                            Gradient.Stop(color: Theme.pillInk, location: 0.84),
                            Gradient.Stop(color: Theme.pillAccent, location: 0.9),
                            Gradient.Stop(color: Theme.pillAccent, location: 1),
                        ]
                        let shading = GraphicsContext.Shading.linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                        gc.stroke(path, with: shading, style: style)
                    } else {
                        gc.stroke(path, with: .color(Theme.pillInk.opacity(layer.opacity)), style: style)
                    }
                }
            }
        }
    }
}

/// Three thin sine lines of different speed and weight. The amplitude follows the voice and is
/// tapered to zero at both ends, so it reads as one soft ribbon rather than a graph.
struct LineWave: View {
    let level: CGFloat

    private struct Layer {
        let frequency: Double
        let speed: Double
        let opacity: Double
        let lineWidth: CGFloat
        let amplitude: Double  // share of the full amplitude
    }

    private let layers = [
        Layer(frequency: 1.6, speed: 2.4, opacity: 1.0, lineWidth: 1.6, amplitude: 1.0),
        Layer(frequency: 2.3, speed: -3.1, opacity: 0.5, lineWidth: 1.2, amplitude: 0.7),
        Layer(frequency: 3.1, speed: 4.0, opacity: 0.28, lineWidth: 1.0, amplitude: 0.5),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let midY = size.height / 2
                let amplitude = 1.2 + pow(Double(level), 0.6) * (Double(size.height) / 2 - 1.8)
                let steps = max(2, Int(size.width / 2))
                for layer in layers {
                    var path = Path()
                    for s in 0...steps {
                        let x = Double(s) / Double(steps)
                        let taper = sin(x * .pi)  // zero at both ends
                        let phase = x * 2 * .pi * layer.frequency + t * layer.speed
                        let point = CGPoint(x: x * Double(size.width),
                                            y: midY + CGFloat(sin(phase) * amplitude * layer.amplitude * taper))
                        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    gc.stroke(path, with: .color(Theme.pillInk.opacity(layer.opacity)),
                              style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// Slim bars mirrored around the centre line, one per recent sample: the newest sample is on the
/// right, older ones fade out to the left.
struct MirrorBars: View {
    let levels: [CGFloat]

    var body: some View {
        Canvas { gc, size in
            let count = levels.count
            let step = size.width / CGFloat(count)
            for (i, v) in levels.enumerated() {
                let height = max(2, size.height * pow(v, 0.7))
                let rect = CGRect(x: CGFloat(i) * step + step * 0.25, y: (size.height - height) / 2,
                                  width: step * 0.5, height: height)
                let fade = 0.2 + 0.8 * Double(i) / Double(max(1, count - 1))
                gc.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color(Theme.pillInk.opacity(fade)))
            }
        }
    }
}

/// A dotted wave: each dot rides a travelling sine whose height follows that moment's loudness.
struct DotWave: View {
    let levels: [CGFloat]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let count = levels.count
                let step = size.width / CGFloat(count)
                for (i, v) in levels.enumerated() {
                    let swing = Double(size.height) / 2 - 2
                    let y = size.height / 2 + CGFloat(sin(Double(i) * 0.55 + t * 4) * swing * pow(Double(v), 0.7))
                    let fade = 0.25 + 0.75 * Double(i) / Double(max(1, count - 1))
                    let r: CGFloat = 1.4
                    gc.fill(Path(ellipseIn: CGRect(x: CGFloat(i) * step + step / 2 - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Theme.pillInk.opacity(fade)))
                }
            }
        }
    }
}

/// A filled, mirrored ribbon through the recent loudness; it fades in from the left and
/// tapers to a point at both ends.
struct RibbonWave: View {
    let levels: [CGFloat]

    var body: some View {
        Canvas { gc, size in
            let count = levels.count
            let midY = size.height / 2
            let reach = size.height / 2 - 1
            func half(_ i: Int) -> CGFloat {
                let x = Double(i) / Double(max(1, count - 1))
                return max(0.6, reach * pow(levels[i], 0.7) * CGFloat(sin(x * .pi)))
            }
            var path = Path()
            for i in 0..<count {
                let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, count - 1)), y: midY - half(i))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            for i in stride(from: count - 1, through: 0, by: -1) {
                path.addLine(to: CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, count - 1)), y: midY + half(i)))
            }
            path.closeSubpath()
            gc.fill(path, with: .linearGradient(
                Gradient(colors: [Theme.pillInk.opacity(0.1), Theme.pillInk.opacity(0.9)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
    }
}

/// Five dots that swell with the voice, each on its own slow rhythm: the quietest option.
struct PulseDots: View {
    let level: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let n = 5
                let gap: CGFloat = 14
                let startX = (size.width - gap * CGFloat(n - 1)) / 2
                for i in 0..<n {
                    let breath = 0.7 + 0.3 * sin(t * 5 + Double(i) * 0.9)
                    let r = 1.8 + CGFloat(pow(Double(level), 0.6) * 4.2 * breath)
                    let c = CGPoint(x: startX + gap * CGFloat(i), y: size.height / 2)
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                            with: .color(Theme.pillInk.opacity(0.9)))
                }
            }
        }
    }
}

// MARK: - small parts

struct StatusLine: View {
    let text: String
    @State private var dots = 0

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Spinner()
            Text(text + String(repeating: ".", count: dots))
                .font(Theme.Typeface.captionStrong)
                .foregroundStyle(Theme.pillInk.opacity(0.85))
        }
        .padding(.top, Theme.Space.xs)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                dots = (dots + 1) % 4
            }
        }
    }
}

/// Drawn by hand because the system ProgressView ignores tint and renders dark grey on black.
struct Spinner: View {
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.85)
            .stroke(Theme.pillInk.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

/// The recording indicator, in the product's one accent colour.
struct RecordingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.signal)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Pill outline with concave "ears" at the top corners: the top edge is `2 * ear` wider than
/// the body, and each side curves inward as it comes down, like the notch itself.
struct EarShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - ear, y: ear), control: CGPoint(x: w - ear, y: 0))
        p.addLine(to: CGPoint(x: w - ear, y: h - bottom))
        p.addQuadCurve(to: CGPoint(x: w - ear - bottom, y: h), control: CGPoint(x: w - ear, y: h))
        p.addLine(to: CGPoint(x: ear + bottom, y: h))
        p.addQuadCurve(to: CGPoint(x: ear, y: h - bottom), control: CGPoint(x: ear, y: h))
        p.addLine(to: CGPoint(x: ear, y: ear))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: ear, y: 0))
        p.closeSubpath()
        return p
    }
}
