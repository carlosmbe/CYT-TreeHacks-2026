//
//  PiPService.swift
//  CYT
//
//  Manages AVPictureInPictureController for background conversation display.
//  Renders PiPContentView into an AVSampleBufferDisplayLayer at ~1 Hz.
//  PiP keeps the app in a foreground rendering context, enabling GPU/Metal.
//

import AVFoundation
import AVKit
import SwiftUI
import UIKit
import os

@available(iOS 26.0, *)
@MainActor
@Observable
final class PiPService: NSObject {

    // MARK: - Public State

    private(set) var isPiPActive = false
    private(set) var userDismissedPiP = false

    // MARK: - PiP Infrastructure

    private var pipController: AVPictureInPictureController?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderer = PiPSampleBufferRenderer()
    private var renderTimer: Timer?
    private var possibleObservation: NSKeyValueObservation?

    /// Tiny UIView hosting the AVSampleBufferDisplayLayer. Must be in the view hierarchy.
    let hostView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        return view
    }()

    // MARK: - State Mirror (set by ConversationViewModel)

    var isRecording = false
    var audioLevel: Int = 0
    var moodColor: String = "neutral"
    var statusText: String = "Tap to talk to Vera"
    var sessionStart: Date = Date()
    var latestCardTitle: String?
    var latestCardIcon: String?

    private static let logger = Logger(subsystem: "com.cyt.vera", category: "PiP")

    // MARK: - Setup

    override init() {
        super.init()
    }

    /// Call once after hostView is added to the view hierarchy.
    func configure() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Self.logger.warning("PiP not supported on this device")
            return
        }

        displayLayer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        displayLayer.videoGravity = .resizeAspect
        hostView.layer.addSublayer(displayLayer)

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller

        renderFrame()
        startRenderLoop()

        // Watch for when PiP becomes possible (requires active audio session)
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                Self.logger.info("PiP isPossible changed: \(ctrl.isPictureInPicturePossible)")
                let _ = self // prevent unused capture warning
            }
        }

        Self.logger.info("PiP configured, isPossible: \(controller.isPictureInPicturePossible)")
    }

    /// Ensure audio session is active so PiP considers itself possible.
    /// Call before starting PiP if no recording/TTS is currently active.
    private func ensureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Self.logger.error("Failed to activate audio session for PiP: \(error.localizedDescription)")
        }
    }

    // MARK: - Start / Stop

    func startPiP() {
        guard let pipController else {
            Self.logger.warning("PiP controller not configured")
            return
        }

        // Ensure audio session is active — PiP requires it
        ensureAudioSession()

        // Render a fresh frame so the display layer has content
        renderFrame()

        guard pipController.isPictureInPicturePossible else {
            Self.logger.warning("PiP not possible — isPossible: \(pipController.isPictureInPicturePossible), audioSession active: \(AVAudioSession.sharedInstance().isOtherAudioPlaying)")
            return
        }

        userDismissedPiP = false
        pipController.startPictureInPicture()
        startRenderLoop()
        Self.logger.info("PiP start requested")
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
        stopRenderLoop()
        isPiPActive = false
    }

    func resetDismissFlag() {
        userDismissedPiP = false
    }

    // MARK: - Render Loop

    private func startRenderLoop() {
        stopRenderLoop()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderFrame()
            }
        }
        renderFrame()
    }

    private func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    private func renderFrame() {
        let view = PiPContentView(
            isRecording: isRecording,
            audioLevel: audioLevel,
            moodColor: moodColor,
            statusText: statusText,
            sessionStart: sessionStart,
            latestCardTitle: latestCardTitle,
            latestCardIcon: latestCardIcon
        )

        guard let sampleBuffer = renderer.render(view: view) else {
            Self.logger.error("Failed to render PiP frame")
            return
        }

        displayLayer.sampleBufferRenderer.flush()
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)

        // Tell the system playback state changed so PiP stays alive
        pipController?.invalidatePlaybackState()
    }

    /// Trigger an immediate re-render when conversation state changes.
    func setNeedsRender() {
        renderFrame()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 26.0, *)
extension PiPService: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            isPiPActive = true
            startRenderLoop()
            Self.logger.info("PiP started")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            isPiPActive = false
            userDismissedPiP = true
            stopRenderLoop()
            Self.logger.info("PiP stopped")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            Self.logger.error("PiP failed to start: \(error.localizedDescription)")
            isPiPActive = false
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 26.0, *)
extension PiPService: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // No-op: not real video playback
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // Could adjust render resolution if needed
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void
    ) {
        completion()
    }
}
