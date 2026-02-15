#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# Download NVIDIA Nemotron-Mini-4B-Instruct Q4_K_M (GGUF)
# ─────────────────────────────────────────────────────────
# Source: bartowski/Nemotron-Mini-4B-Instruct-GGUF on HuggingFace
# Size  : ~2.7 GB
# Quant : Q4_K_M  (4-bit, k-quant medium – best quality/size for mobile)
#
# Usage:
#   chmod +x scripts/download_nemotron.sh
#   ./scripts/download_nemotron.sh
#
# The model will be saved to CYT/nemotron-mini-4b-instruct-q4_k_m.gguf
# Then add this file to your Xcode project as a bundle resource.
# ─────────────────────────────────────────────────────────

set -euo pipefail

MODEL_URL="https://huggingface.co/bartowski/Nemotron-Mini-4B-Instruct-GGUF/resolve/main/Nemotron-Mini-4B-Instruct-Q4_K_M.gguf"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/CYT"
OUTPUT_FILE="${OUTPUT_DIR}/nemotron-mini-4b-instruct-q4_k_m.gguf"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  NVIDIA Nemotron-Mini-4B-Instruct Q4_K_M Downloader     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

if [ -f "$OUTPUT_FILE" ]; then
    echo "✓ Model already exists at:"
    echo "  $OUTPUT_FILE"
    echo ""
    echo "  Delete it and re-run if you want to re-download."
    exit 0
fi

echo "Downloading (~2.7 GB) …"
echo "  From: $MODEL_URL"
echo "  To:   $OUTPUT_FILE"
echo ""

curl -L --progress-bar -o "$OUTPUT_FILE" "$MODEL_URL"

echo ""
echo "✓ Download complete!"
echo "  File: $OUTPUT_FILE"
echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "Next steps:"
echo "  1. Open the Xcode project"
echo "  2. Drag the .gguf file into the CYT target (ensure 'Copy items if needed' is OFF)"
echo "  3. Verify it appears under Build Phases → Copy Bundle Resources"
