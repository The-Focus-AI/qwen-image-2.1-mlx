#!/usr/bin/env bash
# Download the weight files each runner expects.
#
#   ./scripts/download_weights.sh mflux
#       Qwen/Qwen-Image-2.1 into the Hugging Face cache (~47 GB).
#       mflux reads it from there. Nothing is copied into this repo.
#
#   ./scripts/download_weights.sh official
#       leejet Q4_K diffusion (3.9 GB), Qwen3-VL Q4_K_M encoder (4.7 GB),
#       and a symlink to the official VAE. Files land in
#       stable-diffusion.cpp/models/. Requires the mflux snapshot first,
#       because the VAE is taken from that cache.
#
#   ./scripts/download_weights.sh uncensored
#       abenzerps UC Q4_K_M diffusion (4.3 GB) into the same models directory.
#       Also downloads the encoder and VAE link if they are missing.
#
#   ./scripts/download_weights.sh all
set -euo pipefail
cd "$(dirname "$0")/.."

root="$(pwd)"
sdcpp="${SDCPP_DIR:-"$root/stable-diffusion.cpp"}"
models="$sdcpp/models"
hf="$root/.venv/bin/hf"

if [[ ! -x "$hf" ]]; then
  echo "missing $hf; run ./scripts/setup_mflux.sh first" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $0 mflux|official|uncensored|all" >&2
  exit 1
fi

link_vae() {
  local cache="$HOME/.cache/huggingface/hub/models--Qwen--Qwen-Image-2.1/snapshots"
  local vae=""
  local snap
  if [[ ! -d "$cache" ]]; then
    echo "no Qwen-Image-2.1 snapshot in $cache; run: $0 mflux" >&2
    exit 1
  fi
  for snap in "$cache"/*; do
    if [[ -f "$snap/vae/diffusion_pytorch_model.safetensors" ]]; then
      vae="$snap/vae/diffusion_pytorch_model.safetensors"
    fi
  done
  if [[ -z "$vae" ]]; then
    echo "VAE not in the Hugging Face snapshot; run: $0 mflux" >&2
    exit 1
  fi
  mkdir -p "$models"
  ln -sfn "$vae" "$models/qwen_image_2.1_vae.safetensors"
  echo "vae -> $models/qwen_image_2.1_vae.safetensors"
}

download_mflux() {
  echo "downloading Qwen/Qwen-Image-2.1 into the Hugging Face cache (~47 GB)"
  "$hf" download Qwen/Qwen-Image-2.1
}

download_encoder() {
  mkdir -p "$models"
  echo "downloading Qwen3VL-8B-Instruct-Q4_K_M.gguf (4.7 GB)"
  "$hf" download Qwen/Qwen3-VL-8B-Instruct-GGUF \
    Qwen3VL-8B-Instruct-Q4_K_M.gguf \
    --local-dir "$models"
}

download_official() {
  mkdir -p "$models"
  echo "downloading qwen_image_2.1-Q4_K.gguf (3.9 GB)"
  "$hf" download leejet/Qwen-Image-2.1-GGUF \
    qwen_image_2.1-Q4_K.gguf \
    --local-dir "$models"
  download_encoder
  link_vae
}

download_uncensored() {
  mkdir -p "$models"
  echo "downloading qwen-image-2.1-UC-Q4_K_M.gguf (4.3 GB)"
  "$hf" download abenzerps/Qwen-Image-2.1-Uncensored-GGUF \
    qwen-image-2.1-UC-Q4_K_M.gguf \
    --local-dir "$models"
  if [[ ! -f "$models/Qwen3VL-8B-Instruct-Q4_K_M.gguf" ]]; then
    download_encoder
  fi
  if [[ ! -e "$models/qwen_image_2.1_vae.safetensors" ]]; then
    link_vae
  fi
}

for arg in "$@"; do
  case "$arg" in
    mflux) download_mflux ;;
    official) download_official ;;
    uncensored) download_uncensored ;;
    all)
      download_mflux
      download_official
      download_uncensored
      ;;
    *)
      echo "unknown target: $arg" >&2
      exit 1
      ;;
  esac
done

echo "done"
