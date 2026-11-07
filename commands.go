package main

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"sort"
	"strings"
)

func runCommand(name string, args []string) error {
	switch name {
	case "report":
		return cmdReport()
	case "forget":
		return cmdForget(args)
	case "hints":
		return cmdHints()
	case "styles":
		return cmdStyles()
	case "drill":
		return cmdDrill(args)
	case "progress":
		return cmdProgress()
	case "score":
		return cmdScore(args)
	case "clean":
		return cmdClean(args)
	case "models":
		return cmdModels(args)
	case "providers":
		return cmdProviders()
	case "version":
		fmt.Println("murmr", version)
		return nil
	case "fetch-models":
		return cmdFetchModels()
	default:
		return fmt.Errorf("unknown command %q (try: report, forget, hints, styles, drill, progress, score, clean, models, providers, fetch-models, version)", name)
	}
}

func cmdReport() error {
	hist, err := LoadHistory(historyPath())
	if err != nil {
		return err
	}
	if len(hist) == 0 {
		fmt.Println("No history yet. Dictate for a few days, then run this again.")
		return nil
	}
	fmt.Printf("%d dictations, %s to %s\n\n", len(hist),
		hist[0].Time.Format("2006-01-02"), hist[len(hist)-1].Time.Format("2006-01-02"))

	pairs := LearnPairs(hist, LoadIgnored(ignoredPath()), 2)
	fmt.Println("Recurring mishearings (Whisper heard => you meant):")
	if len(pairs) == 0 {
		fmt.Println("  none yet")
	}
	for _, p := range pairs {
		note := ""
		if p.Count < learnMinCount {
			note = "  (not applied yet, needs " + fmt.Sprint(learnMinCount) + ")"
		}
		fmt.Printf("  %3dx  %s => %s%s\n", p.Count, p.From, p.To, note)
	}

	weak := map[string]int{}
	for _, e := range hist {
		for _, w := range e.Weak {
			weak[strings.ToLower(w)]++
		}
	}
	type kv struct {
		w string
		n int
	}
	var ws []kv
	for w, n := range weak {
		if n >= 2 {
			ws = append(ws, kv{w, n})
		}
	}
	slices.SortFunc(ws, func(a, b kv) int { return cmp.Or(cmp.Compare(b.n, a.n), cmp.Compare(a.w, b.w)) })
	fmt.Println("\nWords Whisper was often unsure about:")
	if len(ws) == 0 {
		fmt.Println("  none yet")
	}
	for i, x := range ws {
		if i == 20 {
			break
		}
		fmt.Printf("  %3dx  %s\n", x.n, x.w)
	}
	fmt.Println("\nWrong hint? `murmr forget \"<heard text>\"` stops it being used.")
	return nil
}

func cmdForget(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: murmr forget \"<heard text>\"")
	}
	f, err := os.OpenFile(ignoredPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, strings.Join(args, " "))
	return err
}

// cmdClean runs the cleanup step on given text, to try prompt changes without speaking.
func cmdClean(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf(`usage: murmr clean [--casual] "<raw transcript>"`)
	}
	dict, cleaner := loadCleaner()
	if cleaner == nil {
		return fmt.Errorf("no cleanup provider configured (add a key in Settings, or set MURMR_CLEANUP and its key; see: murmr providers)")
	}
	style := styleNeutral
	if args[0] == "--casual" {
		style, args = styleCasual, args[1:]
	}
	ctx, cancel := context.WithTimeout(context.Background(), cleanupTimeout)
	defer cancel()
	out, err := cleaner.Clean(ctx, dict.Apply(strings.Join(args, " ")), stylePrompt(style))
	if err != nil {
		return err
	}
	fmt.Println(dict.Apply(out))
	return nil
}

// hintJSON is one learned "heard => meant" pair, as the app's Settings window shows it.
type hintJSON struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Count  int    `json:"count"`
	Active bool   `json:"active"` // seen often enough to be sent to the LLM as a hint
}

// hintsJSON lists pairs seen at least twice (the report's view), most frequent first.
func hintsJSON(hist []Entry, ignored map[string]bool) ([]byte, error) {
	out := []hintJSON{} // never nil, so an empty list encodes as [] and not null
	for _, p := range LearnPairs(hist, ignored, 2) {
		out = append(out, hintJSON{From: p.From, To: p.To, Count: p.Count, Active: p.Count >= learnMinCount})
	}
	return json.Marshal(out)
}

func cmdHints() error {
	hist, err := LoadHistory(historyPath())
	if err != nil {
		return err
	}
	b, err := hintsJSON(hist, LoadIgnored(ignoredPath()))
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

// stylesJSON describes the built-in pronoun-style rules, so the app's Settings window can show which
// apps are casual (tao/mày) by default without keeping a second copy of the list.
func stylesJSON() ([]byte, error) {
	casual := make([]string, 0, len(defaultCasualApps))
	for bundle := range defaultCasualApps {
		casual = append(casual, bundle)
	}
	sort.Strings(casual)
	rules := make([]map[string]string, 0, len(defaultTitleRules))
	for _, r := range defaultTitleRules {
		rules = append(rules, map[string]string{"contains": r.contains, "style": r.style})
	}
	return json.Marshal(map[string]any{"casual": casual, "titleRules": rules})
}

func cmdStyles() error {
	b, err := stylesJSON()
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

// cmdFetchModels downloads the speech models now (the app does the same on first launch), printing progress.
func cmdFetchModels() error {
	var lastPct = map[string]int{}
	return ensureSpeechModels(context.Background(), func(id string, done, total int64) {
		if total <= 0 {
			return
		}
		if pct := int(done * 100 / total); pct != lastPct[id] && (pct%5 == 0 || done == total) {
			lastPct[id] = pct
			fmt.Fprintf(os.Stderr, "%s: %d%% (%d / %d MB)\n", id, pct, done/1_000_000, total/1_000_000)
		}
	})
}
