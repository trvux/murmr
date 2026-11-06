package main

import (
	"cmp"
	"os"
	"slices"
	"strings"
	"unicode"
)

// Pair is a recurring "Whisper heard From, but the speaker meant To".
type Pair struct {
	From, To string
	Count    int
}

const (
	learnMinCount = 3 // one-off differences are noise; repeats are the speaker's habit
	maxChunkWords = 3 // longer rewrites are paraphrase, not mishearing
)

func tokens(s string) []string {
	var out []string
	for _, f := range strings.Fields(s) {
		f = strings.TrimFunc(f, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
		if f != "" {
			out = append(out, f)
		}
	}
	return out
}

// diffChunks aligns two word lists (Levenshtein) and returns each maximal run
// of changed words where BOTH sides are non-empty, i.e. a substitution.
// Pure deletions (filler words) and pure insertions are ignored.
func diffChunks(a, b []string) [][2][]string {
	n, m := len(a), len(b)
	d := make([][]int, n+1)
	for i := range d {
		d[i] = make([]int, m+1)
		d[i][0] = i
	}
	for j := 0; j <= m; j++ {
		d[0][j] = j
	}
	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			cost := 1
			if strings.EqualFold(a[i-1], b[j-1]) {
				cost = 0
			}
			d[i][j] = min(d[i-1][j-1]+cost, d[i-1][j]+1, d[i][j-1]+1)
		}
	}

	// Walk back from the end, preferring the diagonal on ties.
	type run struct{ a, b []string }
	var runs []run
	var cur run
	flush := func() {
		if len(cur.a) > 0 || len(cur.b) > 0 {
			slices.Reverse(cur.a)
			slices.Reverse(cur.b)
			runs = append(runs, cur)
			cur = run{}
		}
	}
	i, j := n, m
	for i > 0 || j > 0 {
		switch {
		case i > 0 && j > 0 && strings.EqualFold(a[i-1], b[j-1]) && d[i][j] == d[i-1][j-1]:
			flush()
			i, j = i-1, j-1
		case i > 0 && j > 0 && d[i][j] == d[i-1][j-1]+1:
			cur.a, cur.b = append(cur.a, a[i-1]), append(cur.b, b[j-1])
			i, j = i-1, j-1
		case i > 0 && d[i][j] == d[i-1][j]+1:
			cur.a = append(cur.a, a[i-1])
			i--
		default:
			cur.b = append(cur.b, b[j-1])
			j--
		}
	}
	flush()

	var out [][2][]string
	for k := len(runs) - 1; k >= 0; k-- {
		r := runs[k]
		if len(r.a) > 1 && len(r.a) == len(r.b) {
			// Equal-length run: the alignment paired word with word, so keep them
			// separate. Otherwise adjacent mistakes glue into one unlearnable pair.
			for x := range r.a {
				out = append(out, [2][]string{{r.a[x]}, {r.b[x]}})
			}
			continue
		}
		if len(r.a) > 0 && len(r.b) > 0 && len(r.a) <= maxChunkWords && len(r.b) <= maxChunkWords {
			out = append(out, [2][]string{r.a, r.b})
		}
	}
	return out
}

// LearnPairs counts substitutions between what Whisper heard and what was
// pasted, and returns those seen at least minCount times (most frequent first).
func LearnPairs(hist []Entry, ignored map[string]bool, minCount int) []Pair {
	type acc struct {
		to    map[string]int
		total int
	}
	byFrom := map[string]*acc{}
	for _, e := range hist {
		for _, c := range diffChunks(tokens(e.Raw), tokens(e.Final)) {
			from, to := strings.ToLower(strings.Join(c[0], " ")), strings.Join(c[1], " ")
			if hasPronoun(c[0]) || hasPronoun(c[1]) {
				continue
			}
			if ignored[from] || strings.EqualFold(from, to) {
				continue
			}
			a := byFrom[from]
			if a == nil {
				a = &acc{to: map[string]int{}}
				byFrom[from] = a
			}
			a.to[to]++
			a.total++
		}
	}
	var out []Pair
	for from, a := range byFrom {
		// If the LLM disagrees with itself, keep the most common target.
		best, bestN := "", 0
		for to, n := range a.to {
			if n > bestN || (n == bestN && to < best) {
				best, bestN = to, n
			}
		}
		if bestN >= minCount {
			out = append(out, Pair{from, best, bestN})
		}
	}
	slices.SortFunc(out, func(x, y Pair) int {
		return cmp.Or(cmp.Compare(y.Count, x.Count), cmp.Compare(x.From, y.From))
	})
	return out
}

// LoadIgnored reads lines of "from" phrases the user asked to forget.
func LoadIgnored(path string) map[string]bool {
	m := map[string]bool{}
	b, err := os.ReadFile(path)
	if err != nil {
		return m
	}
	for _, l := range strings.Split(string(b), "\n") {
		if l = strings.ToLower(strings.TrimSpace(l)); l != "" {
			m[l] = true
		}
	}
	return m
}

func hasPronoun(ws []string) bool {
	for _, w := range ws {
		if pronouns[strings.ToLower(w)] {
			return true
		}
	}
	return false
}
