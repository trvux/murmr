package main

import (
	"strings"
	"testing"
)

func TestDiffChunks(t *testing.T) {
	got := diffChunks(
		tokens("Ừm hôm nay ta phải deploy Nhưng mà test chưa bad nên chưa boot lên branchman"),
		tokens("Hôm nay tao phải deploy. Nhưng mà test chưa pass nên chưa push lên branch main."),
	)
	var s []string
	for _, c := range got {
		s = append(s, strings.Join(c[0], " ")+"=>"+strings.Join(c[1], " "))
	}
	want := "ta=>tao | bad=>pass | boot=>push | branchman=>branch main"
	if strings.Join(s, " | ") != want {
		t.Fatalf("got %q, want %q", strings.Join(s, " | "), want)
	}
}

func TestLearnPairsThreshold(t *testing.T) {
	e := Entry{Raw: "chưa boot lên", Final: "chưa push lên"}
	if got := LearnPairs([]Entry{e, e}, nil, 3); len(got) != 0 {
		t.Fatalf("2 occurrences must not learn, got %v", got)
	}
	got := LearnPairs([]Entry{e, e, e}, nil, 3)
	if len(got) != 1 || got[0].From != "boot" || got[0].To != "push" || got[0].Count != 3 {
		t.Fatalf("got %v", got)
	}
	if got := LearnPairs([]Entry{e, e, e}, map[string]bool{"boot": true}, 3); len(got) != 0 {
		t.Fatalf("ignored pair must be dropped, got %v", got)
	}
}

func TestDiffChunksSplitsAdjacentSubstitutions(t *testing.T) {
	got := diffChunks(tokens("xong ta boot lên"), tokens("Xong tao push lên"))
	if len(got) != 2 || got[0][0][0] != "ta" || got[0][1][0] != "tao" || got[1][0][0] != "boot" || got[1][1][0] != "push" {
		t.Fatalf("got %v", got)
	}
}

func TestLearnPairsSkipsPronouns(t *testing.T) {
	e := Entry{Raw: "tôi nghĩ vậy", Final: "tao nghĩ vậy"}
	if got := LearnPairs([]Entry{e, e, e, e}, nil, 3); len(got) != 0 {
		t.Fatalf("pronoun pairs depend on audience and must not be learned, got %v", got)
	}
}
