package main

import (
	"reflect"
	"testing"
)

func TestAgree(t *testing.T) {
	cases := []struct {
		name                      string
		prev, cur                 string
		wantStable, wantTentative []string
	}{
		{"first hypothesis has nothing to agree with", "", "Hôm nay ta", nil, []string{"Hôm", "nay", "ta"}},
		{"common prefix is stable", "Hôm nay ta phải", "Hôm nay tao phải deploy", []string{"Hôm", "nay"}, []string{"tao", "phải", "deploy"}},
		{"case and punctuation do not break agreement", "Hôm nay, ta", "hôm nay ta phải", []string{"hôm", "nay", "ta"}, []string{"phải"}},
		{"identical growing text", "Hôm nay", "Hôm nay ta phải", []string{"Hôm", "nay"}, []string{"ta", "phải"}},
		{"a hypothesis that shrinks keeps only the agreed part", "Hôm nay ta phải deploy", "Hôm nay", []string{"Hôm", "nay"}, []string{}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			stable, tentative := agree(fields(c.prev), fields(c.cur))
			if !reflect.DeepEqual(norm(stable), norm(c.wantStable)) || !reflect.DeepEqual(norm(tentative), norm(c.wantTentative)) {
				t.Fatalf("stable %q tentative %q, want %q / %q", stable, tentative, c.wantStable, c.wantTentative)
			}
		})
	}
}

func fields(s string) []string { return splitWords(s) }

func splitWords(s string) []string {
	var out []string
	cur := ""
	for _, r := range s {
		if r == ' ' {
			if cur != "" {
				out = append(out, cur)
				cur = ""
			}
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}

func norm(ws []string) []string {
	if len(ws) == 0 {
		return nil
	}
	return ws
}

func TestSnapshotReturnsTheLastSamples(t *testing.T) {
	r := &Recorder{pcm: []int16{1, 2, 3, 4, 5}}
	if got := r.Snapshot(3); !reflect.DeepEqual(got, []int16{3, 4, 5}) {
		t.Fatalf("last 3: %v", got)
	}
	if got := r.Snapshot(99); !reflect.DeepEqual(got, []int16{1, 2, 3, 4, 5}) {
		t.Fatalf("more than recorded: %v", got)
	}
	r.pcm[0] = 9 // the snapshot must be a copy
	if got := r.Snapshot(99); got[0] != 9 {
		t.Fatalf("expected live data, got %v", got)
	}
}
