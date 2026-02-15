//
//  EmotionPrediction.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//


@preconcurrency import AVFoundation
import CoreML
import os

private let log = Logger(subsystem: "com.camysoftworks.dev.Test-Speech-Model", category: "EmotionClassifier")

struct EmotionPrediction: Sendable {
    let label: String
    let confidence: Float
    let allScores: [(label: String, score: Float)]
}

nonisolated
final class SpeechEmotionClassifier: @unchecked Sendable {

    // Wav2Vec2 emotion labels (4-class)
    static let emotionLabels = ["neutral", "angry", "happy", "sad"]

    private let model: MLModel

    init() throws {
        log.info("Loading EmotionClassifierDirect model (sync)...")
        let config = MLModelConfiguration()
        // Use cpuAndGPU to avoid the lengthy Neural Engine compilation on iPhone.
        // The ANE compile step can take minutes for large transformer models on first launch.
        config.computeUnits = .cpuAndGPU
        do {
            self.model = try EmotionClassifierDirect(configuration: config).model
            log.info("Model loaded successfully (cpuAndGPU)")
        } catch {
            log.error("Model failed to load: \(error.localizedDescription)")
            throw error
        }
    }

    /// Async factory that loads the pre-compiled model off the main thread.
    static func load() async throws -> SpeechEmotionClassifier {
        log.info("Loading EmotionClassifierDirect model (async)...")
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU

        let modelURL = EmotionClassifierDirect.urlOfModelInThisBundle
        log.info("Loading pre-compiled model from: \(modelURL.lastPathComponent)")

        let model = try await MLModel.load(contentsOf: modelURL, configuration: config)
        log.info("Model loaded successfully (async, cpuAndGPU)")
        return self.init(preloadedModel: model)
    }

    /// Internal init for pre-loaded model.
    private init(preloadedModel: MLModel) {
        self.model = preloadedModel
    }

    /// Classify the emotion in a bundled .wav file.
    func classify(wavResource name: String) throws -> EmotionPrediction {
        log.info("Looking up bundle resource: \(name).wav")
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            log.error("File not found in bundle: \(name).wav")
            throw ClassifierError.fileNotFound(name)
        }
        log.info("Found at: \(url.path)")
        return try classify(fileURL: url)
    }

    /// Classify the emotion in an audio file at the given URL.
    func classify(fileURL url: URL) throws -> EmotionPrediction {
        let samples = try loadAndPrepareAudio(url: url)
        return try predict(samples: samples)
    }

    // MARK: - Audio Loading

    /// Load a WAV file, resample to 16 kHz mono Float32, pad/truncate to 48000 samples.
    private func loadAndPrepareAudio(url: URL) throws -> [Float] {
        log.info("Loading audio from: \(url.lastPathComponent)")

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            log.error("AVAudioFile failed to open: \(error.localizedDescription)")
            throw error
        }

        let targetSampleRate: Double = 16000
        let targetLength = 48000

        let fileSampleRate = file.processingFormat.sampleRate
        let fileChannels = file.processingFormat.channelCount
        let fileFrames = file.length
        log.info("File format: \(fileSampleRate) Hz, \(fileChannels) ch, \(fileFrames) frames (\(String(format: "%.2f", Double(fileFrames) / fileSampleRate))s)")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            log.error("Failed to create target AVAudioFormat")
            throw ClassifierError.audioFormatError
        }

        // Read audio into a buffer at the file's native format, then convert
        let frameCount = AVAudioFrameCount(file.length)
        guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            log.error("Failed to allocate file PCM buffer (capacity: \(frameCount))")
            throw ClassifierError.audioFormatError
        }

        do {
            try file.read(into: fileBuffer)
            log.info("Read \(fileBuffer.frameLength) frames from file")
        } catch {
            log.error("Failed to read audio data: \(error.localizedDescription)")
            throw error
        }

        // Convert to target format if needed
        let buffer: AVAudioPCMBuffer
        if file.processingFormat.sampleRate == targetSampleRate &&
            file.processingFormat.channelCount == 1 {
            log.info("Audio already at 16kHz mono, no conversion needed")
            buffer = fileBuffer
        } else {
            log.info("Converting from \(fileSampleRate)Hz/\(fileChannels)ch to 16000Hz/1ch")
            guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
                log.error("Failed to create AVAudioConverter")
                throw ClassifierError.audioFormatError
            }
            let convertedCount = AVAudioFrameCount(
                Double(frameCount) * targetSampleRate / file.processingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: convertedCount) else {
                log.error("Failed to allocate converted PCM buffer (capacity: \(convertedCount))")
                throw ClassifierError.audioFormatError
            }
            var conversionError: NSError?
            converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .haveData
                return fileBuffer
            }
            if let conversionError {
                log.error("Audio conversion failed: \(conversionError.localizedDescription)")
                throw conversionError
            }
            log.info("Converted to \(convertedBuffer.frameLength) frames")
            buffer = convertedBuffer
        }

        guard let channelData = buffer.floatChannelData else {
            log.error("No float channel data in buffer")
            throw ClassifierError.audioFormatError
        }

        let sampleCount = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: targetLength)

        // Copy available samples (truncate if longer, zero-pad if shorter)
        let copyCount = min(sampleCount, targetLength)
        for i in 0..<copyCount {
            samples[i] = channelData[0][i]
        }

        if sampleCount < targetLength {
            log.info("Audio has \(sampleCount) samples, zero-padded to \(targetLength)")
        } else if sampleCount > targetLength {
            log.info("Audio has \(sampleCount) samples, truncated to \(targetLength)")
        } else {
            log.info("Audio exactly \(targetLength) samples, no padding needed")
        }

        return samples
    }

    // MARK: - Prediction

    private func predict(samples: [Float]) throws -> EmotionPrediction {
        log.info("Preparing MLMultiArray input [1, 48000]")
        let inputArray = try MLMultiArray(shape: [1, 48000], dataType: .float32)

        samples.withUnsafeBufferPointer { ptr in
            let dst = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 48000)
            ptr.baseAddress!.withMemoryRebound(to: Float.self, capacity: 48000) { src in
                dst.update(from: src, count: 48000)
            }
        }

        let input = try MLDictionaryFeatureProvider(
            dictionary: ["audio": MLFeatureValue(multiArray: inputArray)]
        )

        log.info("Running model inference...")
        let output: MLFeatureProvider
        do {
            output = try model.prediction(from: input)
        } catch {
            log.error("Model prediction threw: \(error.localizedDescription)")
            throw error
        }

        guard let logitsArray = output.featureValue(for: "var_920")?.multiArrayValue else {
            log.error("Output 'var_920' missing or not a MultiArray")
            throw ClassifierError.predictionFailed
        }

        // Extract [1, 1, 4] -> 4 raw values
        var rawValues = [Float](repeating: 0, count: 4)
        for i in 0..<4 {
            rawValues[i] = logitsArray[[0, 0, i] as [NSNumber]].floatValue
        }
        log.info("Raw output: \(rawValues.map { String(format: "%g", $0) }.joined(separator: ", "))")

        // The model outputs unnormalized scores (already exp'd), not logits.
        // Normalize directly instead of applying softmax again.
        let clampedValues = rawValues.map { max($0, 0) }  // ensure non-negative
        let sum = clampedValues.reduce(0, +)
        let probs: [Float]
        if sum > 0 {
            probs = clampedValues.map { $0 / sum }
        } else {
            log.warning("All outputs zero or negative, falling back to uniform")
            probs = [Float](repeating: 1.0 / 4.0, count: 4)
        }
        log.info("Normalized: \(zip(Self.emotionLabels, probs).map { "\($0.0)=\(String(format: "%.4f", $0.1))" }.joined(separator: ", "))")

        let allScores = zip(Self.emotionLabels, probs)
            .map { (label: $0.0, score: $0.1) }
            .sorted { $0.score > $1.score }

        let bestIdx = probs.indices.max(by: { probs[$0] < probs[$1] })!

        let resultLine = allScores.map { "\($0.label): \(String(format: "%.1f%%", $0.score * 100))" }.joined(separator: " | ")
        log.info("Result -> \(Self.emotionLabels[bestIdx]) (\(String(format: "%.1f%%", probs[bestIdx] * 100))) [\(resultLine)]")

        return EmotionPrediction(
            label: Self.emotionLabels[bestIdx],
            confidence: probs[bestIdx],
            allScores: allScores
        )
    }
}

enum ClassifierError: LocalizedError {
    case fileNotFound(String)
    case audioFormatError
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): "Audio file '\(name).wav' not found in bundle"
        case .audioFormatError: "Failed to process audio format"
        case .predictionFailed: "Model prediction failed"
        }
    }
}
