package main

import (
	"os"
	"regexp"
	"strings"
)

// Dictionary is the user's personal vocabulary (names, jargon). Each line of
// the file is either "Term" or "wrong -> Right"; '#' starts a comment.
type Dictionary struct {
	Terms []string
	Hints []Pair // learned from history; soft hints for the LLM, never hard-replaced
	fixes []fix
}

type fix struct {
	re *regexp.Regexp
	to string
}

func LoadDictionary(path string) *Dictionary {
	d := &Dictionary{}
	b, err := os.ReadFile(path)
	if err != nil {
		return d // no file is fine
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if from, to, ok := strings.Cut(line, "->"); ok {
			from, to = strings.TrimSpace(from), strings.TrimSpace(to)
			if from == "" || to == "" {
				continue
			}
			d.Terms = append(d.Terms, to)
			d.fixes = append(d.fixes, fix{regexp.MustCompile("(?i)" + regexp.QuoteMeta(from)), to})
			continue
		}
		d.Terms = append(d.Terms, line)
	}
	return d
}

// Apply runs the deterministic "wrong -> Right" replacements.
func (d *Dictionary) Apply(s string) string {
	for _, f := range d.fixes {
		s = f.re.ReplaceAllLiteralString(s, f.to)
	}
	return s
}

// WhisperPrompt biases decoding toward the user's vocabulary. Whisper only
// reads the tail of a ~224-token prompt, so the list is capped.
func (d *Dictionary) WhisperPrompt(base string) string {
	if len(d.Terms) == 0 {
		return base
	}
	list := strings.Join(d.Terms, ", ")
	if r := []rune(list); len(r) > 500 {
		list = string(r[:500])
	}
	return base + " Từ vựng: " + list + "."
}

// CleanupSystem extends the LLM system prompt with the vocabulary.
func (d *Dictionary) CleanupSystem(base string) string {
	base += d.hintsPrompt()
	if len(d.Terms) == 0 {
		return base
	}
	return base + "\n\nPersonal vocabulary (names and terms the speaker uses): " +
		strings.Join(d.Terms, "; ") +
		".\nSpeech recognition often mishears these. If a word or phrase in the transcript sounds like one of them " +
		"(compare by pronunciation, ignoring Vietnamese tone marks), replace it with the exact spelling above."
}

// hintsPrompt lists recurring mishearings learned from past dictations. They are
// offered as hints only: the LLM must still check that the context fits, so a
// real word like "boot" is not rewritten when the speaker truly meant it.
func (d *Dictionary) hintsPrompt() string {
	if len(d.Hints) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("\n\nRecurring recognition mistakes for this speaker (heard => usually meant). " +
		"Apply one only when the surrounding context makes the 'meant' reading plausible:\n")
	for i, h := range d.Hints {
		if i == 30 {
			break
		}
		b.WriteString("- \"" + h.From + "\" => \"" + h.To + "\"\n")
	}
	return strings.TrimRight(b.String(), "\n")
}
