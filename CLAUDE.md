# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode-based iOS project (no SPM root package). Build and run through Xcode or:

```bash
xcodebuild -project CYT.xcodeproj -scheme CYT -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Deployment target: iOS 26.0** — requires Xcode with iOS 26 SDK. The app uses Apple Intelligence (`FoundationModels` framework) which is only available on iOS 26+.

There are no tests or linter configured in this project.

## Architecture

**CYT** is a voice-first mental wellness iOS app featuring **Vera**, an AI conversational companion. Everything runs on-device for privacy.

### Core Pattern: MVVM + Services

```
ConversationView (SwiftUI UI)
    └─ ConversationViewModel (@Observable, orchestrates everything)
        ├─ SpeechRecognizer      — AVAudioEngine + SFSpeechRecognizer, silence detection, writes 16kHz mono WAV
        ├─ EmotionClassifierService — Core ML model on audio chunks, returns emotion label
        ├─ LLMService            — Apple Intelligence FoundationModels (iOS 26), Vera persona
        ├─ TextToSpeechService   — FluidAudio/PocketTTS (local package), sentence-level pipelining
        ├─ HealthDataProvider    — HealthKit (HR, HRV, sleep, steps, respiratory), synthetic fallback
        └─ JournalStore          — JSON file persistence in Documents/
```

### Conversation Flow

1. User taps orb → `startRecording()` → AVAudioEngine tap streams to SpeechRecognizer + writes temp WAV
2. 3-second silence detected → `handleAutoStop()` → `stopAndProcess()`
3. Parallel: emotion classification on WAV file + LLM generation with last 6 messages + health context
4. TTS plays response with sentence-level pipelining (synthesize next while playing current)
5. Auto-restarts recording after TTS finishes

### Conversation State Machine

`idle` → `recording` → `processing` → `veraSpeaking` → `recording` (auto-continue loop)
`recording` ↔ `paused` (manual pause/resume)

### Targets

- **CYT** — Main app
- **VeraLiveActivityExtension** — Dynamic Island + Lock Screen widget showing conversation status, waveform bars, mood color, and card suggestions via ActivityKit

### Key Data Types (CarePackageModels.swift)

- `CarePackageCard` — contextual self-care suggestions (breathe, music, connect, move, express, rest, celebrate)
- `CarePackage` — end-of-session summary with cards, DJ session, health signals
- `CheckInSignals` — emotion label + confidence + health snapshot
- `ConversationActivityAttributes` — shared between app and widget for Live Activity state

### Local Packages

- `LocalPackages/FluidAudio/` — PocketTTS wrapper for on-device text-to-speech

### UI

- **Voice mode** (default): Central orb morphs by state (mic → waveform → spinner → glow)
- **Text mode**: Message bubbles with compact orb
- **AnimatedGradientBackground**: 7 drifting blobs at 30fps, colors shift instantly with detected mood
- **FloatingCardStack**: Side drawer with max 3 care cards, peek/reveal/dismiss gestures, auto-retract after 10s

## Conventions

- Uses Swift `@Observable` macro (not Combine/ObservableObject)
- Async/await throughout, structured concurrency with `Task` and `async let`
- Audio format: 16kHz mono WAV for emotion classifier compatibility
- LLM prompts include health context on first turn and last 6 messages for context window
- Card suggestions are rule-based (emotion thresholds + health data + turn count)
