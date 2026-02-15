//
//  TextToSpeechService.swift
//  CYT
//
//  Wraps FluidAudio PocketTTS for on-device text-to-speech. Models auto-download from HuggingFace on first use.
//

import AVFoundation
import FluidAudio
import Foundation

@MainActor
@Observable
final class TextToSpeechService {

    private let pocketTts = PocketTtsManager()
    private var audioPlayer: AVAudioPlayer?
    private(set) var isInitialized = false
    private(set) var isPlaying = false

    init() {}

    /// Initialize TTS (downloads models on first use). Call before synthesize.
    func initialize() async {
        guard !isInitialized else { return }
        do {
            try await pocketTts.initialize()
            isInitialized = true
        } catch {
            isInitialized = false
        }
    }

    /// Synthesize text to WAV audio data. Returns nil if not initialized or synthesis fails.
    func synthesize(text: String) async -> Data? {
        guard isInitialized else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try await pocketTts.synthesize(text: trimmed)
        } catch {
            return nil
        }
    }

    /// Synthesize and play the response. Does nothing if TTS is disabled or synthesis fails.
    func speak(text: String) async {
        guard let audioData = await synthesize(text: text) else { return }
        await play(audioData: audioData)
    }

    /// Play WAV audio data.
    func play(audioData: Data) async {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(data: audioData)
            player.delegate = AudioPlayerDelegate { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                }
            }
            audioPlayer = player
            isPlaying = true
            player.play()
        } catch {
            isPlaying = false
        }
    }

    /// Stop current playback.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
