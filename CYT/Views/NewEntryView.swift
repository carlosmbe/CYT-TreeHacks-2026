import PhotosUI
import SwiftUI

struct NewEntryView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedMood: MoodLevel = .neutral
    @State private var showMoodPicker = false
    @State private var showAudioRecorder = false
    @State private var showHealthPicker = false
    @State private var showVideoPicker = false

    // Photo picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachedImages: [Data] = []

    // Voice memo
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var hasRecording = false
    @State private var transcriptText = ""
    @State private var isTranscribing = false

    // Video
    @State private var videoThumbnail: Data?

    // Pre-filled mood from vibe check
    var initialMood: MoodLevel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Mood indicator
                        moodSection

                        // Title
                        TextField("Title", text: $title)
                            .font(.title2)
                            .fontWeight(.bold)

                        // Body
                        ZStack(alignment: .topLeading) {
                            if bodyText.isEmpty {
                                Text("What's on your mind?")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                            }
                            TextEditor(text: $bodyText)
                                .frame(minHeight: 200)
                                .scrollContentBackground(.hidden)
                        }

                        // Attached media
                        if !attachedImages.isEmpty || hasRecording || videoThumbnail != nil {
                            attachedMediaSection
                        }
                    }
                    .padding()
                }

                Divider()

                // Bottom attachment bar
                attachmentBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty && bodyText.isEmpty)
                }
            }
            .sheet(isPresented: $showMoodPicker) {
                moodPickerSheet
            }
            .sheet(isPresented: $showAudioRecorder) {
                voiceRecorderSheet
            }
            .sheet(isPresented: $showHealthPicker) {
                healthPickerSheet
            }
            .sheet(isPresented: $showVideoPicker) {
                videoPickerSheet
            }
            .onChange(of: selectedPhotos) { _, newItems in
                loadPhotos(from: newItems)
            }
            .onAppear {
                if let mood = initialMood {
                    selectedMood = mood
                }
            }
        }
    }

    // MARK: - Mood Section

    private var moodSection: some View {
        Button {
            showMoodPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(selectedMood.emoji)
                    .font(.title)
                Text(selectedMood.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attached Media

    private var attachedMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Photos
                    ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, imageData in
                        if let uiImage = UIImage(data: imageData) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                Button {
                                    attachedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }

                    // Voice memo
                    if hasRecording {
                        VStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text("Voice Memo")
                                .font(.caption2)
                        }
                        .frame(width: 80, height: 80)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Video
                    if videoThumbnail != nil {
                        VStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            Text("Video")
                                .font(.caption2)
                        }
                        .frame(width: 80, height: 80)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - Attachment Bar

    private var attachmentBar: some View {
        HStack(spacing: 0) {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            ) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                    Text("Photos")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
            }

            attachmentButton(icon: "mic.fill", label: "Voice") {
                showAudioRecorder = true
            }
            attachmentButton(icon: "video.fill", label: "Video") {
                showVideoPicker = true
            }
            attachmentButton(icon: "heart.text.clipboard", label: "Health") {
                showHealthPicker = true
            }
            attachmentButton(icon: "face.smiling", label: "Mood") {
                showMoodPicker = true
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func attachmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mood Picker Sheet

    private var moodPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How are you feeling?")
                    .font(.title2)
                    .fontWeight(.bold)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(MoodLevel.allCases, id: \.self) { mood in
                        Button {
                            selectedMood = mood
                            showMoodPicker = false
                        } label: {
                            VStack(spacing: 8) {
                                Text(mood.emoji)
                                    .font(.system(size: 40))
                                Text(mood.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(selectedMood == mood ? .primary : .secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedMood == mood ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedMood == mood ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Spacer()
            }
            .padding(.top, 32)
            .presentationDetents([.medium])
        }
    }

    // MARK: - Voice Recorder Sheet

    private var voiceRecorderSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Waveform visualization
                HStack(spacing: 3) {
                    ForEach(0..<20, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isRecording ? .red : .gray.opacity(0.3))
                            .frame(width: 4, height: isRecording ? CGFloat.random(in: 8...40) : 8)
                            .animation(
                                isRecording ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.05) : .default,
                                value: isRecording
                            )
                    }
                }
                .frame(height: 50)

                // Timer
                Text(formatTime(recordingTime))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(isRecording ? .red : .primary)

                // Record button
                Button {
                    toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? .red.opacity(0.2) : .red.opacity(0.1))
                            .frame(width: 80, height: 80)
                            .scaleEffect(isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)

                        Circle()
                            .fill(.red)
                            .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                            .clipShape(isRecording ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(Circle()))
                            .animation(.easeInOut(duration: 0.2), value: isRecording)
                    }
                }

                if isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if !transcriptText.isEmpty {
                    VStack(spacing: 4) {
                        Text("Transcript")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transcriptText)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isRecording { stopRecording() }
                        showAudioRecorder = false
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Video Picker Sheet

    private var videoPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Attach Video")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Record or select a video to attach to your journal entry. VLM analysis of video frames coming soon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                PhotosPicker(
                    selection: .init(get: { nil }, set: { item in
                        if item != nil {
                            videoThumbnail = Data()
                            showVideoPicker = false
                        }
                    }),
                    matching: .videos
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showVideoPicker = false }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Health Picker Sheet

    private var healthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 48))
                    .foregroundStyle(.pink)
                Text("Health Snapshot")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Attach current health metrics from Apple Watch, Oura Ring, and AirPods.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHealthPicker = false }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Recording Helpers

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }

    private func stopRecording() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        hasRecording = true

        // Simulate transcription
        isTranscribing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTranscribing = false
            transcriptText = "Voice memo recorded. On-device transcription will process this locally."
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: - Photo Loading

    private func loadPhotos(from items: [PhotosPickerItem]) {
        for item in items {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    attachedImages.append(data)
                }
            }
        }
    }

    // MARK: - Save

    private func saveEntry() {
        var attachments: [EntryAttachment] = []

        for imageData in attachedImages {
            attachments.append(EntryAttachment(type: .image, data: imageData, label: "Photo"))
        }
        if hasRecording {
            attachments.append(EntryAttachment(type: .audio, label: "Voice Memo"))
        }
        if videoThumbnail != nil {
            attachments.append(EntryAttachment(type: .video, label: "Video"))
        }

        let entry = JournalEntry(
            title: title.isEmpty ? "Untitled" : title,
            body: bodyText,
            mood: selectedMood,
            attachments: attachments,
            audioTranscript: hasRecording ? transcriptText : nil
        )
        store.addEntry(entry)
        dismiss()
    }
}

#Preview {
    NewEntryView()
        .environment(JournalStore())
}
