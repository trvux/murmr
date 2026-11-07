#!/bin/zsh
# Builds whisper-server as ONE self-contained file that runs on macOS 14 or later, into app/vendor/.
#
# Why not copy Homebrew's: it links dynamic libraries by absolute path (/opt/homebrew/...) and is built for the
# newest macOS only. Here the libraries are compiled in (static), Metal's GPU code is embedded, and the minimum
# macOS is set to 14, so the file works anywhere the app does. Needs: cmake (brew install cmake), git.
#
#   scripts/build-whisper.sh                  builds the pinned version
#   WHISPER_TAG=v1.9.6 scripts/build-whisper.sh   builds another release
set -euo pipefail
cd "${0:A:h}/.."   # app/

TAG="${WHISPER_TAG:-v1.9.5}"
SRC="vendor/whisper.cpp"
mkdir -p vendor

if [[ -d "$SRC/.git" ]] && [[ "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" != "$TAG" ]]; then
  echo "==> $SRC is not $TAG, fetching again"
  rm -rf "$SRC"
fi
if [[ ! -d "$SRC/.git" ]]; then
  echo "==> clone whisper.cpp $TAG"
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/whisper.cpp "$SRC"
fi

echo "==> configure"
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON > /dev/null

echo "==> build"
cmake --build "$SRC/build" --target whisper-server -j "$(sysctl -n hw.ncpu)" > "$SRC/build/build.log" 2>&1 \
  || { tail -20 "$SRC/build/build.log"; exit 1; }
cp "$SRC/build/bin/whisper-server" vendor/whisper-server

mkdir -p vendor/licenses
cp "$SRC/LICENSE" vendor/licenses/whisper.cpp-LICENSE.txt
[[ -f "$SRC/ggml/LICENSE" ]] && cp "$SRC/ggml/LICENSE" vendor/licenses/ggml-LICENSE.txt

echo "==> verify"
# 1. it must not depend on anything outside the system: that is the whole point
bad="$(otool -L vendor/whisper-server | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/|/usr/lib/)' || true)"
[[ -z "$bad" ]] || { echo "FAIL: links outside the system:\n$bad"; exit 1; }
# 2. it must accept macOS 14
minos="$(otool -l vendor/whisper-server | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
[[ "$minos" == "14.0" ]] || { echo "FAIL: minimum macOS is $minos, expected 14.0"; exit 1; }
echo "built: $PWD/vendor/whisper-server ($(du -h vendor/whisper-server | cut -f1), macOS $minos+, no outside libraries)"
