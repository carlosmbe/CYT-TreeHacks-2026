#!/usr/bin/env python3
"""
Download MiniLM tokenizer files for bundling in the iOS app.
=============================================================
Downloads the tokenizer config from HuggingFace so the app
can tokenize queries fully offline (no network needed on-device).

Files are renamed with a ``minilm_`` prefix to avoid collisions
with other tokenizer files (e.g. FastVLM) in the Xcode bundle.

Usage:
    pip install huggingface_hub
    python scripts/download_tokenizer.py

Output:
    CYT/minilm_tokenizer/minilm_tokenizer.json
    CYT/minilm_tokenizer/minilm_tokenizer_config.json

Add the two output files to your Xcode project as individual bundle resources.
"""

from huggingface_hub import hf_hub_download
from pathlib import Path
import shutil

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_DIR = Path("CYT/minilm_tokenizer")

# HuggingFace filename -> renamed bundle filename
FILES = {
    "tokenizer.json": "minilm_tokenizer.json",
    "tokenizer_config.json": "minilm_tokenizer_config.json",
}


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for hf_name, bundle_name in FILES.items():
        print(f"Downloading {hf_name}...")
        path = hf_hub_download(
            repo_id=MODEL_NAME,
            filename=hf_name,
            local_dir=OUTPUT_DIR,
        )
        dest = OUTPUT_DIR / bundle_name
        shutil.move(path, dest)
        print(f"  Saved to {dest}")

    print(f"\nDone. Add the files in '{OUTPUT_DIR}/' to your Xcode project as bundle resources.")


if __name__ == "__main__":
    main()
