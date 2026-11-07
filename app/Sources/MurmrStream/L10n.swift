import Foundation
import SwiftUI

/// The language of the app's own words (menus, pages, the notch). It is not the language you dictate in: Whisper
/// listens for whatever you speak.
enum UILanguage: String, CaseIterable, Identifiable {
    case auto, vi, en

    var id: String { rawValue }

    /// What a choice means right now: Vietnamese when the Mac's first preferred language is Vietnamese, English
    /// otherwise. A fixed choice stays as it is.
    static func resolve(_ choice: UILanguage, preferred: [String] = Locale.preferredLanguages) -> UILanguage {
        switch choice {
        case .vi, .en: return choice
        case .auto: return (preferred.first ?? "").lowercased().hasPrefix("vi") ? .vi : .en
        }
    }
}

/// Looks words up in the language files (`Resources/<lang>.lproj/Localizable.strings`). The key is the Vietnamese text
/// the code was written with, so Vietnamese needs no file and a word missing from the English file shows up in
/// Vietnamese (`scripts/check-strings.sh` keeps that from happening).
enum L10n {
    nonisolated(unsafe) static var choice: UILanguage = saved

    static var saved: UILanguage { UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .auto }

    static func save(_ choice: UILanguage) {
        self.choice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "uiLanguage")
    }

    /// `.vi` or `.en`, never `.auto`.
    static var current: UILanguage { UILanguage.resolve(choice) }

    /// For SwiftUI's own lookups of literal text: `.environment(\.locale, L10n.locale)` at the root of a window.
    static var locale: Locale { Locale(identifier: current.rawValue) }

    private static func bundle(_ language: UILanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    static func tr(_ key: String, in language: UILanguage? = nil) -> String {
        let language = language ?? current
        guard language == .en, let bundle = bundle(.en) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// With values: the key holds `%@` (text) or `%d` (whole number) where they go.
    static func tr(_ key: String, _ args: CVarArg..., in language: UILanguage? = nil) -> String {
        String(format: tr(key, in: language), arguments: args)
    }
}

/// Shorthand for `L10n.tr`, used for words that reach the screen as plain `String`s. (`Text("...")` with a literal
/// is looked up by SwiftUI itself.)
func tr(_ key: String) -> String { L10n.tr(key) }
func tr(_ key: String, _ args: CVarArg...) -> String { String(format: L10n.tr(key), arguments: args) }

/// Words with their values, kept apart until they are shown, so something already on screen (the engine's status, a
/// download line) changes language together with the rest when the person switches.
struct Say: Equatable {
    var key: String
    var args: [String] = []

    init(_ key: String, _ args: String...) {
        self.key = key
        self.args = args
    }

    var text: String { args.isEmpty ? tr(key) : String(format: tr(key), arguments: args.map { $0 as CVarArg }) }
}
