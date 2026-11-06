package main

import (
	"cmp"
	"context"
	"fmt"
	"os"
	"slices"
	"strings"
)

func runCommand(name string, args []string) error {
	switch name {
	case "report":
		return cmdReport()
	case "forget":
		return cmdForget(args)
	case "drill":
		return cmdDrill(args)
	case "progress":
		return cmdProgress()
	case "score":
		return cmdScore(args)
	case "clean":
		return cmdClean(args)
	default:
		return fmt.Errorf("unknown command %q (try: report, forget, drill, progress, score, clean)", name)
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
		return fmt.Errorf("no cleanup provider configured (set DEEPSEEK_API_KEY)")
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
