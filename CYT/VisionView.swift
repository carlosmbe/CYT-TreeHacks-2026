//
//  VisionView.swift
//  CYT
//
//  VLM-based image analysis with camera. Secondary to the main conversation UI.
//

import AVFoundation
import MLXLMCommon
import SwiftUI

extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

private let FRAME_DELAY = Duration.milliseconds(1)

struct VisionView: View {
    @State private var camera = CameraController()
    @State private var model = FastVLMModel()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var prompt = "Describe the image in English."
    @State private var promptSuffix = "Output should be brief, about 15 words or less."
    @State private var selectedCameraType: CameraType = .continuous
    @State private var isEditingPrompt = false

    var statusTextColor: Color {
        model.evaluationState == .processingPrompt ? .black : .white
    }

    var statusBackgroundColor: Color {
        switch model.evaluationState {
        case .idle: return .gray
        case .generatingResponse: return .green
        case .processingPrompt: return .yellow
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10.0) {
                        Picker("Camera Type", selection: $selectedCameraType) {
                            ForEach(CameraType.allCases, id: \.self) { cameraType in
                                Text(cameraType.rawValue.capitalized).tag(cameraType)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: selectedCameraType) { _, _ in
                            model.cancel()
                        }

                        if let framesToDisplay {
                            VideoFrameView(
                                frames: framesToDisplay,
                                cameraType: selectedCameraType,
                                action: { frame in processSingleFrame(frame) }
                            )
                            .aspectRatio(4/3, contentMode: .fit)
                            #if os(macOS)
                            .frame(maxWidth: 750)
                            #endif
                            .overlay(alignment: .top) {
                                if !model.promptTime.isEmpty {
                                    Text("TTFT \(model.promptTime)")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .monospaced()
                                        .padding(.vertical, 4.0)
                                        .padding(.horizontal, 6.0)
                                        .background { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)) }
                                        .padding(.top)
                                }
                            }
                            #if !os(macOS)
                            .overlay(alignment: .topTrailing) {
                                CameraControlsView(
                                    backCamera: $camera.backCamera,
                                    device: $camera.device,
                                    devices: $camera.devices
                                )
                                .padding()
                            }
                            #endif
                            .overlay(alignment: .bottom) {
                                if selectedCameraType == .continuous {
                                    Group {
                                        if model.evaluationState == .processingPrompt {
                                            HStack {
                                                ProgressView().tint(statusTextColor).controlSize(.small)
                                                Text(model.evaluationState.rawValue)
                                            }
                                        } else if model.evaluationState == .idle {
                                            HStack(spacing: 6.0) {
                                                Image(systemName: "clock.fill").font(.caption)
                                                Text(model.evaluationState.rawValue)
                                            }
                                        } else {
                                            HStack(spacing: 6.0) {
                                                Image(systemName: "lightbulb.fill").font(.caption)
                                                Text(model.evaluationState.rawValue)
                                            }
                                        }
                                    }
                                    .foregroundStyle(statusTextColor)
                                    .font(.caption).bold()
                                    .padding(.vertical, 6.0).padding(.horizontal, 8.0)
                                    .background(statusBackgroundColor)
                                    .clipShape(.capsule)
                                    .padding(.bottom)
                                }
                            }
                            #if os(macOS)
                            .frame(maxWidth: .infinity).frame(minWidth: 500).frame(minHeight: 375)
                            #endif
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                promptSections

                Section {
                    if model.output.isEmpty && model.running {
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            Text(model.output)
                                .foregroundStyle(isEditingPrompt ? .secondary : .primary)
                                .textSelection(.enabled)
                                #if os(macOS)
                                .font(.headline).fontWeight(.regular)
                                #endif
                        }
                        .frame(minHeight: 50.0, maxHeight: 200.0)
                    }
                } header: {
                    Text("Response")
                        #if os(macOS)
                        .font(.headline).padding(.bottom, 2.0)
                        #endif
                }

                #if os(macOS)
                Spacer()
                #endif
            }
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .task { camera.start() }
            .task { await model.load() }
            #if !os(macOS)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            #endif
            .task { await distributeVideoFrames() }
            .navigationTitle("Vision")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isEditingPrompt {
                        Button("Done") { isEditingPrompt = false }.fontWeight(.bold)
                    } else {
                        Menu {
                            Button("Describe image") {
                                prompt = "Describe the image in English."
                                promptSuffix = "Output should be brief, about 15 words or less."
                            }
                            Button("Facial expression") {
                                prompt = "What is this person's facial expression?"
                                promptSuffix = "Output only one or two words."
                            }
                            Button("Read text") {
                                prompt = "What is written in this image?"
                                promptSuffix = "Output only the text in the image."
                            }
                            #if !os(macOS)
                            Button("Customize...") { isEditingPrompt = true }
                            #endif
                        } label: { Text("Prompts") }
                    }
                }
            }
        }
    }

    var promptSummary: some View {
        Section("Prompt") {
            VStack(alignment: .leading, spacing: 4.0) {
                let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrompt.isEmpty {
                    Text(trimmedPrompt).foregroundStyle(.secondary)
                }
                let trimmedSuffix = promptSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSuffix.isEmpty {
                    Text(trimmedSuffix).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    var promptForm: some View {
        Group {
            #if os(iOS)
            Section("Prompt") {
                TextEditor(text: $prompt).frame(minHeight: 38)
            }
            Section("Prompt Suffix") {
                TextEditor(text: $promptSuffix).frame(minHeight: 38)
            }
            #elseif os(macOS)
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("Prompt").font(.headline)
                        TextEditor(text: $prompt)
                            .frame(height: 38)
                            .padding(.horizontal, 8.0).padding(.vertical, 10.0)
                            .background(Color(.textBackgroundColor)).cornerRadius(10.0)
                    }
                    VStack(alignment: .leading) {
                        Text("Prompt Suffix").font(.headline)
                        TextEditor(text: $promptSuffix)
                            .frame(height: 38)
                            .padding(.horizontal, 8.0).padding(.vertical, 10.0)
                            .background(Color(.textBackgroundColor)).cornerRadius(10.0)
                    }
                }
            }
            .padding(.vertical)
            #endif
        }
    }

    var promptSections: some View {
        Group {
            #if os(iOS)
            if isEditingPrompt { promptForm } else { promptSummary }
            #elseif os(macOS)
            promptForm
            #endif
        }
    }

    func analyzeVideoFrames(_ frames: AsyncStream<CVImageBuffer>) async {
        for await frame in frames {
            let userInput = UserInput(
                prompt: .text("\(prompt) \(promptSuffix)"),
                images: [.ciImage(CIImage(cvPixelBuffer: frame))]
            )
            let t = await model.generate(userInput)
            _ = await t.result
            do { try await Task.sleep(for: FRAME_DELAY) } catch { return }
        }
    }

    func distributeVideoFrames() async {
        let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
            camera.attach(continuation: $0)
        }
        let (framesToDisplay, framesToDisplayContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self, bufferingPolicy: .bufferingNewest(1)
        )
        self.framesToDisplay = framesToDisplay
        let (framesToAnalyze, framesToAnalyzeContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self, bufferingPolicy: .bufferingNewest(1)
        )
        async let distributeFrames: () = {
            for await sampleBuffer in frames {
                if let frame = sampleBuffer.imageBuffer {
                    framesToDisplayContinuation.yield(frame)
                    if await selectedCameraType == .continuous {
                        framesToAnalyzeContinuation.yield(frame)
                    }
                }
            }
            await MainActor.run {
                self.framesToDisplay = nil
                self.camera.detatch()
            }
            framesToDisplayContinuation.finish()
            framesToAnalyzeContinuation.finish()
        }()
        if selectedCameraType == .continuous {
            async let analyze: () = analyzeVideoFrames(framesToAnalyze)
            await distributeFrames
            await analyze
        } else {
            await distributeFrames
        }
    }

    func processSingleFrame(_ frame: CVImageBuffer) {
        Task { @MainActor in model.output = "" }
        let userInput = UserInput(
            prompt: .text("\(prompt) \(promptSuffix)"),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )
        Task { await model.generate(userInput) }
    }
}
