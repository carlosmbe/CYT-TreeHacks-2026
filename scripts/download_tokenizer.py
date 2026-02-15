#!/usr/bin/env python3
"""
Download MiniLM tokenizer files for bundling in the iOS app.
=============================================================
Downloads the tokenizer config from HuggingFace so the app
can tokenize queries fully offline (no network needed on-device).

Usage:
    pip install huggingface_hub
    python scripts/download_tokenizer.py

Output:
    tokenizer/tokenizer.json
    tokenizer/tokenizer_config.json

Add the tokenizer/ folder to your Xcode project as a bundle resource.
"""

from huggingface_hub import hf_hub_download
from pathlib import Path

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_DIR = Path("tokenizer")

FILES = [
    "tokenizer.json",
    "tokenizer_config.json",
]


def main():
    OUTPUT_DIR.mkdir(exist_ok=True)

    for filename in FILES:
        print(f"Downloading {filename}...")
        path = hf_hub_download(
            repo_id=MODEL_NAME,
            filename=filename,
            local_dir=OUTPUT_DIR,
        )
        print(f"  Saved to {path}")

    print(f"\nDone. Add the '{OUTPUT_DIR}/' folder to your Xcode project as a bundle resource.")


if __name__ == "__main__":
    main()
