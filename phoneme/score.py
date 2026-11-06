"""Phoneme-level pronunciation scoring, fully local and free.

For a recording and the sentence the speaker was trying to say, compare
  expected phonemes  (espeak-ng IPA for the text)
  heard phonemes     (wav2vec2 phoneme recognizer on the audio)
and report, per word, which sounds were substituted, dropped or added.

Usage:
  score.py --wav a.wav --text "push the request"     one-shot, JSON on stdout
  score.py --serve                                   JSON lines on stdin -> stdout
                                                     (keeps the model loaded between clips)

Honest limits: the recognizer is itself imperfect and hears *acoustics*, so
single results are noisy. Patterns that repeat over many clips are the signal.
"""
import argparse
import json
import os
import sys

os.environ.setdefault("PHONEMIZER_ESPEAK_LIBRARY", "/opt/homebrew/lib/libespeak-ng.dylib")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

import numpy as np
import soundfile as sf
import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

MODEL = "facebook/wav2vec2-xlsr-53-espeak-cv-ft"
PAD_SECONDS = 0.4  # CTC tends to drop the first phoneme when speech starts at the very edge

# Variants that sound the same for our purposes. The length mark is ignored.
CANON = {"ᵻ": "ɪ", "ᵿ": "ʊ", "ɚ": "ə", "ɝ": "ə", "ɜ": "ə", "r": "ɹ", "ɐ": "ə", "ɫ": "l", "ɾ": "t"}
# Native speakers reduce the vowel of these words ("to" -> /tə/), so a schwa there is not an error.
FUNCTION_WORDS = {"to", "the", "a", "an", "of", "for", "and", "at", "from", "that", "can", "is", "are",
                  "was", "be", "been", "have", "has", "do", "in", "on", "as", "or", "but", "so", "we", "you"}
VOWEL_START = set("aeiouyæɑɒɔəɛɜɪʊʌɐøœɯ")


def canon(p: str) -> str:
    p = p.replace("ː", "")
    return CANON.get(p, p)


def is_vowel(p: str) -> bool:
    return bool(p) and p[0] in VOWEL_START


class Scorer:
    def __init__(self):
        self.proc = Wav2Vec2Processor.from_pretrained(MODEL)
        self.tok = self.proc.tokenizer
        self.model = Wav2Vec2ForCTC.from_pretrained(MODEL).eval()

    def expected(self, word: str) -> list[str]:
        ids = self.tok(word).input_ids
        toks = self.tok.decode(ids).split()
        return [canon(t) for t in toks if t not in ("<unk>", "|")]

    def expected_words(self, words: list[str]) -> list[list[str]]:
        """Phonemize the whole sentence so espeak applies context (weak forms like
        "a" -> /ə/, flapped t). The tokenizer marks word boundaries with <unk>.
        Falls back to word-by-word if the boundaries don't line up."""
        toks = self.tok.decode(self.tok(" ".join(words)).input_ids).split()
        groups = [[]]
        for t in toks:
            if t == "<unk>":
                groups.append([])
            else:
                groups[-1].append(canon(t))
        groups = [g for g in groups if g]
        if len(groups) == len(words):
            return groups
        return [self.expected(w) for w in words]

    def heard(self, wav_path: str) -> list[str]:
        audio, sr = sf.read(wav_path, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        if sr != 16000:
            raise ValueError(f"need 16kHz audio, got {sr}")
        pad = np.zeros(int(PAD_SECONDS * sr), dtype="float32")
        audio = np.concatenate([pad, audio, pad])
        x = self.proc(audio, sampling_rate=16000, return_tensors="pt").input_values
        with torch.no_grad():
            ids = self.model(x).logits.argmax(-1)
        return [canon(t) for t in self.tok.decode(ids[0]).split() if t not in ("<unk>", "|")]

    def score(self, wav_path: str, text: str) -> dict:
        words = [w.strip(".,!?;:\"'()") for w in text.split()]
        words = [w for w in words if w]
        exp_by_word = self.expected_words(words)
        exp = [(wi, p) for wi, ps in enumerate(exp_by_word) for p in ps]
        got = self.heard(wav_path)
        pairs = align([p for _, p in exp], got)

        res = [{"word": w, "expected": ps, "ops": [], "ok": True} for w, ps in zip(words, exp_by_word)]
        pos_in_word = {}
        for wi, ps in enumerate(exp_by_word):
            for k, _ in enumerate(ps):
                pos_in_word[(wi, k)] = "initial" if k == 0 else ("final" if k == len(ps) - 1 else "medial")
        counters = {}
        for ei, gi in pairs:
            if ei is None:
                continue  # extra heard sound; recorded below as an insertion only if it sits inside a word
            wi, p = exp[ei]
            k = counters.get(wi, 0)
            counters[wi] = k + 1
            g = got[gi] if gi is not None else None
            if g == p:
                continue
            if res[wi]["word"].lower() in FUNCTION_WORDS and is_vowel(p) and g in ("ə", "ɪ"):
                continue
            res[wi]["ok"] = False
            res[wi]["ops"].append({
                "kind": "del" if g is None else "sub",
                "exp": p,
                "got": g,
                "pos": pos_in_word[(wi, k)],
                "consonant": not is_vowel(p),
            })
        n_exp = len(exp)
        n_bad = sum(len(w["ops"]) for w in res)
        return {
            "text": text,
            "heard": " ".join(got),
            "words": res,
            "accuracy": round(1 - n_bad / n_exp, 3) if n_exp else None,
        }


def align(a: list[str], b: list[str]):
    """Align expected phonemes `a` to heard phonemes `b`.

    Semi-global: heard sounds before/after the expected span are free (silence
    artefacts, a neighbouring word), but every expected phoneme must be matched,
    substituted or counted as dropped. Returns [(i|None, j|None)].
    """
    n, m = len(a), len(b)
    INF = 10 ** 9
    d = [[INF] * (m + 1) for _ in range(n + 1)]
    for j in range(m + 1):
        d[0][j] = 0  # free leading heard sounds
    for i in range(1, n + 1):
        d[i][0] = i
        for j in range(1, m + 1):
            sub = d[i - 1][j - 1] + (0 if a[i - 1] == b[j - 1] else 1)
            d[i][j] = min(sub, d[i - 1][j] + 1, d[i][j - 1] + 1)
    j = min(range(m + 1), key=lambda jj: d[n][jj])  # free trailing heard sounds
    out = []
    i = n
    while i > 0:
        if j > 0 and d[i][j] == d[i - 1][j - 1] + (0 if a[i - 1] == b[j - 1] else 1):
            out.append((i - 1, j - 1))
            i, j = i - 1, j - 1
        elif d[i][j] == d[i - 1][j] + 1:
            out.append((i - 1, None))
            i -= 1
        else:
            j -= 1  # skip an inserted heard sound
    out.reverse()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav")
    ap.add_argument("--text")
    ap.add_argument("--serve", action="store_true")
    args = ap.parse_args()

    sc = Scorer()
    if args.serve:
        print(json.dumps({"ready": True}), flush=True)
        for line in sys.stdin:
            try:
                req = json.loads(line)
                out = sc.score(req["wav"], req["text"])
            except Exception as e:  # keep serving after a bad request
                out = {"error": str(e)}
            print(json.dumps(out, ensure_ascii=False), flush=True)
        return
    if not (args.wav and args.text):
        ap.error("need --wav and --text, or --serve")
    print(json.dumps(sc.score(args.wav, args.text), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
