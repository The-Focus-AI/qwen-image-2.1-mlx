# Qwen-Image-2.1 on Apple Silicon

Local text-to-image for [Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) on a Mac. Two runners, both on the Metal GPU:

- **mflux** is the default. It loads the official diffusers weights through MLX. About 6 seconds per step at 1024, about 30 GB.
- **stable-diffusion.cpp** loads a Q4 GGUF. About 12.5 seconds per step at 1024, about 11 GB.

The CUDA ComfyUI installer at [alesha-pro/tools](https://github.com/alesha-pro/tools/blob/main/qwen-image-2.1/INSTALL-WITH-AGENT.md) is for an NVIDIA GPU. It is pinned to a CUDA PyTorch wheel and does not run on this machine.

Tested on a MacBook Pro with an M4 Max (40 GPU cores, 64 GB unified memory).

## What is not in this repo

mflux is installed into `.venv/`. stable-diffusion.cpp is cloned into `stable-diffusion.cpp/` inside this working tree. Both that checkout and the weight files are gitignored. This repo is the scripts that install them, download the files, and run generation.

| Piece | Where it ends up | Script |
|---|---|---|
| mflux `0.20.0` at `ada53237` | `.venv/` in this repo | `./scripts/setup_mflux.sh` |
| Official diffusers weights, ~47 GB | `~/.cache/huggingface` | `./scripts/download_weights.sh mflux` |
| stable-diffusion.cpp at `88411ef`, Metal `sd-cli` | `stable-diffusion.cpp/` in this repo | `./scripts/setup_sdcpp.sh` |
| Official Q4 GGUF, text encoder, VAE link | `stable-diffusion.cpp/models/` | `./scripts/download_weights.sh official` |
| Uncensored Q4 GGUF, 4.3 GB | same `models/` directory | `./scripts/download_weights.sh uncensored` |

`mise run setup` installs both runners and downloads every weight file. `mise run generate` runs the prompt files one at a time and skips any image already on disk.

```bash
mise run setup
mise run generate
mise tasks
```

Python 3.13, [uv](https://docs.astral.sh/uv/), `cmake`, and a Metal Mac are required. The GGUF VAE symlink points at the mflux snapshot, so that download runs first.

## Where images go

Each run is a directory named by the runner and the settings. The prompt sits beside the PNG: mflux writes a metadata JSON, and the GGUF script writes `prompt.txt`.

```
outputs/
  mflux/
    768-q8-20step/
    1024-q8-12step/
    1024-q8-20step/
    1024-q8-40step/
    2048x1152-q8-50step/
  sdcpp/
    official-q4/
      bicycle-1024-20step/
    uncensored-q4/
      bicycle-1024-20step/
```

Square sizes use the width only (`1024-q8-20step`). Other sizes use both (`2048x1152-q8-50step`). An image that is already in that directory is skipped.

## mflux

```bash
./generate.sh --prompt "A cobalt blue ceramic teapot on a worn oak table, morning window light" \
  --seed 42
```

With no `--output`, the PNG is written under `outputs/mflux/1024-q8-20step/`. `--fast` is 768×768 and uses `outputs/mflux/768-q8-20step/`. Pass `--output` to choose a file yourself.

Defaults are 1024×1024, 20 steps, guidance 1, and 8-bit diffusion weights. Later flags override those defaults. The text encoder stays bfloat16. mflux leaves it that way because quantizing it damages the prompt. Pass `--width` and `--height` for any other size that is a multiple of 32.

Ten prompts used to check that a specific prompt beats a short one are in `prompts/detailed.json`. A short prompt such as "a red bicycle on a wet street" produced a fused frame. The detailed bicycle prompt produced one bicycle with two intact wheels.

```bash
.venv/bin/python scripts/batch_generate.py --steps 20
```

That writes `outputs/mflux/1024-q8-20step/`. `--steps 12` writes `outputs/mflux/1024-q8-12step/`. `--width 768 --height 768` writes `outputs/mflux/768-q8-20step/`.

The batch script starts a new process for each image. One long-lived process held the text encoder and the Metal buffer cache until the machine started swapping and the process was killed.

### What we measured

Each step is one compiled forward pass of the 7B diffusion model. On this M4 Max the pass takes about 6 seconds at 1024, so 20 steps is a little over two minutes. Forty steps took about four minutes and did not look better on the prompts we tried. Twelve steps took about 81 seconds, and the bicycle spokes went soft, so the default stays at 20.

| Size | Seconds per step | 20-step image | Peak memory |
|---|---:|---:|---:|
| 1024×1024 | 6.0 | ~130 s | ~30 GB |
| 768×768 (`--fast`) | 3.1 | 79 s | 25 GB |
| 640×640 | 2.2 | ~45 s | 22 GB |
| 2048×1152, 50 steps | 19 | 942 s | 48 GB |

The wide 2048×1152 image is a native generation, not an upscale of a smaller one.

Weight precision does not speed this up. The sampler still multiplies in bfloat16, and `-q` only packs the diffusion weights before they are unpacked again. At 1024, full bfloat16 was 5.1 seconds per step, 4-bit was 5.8, 8-bit was 6.0, and 6-bit was 6.8. An 8 GB Metal cache cap did not help.

Guidance above 1 together with a negative prompt runs the diffusion pass twice per step. The default guidance of 1 does one pass.

### Enlarge an image you like

Running again at a larger size with the same seed creates a new picture. To enlarge a PNG you already kept, use SeedVR2, which ships with mflux. The first run downloads that model separately.

```bash
.venv/bin/mflux-upscale-seedvr2 \
  --model seedvr2-3b \
  --image-path outputs/mflux/1024-q8-40step/bike.png \
  --resolution 2x \
  --output outputs/mflux/1024-q8-40step/bike-2x.png
```

SeedVR2 invents the extra detail, so small text and thin spokes can shift. A plain resize only stretches the pixels you already have.

## GGUF

`./scripts/setup_sdcpp.sh` clones [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) into `stable-diffusion.cpp/` in this working tree, checks out `88411ef`, and builds `build/bin/sd-cli` with `-DSD_METAL=ON`. That directory is gitignored, along with its build and its weight files. A full `cmake --build` also tries to install a web frontend and fails without `examples/server/frontend/package.json`, so the script builds only `sd-cli`.

`./scripts/download_weights.sh official` places these files in `stable-diffusion.cpp/models/`:

| Role | File | From |
|---|---|---|
| Official diffusion | `qwen_image_2.1-Q4_K.gguf` (3.9 GB) | [leejet/Qwen-Image-2.1-GGUF](https://huggingface.co/leejet/Qwen-Image-2.1-GGUF) |
| Text encoder | `Qwen3VL-8B-Instruct-Q4_K_M.gguf` (4.7 GB) | [Qwen/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF) |
| VAE | `qwen_image_2.1_vae.safetensors` | symlink to the official diffusers VAE |

`./scripts/download_weights.sh uncensored` adds `qwen-image-2.1-UC-Q4_K_M.gguf` (4.3 GB) from [abenzerps/Qwen-Image-2.1-Uncensored-GGUF](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF).

Prompts are in `prompts/sdcpp.json`.

```bash
.venv/bin/python scripts/generate_sdcpp.py --weights official --id bicycle
.venv/bin/python scripts/generate_sdcpp.py --weights uncensored
```

`--weights official` is the leejet Q4 file. `--weights uncensored` is the UC Q4 file. Omit `--id` to run every prompt in the file. Output for the bicycle prompt is `outputs/sdcpp/official-q4/bicycle-1024-20step/image.png`, with `prompt.txt` beside it.

On this M4 Max a 1024 image is about 12.5 seconds per step and about 11 GB, against about 6 seconds and 30 GB for mflux q8. Five steps left the bicycle smeared. Twenty steps matched the mflux default. Guidance is 1 so each step is one forward; the upstream example uses `--cfg-scale 6`, which runs a second forward.

The uncensored card is the upstream Qwen-Image-2.1 weights with no safety checker. This `sd-cli` build has no checker either, and neither does mflux. On the prompts in `prompts/sdcpp.json`, including ones a checker would normally refuse, the official Q4 and the UC Q4 produced the same kind of image.

## Not in this install

Instruction editing, several reference images, and transparent PNG output are not in the pinned mflux commit. A follow-up pull request was still open when this was set up. There is no ComfyUI server and nothing listens on port 8188.

The weights are under the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (non-commercial). mflux keeps its own license.
