# Local RAG — Pre-computed Embeddings Architecture

This folder contains a local-first RAG pipeline for on-device retrieval-augmented
generation on iPhone. Document embeddings are **pre-computed offline** and bundled
with the app; only the user's query is embedded on-device at runtime.

Everything runs locally — no network calls at any point.

## Components

| File | Role |
|---|---|
| `RAGService.swift` | Orchestrator: loads index, searches, builds grounded prompts. |
| `VectorIndex.swift` | `BundledVectorIndex` — loads pre-computed index from app bundle. SIMD-accelerated cosine search via Accelerate/vDSP. |
| `CoreMLEmbedder.swift` | On-device query embedder using a Core ML sentence-transformer (`all-MiniLM-L6-v2`). Loads bundled tokenizer JSON directly into `Hub.Config` objects — no temp files or network. |
| `Embedder.swift` | `TextEmbeddingProvider` protocol + `EmbeddingError` enum. |
| `RAGTypes.swift` | `RAGChunk` and `RAGSearchHit` data types. |

## Offline Scripts (run on your Mac)

| Script | Purpose |
|---|---|
| `scripts/build_rag_index.py` | Extracts text from PDFs in `health_docs/`, chunks, embeds with sentence-transformers, exports `CYT/RAG/rag_index.json`. |
| `scripts/export_coreml_embedder.py` | Exports the same model to `MiniLMEmbedder.mlpackage` for on-device query embedding. |
| `scripts/download_tokenizer.py` | Downloads tokenizer files from HuggingFace, renames with `minilm_` prefix, saves to `CYT/minilm_tokenizer/`. |

## Setup — Step by Step

### 1. Prepare knowledge documents

Put your PDF files in the `health_docs/` folder at the project root.

### 2. Build the pre-computed index

```bash
pip install sentence-transformers pymupdf
python scripts/build_rag_index.py
```

This reads PDFs from `health_docs/`, chunks them (200 whitespace tokens, 40 overlap),
embeds with `all-MiniLM-L6-v2`, and writes `CYT/RAG/rag_index.json`.

Add `rag_index.json` to your Xcode project as a **bundle resource** (drag into
the project, check "Add to target: CYT").

### 3. Export the Core ML query embedder

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install "coremltools==8.1" "torch==2.5.1" "transformers==4.46.0" "numpy<2"
python scripts/export_coreml_embedder.py
```

Drag `MiniLMEmbedder.mlpackage` into the Xcode project (target: CYT) and build
once. Xcode generates a Swift wrapper class `MiniLMEmbedder`.

### 4. Download and bundle the tokenizer

```bash
pip install huggingface_hub
python scripts/download_tokenizer.py
```

This downloads `tokenizer.json` and `tokenizer_config.json`, renames them to
`minilm_tokenizer.json` and `minilm_tokenizer_config.json` (to avoid collisions
with FastVLM's tokenizer files), and saves them to `CYT/minilm_tokenizer/`.

Add both files to your Xcode project as **individual bundle resources**.

### 5. Add swift-transformers package

```
// In Xcode: File → Add Package Dependencies
// URL: https://github.com/huggingface/swift-transformers
```

This provides the `Tokenizers` and `Hub` modules used by `CoreMLEmbedder.swift`.

## Runtime Flow

```
User query
  │
  ├─ CoreMLEmbedder.embed(text:)    ← on-device, single query
  │
  ├─ BundledVectorIndex.search()    ← cosine similarity via vDSP
  │
  ├─ RAGService.makeGroundedPrompt() ← budget-capped to fit context window
  │
  └─ LLMService.chat()              ← NVIDIA Nemotron-Mini-4B via llama.cpp (on-device, multi-turn)
```

## Important

The **same embedding model** must be used for both:
- Offline index building (`build_rag_index.py` uses `all-MiniLM-L6-v2`)
- On-device query embedding (`CoreMLEmbedder` uses the exported `.mlpackage`)

If you change models, rebuild both the index and the `.mlpackage`.
