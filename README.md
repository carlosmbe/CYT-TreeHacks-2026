# Project CYT - Vera: Your AI Wellness Companion

Project CYT (Carlos, Yash, Tom) is a voice-first mental wellness iOS app built at **TreeHacks 2026**. It features **Vera**, an AI conversational companion that listens, asks good questions, and helps you check in with yourself. Everything runs on-device for privacy — no cloud APIs, no data leaving your phone.

## What It Does

- **Voice Conversations**: Talk to Vera like you would a thoughtful friend. She listens, picks up on your tone, and asks questions that actually dig deeper.
- **Real-Time Emotion Detection**: A Core ML model analyzes your voice in real-time to understand how you're feeling — the background colors shift to match your mood.
- **Health-Aware Context**: Vera pulls in HealthKit data (heart rate, HRV, sleep, steps) to give responses that are grounded in how your body is actually doing.
- **RAG-Powered Knowledge**: On-device retrieval-augmented generation so Vera's advice is backed by real wellness knowledge, not generic platitudes.
- **Care Packages**: At the end of a session, you get personalized self-care suggestions — breathing exercises, music, movement, connection prompts — based on what came up in your conversation.
- **Live Activity + Dynamic Island**: See your conversation status, mood, and card suggestions right from your Lock Screen or Dynamic Island.
- **Picture-in-Picture**: Keep Vera visible while you use other apps.

## Requirements

- **Xcode** with iOS 26 SDK
- **iOS 26.0+** deployment target
- A device or simulator that supports Apple Intelligence (`FoundationModels` framework)

## Setup - Important!

This project uses large ML models that are **not included in the Git repo**. You need to download them separately before building.

### Step 1: Download the Model Zip Files

Download the following zip files from Google Drive:

| File | Size | Contents | Download |
|------|------|----------| ---------- |
| `CYT-Nemotron-Model.zip` | ~2.5 GB | NVIDIA Nemotron-Mini-4B-Instruct (quantized GGUF) — the main LLM that powers Vera | [Here](https://drive.google.com/file/d/1EXctUuIKNnKn1UccJYkbMao6zcc-kYPL/view?usp=share_link) |
| `MiniLMEmbedder.mlpackage.zip` | ~40 MB | MiniLM sentence embedder for RAG search | [Here](https://drive.google.com/file/d/1II_hYj9HjFEVll4hn6dfsfVjvCU-_axL/view?usp=share_link) |
| Optional `Emotion Recognition Wav2Vec2-IEMOCAP ` | ~180 MB |CoreML Port of `speechbrain/emotion-recognition-wav2vec2-IEMOCAP`| [Here](https://drive.google.com/file/d/1elYZgcwZJ4l6vBbMKI2VuBxPQzG-k-GZ/view?usp=share_link) |

### Step 2: Extract the Models into the Project

1. **Unzip `CYT-Nemotron-Model.zip`** — this will produce `CYT/nemotron-mini-4b-instruct-q4_k_m.gguf`. Place it so the file lives at:
   ```
   CYT-TreeHacks-2026/CYT/nemotron-mini-4b-instruct-q4_k_m.gguf
   ```

2. **Unzip `MiniLMEmbedder.mlpackage.zip`** — this will produce the `CYT/MiniLMEmbedder.mlpackage/` folder. Place it so the folder lives at:
   ```
   CYT-TreeHacks-2026/CYT/MiniLMEmbedder.mlpackage/
   ```

Both zips are structured so that if you unzip them from the project root directory, the files will land in the right place automatically.

### Step 3: Build and Run

Just open `CYT.xcodeproj` in Xcode, change the Developer Team and hit Run.

## Architecture

The app follows **MVVM + Services**:

```
ConversationView (SwiftUI)
  └─ ConversationViewModel (orchestrates everything)
      ├─ SpeechRecognizer       — AVAudioEngine + SFSpeechRecognizer, silence detection
      ├─ EmotionClassifierService — Core ML emotion classification on audio
      ├─ LLMService             — Nemotron-Mini-4B via llama.cpp, on-device
      ├─ RAGService             — MiniLM embedder + vector index for knowledge retrieval
      ├─ TextToSpeechService    — PocketTTS (local package), sentence-level pipelining
      ├─ HealthDataProvider     — HealthKit integration (HR, HRV, sleep, steps)
      └─ JournalStore           — JSON persistence for conversation journals
```
<img width="1920" height="1080" alt="Slide2" src="https://github.com/user-attachments/assets/5d63c154-a072-42dd-a3cd-0141f97a989a" />

### Conversation Flow

1. Tap the orb to start recording
2. 3 seconds of silence → auto-stop and process
3. In parallel: emotion classification on your audio + LLM generates a response with health context
4. Vera speaks back with sentence-level TTS pipelining
5. Recording auto-restarts — it's a natural conversation loop


## Built With

- Swift + SwiftUI
- llama.cpp (Nemotron-Mini-4B-Instruct, Q4_K_M quantization)
- Core ML (MiniLM embedder, emotion classifier)
- AVAudioEngine + Speech framework
- HealthKit
- ActivityKit (Live Activities + Dynamic Island)
- PocketTTS (on-device text-to-speech)

## Beautiful Pictures
<img width="1920" height="1080" alt="Slide4" src="https://github.com/user-attachments/assets/4b166016-5468-4422-9771-1d57369c1619" />

## Beautiful Video

Make sure to unmute 

https://github.com/user-attachments/assets/91bb3aa6-1241-4ef7-8c8d-c372960db38c

