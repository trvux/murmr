"""JSON-lines server around voice/convert.py, used by `./murmr drill`.

stdin : {"text": "...", "out": "/path/out.wav"}   one request per line
stdout: {"ready": true} once, then {"ok": true} or {"error": "..."} per request

Reference clips (the learner's voice): $MURMR_VOICE_REFS, default ../clips.
Third-party libraries print to stdout, which would corrupt the protocol, so the
real stdout is duplicated for protocol use and sys.stdout is pointed at stderr.
"""
import glob
import json
import os
import sys

proto = os.fdopen(os.dup(1), "w")
sys.stdout = sys.stderr

from convert import Golden

HERE = os.path.dirname(os.path.abspath(__file__))


def reply(obj):
    print(json.dumps(obj, ensure_ascii=False), file=proto, flush=True)


refs_dir = os.environ.get("MURMR_VOICE_REFS") or os.path.join(HERE, "..", "clips")
refs = sorted(glob.glob(os.path.join(refs_dir, "*.wav")))
if not refs:
    reply({"error": f"no reference clips in {refs_dir}"})
    raise SystemExit(1)

golden = Golden(refs)
reply({"ready": True})

for line in sys.stdin:
    try:
        req = json.loads(line)
        golden.speak(req["text"], req["out"])
        reply({"ok": True})
    except Exception as e:  # keep serving after a bad request
        reply({"error": str(e)})
