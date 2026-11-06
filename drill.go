package main

import (
	"bufio"
	"cmp"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// Practice sentences, chosen for sounds that are hard for Vietnamese speakers:
// final consonants (-sh, -ch, -st, -ts), clusters, th, r/l, plus dev vocabulary.
var drillBank = []string{
	"Please push the pull request to the main branch.",
	"I will merge this change after the tests pass.",
	"The leader election failed because the cluster lost consensus.",
	"Kafka keeps every message in an ordered log on disk.",
	"Can you review my commit and check the deploy script?",
	"The request timed out, so the client retried the call.",
	"We should reduce the latency and improve the throughput.",
	"This service handles thousands of requests every second.",
	"She thought about the third bug in the process.",
	"He pushed the fixed patch and watched the build finish.",
	"Kubernetes schedules each container on a healthy node.",
	"Etcd stores the cluster state and replicates it across three nodes.",
	"I asked them to rollback the release and restart the server.",
	"The database connection pool was exhausted at night.",
	"Check the logs first, then restart the failed process.",
}

type DrillEntry struct {
	Time     time.Time   `json:"t"`
	Text     string      `json:"text"`
	Accuracy float64     `json:"accuracy"`
	Words    []WordScore `json:"words"`
}

func drillPath() string { return filepath.Join(configDir(), "drill.jsonl") }

func loadDrills() []DrillEntry {
	f, err := os.Open(drillPath())
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []DrillEntry
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		var e DrillEntry
		if json.Unmarshal(sc.Bytes(), &e) == nil {
			out = append(out, e)
		}
	}
	return out
}

func appendDrill(e DrillEntry) {
	_ = os.MkdirAll(configDir(), 0o700)
	f, err := os.OpenFile(drillPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	_ = json.NewEncoder(f).Encode(e)
}

// pickSentences ranks the bank by how much it exercises this speaker's known
// trouble: words the LLM keeps having to fix (history) and words that failed
// in earlier drills. A little randomness avoids the same order every time.
func pickSentences(n int) []string {
	trouble := map[string]float64{}
	hist, _ := LoadHistory(historyPath())
	for _, p := range LearnPairs(hist, LoadIgnored(ignoredPath()), 2) {
		for _, w := range tokens(p.To) {
			trouble[strings.ToLower(w)] += 1
		}
	}
	type tally struct{ fail, total float64 }
	byWord := map[string]*tally{}
	for _, d := range loadDrills() {
		for _, w := range d.Words {
			k := strings.ToLower(w.Word)
			t := byWord[k]
			if t == nil {
				t = &tally{}
				byWord[k] = t
			}
			t.total++
			if !w.OK {
				t.fail++
			}
		}
	}
	for w, t := range byWord {
		trouble[w] += 2 * t.fail / t.total
	}

	type scored struct {
		s string
		v float64
	}
	var all []scored
	for _, s := range drillBank {
		v := rand.Float64() * 0.5
		for _, w := range tokens(s) {
			v += trouble[strings.ToLower(w)]
		}
		all = append(all, scored{s, v})
	}
	slices.SortFunc(all, func(a, b scored) int { return cmp.Compare(b.v, a.v) })
	var out []string
	for i := 0; i < n && i < len(all); i++ {
		out = append(out, all[i].s)
	}
	return out
}

var posVN = map[string]string{"initial": "đầu từ", "medial": "giữa từ", "final": "cuối từ"}

func describeOp(o Op) string {
	switch {
	case o.Kind == "del" && o.Consonant && o.Pos == "final":
		return fmt.Sprintf("thiếu âm cuối /%s/", o.Exp)
	case o.Kind == "del":
		return fmt.Sprintf("thiếu âm /%s/ (%s)", o.Exp, posVN[o.Pos])
	default:
		return fmt.Sprintf("/%s/ nghe thành /%s/ (%s)", o.Exp, *o.Got, posVN[o.Pos])
	}
}

func cmdDrill(args []string) error {
	n := 5
	sentences := pickSentences(n)
	fmt.Println("Đang nạp model âm vị (lần đầu ~30-60s, sau đó nhanh hơn)...")
	sc, err := StartScorer()
	if err != nil {
		return err
	}
	defer sc.Close()

	// Optional: the same sentence read correctly in the learner's own voice.
	var voice *Voice
	if v, err := StartVoice(); err != nil {
		fmt.Println("  (không có giọng mẫu, bỏ qua phần nghe so sánh:", err, ")")
	} else {
		voice = v
		defer voice.Close()
	}
	rec, err := NewRecorder()
	if err != nil {
		return err
	}
	defer rec.Close()

	in := bufio.NewReader(os.Stdin)
	fmt.Printf("\n%d câu. Mỗi câu: Enter để bắt đầu ghi, đọc, Enter lần nữa để dừng. Gõ q rồi Enter để thoát.\n", len(sentences))
	for i, text := range sentences {
		fmt.Printf("\n[%d/%d]  %s\n", i+1, len(sentences), text)
		fmt.Print("  Enter để ghi... ")
		line, _ := in.ReadString('\n')
		if strings.TrimSpace(line) == "q" {
			break
		}
		if err := rec.Start(); err != nil {
			return err
		}
		fmt.Print("  ● đang ghi, Enter để dừng... ")
		in.ReadString('\n')
		pcm := rec.Stop()
		if isSilent(pcm) {
			fmt.Println("  không nghe thấy gì, bỏ qua câu này.")
			continue
		}
		tmp, err := os.CreateTemp("", "murmr-drill-*.wav") // your attempt; deleted after this sentence
		if err != nil {
			return err
		}
		tmp.Write(encodeWAV(pcm))
		tmp.Close()
		res, err := sc.Score(tmp.Name(), text)
		if err != nil {
			os.Remove(tmp.Name())
			fmt.Println("  lỗi:", err)
			continue
		}
		printScore(res)
		appendDrill(DrillEntry{Time: time.Now(), Text: text, Accuracy: res.Accuracy, Words: res.Words})
		if voice != nil && res.Accuracy < goldenBelow {
			offerGolden(in, voice, text, tmp.Name())
		}
		os.Remove(tmp.Name())
	}
	fmt.Println("\nXem tiến bộ: ./murmr progress")
	return nil
}

func printScore(r Score) {
	fmt.Printf("  chính xác %.0f%%\n", r.Accuracy*100)
	bad := 0
	for _, w := range r.Words {
		if w.OK {
			continue
		}
		bad++
		fmt.Printf("  ✗ %-12s chuẩn /%s/\n", w.Word, strings.Join(w.Expected, " "))
		for _, o := range w.Ops {
			fmt.Printf("      - %s\n", describeOp(o))
		}
	}
	if bad == 0 {
		fmt.Println("  ✓ tất cả các từ đều khớp")
	}
}

// cmdScore scores an existing WAV, handy for testing without a microphone.
func cmdScore(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf(`usage: murmr score <file.wav> "<sentence>"`)
	}
	sc, err := StartScorer()
	if err != nil {
		return err
	}
	defer sc.Close()
	res, err := sc.Score(args[0], args[1])
	if err != nil {
		return err
	}
	fmt.Println("nghe được:", res.Heard)
	printScore(res)
	return nil
}

func cmdProgress() error {
	ds := loadDrills()
	if len(ds) == 0 {
		fmt.Println("Chưa có dữ liệu. Chạy ./murmr drill vài lần trước.")
		return nil
	}
	type week struct {
		n   int
		sum float64
	}
	weeks := map[string]*week{}
	for _, d := range ds {
		y, w := d.Time.ISOWeek()
		k := fmt.Sprintf("%d-W%02d", y, w)
		if weeks[k] == nil {
			weeks[k] = &week{}
		}
		weeks[k].n++
		weeks[k].sum += d.Accuracy
	}
	keys := make([]string, 0, len(weeks))
	for k := range weeks {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	fmt.Println("Độ chính xác trung bình theo tuần:")
	for _, k := range keys {
		fmt.Printf("  %s  %3.0f%%  (%d câu)\n", k, weeks[k].sum/float64(weeks[k].n)*100, weeks[k].n)
	}

	// Which sounds, in which position, fail most often? Count opportunities too,
	// so "dropped /ʃ/ 5 of 5 times" is distinguishable from "5 of 50".
	type stat struct{ fail, total int }
	pat := map[string]*stat{}
	for _, d := range ds {
		for _, w := range d.Words {
			bad := map[int]bool{}
			for _, o := range w.Ops {
				for k, e := range w.Expected {
					if e == o.Exp && posOf(k, len(w.Expected)) == o.Pos {
						bad[k] = true
					}
				}
			}
			for k, e := range w.Expected {
				key := posVN[posOf(k, len(w.Expected))] + " /" + e + "/"
				if pat[key] == nil {
					pat[key] = &stat{}
				}
				pat[key].total++
				if bad[k] {
					pat[key].fail++
				}
			}
		}
	}
	type row struct {
		k string
		s *stat
	}
	var rows []row
	for k, s := range pat {
		if s.total >= 3 && s.fail > 0 {
			rows = append(rows, row{k, s})
		}
	}
	slices.SortFunc(rows, func(a, b row) int {
		return cmp.Or(cmp.Compare(float64(b.s.fail)/float64(b.s.total), float64(a.s.fail)/float64(a.s.total)), cmp.Compare(b.s.total, a.s.total))
	})
	printCategories(ds)

	fmt.Println("\nÂm hay sai nhất (sai / số lần gặp, chỉ tính âm gặp từ 3 lần):")
	for i, r := range rows {
		if i == 12 {
			break
		}
		fmt.Printf("  %-22s %d/%d  (%.0f%%)\n", r.k, r.s.fail, r.s.total, float64(r.s.fail)/float64(r.s.total)*100)
	}
	return nil
}

func posOf(k, n int) string {
	switch {
	case k == 0:
		return "initial"
	case k == n-1:
		return "final"
	}
	return "medial"
}

const vowelStarts = "aeiouyæɑɒɔəɛɜɪʊʌɐøœɯ"

// printCategories groups every expected sound into a broad class and shows how
// often it was wrong, so the answer to "which kind of sound is my problem?" is
// one table. Final consonants are split into dropped vs replaced: dropping is
// the classic Vietnamese-English pattern (no final -sh, -ch, -d, -l in Vietnamese).
func printCategories(ds []DrillEntry) {
	type stat struct{ fail, total int }
	cat := map[string]*stat{}
	bump := func(name string, bad bool) {
		if cat[name] == nil {
			cat[name] = &stat{}
		}
		cat[name].total++
		if bad {
			cat[name].fail++
		}
	}
	dropped, replaced := 0, 0
	for _, d := range ds {
		for _, w := range d.Words {
			n := len(w.Expected)
			bad := map[int]Op{}
			for _, o := range w.Ops {
				for k, e := range w.Expected {
					if e == o.Exp && posOf(k, n) == o.Pos {
						bad[k] = o
					}
				}
			}
			for k, e := range w.Expected {
				o, isBad := bad[k]
				vowel := strings.ContainsRune(vowelStarts, []rune(e)[0])
				switch {
				case e == "ð" || e == "θ":
					bump("âm 'th' (ð, θ)", isBad)
				case vowel:
					bump("nguyên âm", isBad)
				case k == n-1 && n > 1:
					bump("phụ âm CUỐI từ", isBad)
					if isBad && o.Kind == "del" {
						dropped++
					} else if isBad {
						replaced++
					}
				case k == 0:
					bump("phụ âm ĐẦU từ", isBad)
				default:
					bump("phụ âm giữa từ", isBad)
				}
			}
		}
	}
	names := make([]string, 0, len(cat))
	for k := range cat {
		names = append(names, k)
	}
	slices.SortFunc(names, func(a, b string) int {
		return cmp.Compare(float64(cat[b].fail)/float64(cat[b].total), float64(cat[a].fail)/float64(cat[a].total))
	})
	fmt.Println("\nTheo loại âm (sai / số lần gặp):")
	for _, k := range names {
		s := cat[k]
		fmt.Printf("  %-18s %3d/%-3d  %3.0f%%\n", k, s.fail, s.total, float64(s.fail)/float64(s.total)*100)
	}
	if dropped+replaced > 0 {
		fmt.Printf("  (phụ âm cuối sai: %d bị bỏ hẳn, %d bị thay bằng âm khác)\n", dropped, replaced)
	}
}

// Below this accuracy the learner is offered the "same sentence, said right, in
// your own voice" comparison. Above it there is little to hear.
const goldenBelow = 0.98

// offerGolden renders the sentence in the learner's voice with native pronunciation
// and lets them hear their own attempt and the correct version back to back.
func offerGolden(in *bufio.Reader, voice *Voice, text, yours string) {
	golden, err := os.CreateTemp("", "murmr-golden-*.wav")
	if err != nil {
		return
	}
	golden.Close()
	defer os.Remove(golden.Name())

	fmt.Print("  đang tạo bản đúng bằng giọng mày... ")
	if err := voice.Speak(text, golden.Name()); err != nil {
		fmt.Println("lỗi:", err)
		return
	}
	fmt.Println("xong.")

	fmt.Print("  Enter = nghe so sánh (bản của mày, rồi bản đúng), s = bỏ qua: ")
	for {
		line, err := in.ReadString('\n')
		if err != nil || strings.TrimSpace(line) == "s" {
			return
		}
		fmt.Println("  [1] mày nói")
		playFile(yours)
		time.Sleep(600 * time.Millisecond)
		fmt.Println("  [2] bản đúng, giọng mày")
		playFile(golden.Name())
		fmt.Print("  Enter = nghe lại, s = câu tiếp: ")
	}
}

func playFile(path string) { _ = exec.Command("afplay", path).Run() }
