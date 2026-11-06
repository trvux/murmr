"""Generate golden-speaker test clips from the learner's recordings in ../clips.

Run:  cd ~/Documents/murmr/voice && .venv/bin/python gen.py
Writes out/<name>.wav (learner's timbre, native pronunciation) and
       out/<name>_native.wav (the plain macOS voice, for comparison).
"""
import glob
import os
import time

from convert import Golden, say_to_wav

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ITEMS = [
    ("push", "push"),
    ("pull_request", "pull request"),
    ("crash", "crash"),
    ("sentence", "Please push the pull request to the main branch."),
]

os.makedirs(OUT, exist_ok=True)
refs = sorted(glob.glob(os.path.join(HERE, "..", "clips", "*.wav")))
if not refs:
    raise SystemExit("no reference clips in ../clips")
print(f"reference clips: {len(refs)}")

t = time.time()
g = Golden(refs)
print(f"model loaded and voice embedded in {time.time() - t:.1f}s")

for name, text in ITEMS:
    t = time.time()
    g.speak(text, os.path.join(OUT, f"{name}.wav"))
    say_to_wav(text, os.path.join(OUT, f"{name}_native.wav"))
    print(f"  {name:14} {time.time() - t:.1f}s")

print("\ndone. listen with:")
print("  for n in push pull_request crash sentence; do echo $n native; afplay out/${n}_native.wav; echo $n your-voice; afplay out/$n.wav; done")
