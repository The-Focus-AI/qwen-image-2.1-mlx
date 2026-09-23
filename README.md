# Qwen-Image-2.1 on Apple Silicon

Local text-to-image for [Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) on a Mac, using [mflux](https://github.com/mflux-community/mflux) and MLX. The model runs on the Metal GPU.

The CUDA ComfyUI installer at [alesha-pro/tools](https://github.com/alesha-pro/tools/blob/main/qwen-image-2.1/INSTALL-WITH-AGENT.md) is for an NVIDIA GPU. It is pinned to a CUDA PyTorch wheel and does not run on this machine. This repo is the Apple Silicon path: mflux `0.20.0` at commit `ada53237`, which added `mflux-generate-qwen-2.1`.

Tested on a MacBook Pro with an M4 Max (40 GPU cores, 64 GB unified memory).

## Setup

Python 3.13 and [uv](https://docs.astral.sh/uv/) are required. The first generation downloads the official `Qwen/Qwen-Image-2.1` weights into the Hugging Face cache (`~/.cache/huggingface`). That download is about 47 GB. Later runs reuse it.

```bash
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python \
  "mflux @ git+https://github.com/mflux-community/mflux.git@ada53237b2ac865bc649ef1d06ac1b19b6983865"
```

## Generate

```bash
./generate.sh --prompt "A cobalt blue ceramic teapot on a worn oak table, morning window light" \
  --seed 42 --output outputs/teapot.png
```

Defaults are 1024×1024, 20 steps, guidance 1, and 8-bit diffusion weights. Later flags override those defaults. The text encoder stays bfloat16. mflux leaves it that way because quantizing it damages the prompt.

```bash
./generate.sh --fast --prompt "..." --seed 7 --output outputs/bike.png
```

`--fast` is 768×768 and the same 20 steps. Pass `--width` and `--height` for any other size that is a multiple of 32.

A short prompt such as "a red bicycle on a wet street" produced a fused frame. The same model with a prompt that names the object, the count, the material, the light, and the setting produced one bicycle with two intact wheels. Ten prompts used for that check are in `prompts/detailed.json`.

```bash
.venv/bin/python scripts/batch_generate.py \
  --prompts prompts/detailed.json \
  --out outputs/detailed-20 \
  --steps 20
```

The batch script starts a new process for each image. One long-lived process held the text encoder and the Metal buffer cache until the machine started swapping and the process was killed.

## What we measured

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

## Enlarge an image you like

Running again at a larger size with the same seed creates a new picture. To enlarge a PNG you already kept, use SeedVR2, which ships with mflux. The first run downloads that model separately.

```bash
.venv/bin/mflux-upscale-seedvr2 \
  --model seedvr2-3b \
  --image-path outputs/bike.png \
  --resolution 2x \
  --output outputs/bike-2x.png
```

SeedVR2 invents the extra detail, so small text and thin spokes can shift. A plain resize only stretches the pixels you already have.

## Not in this install

Instruction editing, several reference images, and transparent PNG output are not in the pinned mflux commit. A follow-up pull request was still open when this was set up. There is no ComfyUI server and nothing listens on port 8188.

The weights are under the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (non-commercial). mflux keeps its own license.
