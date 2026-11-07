package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
)

// Pronouns: how the speaker refers to themself and to the listener, which the recognizer tends to flatten ("tao" is
// heard as "tôi", "mày" as "bạn"). The app does not choose for anyone: out of the box pronouns are left exactly as
// recognised, and the user can define profiles ("tao / mày / tụi tao", "tôi / bạn", "anh / em"...) and say which one
// applies by default, in a given app, or when the window title contains some text.
//
// ~/.config/murmr/apps.txt, one line each (the file is re-read at every dictation):
//
//	profile <id> = <self> / <you> / <we>   define a profile; <you> and <we> are optional
//	default <id>                           used when no other rule applies (otherwise: keep)
//	<bundle id> <id>                       a rule for one app
//	title:<text in window title> <id>      a rule for window titles; it beats the app rule
//
// <id> is a profile's id or "keep" (leave pronouns as recognised). The old words "neutral" (= keep) and "casual"
// (= tao / mày / tụi tao) still work.
const profileKeepID = "keep"

// Profile is one way of addressing. The zero value, and "keep", mean "leave pronouns alone".
type Profile struct{ ID, Self, You, We string }

var profileKeep = Profile{ID: profileKeepID}

func (p Profile) IsKeep() bool {
	return p.ID == profileKeepID || (p.Self == "" && p.You == "" && p.We == "")
}

// Label is what the notch shows next to the recording dot ("tao / mày"); "" when pronouns are left alone.
func (p Profile) Label() string {
	if p.IsKeep() {
		return ""
	}
	parts := []string{}
	for _, w := range []string{p.Self, p.You} {
		if w != "" {
			parts = append(parts, w)
		}
	}
	return strings.Join(parts, " / ")
}

type titleRule struct{ contains, profile string }

// Pronouns is the parsed apps.txt.
type Pronouns struct {
	Profiles map[string]Profile
	Default  string
	Apps     map[string]string
	Titles   []titleRule
}

// cleanWord makes a user-typed pronoun safe to put in a prompt: one short plain word or phrase, no quotes or line breaks.
func cleanWord(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '"' || r == '\'' || r == '`' || r == '“' || r == '”' || r == '/' || r == '\\':
			continue
		case unicode.IsControl(r):
			b.WriteRune(' ')
		default:
			b.WriteRune(r)
		}
	}
	out := strings.Join(strings.Fields(b.String()), " ")
	if r := []rune(out); len(r) > 24 {
		out = string(r[:24])
	}
	return out
}

// ParsePronouns reads apps.txt text. Lines it does not understand are ignored (the Settings window keeps them as they were).
func ParsePronouns(text string) Pronouns {
	pr := Pronouns{Profiles: map[string]Profile{}, Apps: map[string]string{}}
	lines := strings.Split(text, "\n")

	// First the definitions, so a rule may come before the profile it names.
	for _, raw := range lines {
		t := strings.TrimSpace(raw)
		f := strings.Fields(t)
		if len(f) < 2 || strings.HasPrefix(t, "#") {
			continue
		}
		switch f[0] {
		case "profile":
			id := f[1]
			if id == profileKeepID || strings.ContainsAny(id, "/=") {
				continue
			}
			rest := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(strings.TrimPrefix(t, "profile")), id))
			rest = strings.TrimSpace(strings.TrimPrefix(rest, "="))
			parts := strings.Split(rest, "/")
			p := Profile{ID: id, Self: cleanWord(parts[0])}
			if len(parts) > 1 {
				p.You = cleanWord(parts[1])
			}
			if len(parts) > 2 {
				p.We = cleanWord(parts[2])
			}
			if p.Self != "" || p.You != "" {
				pr.Profiles[id] = p
			}
		case "default":
			pr.Default = f[1]
		}
	}

	known := func(id string) bool {
		_, ok := pr.Profiles[id]
		return ok || id == profileKeepID || id == "neutral" || id == "casual"
	}
	for _, raw := range lines {
		t := strings.TrimSpace(raw)
		f := strings.Fields(t)
		if len(f) < 2 || strings.HasPrefix(t, "#") || f[0] == "profile" || f[0] == "default" {
			continue
		}
		id := f[len(f)-1]
		if !known(id) {
			continue
		}
		if rest, ok := strings.CutPrefix(t, "title:"); ok {
			if text := strings.TrimSpace(strings.TrimSuffix(rest, id)); text != "" {
				pr.Titles = append(pr.Titles, titleRule{text, id})
			}
		} else if len(f) == 2 {
			pr.Apps[f[0]] = id
		}
	}
	return pr
}

// LoadPronouns reads the user's apps.txt (a missing file means no rules: pronouns are left alone).
func LoadPronouns() Pronouns {
	b, _ := os.ReadFile(appsPath())
	return ParsePronouns(string(b))
}

func (c Pronouns) HasTitleRules() bool { return len(c.Titles) > 0 }

func (c Pronouns) lookup(id string) Profile {
	if p, ok := c.Profiles[id]; ok {
		return p
	}
	switch id {
	case "casual":
		return Profile{ID: "casual", Self: "tao", You: "mày", We: "tụi tao"}
	default: // "", "keep", "neutral", or a name nobody defined
		return profileKeep
	}
}

// For picks the profile for where the text will be pasted: a window-title rule beats an app rule, which beats the default.
func (c Pronouns) For(ctx appCtx) Profile {
	if ctx.Title != "" {
		lower := strings.ToLower(ctx.Title)
		for _, r := range c.Titles {
			if strings.Contains(lower, strings.ToLower(r.contains)) {
				return c.lookup(r.profile)
			}
		}
	}
	if id, ok := c.Apps[ctx.Bundle]; ok {
		return c.lookup(id)
	}
	return c.lookup(c.Default)
}

// Prompt is appended to the cleanup system prompt for this dictation.
func (p Profile) Prompt() string {
	if p.IsKeep() {
		return `

Pronouns: keep every pronoun exactly as the recognizer wrote it (tôi, tao, mày, anh, em, ...). Do not formalize them, change register, or swap one pronoun for another, even if it seems inappropriate for the context.`
	}
	var roles, back []string
	if p.Self != "" {
		roles = append(roles, fmt.Sprintf("refers to themself as %q (I)", p.Self))
		back = append(back, fmt.Sprintf("the speaker -> %q", p.Self))
	}
	if p.You != "" {
		roles = append(roles, fmt.Sprintf("refers to the person addressed as %q (you)", p.You))
		back = append(back, fmt.Sprintf("the addressee -> %q", p.You))
	}
	if p.We != "" {
		roles = append(roles, fmt.Sprintf("refers to their own group as %q (we, not including the listener)", p.We))
		back = append(back, fmt.Sprintf(`"chúng ta" / "chúng tôi" -> %q`, p.We))
	}
	// whatever the user did not say is left exactly as recognised
	var leave []string
	if p.You == "" {
		leave = append(leave, "the pronouns for the person addressed")
	}
	if p.We == "" {
		leave = append(leave, `"chúng ta" and "chúng tôi"`)
	}
	rest := ""
	if len(leave) > 0 {
		rest = " Leave " + strings.Join(leave, " and ") + " exactly as the recognizer wrote them."
	}
	return "\n\nPronouns: the speaker always " + strings.Join(roles, ", ") + `. The recognizer often "normalizes" pronouns into "tôi", "mình", "bạn", "chúng ta", "chúng tôi" or similar. Convert them to the speaker's own words using the sentence roles: ` +
		strings.Join(back, "; ") + `. Keep "mình" when it clearly means an inclusive "we" (e.g. "mình merge luôn" = let's merge).` + rest + " Change no other pronoun."
}

// pronounPresets are starting points shown in Settings. Nothing here is applied unless the user adds it. They cover
// the common pairs by the relationship between speaker and listener (peers, older to younger, younger to older,
// formal), not any one person's habit.
func pronounPresets() []Profile {
	return []Profile{
		{Self: "tôi", You: "bạn", We: "chúng tôi"},
		{Self: "mình", You: "bạn", We: "chúng mình"},
		{Self: "mình", You: "cậu", We: "tụi mình"},
		{Self: "tớ", You: "cậu", We: "tụi tớ"},
		{Self: "tao", You: "mày", We: "tụi tao"},
		{Self: "tui", You: "bạn", We: "tụi tui"},
		{Self: "anh", You: "em"},
		{Self: "chị", You: "em"},
		{Self: "em", You: "anh"},
		{Self: "em", You: "chị"},
		{Self: "tôi", You: "anh"},
		{Self: "tôi", You: "chị"},
	}
}

var bundleRe = regexp.MustCompile(`bundleID="([^"]+)"`)

// frontApp returns the bundle id of the focused app (~20ms), or "".
func frontApp() string {
	asn, err := exec.Command("lsappinfo", "front").Output()
	if err != nil {
		return ""
	}
	out, err := exec.Command("lsappinfo", "info", "-only", "bundleid", strings.TrimSpace(string(asn))).Output()
	if err != nil {
		return ""
	}
	if m := bundleRe.FindSubmatch(out); m != nil {
		return string(m[1])
	}
	return ""
}

func appsPath() string { return filepath.Join(configDir(), "apps.txt") }

// appCtx is what we know about where the text will be pasted.
type appCtx struct{ Bundle, Title string }

// readAppCtx is slow (~0.3s for the title), so callers run it while the user speaks.
func readAppCtx() appCtx {
	c := appCtx{Bundle: frontApp()}
	if LoadPronouns().HasTitleRules() {
		c.Title = windowTitle() // only needed when the user wrote a rule that reads it
	}
	return c
}

func windowTitle() string {
	out, err := exec.Command("osascript", "-e",
		`tell application "System Events" to tell (first application process whose frontmost is true) to get name of front window`).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// pronouns are excluded from learning: they depend on who is listening, so a
// "tôi -> tao" pair learned in a terminal must not leak into a chat with a person.
var pronouns = map[string]bool{
	"tao": true, "mày": true, "tôi": true, "bạn": true, "mình": true, "ta": true,
	"chúng": true, "tụi": true, "tớ": true, "cậu": true,
}

// profileLabel names a profile for the engine log (never the user's text).
func profileLabel(p Profile) string {
	if p.IsKeep() {
		return profileKeepID
	}
	return p.ID
}
