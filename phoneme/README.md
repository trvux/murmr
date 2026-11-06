# phoneme scorer (local, free)

Used by `./murmr drill` and `./murmr score`. Setup once:

    brew install uv espeak-ng
    cd phoneme && uv venv --python 3.12 .venv
    uv pip install --python .venv/bin/python torch transformers phonemizer soundfile numpy

The model (facebook/wav2vec2-xlsr-53-espeak-cv-ft, ~1.2GB) downloads on first run.
