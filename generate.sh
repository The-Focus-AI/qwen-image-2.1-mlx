#!/usr/bin/env bash
# Text-to-image with Qwen-Image-2.1 on this Mac (M4 Max, MLX).
# Extra CLI flags are passed through and override the defaults.
#   ./generate.sh --prompt "..." --seed 7
#   ./generate.sh --fast --prompt "..." --seed 7
# With no --output, the PNG lands in outputs/mflux/{size}-q8-20step/.
# --fast is 768 square, about 3s per step instead of 6s. Same 20 steps.
set -euo pipefail
cd "$(dirname "$0")"

width=1024
height=1024
steps=20
quantize=8
args=()
has_output=0
prompt=""
prev=""
for arg in "$@"; do
  if [[ "$arg" == "--fast" ]]; then
    width=768
    height=768
    prev=""
    continue
  fi
  case "$prev" in
    --output|-o) has_output=1 ;;
    --prompt|-p) prompt="$arg" ;;
    --width|-W) width="$arg" ;;
    --height|-H) height="$arg" ;;
    --steps) steps="$arg" ;;
    -q|--quantize) quantize="$arg" ;;
  esac
  args+=("$arg")
  prev="$arg"
done

if [[ "$has_output" -eq 0 ]]; then
  if [[ "$width" == "$height" ]]; then
    size="$width"
  else
    size="${width}x${height}"
  fi
  out_dir="outputs/mflux/${size}-q${quantize}-${steps}step"
  mkdir -p "$out_dir"
  stamp="$(date +%Y%m%d-%H%M%S)"
  out="${out_dir}/${stamp}.png"
  args+=(--output "$out" --metadata)
  if [[ -n "$prompt" ]]; then
    printf 'prompt: %s\nrunner: mflux\nquantize: %s\nsteps: %s\nguidance: 1\nsize: %sx%s\n' \
      "$prompt" "$quantize" "$steps" "$width" "$height" > "${out_dir}/${stamp}.txt"
  fi
  echo "writing ${out}" >&2
fi

exec .venv/bin/mflux-generate-qwen-2.1 \
  --model qwen-image-2.1 \
  -q "$quantize" \
  --width "$width" \
  --height "$height" \
  --steps "$steps" \
  --guidance 1 \
  "${args[@]}"
