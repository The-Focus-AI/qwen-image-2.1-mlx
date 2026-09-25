"""Generate every prompt in a JSON file, one process per image.

A single long-lived process keeps the text encoder and the Metal buffer cache
resident. After a few 1024 images that grew past this Mac's free memory and
the process was killed. A fresh process per image matches the CLI path, which
drops the encoder after encoding and exits cleanly.
"""

import argparse
import json
import subprocess
import time
from pathlib import Path


def output_dir(width: int, height: int, quantize: int, steps: int) -> Path:
    size = str(width) if width == height else f"{width}x{height}"
    return Path(f"outputs/mflux/{size}-q{quantize}-{steps}step")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompts", type=Path, default=Path("prompts/detailed.json"))
    parser.add_argument(
        "--out",
        type=Path,
        help="defaults to outputs/mflux/{size}-q{bits}-{steps}step",
    )
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--quantize", type=int, default=8)
    args = parser.parse_args()
    if args.out is None:
        args.out = output_dir(args.width, args.height, args.quantize, args.steps)

    jobs = json.loads(args.prompts.read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    log_path = args.out / "timings.jsonl"
    python = Path(__file__).resolve().parents[1] / ".venv" / "bin" / "mflux-generate-qwen-2.1"

    for job in jobs:
        image_path = args.out / f"{job['id']}.png"
        if image_path.exists():
            print(f"skip {job['id']}", flush=True)
            continue
        cmd = [
            str(python),
            "--model",
            "qwen-image-2.1",
            "-q",
            str(args.quantize),
            "--steps",
            str(args.steps),
            "--width",
            str(args.width),
            "--height",
            str(args.height),
            "--guidance",
            "1",
            "--seed",
            str(job["seed"]),
            "--prompt",
            job["prompt"],
            "--output",
            str(image_path),
            "--metadata",
        ]
        print(f"start {job['id']} seed={job['seed']} steps={args.steps}", flush=True)
        t0 = time.perf_counter()
        subprocess.run(cmd, check=True)
        elapsed = time.perf_counter() - t0
        record = {
            "id": job["id"],
            "seed": job["seed"],
            "steps": args.steps,
            "seconds": round(elapsed, 2),
            "path": str(image_path),
        }
        with log_path.open("a") as handle:
            handle.write(json.dumps(record) + "\n")
        print(f"done {job['id']} {elapsed:.1f}s", flush=True)


if __name__ == "__main__":
    main()
