package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
)

// Op is one sound that differs from the expected pronunciation.
type Op struct {
	Kind      string  `json:"kind"` // "sub" or "del"
	Exp       string  `json:"exp"`
	Got       *string `json:"got"`
	Pos       string  `json:"pos"` // initial | medial | final
	Consonant bool    `json:"consonant"`
}

type WordScore struct {
	Word     string   `json:"word"`
	Expected []string `json:"expected"`
	Ops      []Op     `json:"ops"`
	OK       bool     `json:"ok"`
}

type Score struct {
	Text     string      `json:"text"`
	Heard    string      `json:"heard"`
	Words    []WordScore `json:"words"`
	Accuracy float64     `json:"accuracy"`
	Error    string      `json:"error"`
}

// Scorer talks to phoneme/score.py --serve over JSON lines, so the 1GB model
// is loaded once per session instead of once per clip.
type Scorer struct {
	cmd *exec.Cmd
	in  io.WriteCloser
	out *bufio.Reader
}

func StartScorer() (*Scorer, error) {
	dir := getenv("MURMR_PHONEME_DIR", "phoneme")
	py := filepath.Join(dir, ".venv", "bin", "python")
	if !fileExists(py) {
		return nil, fmt.Errorf("phoneme env missing at %s (see phoneme/README.md)", dir)
	}
	cmd := exec.Command(py, filepath.Join(dir, "score.py"), "--serve")
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
	s := &Scorer{cmd: cmd, in: in, out: bufio.NewReaderSize(out, 1<<20)}
	line, err := s.out.ReadBytes('\n') // {"ready": true} once the model is loaded
	if err != nil {
		return nil, fmt.Errorf("scorer died while loading (run phoneme/score.py by hand to see why): %w", err)
	}
	var ready struct{ Ready bool }
	if json.Unmarshal(line, &ready) != nil || !ready.Ready {
		return nil, fmt.Errorf("unexpected scorer output: %s", line)
	}
	return s, nil
}

func (s *Scorer) Score(wavPath, text string) (Score, error) {
	req, _ := json.Marshal(map[string]string{"wav": wavPath, "text": text})
	if _, err := s.in.Write(append(req, '\n')); err != nil {
		return Score{}, err
	}
	line, err := s.out.ReadBytes('\n')
	if err != nil {
		return Score{}, err
	}
	var sc Score
	if err := json.Unmarshal(line, &sc); err != nil {
		return Score{}, err
	}
	if sc.Error != "" {
		return sc, fmt.Errorf("scorer: %s", sc.Error)
	}
	return sc, nil
}

func (s *Scorer) Close() {
	s.in.Close()
	_ = s.cmd.Wait()
}
