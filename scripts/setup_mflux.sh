#!/usr/bin/env bash
# Install the pinned mflux into .venv. Does not download model weights.
#   ./scripts/setup_mflux.sh
#   ./scripts/download_weights.sh mflux
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v uv >/dev/null; then
  echo "uv is required: https://docs.astral.sh/uv/" >&2
  exit 1
fi

uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python \
  "mflux @ git+https://github.com/mflux-community/mflux.git@ada53237b2ac865bc649ef1d06ac1b19b6983865"

echo "mflux 0.20.0 (ada53237) is in .venv."
echo "Download weights with: ./scripts/download_weights.sh mflux"
