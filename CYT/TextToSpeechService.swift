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
    private var playbackDelegate: AudioPlayerDelegate?
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

    /// Synthesize and play the response. Chunks by sentence and pipelines synthesis with playback:
    /// while one sentence plays, the next is synthesized.
    func speak(text: String) async {
        let sentences = Self.splitIntoSentences(text)
        guard !sentences.isEmpty else { return }

        var nextAudio: Data? = await synthesize(text: sentences[0])

        for i in 0..<sentences.count {
            let audioToPlay = nextAudio

            if i + 1 < sentences.count {
                let nextSentence = sentences[i + 1]
                async let next: Data? = synthesize(text: nextSentence)

                if let audioToPlay {
                    await playAndWait(audioData: audioToPlay)
                }

                nextAudio = await next
            } else {
                if let audioToPlay {
                    await playAndWait(audioData: audioToPlay)
                }
                break
            }
        }
    }

    /// Play WAV audio data and wait until playback finishes.
    private func playAndWait(audioData: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)

                let player = try AVAudioPlayer(data: audioData)
                let delegate = AudioPlayerDelegate {
                    Task { @MainActor [weak self] in
                        self?.playbackDelegate = nil
                    }
                    continuation.resume()
                }
                playbackDelegate = delegate
                player.delegate = delegate

                audioPlayer = player
                isPlaying = true
                player.play()
            } catch {
                isPlaying = false
                continuation.resume()
            }
        }
        isPlaying = false
        audioPlayer = nil
        playbackDelegate = nil
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sentinel = "\u{0001}"
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+"#) else { return [trimmed] }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let withSentinels = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: sentinel)
        let sentences = withSentinels.components(separatedBy: sentinel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sentences.isEmpty ? [trimmed] : sentences
    }

    /// Stop current playback.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
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
