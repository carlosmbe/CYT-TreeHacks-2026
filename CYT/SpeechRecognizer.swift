//
//  SpeechRecognizer.swift
//  CYT
//
//  On-device speech-to-text using SFSpeechRecognizer and AVAudioEngine.
//  Writes audio to a temp file for parallel emotion classification.
//  Auto-stops when silence is detected for silenceDurationThreshold.
//

import AVFoundation
import Speech

@MainActor
@Observable
final class SpeechRecognizer {

    enum AuthorizationStatus {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    private(set) var isRecording = false
    private(set) var currentAmplitude: Float = 0

    /// Callback invoked when silence is detected for silenceDurationThreshold. Set before startRecording().
    var onEndOfSpeechDetected: (() async -> Void)?

    /// Callback for real-time amplitude updates (0.0–1.0 normalized RMS). Called on audio thread.
    var onAmplitudeUpdate: ((Float) -> Void)?

    /// Duration of silence (seconds) before auto-stop. Default 3.0.
    var silenceDurationThreshold: TimeInterval = 3.0

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let interruptEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptContinuation: CheckedContinuation<String, Error>?
    private var audioFile: AVAudioFile?
    private var tempAudioURL: URL?

    private final class SilenceState: @unchecked Sendable {
        let lock = NSLock()
        var sampleCount = 0
        var thresholdSamples = 0
        var hasFired = false
    }
    private let silenceState = SilenceState()
    private static let silenceAmplitudeThreshold: Float = 0.01

    private final class InterruptSpeechState: @unchecked Sendable {
        let lock = NSLock()
        var sampleCount = 0
        var thresholdSamples = 0
        var hasFired = false
    }
    private let interruptSpeechState = InterruptSpeechState()
    private static let interruptSpeechAmplitudeThreshold: Float = 0.02
    private static let interruptSpeechDurationSeconds: TimeInterval = 0.2
    private var interruptCallback: (() async -> Void)?
    private var isInterruptMonitoring = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.supportsOnDeviceRecognition = true
        updateAuthorizationStatus()

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(true, options: .notifyOthersOnDeactivation)
                if isRecording {
                    try? audioEngine.start()
                }
                if isInterruptMonitoring {
                    try? interruptEngine.start()
                }
            }
        }
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                self?.updateAuthorizationStatus()
            }
        }
    }

    private func updateAuthorizationStatus() {
        authorizationStatus = AuthorizationStatus(from: SFSpeechRecognizer.authorizationStatus())
    }

    func startRecording() throws {
        updateAuthorizationStatus()
        guard authorizationStatus == .authorized else {
            throw SpeechRecognizerError.authorizationDenied
        }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }
        guard !isRecording else { return }

        recognitionTask?.cancel()
        recognitionTask = nil

        // Clean up any stale tap/engine state from a previous session
        let inputNode = audioEngine.inputNode
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        inputNode.removeTap(onBus: 0)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let tempAudioURL else { throw SpeechRecognizerError.failedToCreateTempFile }

        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) ?? recordingFormat

        audioFile = try AVAudioFile(
            forWriting: tempAudioURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        recognitionRequest = request

        let converter = AVAudioConverter(from: recordingFormat, to: outputFormat)
        let bufferSize: AVAudioFrameCount = 4096

        silenceState.lock.lock()
        silenceState.sampleCount = 0
        silenceState.hasFired = false
        silenceState.thresholdSamples = Int(recordingFormat.sampleRate * silenceDurationThreshold)
        silenceState.lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Extract RMS amplitude for UI visualization
            let rms = Self.computeRMS(buffer: buffer)
            let amplitudeCallback = self?.onAmplitudeUpdate
            amplitudeCallback?(min(rms * 5.0, 1.0)) // normalized & boosted for visual range
            Task { @MainActor [weak self] in
                self?.currentAmplitude = min(rms * 5.0, 1.0)
            }

            Self.processSilenceDetection(
                buffer: buffer,
                sampleRate: recordingFormat.sampleRate,
                state: self?.silenceState,
                onFired: { [weak self] in
                    Task { @MainActor in
                        await self?.onEndOfSpeechDetected?()
                    }
                }
            )

            guard let self, let converter, let audioFile else { return }
            let frameRatio = Double(outputFormat.sampleRate) / Double(recordingFormat.sampleRate)
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: max(outputFrameCapacity, 1)
            ) else { return }
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if error == nil, outputBuffer.frameLength > 0 {
                try? audioFile.write(from: outputBuffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                transcriptContinuation?.resume(throwing: error)
                transcriptContinuation = nil
                return
            }
            if let result, result.isFinal {
                transcriptContinuation?.resume(returning: result.bestTranscription.formattedString)
                transcriptContinuation = nil
            }
        }

        isRecording = true
    }

    func stopRecording() async throws -> (transcript: String, audioURL: URL) {
        guard isRecording else {
            throw SpeechRecognizerError.notRecording
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioFile = nil
        isRecording = false
        currentAmplitude = 0

        let transcript: String
        do {
            transcript = try await withCheckedThrowingContinuation { continuation in
                transcriptContinuation = continuation
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self, let cont = transcriptContinuation else { return }
                    transcriptContinuation = nil
                    cont.resume(returning: "")
                }
            }
        } catch {
            transcript = ""
        }

        recognitionTask = nil

        guard let url = tempAudioURL else {
            throw SpeechRecognizerError.failedToCreateTempFile
        }
        tempAudioURL = nil

        return (transcript, url)
    }

    func cancelRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioFile = nil
        isRecording = false
        currentAmplitude = 0

        if let cont = transcriptContinuation {
            transcriptContinuation = nil
            cont.resume(returning: "")
        }
        recognitionTask = nil
        tempAudioURL = nil
    }

    func startInterruptMonitoring(onSpeechDetected: @escaping () async -> Void) {
        stopInterruptMonitoring()
        interruptCallback = onSpeechDetected
        isInterruptMonitoring = true
        interruptSpeechState.lock.lock()
        interruptSpeechState.sampleCount = 0
        interruptSpeechState.hasFired = false
        interruptSpeechState.lock.unlock()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = interruptEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            interruptSpeechState.lock.lock()
            interruptSpeechState.thresholdSamples = Int(format.sampleRate * Self.interruptSpeechDurationSeconds)
            interruptSpeechState.lock.unlock()

            let bufferSize: AVAudioFrameCount = 4096
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
                Self.processInterruptSpeechDetection(
                    buffer: buffer,
                    sampleRate: format.sampleRate,
                    state: self?.interruptSpeechState,
                    onFired: { [weak self] in
                        let callback = self?.interruptCallback
                        Task { @MainActor in
                            await callback?()
                        }
                    }
                )
            }

            interruptEngine.prepare()
            try interruptEngine.start()
        } catch {
            isInterruptMonitoring = false
            interruptCallback = nil
        }
    }

    func stopInterruptMonitoring() {
        guard isInterruptMonitoring else { return }
        isInterruptMonitoring = false
        if interruptEngine.isRunning {
            interruptEngine.inputNode.removeTap(onBus: 0)
            interruptEngine.stop()
        }
        interruptCallback = nil
    }

    private static func processInterruptSpeechDetection(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        state: InterruptSpeechState?,
        onFired: @escaping () -> Void
    ) {
        guard let state else { return }
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }

        var sumSq: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                let s = ptr[i]
                sumSq += s * s
            }
        }
        let rms = sqrt(sumSq / Float(frameLength * channelCount))

        state.lock.lock()
        if rms >= interruptSpeechAmplitudeThreshold {
            state.sampleCount += frameLength * channelCount
            if state.sampleCount >= state.thresholdSamples, !state.hasFired {
                state.hasFired = true
                state.lock.unlock()
                onFired()
                return
            }
        } else {
            state.sampleCount = 0
        }
        state.lock.unlock()
    }

    /// Compute RMS amplitude from an audio buffer (0.0–∞, typically 0–0.2 for speech).
    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumSq: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                let s = ptr[i]
                sumSq += s * s
            }
        }
        return sqrt(sumSq / Float(frameLength * channelCount))
    }

    private static func processSilenceDetection(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        state: SilenceState?,
        onFired: @escaping () -> Void
    ) {
        guard let state else { return }
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }

        var sumSq: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                let s = ptr[i]
                sumSq += s * s
            }
        }
        let rms = sqrt(sumSq / Float(frameLength * channelCount))

        state.lock.lock()
        if rms < silenceAmplitudeThreshold {
            state.sampleCount += frameLength * channelCount
            if state.sampleCount >= state.thresholdSamples, !state.hasFired {
                state.hasFired = true
                state.lock.unlock()
                onFired()
                return
            }
        } else {
            state.sampleCount = 0
        }
        state.lock.unlock()
    }
}

private extension SpeechRecognizer.AuthorizationStatus {
    init(from status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorized: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
}

enum SpeechRecognizerError: Error {
    case authorizationDenied
    case recognizerUnavailable
    case notRecording
    case failedToCreateTempFile
}
