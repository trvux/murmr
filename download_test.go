package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func sum(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }

// a server that honours Range like Hugging Face's CDN does
func rangeServer(content []byte, hits *atomic.Int32) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.ServeContent(w, r, "m.bin", time.Time{}, strings.NewReader(string(content)))
	}))
}

func TestDownloadFileWholeAndResumed(t *testing.T) {
	content := []byte(strings.Repeat("whisper-model-bytes-", 5000))
	var hits atomic.Int32
	srv := rangeServer(content, &hits)
	defer srv.Close()
	ctx := context.Background()
	noop := func(done, total int64) {}

	dest := filepath.Join(t.TempDir(), "sub", "m.bin")
	if err := downloadFile(ctx, http.DefaultClient, srv.URL, dest, sum(content), int64(len(content)), noop); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(dest); string(got) != string(content) {
		t.Error("downloaded bytes differ")
	}
	if fileExists(dest + ".part") {
		t.Error("the .part file should be gone after success")
	}

	// an interrupted run left the first 1000 bytes: only the rest is requested
	dest2 := filepath.Join(t.TempDir(), "m.bin")
	_ = os.WriteFile(dest2+".part", content[:1000], 0o644)
	var firstDone int64 = -1
	if err := downloadFile(ctx, http.DefaultClient, srv.URL, dest2, sum(content), int64(len(content)), func(done, total int64) {
		if firstDone < 0 {
			firstDone = done
		}
		if total != int64(len(content)) {
			t.Errorf("total should be the whole file (%d), got %d", len(content), total)
		}
	}); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(dest2); string(got) != string(content) {
		t.Error("resumed file differs")
	}
	if firstDone < 1000 {
		t.Errorf("progress should start from the bytes already there, got %d", firstDone)
	}
}

func TestDownloadFileRejectsBadChecksum(t *testing.T) {
	content := []byte(strings.Repeat("x", 4096))
	var hits atomic.Int32
	srv := rangeServer(content, &hits)
	defer srv.Close()
	dest := filepath.Join(t.TempDir(), "m.bin")
	err := downloadFile(context.Background(), http.DefaultClient, srv.URL, dest, sum([]byte("something else")), int64(len(content)), func(int64, int64) {})
	if err == nil || !strings.Contains(err.Error(), "checksum") {
		t.Fatalf("want a checksum error, got %v", err)
	}
	if fileExists(dest) || fileExists(dest+".part") {
		t.Error("neither the file nor the bad partial may be left behind")
	}
}

func TestDownloadFileServerErrorAndRestartWhenRangeIgnored(t *testing.T) {
	bad := httptest.NewServer(http.NotFoundHandler())
	defer bad.Close()
	if err := downloadFile(context.Background(), http.DefaultClient, bad.URL, filepath.Join(t.TempDir(), "m.bin"), "x", 10, func(int64, int64) {}); err == nil {
		t.Error("a 404 must be an error")
	}

	// a server that ignores Range sends the whole file with 200: the old part must be replaced, not appended to
	content := []byte(strings.Repeat("abcdefgh", 1000))
	plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(content) }))
	defer plain.Close()
	dest := filepath.Join(t.TempDir(), "m.bin")
	_ = os.WriteFile(dest+".part", content[:500], 0o644)
	if err := downloadFile(context.Background(), http.DefaultClient, plain.URL, dest, sum(content), int64(len(content)), func(int64, int64) {}); err != nil {
		t.Fatalf("restart after ignored Range: %v", err)
	}
}

func TestDownloadFileGivesUpWhenStalled(t *testing.T) {
	old := stallTimeout
	stallTimeout = 300 * time.Millisecond
	defer func() { stallTimeout = old }()
	stuck := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "100000")
		w.Write([]byte("a few bytes"))
		w.(http.Flusher).Flush()
		<-r.Context().Done() // then nothing
	}))
	defer stuck.Close()
	start := time.Now()
	err := downloadFile(context.Background(), http.DefaultClient, stuck.URL, filepath.Join(t.TempDir(), "m.bin"), "x", 100000, func(int64, int64) {})
	if err == nil || time.Since(start) > 5*time.Second {
		t.Errorf("a stalled download must fail quickly, got %v after %v", err, time.Since(start))
	}
}

func TestSpeechModelPaths(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("MURMR_MODELS_DIR", dir)
	t.Setenv("MURMR_MODEL", "")
	t.Chdir(t.TempDir()) // no ./models here
	m := speechModelByID("vad")
	if m.path() != filepath.Join(dir, m.Name) {
		t.Errorf("default path: %s", m.path())
	}
	if m.present() {
		t.Error("nothing downloaded yet")
	}
	// a leftover with the wrong size is not a usable model
	_ = os.WriteFile(m.path(), []byte("truncated"), 0o644)
	if m.present() {
		t.Error("a wrong-sized file must not count as present")
	}
	_ = os.WriteFile(m.path(), make([]byte, m.Size), 0o644)
	if !m.present() {
		t.Error("a right-sized file counts as present")
	}
	// the user's own file wins and is trusted
	own := filepath.Join(t.TempDir(), "mine.bin")
	_ = os.WriteFile(own, []byte("mine"), 0o644)
	t.Setenv("MURMR_VAD_MODEL", own)
	if m.path() != own || !m.present() {
		t.Errorf("MURMR_VAD_MODEL should be used as is: %s", m.path())
	}
}

func TestEnsureSpeechModelsDoesNotDownloadWhenPresentOrOverridden(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hits.Add(1); fmt.Fprint(w, "x") }))
	defer srv.Close()
	t.Chdir(t.TempDir())
	t.Setenv("MURMR_MODELS_DIR", t.TempDir())
	own := filepath.Join(t.TempDir(), "w.bin")
	_ = os.WriteFile(own, []byte("w"), 0o644)
	t.Setenv("MURMR_MODEL", own)
	t.Setenv("MURMR_VAD", "off")
	if err := ensureSpeechModels(context.Background(), func(string, int64, int64) {}); err != nil || hits.Load() != 0 {
		t.Errorf("own model + VAD off needs no download: err %v hits %d", err, hits.Load())
	}
	t.Setenv("MURMR_MODEL", filepath.Join(t.TempDir(), "missing.bin"))
	if err := ensureSpeechModels(context.Background(), func(string, int64, int64) {}); err == nil {
		t.Error("a MURMR_MODEL that does not exist must be an error, not a silent download")
	}
}
