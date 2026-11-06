package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
)

// Voice talks to voice/speak_server.py over JSON lines. The server renders a
// sentence with native pronunciation in the learner's own voice (see voice/convert.py);
// keeping it running means the model is loaded once per drill, not once per sentence.
type Voice struct {
	cmd *exec.Cmd
	in  io.WriteCloser
	out *bufio.Reader
}

func StartVoice() (*Voice, error) {
	dir := getenv("MURMR_VOICE_DIR", "voice")
	py := filepath.Join(dir, ".venv", "bin", "python")
	if !fileExists(py) || !fileExists(filepath.Join(dir, "ckpt", "converter", "checkpoint.pth")) {
		return nil, fmt.Errorf("voice env not set up in %s (see voice/README.md)", dir)
	}
	return startVoiceProc(py, "-W", "ignore", filepath.Join(dir, "speak_server.py"))
}

func startVoiceProc(name string, args ...string) (*Voice, error) {
	cmd := exec.Command(name, args...)
	in, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	v := &Voice{cmd: cmd, in: in, out: bufio.NewReaderSize(out, 1<<16)}
	line, err := v.out.ReadBytes('\n') // {"ready": true} once the model is loaded
	if err != nil {
		return nil, fmt.Errorf("voice server died while loading (run voice/speak_server.py by hand to see why): %w", err)
	}
	var ready struct{ Ready bool }
	if json.Unmarshal(line, &ready) != nil || !ready.Ready {
		return nil, fmt.Errorf("unexpected voice server output: %s", line)
	}
	return v, nil
}

// Speak renders text to the WAV file at out.
func (v *Voice) Speak(text, out string) error {
	req, _ := json.Marshal(map[string]string{"text": text, "out": out})
	if _, err := v.in.Write(append(req, '\n')); err != nil {
		return err
	}
	line, err := v.out.ReadBytes('\n')
	if err != nil {
		return err
	}
	var resp struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}
	if err := json.Unmarshal(line, &resp); err != nil {
		return err
	}
	if resp.Error != "" {
		return fmt.Errorf("voice: %s", resp.Error)
	}
	return nil
}

func (v *Voice) Close() {
	v.in.Close()
	_ = v.cmd.Wait()
}
