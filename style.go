package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Style says who the speaker is talking to, which decides how pronouns are written.
//
//	casual:  talking to a computer or AI. Always tao / mày / tụi tao.
//	neutral: talking to people. Pronouns are left as recognised, tao/mày never introduced.
const (
	styleCasual  = "casual"
	styleNeutral = "neutral"
)

// Apps where the speaker talks to a computer/AI. Anything else (Zalo, Mail...) is neutral.
// Bundle ids were read from the installed apps. Override or extend in
// ~/.config/murmr/apps.txt, one rule per line:
//
//	<bundle id> casual|neutral
//	title:<text in window title> casual|neutral
var defaultCasualApps = map[string]bool{
	"com.mitchellh.ghostty":          true,
	"com.anthropic.claudefordesktop": true,
	"com.openai.codex":               true, // ChatGPT
	"com.jetbrains.goland":           true,
	"dev.zed.Zed":                    true,
	"net.imput.helium":               true, // browsers: casual unless the title says otherwise
	"com.google.Chrome":              true,
	"com.apple.Safari":               true,
}

// Window-title rules beat app rules: the same browser is an AI chat in one tab
// and Gmail (talking to people) in another.
var defaultTitleRules = []titleRule{{" - Gmail", styleNeutral}}

type titleRule struct{ contains, style string }

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
	if styleFor(appCtx{Bundle: c.Bundle}) == styleCasual {
		c.Title = windowTitle() // only casual apps can be overridden by a title rule
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

func styleFor(c appCtx) string {
	var userApps map[string]string
	titleRules := defaultTitleRules
	if b, err := os.ReadFile(appsPath()); err == nil {
		userApps = map[string]string{}
		var userTitle []titleRule
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			f := strings.Fields(line)
			if len(f) < 2 || (f[len(f)-1] != styleCasual && f[len(f)-1] != styleNeutral) {
				continue
			}
			style := f[len(f)-1]
			if rest, ok := strings.CutPrefix(line, "title:"); ok {
				userTitle = append(userTitle, titleRule{strings.TrimSpace(strings.TrimSuffix(rest, style)), style})
			} else if len(f) == 2 {
				userApps[f[0]] = style
			}
		}
		titleRules = append(userTitle, titleRules...)
	}
	if c.Title != "" {
		for _, r := range titleRules {
			if r.contains != "" && strings.Contains(strings.ToLower(c.Title), strings.ToLower(r.contains)) {
				return r.style
			}
		}
	}
	if s, ok := userApps[c.Bundle]; ok {
		return s
	}
	if defaultCasualApps[c.Bundle] {
		return styleCasual
	}
	return styleNeutral
}

// stylePrompt is appended to the cleanup system prompt for this dictation.
func stylePrompt(style string) string {
	if style == styleCasual {
		return `

Pronouns: the speaker is talking to a computer/AI and ALWAYS uses the informal Vietnamese pronouns "tao" (I), "mày" (you, the addressee) and "tụi tao" (we, exclusive). The recognizer often "normalizes" them into "tôi", "mình", "bạn", "chúng ta", "chúng tôi". Convert them back using the sentence roles: the speaker -> "tao", the addressee -> "mày", "chúng ta/chúng tôi" -> "tụi tao". Keep "mình" when it clearly means an inclusive "we" (e.g. "mình merge luôn" = let's merge).`
	}
	return `

Pronouns: keep every pronoun exactly as the recognizer wrote it (tôi, tao, mày, anh, em, ...). Do not formalize them, change register, or swap one pronoun for another, even if it seems inappropriate for the context. Never introduce "tao" or "mày" where the recognizer did not write them.`
}

// pronouns are excluded from learning: they depend on who is listening, so a
// "tôi -> tao" pair learned in a terminal must not leak into a chat with a person.
var pronouns = map[string]bool{
	"tao": true, "mày": true, "tôi": true, "bạn": true, "mình": true, "ta": true,
	"chúng": true, "tụi": true, "tớ": true, "cậu": true,
}
