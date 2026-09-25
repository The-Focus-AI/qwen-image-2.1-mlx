"""Text-to-image with the Metal stable-diffusion.cpp build.

The checkout is stable-diffusion.cpp/ inside this repo. Images go to
outputs/sdcpp/{official-q4|uncensored-q4}/{id}-{size}-{steps}step/image.png
next to a prompt.txt. An image that is already there is skipped.
"""

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SDCPP = ROOT / "stable-diffusion.cpp"
SD_CLI = SDCPP / "build" / "bin" / "sd-cli"

WEIGHTS = {
    "official": {
        "folder": "official-q4",
        "file": "qwen_image_2.1-Q4_K.gguf",
        "label": "leejet/Qwen-Image-2.1-GGUF qwen_image_2.1-Q4_K.gguf",
    },
    "uncensored": {
        "folder": "uncensored-q4",
        "file": "qwen-image-2.1-UC-Q4_K_M.gguf",
        "label": "abenzerps/Qwen-Image-2.1-Uncensored-GGUF qwen-image-2.1-UC-Q4_K_M.gguf",
    },
}


def run_dir(weights: str, job_id: str, width: int, height: int, steps: int) -> Path:
    size = str(width) if width == height else f"{width}x{height}"
    folder = WEIGHTS[weights]["folder"]
    return ROOT / "outputs" / "sdcpp" / folder / f"{job_id}-{size}-{steps}step"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompts", type=Path, default=ROOT / "prompts" / "sdcpp.json")
    parser.add_argument("--weights", choices=sorted(WEIGHTS), default="official")
    parser.add_argument("--id", action="append", dest="ids", help="run only these prompt ids")
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--cfg-scale", type=float, default=1.0)
    args = parser.parse_args()

    if not SD_CLI.is_file():
        raise SystemExit(f"missing {SD_CLI}; build sd-cli in {SDCPP}")

    spec = WEIGHTS[args.weights]
    diffusion = SDCPP / "models" / spec["file"]
    llm = SDCPP / "models" / "Qwen3VL-8B-Instruct-Q4_K_M.gguf"
    vae = SDCPP / "models" / "qwen_image_2.1_vae.safetensors"
    for path in (diffusion, llm, vae):
        if not path.exists():
            raise SystemExit(f"missing {path}")

    jobs = json.loads(args.prompts.read_text())
    if args.ids:
        wanted = set(args.ids)
        jobs = [job for job in jobs if job["id"] in wanted]
        missing = wanted - {job["id"] for job in jobs}
        if missing:
            raise SystemExit(f"unknown prompt id: {', '.join(sorted(missing))}")

    for job in jobs:
        folder = run_dir(args.weights, job["id"], args.width, args.height, args.steps)
        image = folder / "image.png"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "prompt.txt").write_text(
            f"prompt: {job['prompt']}\n"
            "runner: stable-diffusion.cpp Metal sd-cli\n"
            f"diffusion: {spec['label']}\n"
            "llm: Qwen3VL-8B-Instruct-Q4_K_M.gguf\n"
            "vae: official Qwen-Image-2.1 diffusers VAE\n"
            f"cfg-scale: {args.cfg_scale}\n"
            "sampler: euler\n"
            f"steps: {args.steps}\n"
            f"size: {args.width}x{args.height}\n"
            f"seed: {job['seed']}\n"
        )
        if image.exists():
            print(f"skip {folder.relative_to(ROOT)}", flush=True)
            continue
        print(f"start {job['id']} -> {folder.relative_to(ROOT)}", flush=True)
        subprocess.run(
            [
                str(SD_CLI),
                "--diffusion-model",
                str(diffusion),
                "--vae",
                str(vae),
                "--llm",
                str(llm),
                "-p",
                job["prompt"],
                "--cfg-scale",
                str(args.cfg_scale),
                "--sampling-method",
                "euler",
                "--steps",
                str(args.steps),
                "-W",
                str(args.width),
                "-H",
                str(args.height),
                "-s",
                str(job["seed"]),
                "-o",
                str(image),
            ],
            cwd=SDCPP,
            check=True,
        )
        print(f"done {job['id']}", flush=True)


if __name__ == "__main__":
    main()
