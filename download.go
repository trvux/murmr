package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// The two speech models are too big to ship inside the app (574 MB), so the first launch fetches them. Both are
// pinned by size and SHA-256 (the values Hugging Face itself reports for these files), so a truncated or swapped
// download is rejected instead of being loaded.
type speechModel struct {
	ID     string // "whisper" or "vad": what progress events call it
	Name   string // file name
	URL    string
	SHA256 string
	Size   int64
	Env    string // variable that points at a file of the user's own, which is then used as is and never downloaded
}

var speechModels = []speechModel{
	{
		ID: "whisper", Name: "ggml-large-v3-turbo-q5_0.bin", Env: "MURMR_MODEL",
		URL:    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
		SHA256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2", Size: 574041195,
	},
	{
		ID: "vad", Name: "ggml-silero-v5.1.2.bin", Env: "MURMR_VAD_MODEL",
		URL:    "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin",
		SHA256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf", Size: 885098,
	},
}

func speechModelByID(id string) speechModel {
	for _, m := range speechModels {
		if m.ID == id {
			return m
		}
	}
	return speechModel{}
}

// modelsDir is where downloaded models live: MURMR_MODELS_DIR, else the app's folder in Application Support.
func modelsDir() string {
	if d := os.Getenv("MURMR_MODELS_DIR"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "Murmr Stream", "models")
}

// path says where the engine reads this model from: the user's own file if the variable is set, else a copy in
// ./models (a source checkout), else the downloaded one.
func (m speechModel) path() string {
	if p := os.Getenv(m.Env); p != "" {
		return p
	}
	if local := filepath.Join("models", m.Name); fileExists(local) {
		return local
	}
	return filepath.Join(modelsDir(), m.Name)
}

// present reports whether the model can be loaded now. A downloaded copy with the wrong size is not present
// (a leftover from an interrupted older run); the user's own file is trusted.
func (m speechModel) present() bool {
	p := m.path()
	st, err := os.Stat(p)
	if err != nil || st.IsDir() {
		return false
	}
	if os.Getenv(m.Env) != "" || !strings.HasPrefix(p, modelsDir()) {
		return true
	}
	return st.Size() == m.Size
}

// ensureSpeechModels downloads whichever required models are missing. progress is called as bytes arrive, with
// the model's ID; total is the whole file's size.
func ensureSpeechModels(ctx context.Context, progress func(id string, done, total int64)) error {
	for _, m := range speechModels {
		if m.ID == "vad" && os.Getenv("MURMR_VAD") == "off" {
			continue
		}
		if m.present() {
			continue
		}
		if os.Getenv(m.Env) != "" {
			return fmt.Errorf("%s=%s does not exist", m.Env, os.Getenv(m.Env))
		}
		dest := filepath.Join(modelsDir(), m.Name)
		err := downloadFile(ctx, http.DefaultClient, m.URL, dest, m.SHA256, m.Size, func(done, total int64) {
			progress(m.ID, done, total)
		})
		if err != nil {
			return fmt.Errorf("download %s: %w", m.Name, err)
		}
	}
	return nil
}

// stallTimeout is how long a download may receive nothing before it is given up (and retried by the next start).
var stallTimeout = 30 * time.Second

// downloadFile fetches url into dest. It writes to dest+".part" and, if a part is already there from an interrupted
// run, resumes with a Range request. When the bytes are all in, the SHA-256 is checked and only then is the part
// renamed to dest, so dest is either absent or complete and correct.
func downloadFile(ctx context.Context, client *http.Client, url, dest, wantSHA string, wantSize int64, progress func(done, total int64)) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	part := dest + ".part"
	var have int64
	if st, err := os.Stat(part); err == nil {
		have = st.Size()
		if wantSize > 0 && have > wantSize {
			_ = os.Remove(part)
			have = 0
		}
	}
	if wantSize > 0 && have < wantSize {
		if free, err := freeBytes(filepath.Dir(dest)); err == nil && free < uint64(wantSize-have)+50<<20 {
			return fmt.Errorf("not enough free disk space: need about %d MB more, %d MB free", (wantSize-have)/1_000_000, free/1_000_000)
		}
	}

	if have == 0 || have < wantSize || wantSize == 0 {
		if err := fetchInto(ctx, client, url, part, have, wantSize, progress); err != nil {
			return err
		}
	}
	got, err := fileSHA256(part)
	if err != nil {
		return err
	}
	if got != wantSHA {
		_ = os.Remove(part) // never resume from a bad file
		return fmt.Errorf("checksum mismatch (got %.12s…, want %.12s…); the partial file was removed", got, wantSHA)
	}
	return os.Rename(part, dest)
}

// fetchInto appends to path starting at offset, restarting from zero if the server will not resume.
func fetchInto(ctx context.Context, client *http.Client, url, path string, offset, wantSize int64, progress func(done, total int64)) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stall := time.AfterFunc(stallTimeout, cancel)
	defer stall.Stop()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "Murmr-Stream")
	if offset > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", offset))
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	flags := os.O_CREATE | os.O_WRONLY
	switch resp.StatusCode {
	case http.StatusPartialContent:
		flags |= os.O_APPEND
	case http.StatusOK: // the server ignored Range (or there was nothing to resume): start over
		flags |= os.O_TRUNC
		offset = 0
	default:
		return fmt.Errorf("server answered %s", resp.Status)
	}
	f, err := os.OpenFile(path, flags, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()

	total := offset + resp.ContentLength
	if resp.ContentLength < 0 {
		total = wantSize
	}
	done := offset
	var last atomic.Int64
	w := writerFunc(func(p []byte) (int, error) {
		stall.Reset(stallTimeout)
		n, err := f.Write(p)
		done += int64(n)
		if now := time.Now().UnixMilli(); now-last.Load() >= 200 { // about five updates a second is plenty
			last.Store(now)
			progress(done, total)
		}
		return n, err
	})
	if _, err := io.Copy(w, resp.Body); err != nil {
		if errors.Is(err, context.Canceled) && ctx.Err() != nil {
			return fmt.Errorf("no data for %v, giving up", stallTimeout)
		}
		return err
	}
	progress(done, total)
	return nil
}

type writerFunc func([]byte) (int, error)

func (f writerFunc) Write(p []byte) (int, error) { return f(p) }

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func freeBytes(dir string) (uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(dir, &st); err != nil {
		return 0, err
	}
	return st.Bavail * uint64(st.Bsize), nil
}
