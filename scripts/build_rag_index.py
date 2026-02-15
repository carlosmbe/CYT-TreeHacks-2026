#!/usr/bin/env python3
"""
Offline RAG Index Builder
=========================
Extracts text from PDF documents in health_docs/, chunks them, embeds
with all-MiniLM-L6-v2, and exports a JSON index that the iOS app
loads from its bundle at startup.

Usage:
    pip install sentence-transformers pymupdf
    python scripts/build_rag_index.py

Then add CYT/RAG/rag_index.json to your Xcode project as a bundle resource.

Output format (JSON):
    [
      {
        "chunk": {
          "id": "...",
          "documentID": "...",
          "source": "filename.pdf",
          "text": "...",
          "tokenStart": 0,
          "tokenEnd": 200
        },
        "vector": [0.012, -0.034, ...]
      },
      ...
    ]
"""

import json
import uuid
from pathlib import Path

import fitz  # PyMuPDF
from sentence_transformers import SentenceTransformer

# ---- Config ----
DOCS_DIR = Path("health_docs")
OUTPUT_PATH = Path("CYT/RAG/rag_index.json")
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
CHUNK_SIZE = 200   # whitespace tokens per chunk (fits MiniLM's 256 word-piece limit)
OVERLAP = 40       # overlap tokens between consecutive chunks


# ---------- PDF Text Extraction ----------

def extract_text_from_pdf(path: Path) -> str:
    """Extract all readable text from a PDF, page by page."""
    doc = fitz.open(str(path))
    pages = []
    for page in doc:
        text = page.get_text()
        if text.strip():
            pages.append(text)
    doc.close()
    return "\n".join(pages)


# ---------- Chunking ----------

def tokenize(text: str) -> list[str]:
    """Whitespace tokeniser."""
    return text.split()


def chunk_document(
    doc_id: str,
    source: str,
    text: str,
) -> list[dict]:
    tokens = tokenize(text)
    if not tokens:
        return []

    chunks = []
    start = 0
    while start < len(tokens):
        end = min(start + CHUNK_SIZE, len(tokens))
        chunk_text = " ".join(tokens[start:end])
        chunks.append(
            {
                "id": uuid.uuid4().hex,
                "documentID": doc_id,
                "source": source,
                "text": chunk_text,
                "tokenStart": start,
                "tokenEnd": end,
            }
        )
        if end == len(tokens):
            break
        start = max(0, end - OVERLAP)

    return chunks


# ---------- Main ----------

def main():
    if not DOCS_DIR.is_dir():
        raise SystemExit(f"❌  {DOCS_DIR} is not a directory.")

    # --- Gather PDFs ---
    doc_files = sorted(
        p for p in DOCS_DIR.iterdir()
        if p.suffix == ".pdf" and p.is_file()
    )
    if not doc_files:
        raise SystemExit(f"❌  No .pdf files found in {DOCS_DIR}")

    print(f"📄  Found {len(doc_files)} PDF(s) in {DOCS_DIR}")

    # --- Extract text & chunk ---
    all_chunks: list[dict] = []
    for path in doc_files:
        text = extract_text_from_pdf(path)
        doc_id = uuid.uuid4().hex
        chunks = chunk_document(doc_id=doc_id, source=path.name, text=text)
        print(f"   {path.name}: {len(chunks)} chunk(s)")
        all_chunks.extend(chunks)

    print(f"🔢  Total chunks: {len(all_chunks)}")

    # --- Embed ---
    print(f"🤖  Loading model: {MODEL_NAME}")
    model = SentenceTransformer(MODEL_NAME)

    texts = [c["text"] for c in all_chunks]
    print(f"⚡  Embedding {len(texts)} chunk(s)...")
    embeddings = model.encode(texts, normalize_embeddings=True, show_progress_bar=True)

    dimension = embeddings.shape[1]
    print(f"📐  Embedding dimension: {dimension}")

    # --- Build index records ---
    records = []
    for chunk, vector in zip(all_chunks, embeddings):
        records.append(
            {
                "chunk": chunk,
                "vector": vector.tolist(),
            }
        )

    # --- Write ---
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False)

    size_mb = OUTPUT_PATH.stat().st_size / (1024 * 1024)
    print(f"✅  Wrote {len(records)} records to {OUTPUT_PATH} ({size_mb:.1f} MB)")
    print(f"   Add this file to your Xcode project as a bundle resource.")


if __name__ == "__main__":
    main()
