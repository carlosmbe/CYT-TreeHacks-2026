//
//  SpeechRecognizer.swift
//  CYT
//
//  On-device speech-to-text using SFSpeechRecognizer and AVAudioEngine.
//  Writes audio to a temp file for parallel emotion classification.
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

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptContinuation: CheckedContinuation<String, Error>?
    private var audioFile: AVAudioFile?
    private var tempAudioURL: URL?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.supportsOnDeviceRecognition = true
        updateAuthorizationStatus()
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

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
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

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

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
