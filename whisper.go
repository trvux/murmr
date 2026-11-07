package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"
)

// Hint to keep Vietnamese diacritics and common English tech terms.
const whisperPrompt = "Xin chào, đây là bản ghi âm tiếng Việt xen lẫn tiếng Anh: Go, Kubernetes, Kafka, etcd, Next.js."

// Whisper owns a whisper-server child process. The model stays loaded in
// memory between requests, so each dictation skips the multi-second load.
type Whisper struct {
	cmd  *exec.Cmd
	base string
	http *http.Client
}

// vadArgs enables Silero voice-activity detection when its model is present.
// Without it Whisper invents text ("Thanks for watching", "What's up?") from
// noise or a button click; measured: noise -> "Hippie, I'm going to go.".
// The looser silence/padding values (500ms, 150ms) scored best on our test clips.
func vadArgs() []string {
	path := getenv("MURMR_VAD_MODEL", "models/ggml-silero-v5.1.2.bin")
	if os.Getenv("MURMR_VAD") == "off" || !fileExists(path) {
		return nil
	}
	return []string{"--vad", "-vm", path, "-vsd", "500", "-vp", "150"}
}

func StartWhisper(ctx context.Context, model, port, prompt string, extra ...string) (*Whisper, error) {
	args := []string{
		"-m", model,
		"--host", "127.0.0.1", "--port", port,
		"-l", "auto", "-nt", "-sns",
		"--prompt", prompt,
	}
	bin, err := whisperBinary()
	if err != nil {
		return nil, err
	}
	reapStaleServer(port) // an orphan on our port would answer the readiness check below and hide a failed start
	log.Printf("whisper: using %s", bin)
	cmd := exec.CommandContext(ctx, bin, append(args, extra...)...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start whisper-server: %w", err)
	}
	w := &Whisper{
		cmd:  cmd,
		base: "http://127.0.0.1:" + port,
		http: &http.Client{Timeout: 60 * time.Second},
	}

	// First launch compiles Metal shaders (~5s) and loads the model.
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := http.Get(w.base + "/")
		if err == nil {
			resp.Body.Close()
			return w, nil
		}
		time.Sleep(300 * time.Millisecond)
	}
	_ = cmd.Process.Kill()
	return nil, fmt.Errorf("whisper-server not ready after 60s")
}

// whisperBinary finds whisper-server: MURMR_WHISPER if set, else the copy bundled next to the engine (inside
// "Murmr Stream.app", so nothing needs installing), else whatever is on PATH (a source checkout with Homebrew).
func whisperBinary() (string, error) {
	if p := os.Getenv("MURMR_WHISPER"); p != "" {
		return p, nil
	}
	if self, err := os.Executable(); err == nil {
		if p := filepath.Join(filepath.Dir(self), "whisper-server"); fileExists(p) {
			return p, nil
		}
	}
	if p, err := exec.LookPath("whisper-server"); err == nil {
		return p, nil
	}
	return "", fmt.Errorf("whisper-server not found: it is bundled in the app; from a source checkout run `brew install whisper-cpp` or app/scripts/build-whisper.sh")
}

// isOrphanedWhisper reads one line of `ps -o ppid=,comm=` and says whether it is a whisper-server whose parent
// is gone (launchd, pid 1). Those are what an engine that was killed hard leaves behind, each holding ~700 MB.
func isOrphanedWhisper(psLine string) bool {
	f := strings.Fields(psLine)
	if len(f) < 2 || f[0] != "1" {
		return false
	}
	return filepath.Base(strings.Join(f[1:], " ")) == "whisper-server"
}

// reapStaleServer stops an orphaned whisper-server still listening on port. It only touches processes that are
// named whisper-server AND have no parent, so a server someone started on purpose is left alone.
func reapStaleServer(port string) {
	out, err := exec.Command("lsof", "-nP", "-iTCP:"+port, "-sTCP:LISTEN", "-t").Output()
	if err != nil {
		return // nothing listening (lsof exits 1)
	}
	for _, pid := range strings.Fields(string(out)) {
		line, err := exec.Command("ps", "-o", "ppid=,comm=", "-p", pid).Output()
		if err != nil || !isOrphanedWhisper(string(line)) {
			continue
		}
		if n, err := strconv.Atoi(pid); err == nil {
			log.Printf("whisper: stopping orphaned server %d left on port %s", n, port)
			_ = syscall.Kill(n, syscall.SIGTERM)
			time.Sleep(500 * time.Millisecond)
		}
	}
}

func (w *Whisper) Stop() {
	if w.cmd.Process != nil {
		_ = w.cmd.Process.Kill()
		_ = w.cmd.Wait()
	}
}

// Transcript is Whisper's text plus the words it was unsure about.
type Transcript struct {
	Text string
	Weak []string // words whose weakest token probability is below weakThreshold
}

const weakThreshold = 0.5

func (w *Whisper) Transcribe(wav []byte) (Transcript, error) {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, err := mw.CreateFormFile("file", "audio.wav")
	if err != nil {
		return Transcript{}, err
	}
	fw.Write(wav)
	mw.WriteField("temperature", "0.0")
	// verbose_json adds per-token probabilities (for the "unsure words" report)
	// but costs ~0.8s per dictation, so it is opt-in.
	format := "json"
	if os.Getenv("MURMR_CONFIDENCE") == "on" {
		format = "verbose_json"
	}
	mw.WriteField("response_format", format)
	mw.Close()

	req, _ := http.NewRequest(http.MethodPost, w.base+"/inference", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := w.http.Do(req)
	if err != nil {
		return Transcript{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return Transcript{}, fmt.Errorf("whisper: %s: %s", resp.Status, b)
	}
	var out struct {
		Text     string `json:"text"`
		Segments []struct {
			Words []struct {
				Word        string  `json:"word"`
				Probability float64 `json:"probability"`
			} `json:"words"`
		} `json:"segments"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return Transcript{}, err
	}

	// Tokens are sub-word pieces: a leading space starts a new word, and the
	// word's confidence is its weakest piece. Punctuation-only tokens are skipped.
	type wordConf struct {
		text string
		min  float64
	}
	var words []wordConf
	for _, seg := range out.Segments {
		for _, t := range seg.Words {
			if !strings.ContainsFunc(t.Word, func(r rune) bool { return unicode.IsLetter(r) || unicode.IsDigit(r) }) {
				continue
			}
			if strings.HasPrefix(t.Word, " ") || len(words) == 0 {
				words = append(words, wordConf{strings.TrimSpace(t.Word), t.Probability})
				continue
			}
			last := &words[len(words)-1]
			last.text += t.Word
			last.min = min(last.min, t.Probability)
		}
	}
	tr := Transcript{Text: strings.TrimSpace(out.Text)}
	for _, wc := range words {
		if wc.min < weakThreshold {
			tr.Weak = append(tr.Weak, wc.text)
		}
	}
	return tr, nil
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// hasWord reports whether s contains at least one letter or digit.
func hasWord(s string) bool {
	return strings.ContainsFunc(s, func(r rune) bool { return unicode.IsLetter(r) || unicode.IsDigit(r) })
}
