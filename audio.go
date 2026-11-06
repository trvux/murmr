package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"math"
	"sync"

	"github.com/gen2brain/malgo"
)

const sampleRate = 16000 // whisper wants 16kHz mono

// Recorder keeps a capture device initialised and only runs it while the
// hotkey is held, so the mic indicator is on only during dictation.
type Recorder struct {
	ctx    *malgo.AllocatedContext
	dev    *malgo.Device
	mu     sync.Mutex
	pcm    []int16
	active bool
}

func NewRecorder() (*Recorder, error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, fmt.Errorf("init audio context: %w", err)
	}
	r := &Recorder{ctx: ctx}

	cfg := malgo.DefaultDeviceConfig(malgo.Capture)
	cfg.Capture.Format = malgo.FormatS16
	cfg.Capture.Channels = 1
	cfg.SampleRate = sampleRate

	dev, err := malgo.InitDevice(ctx.Context, cfg, malgo.DeviceCallbacks{Data: r.onData})
	if err != nil {
		ctx.Uninit()
		ctx.Free()
		return nil, fmt.Errorf("init capture device: %w", err)
	}
	r.dev = dev
	return r, nil
}

// onData runs on the audio thread: keep it short, copy and return.
func (r *Recorder) onData(_, in []byte, frames uint32) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.active {
		return
	}
	n := int(frames)
	for i := 0; i < n; i++ {
		r.pcm = append(r.pcm, int16(binary.LittleEndian.Uint16(in[i*2:])))
	}
}

func (r *Recorder) Start() error {
	r.mu.Lock()
	r.pcm = r.pcm[:0]
	r.active = true
	r.mu.Unlock()
	return r.dev.Start()
}

// Stop ends the capture and returns the samples recorded since Start.
func (r *Recorder) Stop() []int16 {
	_ = r.dev.Stop()
	r.mu.Lock()
	defer r.mu.Unlock()
	r.active = false
	out := make([]int16, len(r.pcm))
	copy(out, r.pcm)
	return out
}

func (r *Recorder) Close() {
	r.dev.Uninit()
	_ = r.ctx.Uninit()
	r.ctx.Free()
}

// isSilent guards against whisper hallucinating ("Thanks for watching")
// on empty or near-empty audio.
func isSilent(pcm []int16) bool {
	return len(pcm) < sampleRate*3/10 || rms(pcm) < 0.003 // < 300ms or near-silent
}

// rms is the loudness of the clip on a 0..1 scale.
func rms(pcm []int16) float64 {
	if len(pcm) == 0 {
		return 0
	}
	var sum float64
	for _, s := range pcm {
		f := float64(s) / 32768
		sum += f * f
	}
	return math.Sqrt(sum / float64(len(pcm)))
}

func encodeWAV(pcm []int16) []byte {
	var b bytes.Buffer
	dataLen := uint32(len(pcm) * 2)
	b.WriteString("RIFF")
	binary.Write(&b, binary.LittleEndian, 36+dataLen)
	b.WriteString("WAVEfmt ")
	binary.Write(&b, binary.LittleEndian, uint32(16))           // fmt chunk size
	binary.Write(&b, binary.LittleEndian, uint16(1))            // PCM
	binary.Write(&b, binary.LittleEndian, uint16(1))            // mono
	binary.Write(&b, binary.LittleEndian, uint32(sampleRate))   // sample rate
	binary.Write(&b, binary.LittleEndian, uint32(sampleRate*2)) // byte rate
	binary.Write(&b, binary.LittleEndian, uint16(2))            // block align
	binary.Write(&b, binary.LittleEndian, uint16(16))           // bits per sample
	b.WriteString("data")
	binary.Write(&b, binary.LittleEndian, dataLen)
	binary.Write(&b, binary.LittleEndian, pcm)
	return b.Bytes()
}
