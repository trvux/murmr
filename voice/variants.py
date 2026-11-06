"""Try to fix the "raspy / robotic" sound: vary the base voice and the reference clips.

Run:  cd ~/Documents/murmr/voice && .venv/bin/python -W ignore variants.py
Writes out/var_<voice>_<refs>.wav for the same sentence, so only one thing differs per file.
"""
import glob
import os
import time

from convert import Golden

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TEXT = "Please push the pull request to the main branch."

REFS = {
    "raw": sorted(glob.glob(os.path.join(HERE, "..", "clips", "*.wav"))),
    "clean": sorted(glob.glob(os.path.join(HERE, "ref_clean", "*.wav"))),  # denoised + loudness-normalised
}
# (label, macOS voice, which reference set)
RUNS = [
    ("samantha", "Samantha", "clean"),  # same voice as before, only the references differ -> isolates the denoising
    ("eddy", "Eddy (English (US))", "clean"),
    ("reed", "Reed (English (US))", "clean"),
    ("shelley", "Shelley (English (US))", "clean"),
]

os.makedirs(OUT, exist_ok=True)
cache = {}
for label, voice, refset in RUNS:
    if not REFS[refset]:
        raise SystemExit(f"no clips for reference set {refset!r}")
    t = time.time()
    if refset not in cache:
        cache[refset] = Golden(REFS[refset])
    path = os.path.join(OUT, f"var_{label}_{refset}.wav")
    cache[refset].speak(TEXT, path, voice=voice)
    print(f"  {label:10} refs={refset:6} {time.time() - t:.1f}s")

print("\nbaseline is out/sentence.wav (Samantha, raw refs). Listen with:")
print("  for f in out/sentence.wav out/var_*.wav; do echo $f; afplay $f; sleep 0.5; done")
