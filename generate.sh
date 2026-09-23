#!/usr/bin/env bash
# Text-to-image with Qwen-Image-2.1 on this Mac (M4 Max, MLX).
# Extra CLI flags are passed through and override the defaults.
#   ./generate.sh --prompt "..." --seed 7 --output outputs/bike.png
#   ./generate.sh --fast --prompt "..." --output outputs/bike.png
# --fast is 768 square, about 3s per step instead of 6s. Same 20 steps.
set -euo pipefail
cd "$(dirname "$0")"

width=1024
height=1024
args=()
for arg in "$@"; do
  if [[ "$arg" == "--fast" ]]; then
    width=768
    height=768
  else
    args+=("$arg")
  fi
done

exec .venv/bin/mflux-generate-qwen-2.1 \
  --model qwen-image-2.1 \
  -q 8 \
  --width "$width" \
  --height "$height" \
  --steps 20 \
  --guidance 1 \
  "${args[@]}"
