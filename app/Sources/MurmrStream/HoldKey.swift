import AppKit
import Foundation

/// The key held to dictate. The engine takes it as a spec (see holdkey.go): "mod:61" is a modifier on its own (the right
/// Option), "combo:49:c0000" is a key with modifiers (Control+Option+Space). The label is what people read.
struct HoldKey: Equatable {
    var spec: String
    var label: String

    static let standard = HoldKey(spec: "mod:61", label: "⌥ phải")

    nonisolated static var saved: HoldKey {
        let defaults = UserDefaults.standard
        guard let spec = defaults.string(forKey: "holdKeySpec"), let label = defaults.string(forKey: "holdKeyLabel") else { return standard }
        return HoldKey(spec: spec, label: label)
    }

    func save() {
        UserDefaults.standard.set(spec, forKey: "holdKeySpec")
        UserDefaults.standard.set(label, forKey: "holdKeyLabel")
    }

    var isStandard: Bool { spec == Self.standard.spec }
    var isModifierOnly: Bool { spec.hasPrefix("mod:") }

    /// What is worth knowing about this key, said once under it (nil when there is nothing to add).
    var note: String? {
        if !isModifierOnly {
            return "Khi bạn giữ tổ hợp này, nó không đến được app đang dùng. Nó cũng có thể trùng phím tắt của một app khác; phím ⌥, ⌘, ⌃ hay fn đứng một mình thì không trùng."
        }
        if spec == "mod:63" {
            return "Phím fn có thể mở Emoji hoặc Dictation của macOS. Tắt trong System Settings, Keyboard nếu bị vướng."
        }
        if spec != Self.standard.spec && spec != "mod:58" {
            return "Phím này hay nằm trong phím tắt (ví dụ ⌘C), nên app chờ một chút và bỏ qua nếu có phím khác bấm cùng."
        }
        return nil
    }
}

/// One key event, reduced to what the recogniser needs (so it can be tested without a keyboard).
struct KeyInput {
    enum Kind { case flags, down }
    let kind: Kind
    let keyCode: Int
    let flags: UInt  // NSEvent.ModifierFlags.rawValue, which also carries the left/right bits
    let characters: String  // the key without modifiers, for naming a letter
}

/// Works out which key or combination the person means while they press it: a modifier held and let go on its own, or a
/// key pressed with modifiers. It also refuses what would make dictation a nuisance, with the reason.
struct HoldKeyRecognizer {
    enum Outcome: Equatable {
        case none
        case commit(HoldKey)
        case reject(String)
        case cancel
    }

    static let shift: UInt = 0x20000, control: UInt = 0x40000, option: UInt = 0x80000, command: UInt = 0x100000
    private static let standardMods: UInt = shift | control | option | command
    private static let fnFlag: UInt = 0x800000

    /// key code -> (device flag, label) for the modifier keys that can be a dictation key on their own.
    static let modifierKeys: [Int: (mask: UInt, label: String)] = [
        61: (0x40, "⌥ phải"), 58: (0x20, "⌥ trái"), 54: (0x10, "⌘ phải"), 55: (0x8, "⌘ trái"),
        62: (0x2000, "⌃ phải"), 59: (0x1, "⌃ trái"), 60: (0x4, "⇧ phải"), 56: (0x2, "⇧ trái"), 63: (fnFlag, "fn"),
    ]

    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// ⌘ plus these is something macOS or every app already uses; taking it would break copy and paste, or worse.
    private static let reservedWithCommand: Set<Int> = [0, 6, 7, 8, 9, 12, 13, 4, 46, 48, 49]  // A Z X C V Q W H M Tab Space

    private var pending: Int?  // a modifier that is down on its own, waiting to see if it is let go alone

    static func glyphs(_ flags: UInt) -> String {
        (flags & control != 0 ? "⌃" : "") + (flags & option != 0 ? "⌥" : "") + (flags & shift != 0 ? "⇧" : "") + (flags & command != 0 ? "⌘" : "")
    }

    mutating func feed(_ e: KeyInput) -> Outcome {
        switch e.kind {
        case .down: return keyDown(e)
        case .flags: return flagsChanged(e)
        }
    }

    private mutating func keyDown(_ e: KeyInput) -> Outcome {
        pending = nil  // a key was pressed: it is a combination, not a modifier on its own
        let mods = e.flags & Self.standardMods
        if e.keyCode == 53 && mods == 0 { return .cancel }  // Esc
        let isFunctionKey = Self.functionKeys[e.keyCode] != nil
        if !isFunctionKey && mods & (Self.control | Self.option | Self.command) == 0 {
            return .reject("Phím này sẽ gõ ra chữ ở app đang dùng. Giữ thêm ⌘, ⌃ hoặc ⌥, hoặc dùng một phím chức năng (F1 đến F20).")
        }
        if mods == Self.command && Self.reservedWithCommand.contains(e.keyCode) {
            return .reject("Tổ hợp này là phím tắt quen thuộc của macOS, chọn tổ hợp khác.")
        }
        let name = Self.functionKeys[e.keyCode] ?? Self.specialKeys[e.keyCode] ?? e.characters.uppercased()
        guard !name.isEmpty else { return .reject("Không nhận ra phím này, thử phím khác.") }
        let label = (Self.glyphs(mods) + " " + name).trimmingCharacters(in: .whitespaces)
        return .commit(HoldKey(spec: "combo:\(e.keyCode):\(String(mods, radix: 16))", label: label))
    }

    private mutating func flagsChanged(_ e: KeyInput) -> Outcome {
        guard let key = Self.modifierKeys[e.keyCode] else { return .none }
        let isDown = e.flags & key.mask != 0
        if isDown {
            let others = (e.flags & Self.standardMods) & ~Self.ownStandardBit(e.keyCode)
            pending = others == 0 && pending == nil ? e.keyCode : nil  // alone, or the start of a chord
            return .none
        }
        guard pending == e.keyCode else { return .none }
        pending = nil
        return .commit(HoldKey(spec: "mod:\(e.keyCode)", label: key.label))
    }

    /// The device-independent flag a modifier key sets, so "this key and nothing else" can be told from a chord.
    private static func ownStandardBit(_ keyCode: Int) -> UInt {
        switch keyCode {
        case 54, 55: return command
        case 58, 61: return option
        case 59, 62: return control
        case 56, 60: return shift
        default: return 0
        }
    }
}

/// Listens, while the person is choosing, for the key or combination they press, and hands it to `onCommit`. It takes the
/// keys over (nothing reaches the window) until it is done, so choosing ⌘W does not close it.
///
/// Letters and function keys arrive as events. A modifier on its own (⌥ phải, ⌘ trái, fn) does not: macOS does not hand
/// those to a window's event monitor reliably, so the modifier state is read from the system a few dozen times a second
/// instead. That also debounces: a press is only seen if it lasts a sample, and nothing counts in the first moments, nor
/// anything that was already held when choosing began (the click, a previous key).
@MainActor
final class HoldKeyCapture: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var message: String?

    /// Seconds after choosing begins in which presses are ignored, so the click and a still-held key settle first.
    static let settle: TimeInterval = 0.25
    private static let sampleEvery: TimeInterval = 0.015

    private var monitor: Any?
    private var sampler: Timer?
    private var lastFlags: UInt = 0
    private var armedAt = Date.distantFuture
    private var recognizer = HoldKeyRecognizer()
    private var onCommit: (HoldKey) -> Void = { _ in }
    private var onActive: (Bool) -> Void = { _ in }

    /// `onActive(true)` when choosing begins and `onActive(false)` however it ends (a key chosen, Esc, the window closing,
    /// a second click): the app uses it to pause the dictation key, so pressing the current key to choose another does
    /// not start a recording.
    func start(onActive: @escaping (Bool) -> Void = { _ in }, onCommit: @escaping (HoldKey) -> Void) {
        stop()
        self.onCommit = onCommit
        self.onActive = onActive
        onActive(true)
        recognizer = HoldKeyRecognizer()
        message = nil
        listening = true
        lastFlags = Self.systemFlags()
        armedAt = Date().addingTimeInterval(Self.settle)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard Date() >= self.armedAt else { return nil }  // still settling: taken, not counted
            let input = KeyInput(kind: .down, keyCode: Int(event.keyCode), flags: event.modifierFlags.rawValue,
                                 characters: event.charactersIgnoringModifiers ?? "")
            let outcome = self.recognizer.feed(input)
            self.handle(outcome)
            return nil  // everything is taken while choosing
        }
        let timer = Timer(timeInterval: Self.sampleEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sampler?.invalidate()
        sampler = nil
        let wasListening = listening
        listening = false
        if wasListening { onActive(false) }
    }

    private static func systemFlags() -> UInt { UInt(CGEventSource.flagsState(.combinedSessionState).rawValue) }

    /// One look at the modifier keys: each one that went down or up since the last look is an event for the recogniser.
    private func sample() {
        let now = Self.systemFlags()
        let changed = now ^ lastFlags
        lastFlags = now
        guard changed != 0, Date() >= armedAt else { return }
        for (code, key) in HoldKeyRecognizer.modifierKeys.sorted(by: { $0.key < $1.key }) where changed & key.mask != 0 {
            let outcome = recognizer.feed(KeyInput(kind: .flags, keyCode: code, flags: now, characters: ""))
            handle(outcome)
            if !listening { return }
        }
    }

    private func handle(_ outcome: HoldKeyRecognizer.Outcome) {
        switch outcome {
        case .none: break
        case .reject(let why): message = why
        case .cancel: stop()
        case .commit(let key):
            stop()
            onCommit(key)
        }
    }
}
