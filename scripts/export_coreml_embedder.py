#!/usr/bin/env python3
"""
Export sentence-transformers model to Core ML (.mlpackage)
==========================================================
Exports the same model used by build_rag_index.py so the on-device
query embeddings live in the same vector space as the pre-computed
document embeddings.

Recommended environment (use the included .venv):
    python3 -m venv .venv && source .venv/bin/activate
    pip install "coremltools==8.1" "torch==2.5.1" "transformers==4.46.0" "numpy<2"

Usage:
    python scripts/export_coreml_embedder.py \
        --model sentence-transformers/all-MiniLM-L6-v2 \
        --output MiniLMEmbedder.mlpackage \
        --max-length 128

Then drag the .mlpackage into your Xcode project (target: CYT).
Build once so Xcode generates the Swift wrapper class.
"""

import argparse

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer


class EmbedderWrapper(nn.Module):
    """Wraps a HuggingFace encoder so it returns a single tensor
    (last_hidden_state) instead of a dict."""

    def __init__(self, encoder: nn.Module):
        super().__init__()
        self.encoder = encoder

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        outputs = self.encoder(input_ids=input_ids, attention_mask=attention_mask)
        return outputs.last_hidden_state


def main():
    parser = argparse.ArgumentParser(description="Export embedding model to Core ML.")
    parser.add_argument(
        "--model",
        default="sentence-transformers/all-MiniLM-L6-v2",
        help="HuggingFace model name.",
    )
    parser.add_argument(
        "--output",
        default="MiniLMEmbedder.mlpackage",
        help="Output .mlpackage path.",
    )
    parser.add_argument(
        "--max-length",
        type=int,
        default=128,
        help="Max token sequence length (pad/truncate to this).",
    )
    args = parser.parse_args()

    seq_len = args.max_length

    print(f"Loading {args.model}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    base_model = AutoModel.from_pretrained(args.model)
    base_model.eval()

    wrapper = EmbedderWrapper(base_model)
    wrapper.eval()

    # Dummy input for tracing
    dummy = tokenizer(
        "hello world",
        return_tensors="pt",
        padding="max_length",
        max_length=seq_len,
        truncation=True,
    )

    print("Tracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (dummy["input_ids"], dummy["attention_mask"]))

    # Convert to Core ML
    print("Converting to Core ML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, seq_len), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, seq_len), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="last_hidden_state")],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.save(args.output)
    print(f"Saved {args.output}")
    print("Drag this into your Xcode project and build to generate Swift wrappers.")


if __name__ == "__main__":
    main()
