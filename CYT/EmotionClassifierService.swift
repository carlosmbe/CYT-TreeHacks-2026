//
//  EmotionClassifierService.swift
//  CYT
//
//  Runs EmotionClassifierDirect Core ML model on audio files in parallel with speech-to-text.
//  Expects 16kHz mono float32 audio. Returns top emotion label or nil if unavailable.
//

import AVFoundation
import CoreML
import Foundation

@MainActor
@Observable
final class EmotionClassifierService {

    private var model: MLModel?
    private let windowSize = 15_600
    private let sampleRate: Double = 16_000

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let modelURL = Bundle.main.url(
            forResource: "EmotionClassifierDirect",
            withExtension: "mlpackage"
        ) else {
            return
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            model = nil
        }
    }

    /// Classifies emotion from an audio file. Returns nil if model unavailable or classification fails.
    func classify(audioURL: URL) async -> String? {
        guard let model else { return nil }

        let winSize = windowSize
        let rate = sampleRate
        return await Task.detached(priority: .userInitiated) { [model] in
            Self.classifySync(audioURL: audioURL, model: model, windowSize: winSize, sampleRate: rate)
        }.value
    }

    private nonisolated static func classifySync(audioURL: URL, model: MLModel, windowSize: Int, sampleRate: Double) -> String? {
        do {
            let (format, buffer) = try loadAndConvertAudio(url: audioURL, sampleRate: sampleRate)
            let samples = extractFloatSamples(from: buffer, format: format)
            guard !samples.isEmpty else { return nil }

            var labelScores: [String: Double] = [:]
            var processedCount = 0

            for chunkStart in stride(from: 0, to: samples.count, by: windowSize) {
                let chunkEnd = min(chunkStart + windowSize, samples.count)
                let chunk = Array(samples[chunkStart..<chunkEnd])

                guard let mlArray = try? MLMultiArray(
                    shape: [windowSize as NSNumber],
                    dataType: .float32
                ) else { continue }

                for (i, sample) in chunk.enumerated() {
                    mlArray[i] = NSNumber(value: sample)
                }
                for i in chunk.count..<windowSize {
                    mlArray[i] = 0
                }

                let input = try? MLDictionaryFeatureProvider(dictionary: ["audio": mlArray])
                guard let input else { continue }

                let output = try? model.prediction(from: input)

                if let output {
                    if let prob = output.featureValue(for: "categoryProbability")?.dictionaryValue as? [String: Double] {
                        for (label, score) in prob {
                            labelScores[label, default: 0] += score
                        }
                        processedCount += 1
                    } else if let prob = output.featureValue(for: "labelProbability")?.dictionaryValue as? [String: Double] {
                        for (label, score) in prob {
                            labelScores[label, default: 0] += score
                        }
                        processedCount += 1
                    } else if let label = output.featureValue(for: "label")?.stringValue,
                              let score = output.featureValue(for: "labelProbability")?.doubleValue {
                        labelScores[label, default: 0] += score
                        processedCount += 1
                    }
                }
            }

            guard processedCount > 0 else { return nil }

            return labelScores.max(by: { $0.value < $1.value })?.key
        } catch {
            return nil
        }
    }

    private nonisolated static func loadAndConvertAudio(url: URL, sampleRate: Double) throws -> (AVAudioFormat, AVAudioPCMBuffer) {
        let file = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        let readBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: readBuffer)

        let frameRatio = sampleRate / Double(file.processingFormat.sampleRate)
        let outputFrameCapacity = AVAudioFrameCount(Double(readBuffer.frameLength) * frameRatio)
        let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity)!

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw NSError(domain: "EmotionClassifier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }

        var error: NSError?
        var inputOffset = 0
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputOffset >= Int(readBuffer.frameLength) {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputOffset = Int(readBuffer.frameLength)
            return readBuffer
        }
        converter.convert(to: buffer, error: &error, withInputFrom: inputBlock)

        if let error { throw error }
        return (targetFormat, buffer)
    }

    private nonisolated static func extractFloatSamples(from buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var samples: [Float] = []
        samples.reserveCapacity(frameLength * channelCount)
        for frame in 0..<frameLength {
            for ch in 0..<channelCount {
                samples.append(channelData[ch][frame])
            }
        }
        if channelCount > 1 {
            var mono: [Float] = []
            mono.reserveCapacity(frameLength)
            for i in stride(from: 0, to: samples.count, by: channelCount) {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += samples[i + ch]
                }
                mono.append(sum / Float(channelCount))
            }
            return mono
        }
        return samples
    }
}
