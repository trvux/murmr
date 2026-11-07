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
        case .flock: FlockWave(levels: levels)
        case .line: LineWave(level: level)
        case .bars: MirrorBars(levels: levels)
        case .dots: DotWave(levels: levels)
        case .ribbon: RibbonWave(levels: levels)
        case .pulse: PulseDots(level: level)
        }
    }
}

/// The brand's mark as a wave: one continuous drawn line made of the logo's wing-beat curves joined end to end (each a
/// rounded arm that falls into a point, like the birds of the flock), so it keeps the logo's hand but is a single
/// stroke. Silence leaves it a calm, nearly flat line; the voice lifts and deepens each beat and sends a ripple along
/// it. It fades in from the left and ends in clay, and it is kept inside the frame, so no part is cut off.
struct FlockWave: View {
    let levels: [CGFloat]

    /// The line for the last `levels`, at time `t`, drawn into `size`. Pure, so it can be checked without a window.
    static func path(levels: [CGFloat], size: CGSize, line: CGFloat, t: Double) -> Path {
        // Every value is typed and every step is small: the older Swift compiler on GitHub's runner gives up on long
        // mixed CGFloat/Double expressions.
        let beats: Int = max(6, min(24, Int(size.width / 15)))
        let step: Int = max(1, levels.count / beats)
        let span: CGFloat = size.width / CGFloat(beats)
        let margin: CGFloat = line / 2 + 0.5
        let height: CGFloat = size.height

        func level(_ j: Int) -> CGFloat {  // joint j sits between beat j - 1 and j; the newest sample is on the right
            let back: Int = (beats - j) * step
            let i: Int = max(0, min(levels.count - 1, levels.count - 1 - back))
            let raw: CGFloat = levels.isEmpty ? 0 : levels[i]
            let v: CGFloat = pow(raw, 0.7)
            let phase: Double = t * 7 + Double(j) * 0.9
            let shimmer: CGFloat = CGFloat(0.78 + 0.22 * sin(phase))  // a ripple running along the line
            return min(1, v * shimmer)
        }
        func clamp(_ y: CGFloat) -> CGFloat { min(max(y, margin), height - margin) }

        let base: CGFloat = height / 2 + height * 0.12
        let lift: CGFloat = height * 0.3
        var joints: [CGFloat] = []
        for j in 0...beats { joints.append(clamp(base - level(j) * lift)) }

        var p = Path()
        p.move(to: CGPoint(x: 0, y: joints[0]))
        for k in 0..<beats {
            let both: CGFloat = level(k) + level(k + 1)
            let amp: CGFloat = min(1, 0.12 + both * 0.55)
            let x0: CGFloat = CGFloat(k) * span
            let x1: CGFloat = x0 + span
            let xm: CGFloat = x0 + span / 2
            let y0: CGFloat = joints[k]
            let y1: CGFloat = joints[k + 1]
            let dipY: CGFloat = clamp((y0 + y1) / 2 + span * 0.12 * amp)
            // the arm rises into an arch before it falls into the point, as in the logo
            func arch(_ from: CGFloat) -> CGFloat {
                let wanted: CGFloat = (from + dipY) / 2 - span * 0.34 * amp
                let top: CGFloat = (from + 2 * wanted + dipY) / 4  // where the curve actually peaks
                if top < margin { return (4 * margin - from - dipY) / 2 }
                return wanted
            }
            let c0 = CGPoint(x: x0 + span * 0.25, y: arch(y0))
            let c1 = CGPoint(x: x0 + span * 0.75, y: arch(y1))
            p.addQuadCurve(to: CGPoint(x: xm, y: dipY), control: c0)
            p.addQuadCurve(to: CGPoint(x: x1, y: y1), control: c1)
        }
        return p
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let line: CGFloat = 1.7
                let path = Self.path(levels: levels, size: size, line: line, t: t)
                let stops: [Gradient.Stop] = [
                    Gradient.Stop(color: Theme.pillInk.opacity(0.1), location: 0),
                    Gradient.Stop(color: Theme.pillInk.opacity(0.95), location: 0.72),
                    Gradient.Stop(color: Theme.pillInk, location: 0.86),
                    Gradient.Stop(color: Theme.pillAccent, location: 0.9),
                    Gradient.Stop(color: Theme.pillAccent, location: 1),
                ]
                let shading = GraphicsContext.Shading.linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                gc.stroke(path, with: shading, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
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
