# voice: "golden speaker" playback (optional, local, free)

Renders a sentence with native pronunciation in the learner's own voice, so
`./murmr drill` can play "your attempt" right next to "the same sentence, said right, in your voice".

- **pronunciation** comes from macOS `say -v Samantha`. It was the only voice that kept final
  consonants intact after conversion (phoneme-scorer accuracy 94-97%; Eddy/Reed/Shelley fell to 58-71%).
- **timbre** comes from your own recordings in `../clips/*.wav` (override: `MURMR_VOICE_REFS=<dir>`),
  swapped in by OpenVoice V2's ToneColorConverter.

## Setup

```sh
cd voice
git clone --depth 1 https://github.com/myshell-ai/OpenVoice.git
# newer librosa wants keyword arguments here
sed -i '' 's/librosa_mel_fn(sampling_rate, n_fft, num_mels, fmin, fmax)/librosa_mel_fn(sr=sampling_rate, n_fft=n_fft, n_mels=num_mels, fmin=fmin, fmax=fmax)/' OpenVoice/openvoice/mel_processing.py
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python torch librosa soundfile numpy inflect unidecode eng_to_ipa
mkdir -p ckpt/converter
for f in config.json checkpoint.pth; do
  curl -L -o ckpt/converter/$f https://huggingface.co/myshell-ai/OpenVoiceV2/resolve/main/converter/$f
done
```

Put a few recordings of your own voice in `../clips/` (16 kHz mono WAV works; `./murmr` can save them with `MURMR_SAVE=clips`).

## Safety notes

This runs third-party code and a downloaded checkpoint, so:

- the checkpoint is loaded with `torch.load(..., weights_only=True)`; anything other than plain
  tensors makes loading fail instead of executing. Its pickle references only
  `torch._utils._rebuild_tensor_v2`, `torch.FloatStorage` and `collections.OrderedDict`.
- the optional watermark model is not used, and the unused Chinese text helpers are stubbed
  (see `convert.py`) rather than installing extra packages.
- nothing here uses the network at run time, and your recordings never leave the machine.

Quality caveat: the converted voice sounds a little raspy and robotic, and conversion slightly
bends some vowels. Always check a new setup with `./murmr score <file.wav> "<text>"`.
