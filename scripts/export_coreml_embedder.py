#!/usr/bin/env python3
"""
Export sentence-transformers model to Core ML (.mlpackage)
==========================================================
Exports all-MiniLM-L6-v2 so the on-device query embeddings live in the
same vector space as the pre-computed document embeddings.

Recommended environment:
    python3 -m venv .venv && source .venv/bin/activate
    pip install "coremltools==8.1" "torch==2.5.1" "transformers==4.46.0" "numpy<2"

Usage:
    python scripts/export_coreml_embedder.py

Then drag MiniLMEmbedder.mlpackage into your Xcode project (target: CYT).
Build once so Xcode generates the Swift wrapper class.
"""

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer

# ---- Config ----
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_PATH = "MiniLMEmbedder.mlpackage"
MAX_LENGTH = 256


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
    print(f"Loading {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    base_model = AutoModel.from_pretrained(MODEL_NAME)
    base_model.eval()

    wrapper = EmbedderWrapper(base_model)
    wrapper.eval()

    # Dummy input for tracing
    dummy = tokenizer(
        "hello world",
        return_tensors="pt",
        padding="max_length",
        max_length=MAX_LENGTH,
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
            ct.TensorType(name="input_ids", shape=(1, MAX_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LENGTH), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="last_hidden_state")],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.save(OUTPUT_PATH)
    print(f"Saved {OUTPUT_PATH}")
    print("Drag this into your Xcode project and build to generate Swift wrappers.")


if __name__ == "__main__":
    main()
