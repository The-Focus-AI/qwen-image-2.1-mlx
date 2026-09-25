#!/usr/bin/env bash
# Clone leejet/stable-diffusion.cpp into this repo and build the Metal CLI.
# The source is not part of this git tree. The web frontend target is skipped;
# it fails without examples/server/frontend/package.json.
#   ./scripts/setup_sdcpp.sh
set -euo pipefail
cd "$(dirname "$0")/.."

root="$(pwd)"
sdcpp="${SDCPP_DIR:-"$root/stable-diffusion.cpp"}"
commit="88411ef"

if [[ ! -d "$sdcpp/.git" ]]; then
  git clone https://github.com/leejet/stable-diffusion.cpp "$sdcpp"
fi

git -C "$sdcpp" fetch --depth 1 origin "$commit"
git -C "$sdcpp" checkout "$commit"
git -C "$sdcpp" submodule update --init ggml thirdparty/libwebp

cmake -S "$sdcpp" -B "$sdcpp/build" -DSD_METAL=ON
cmake --build "$sdcpp/build" --target sd-cli -j"$(sysctl -n hw.ncpu)"

echo "built $sdcpp/build/bin/sd-cli"
echo "Download weights with: ./scripts/download_weights.sh official"
