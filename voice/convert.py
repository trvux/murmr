"""Golden speaker spike: native pronunciation, in the learner's own timbre.

  base:   macOS `say` (native American English)  -> the pronunciation comes from here
  target: the learner's own recordings           -> only the timbre is taken from here

OpenVoice V2's ToneColorConverter swaps the timbre of an existing utterance and
keeps its phonemes, so a dropped final consonant in the learner's clips is not
carried over (that is the property we want to verify with the phoneme scorer).

Safety notes (third-party code and a downloaded checkpoint):
  - torch.load is called with weights_only=True, so anything in the file other
    than tensors makes loading fail instead of executing.
  - the watermark model (wavmark) is not used or installed.
  - nothing here touches the network.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "OpenVoice"))

# openvoice.text imports Chinese text helpers at module level, but mandarin.py only
# calls them (inside functions) for Chinese input. We only use English, so stub them
# instead of installing three extra third-party packages for code that never runs.
from unittest.mock import MagicMock

for _name in ("jieba", "cn2an", "pypinyin"):
    sys.modules.setdefault(_name, MagicMock())

import torch
from openvoice.api import OpenVoiceBaseClass, ToneColorConverter

CKPT = os.path.join(HERE, "ckpt", "converter")
BASE_VOICE = os.environ.get("MURMR_BASE_VOICE", "Samantha")


class Converter(ToneColorConverter):
    """ToneColorConverter without the optional watermark model.

    The upstream __init__ cannot skip it (the base class rejects the
    `enable_watermark` kwarg), so we run the base __init__ directly.
    """

    def __init__(self, config_path: str, device: str = "cpu"):
        OpenVoiceBaseClass.__init__(self, config_path, device=device)
        self.watermark_model = None
        self.version = getattr(self.hps, "_version_", "v1")

    def load_ckpt(self, ckpt_path: str):
        ckpt = torch.load(ckpt_path, map_location=torch.device(self.device), weights_only=True)
        missing, unexpected = self.model.load_state_dict(ckpt["model"], strict=False)
        print(f"loaded {os.path.basename(ckpt_path)}: {len(missing)} missing, {len(unexpected)} unexpected keys")


def say_to_wav(text: str, path: str, voice: str = BASE_VOICE):
    """Native-pronunciation source audio from the macOS speech synthesizer (22.05kHz mono)."""
    with tempfile.NamedTemporaryFile(suffix=".aiff") as t:
        subprocess.run(["say", "-v", voice, "-o", t.name, text], check=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", t.name, "-ar", "22050", "-ac", "1", path], check=True)


class Golden:
    def __init__(self, refs: list[str]):
        self.conv = Converter(os.path.join(CKPT, "config.json"), device="cpu")
        self.conv.load_ckpt(os.path.join(CKPT, "checkpoint.pth"))
        self.tgt_se = self.conv.extract_se(refs)  # mean speaker embedding over the learner's clips

    def speak(self, text: str, out: str, tau: float = 0.3, voice: str = BASE_VOICE):
        """Write `text` read with native pronunciation but the learner's timbre."""
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "src.wav")
            say_to_wav(text, src, voice)
            src_se = self.conv.extract_se(src)
            self.conv.convert(audio_src_path=src, src_se=src_se, tgt_se=self.tgt_se, output_path=out, tau=tau)
