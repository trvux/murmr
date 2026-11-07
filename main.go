// murmr: a free, local Wispr Flow clone.
// Hold the right Option key, speak, release: text is transcribed locally with
// whisper.cpp, optionally cleaned by an LLM, and pasted into the focused app.
package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// version is set at build time (-ldflags "-X main.version=...") from the VERSION file; "dev" for a plain go build.
var version = "dev"

func main() {
	log.SetFlags(log.Ltime)
	if len(os.Args) > 1 {
		if err := runCommand(os.Args[1], os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "murmr:", err)
			os.Exit(1)
		}
		return
	}
	daemon()
}

func configDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "murmr")
}

func historyPath() string { return filepath.Join(configDir(), "history.jsonl") }
func ignoredPath() string { return filepath.Join(configDir(), "ignored.txt") }

func daemon() {
	if os.Getenv("MURMR_EVENTS") == "1" {
		events = newEventSink(os.Stdout) // created first, so the shell can show startup progress
		// If the shell dies, writing an event to the closed pipe would kill this process with SIGPIPE at once, before
		// any defer runs, and leave whisper-server running with nobody to stop it. Ignored, the write just fails and
		// the stdin-closed path below shuts everything down in order.
		signal.Ignore(syscall.SIGPIPE)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if events != nil {
		// Started by the macOS app shell: stop when the shell goes away (its end of our stdin closes). The shell can also
		// send lines: "key <spec>" changes the dictation key right away (see holdkey.go), without a restart, and
		// "capture on" / "capture off" pause it while the person is choosing a new one.
		go func() {
			sc := bufio.NewScanner(os.Stdin)
			for sc.Scan() {
				switch sc.Text() {
				case "capture on": // the person is choosing a new dictation key: the old one must do nothing meanwhile
					hold.SetPaused(true)
					continue
				case "capture off":
					hold.SetPaused(false)
					continue
				}
				if spec, ok := strings.CutPrefix(sc.Text(), "key "); ok {
					if err := SetHoldKey(spec); err != nil {
						log.Printf("dictation key: %v", err)
					} else {
						log.Printf("dictation key changed")
					}
				}
			}
			cancel()
		}()
	}

	events.emit("loading", "stage", "dictionary")
	dict, cleaner := loadCleaner()

	events.emit("loading", "stage", "models")
	if err := ensureSpeechModels(ctx, func(id string, done, total int64) {
		events.emit("download", "name", id, "done", done, "total", total)
	}); err != nil {
		events.emit("error", "msg", "Không tải được model giọng nói: "+err.Error())
		log.Fatalf("speech model: %v", err)
	}
	model := speechModelByID("whisper").path()

	if len(vadArgs()) > 0 {
		log.Printf("vad: on (non-speech is ignored)")
	} else {
		log.Printf("vad: OFF (model missing or MURMR_VAD=off): Whisper may invent text from noise")
	}
	log.Printf("murmr %s", version)
	log.Printf("starting whisper-server (first launch compiles Metal shaders, ~10s)...")
	events.emit("loading", "stage", "whisper")
	wh, err := StartWhisper(ctx, model, getenv("MURMR_PORT", "8178"), dict.WhisperPrompt(whisperPrompt), vadArgs()...)
	if err != nil {
		log.Fatal(err)
	}
	defer wh.Stop()

	// Optional live captions (MURMR_PREVIEW=on) need a second, faster server; it loads in the background.
	if events != nil && os.Getenv("MURMR_PREVIEW") == "on" {
		go func() {
			pw, err := StartWhisper(ctx, model, getenv("MURMR_PREVIEW_PORT", "8179"), dict.WhisperPrompt(whisperPrompt), "-ac", previewACArg)
			if err != nil {
				log.Printf("preview server: %v (live text off)", err)
				return
			}
			previewSrv.Store(pw)
			log.Printf("live preview: on")
		}()
		defer func() {
			if pw := previewSrv.Load(); pw != nil {
				pw.Stop()
			}
		}()
	}

	events.emit("loading", "stage", "audio")
	rec, err := NewRecorder()
	if err != nil {
		log.Fatal(err)
	}
	defer rec.Close()

	events.emit("loading", "stage", "keys")
	if spec := os.Getenv("MURMR_KEY"); spec != "" { // the key the user chose; otherwise the right Option
		if err := SetHoldKey(spec); err != nil {
			log.Printf("dictation key: %v (using the right Option)", err)
		}
	}
	keys, err := StartHoldKey()
	if err != nil {
		log.Fatal(err)
	}

	// Jobs run one at a time so pastes keep the order you spoke them in.
	jobs := make(chan job, 4)
	go func() {
		for j := range jobs {
			process(wh, cleaner, dict, j)
		}
	}()

	playSound(getenv("MURMR_SOUND_READY", "Glass"))
	log.Printf("ready. hold the dictation key (default: right Option), Ctrl+C to quit")
	events.emit("ready")

	stopLevels, stopPreview := func() {}, func() {}
	var appc <-chan appCtx
	for {
		select {
		case <-ctx.Done():
			log.Printf("bye")
			return
		case down := <-keys:
			if !down {
				stopLevels()
				stopPreview()
				pcm := rec.Stop()
				playSound(getenv("MURMR_SOUND_STOP", "Pop"))
				select {
				case jobs <- job{pcm: pcm, ctx: appc}:
				default:
					log.Printf("busy, dropped this clip")
				}
				continue
			}
			if err := rec.Start(); err != nil {
				log.Printf("mic start: %v", err)
				continue
			}
			// Read the target app now, before the user can switch away; the slow
			// part runs in the background while they speak.
			ch := make(chan appCtx, 1)
			go func() {
				c := readAppCtx()
				ch <- c
				events.emit("app", "bundle", c.Bundle, "style", LoadPronouns().For(c).Label()) // never the title: it can hold an email address
			}()
			appc = ch
			events.emit("recording")
			stopLevels = startLevels(events, rec)
			stopPreview = startPreview(events, rec)
			playSound(getenv("MURMR_SOUND_START", "Tink"))
			log.Printf("recording...")
		}
	}
}

type job struct {
	pcm []int16
	ctx <-chan appCtx // resolved while the user was speaking
}

func process(wh *Whisper, cleaner Cleaner, dict *Dictionary, j job) {
	pcm := j.pcm
	app := <-j.ctx
	profile := LoadPronouns().For(app)
	if isSilent(pcm) {
		log.Printf("too short/silent, skipped (%.1fs, level %.4f)", float64(len(pcm))/sampleRate, rms(pcm))
		events.emit("skipped", "reason", "silent")
		return
	}
	t0 := time.Now()
	wav := encodeWAV(pcm)
	if dir := os.Getenv("MURMR_SAVE"); dir != "" {
		_ = os.MkdirAll(dir, 0o755)
		_ = os.WriteFile(filepath.Join(dir, time.Now().Format("150405")+".wav"), wav, 0o644)
	}
	events.emit("processing", "stage", "transcribe")
	tr, err := wh.Transcribe(wav)
	if err != nil {
		log.Printf("transcribe: %v", err)
		events.emit("error", "msg", "Không nghe được: "+err.Error())
		return
	}
	if !hasWord(tr.Text) { // Whisper sometimes returns just "." for silence or noise
		log.Printf("no speech detected (%.1fs of audio, level %.4f)", float64(len(pcm))/sampleRate, rms(pcm))
		events.emit("skipped", "reason", "no_speech")
		return
	}
	raw := dict.Apply(tr.Text)
	tSTT := time.Since(t0)

	text := raw
	note := "" // shown on the notch after the text, for example that the backup service was used
	if cleaner != nil {
		events.emit("processing", "stage", "cleanup")
		timeout := cleanupTimeout
		var cleaned string
		var err error
		if nc, ok := cleaner.(noteCleaner); ok {
			timeout = nc.Timeout()
		}
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		if nc, ok := cleaner.(noteCleaner); ok {
			cleaned, note, err = nc.CleanNote(ctx, raw, profile.Prompt())
		} else {
			cleaned, err = cleaner.Clean(ctx, raw, profile.Prompt())
		}
		cancel()
		if err != nil || cleaned == "" {
			log.Printf("cleanup failed, using raw: %v", err)
		} else {
			text = cleaned
		}
	}
	text = dict.Apply(text)
	log.Printf("stt %v, total %v, level %.4f, app %s [%s] (%s)\n  raw:   %s\n  final: %s",
		tSTT.Round(time.Millisecond), time.Since(t0).Round(time.Millisecond), rms(pcm), app.Bundle, app.Title, profileLabel(profile), raw, text)

	if os.Getenv("MURMR_HISTORY") != "off" {
		e := Entry{Time: time.Now(), Raw: tr.Text, Final: text, Weak: tr.Weak, App: app.Bundle}
		if err := AppendHistory(historyPath(), e); err != nil {
			log.Printf("history: %v", err)
		}
	}

	if err := pasteText(text); err != nil {
		log.Printf("paste (grant Accessibility to your terminal?): %v", err)
		events.emit("error", "msg", "Không dán được, cần quyền Accessibility")
		return
	}
	events.emit("done", "text", text, "ms", time.Since(t0).Milliseconds(), "note", note)
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// loadCleaner builds the personal dictionary (with hints learned from history)
// and the LLM cleaner that uses it.
func loadCleaner() (*Dictionary, Cleaner) {
	dict := LoadDictionary(getenv("MURMR_DICT", filepath.Join(configDir(), "dictionary.txt")))
	hist, _ := LoadHistory(historyPath())
	dict.Hints = LearnPairs(hist, LoadIgnored(ignoredPath()), learnMinCount)
	log.Printf("dictionary: %d terms, learned hints: %d (from %d dictations)", len(dict.Terms), len(dict.Hints), len(hist))
	system := dict.CleanupSystem(cleanupSystem)
	cleaner := pickCleaner(os.Getenv("MURMR_CLEANUP"), os.Getenv, system)
	// MURMR_FALLBACK names a second service to try when the first fails. It needs its own key, and it is the
	// user's choice because it sends the text to a service they did not pick as the main one.
	if backupID := os.Getenv("MURMR_FALLBACK"); cleaner != nil && backupID != "" && backupID != cleaner.Name() {
		if backup, err := buildCleaner(backupID, os.Getenv, system); err == nil {
			cleaner = &fallbackCleaner{primary: cleaner, backup: backup}
		} else {
			log.Printf("cleanup: no backup: %v", err)
		}
	}
	if cleaner != nil {
		log.Printf("cleanup: %s", cleaner.Name())
	} else {
		log.Printf("cleanup: off (raw whisper output)")
	}
	return dict, cleaner
}
