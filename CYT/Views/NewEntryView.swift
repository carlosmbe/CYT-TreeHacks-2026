import SwiftUI

struct NewEntryView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedMood: MoodLevel = .neutral
    @State private var showMoodPicker = false
    @State private var showImagePicker = false
    @State private var showAudioRecorder = false
    @State private var showHealthPicker = false

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
                                .frame(minHeight: 300)
                                .scrollContentBackground(.hidden)
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
            .sheet(isPresented: $showImagePicker) {
                placeholderSheet(title: "Add Photos", icon: "photo.on.rectangle", description: "Camera and photo library access will be available here.")
            }
            .sheet(isPresented: $showAudioRecorder) {
                placeholderSheet(title: "Voice Recording", icon: "mic.fill", description: "Record your thoughts. Speech-to-text transcription will process your audio locally on-device.")
            }
            .sheet(isPresented: $showHealthPicker) {
                placeholderSheet(title: "Health Snapshot", icon: "heart.text.clipboard", description: "Attach current health metrics from Apple Watch, Oura Ring, and AirPods.")
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

    // MARK: - Attachment Bar

    private var attachmentBar: some View {
        HStack(spacing: 0) {
            attachmentButton(icon: "photo.on.rectangle", label: "Photos") {
                showImagePicker = true
            }
            attachmentButton(icon: "mic.fill", label: "Voice") {
                showAudioRecorder = true
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

    // MARK: - Placeholder Sheets

    private func placeholderSheet(title: String, icon: String, description: String) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showImagePicker = false
                        showAudioRecorder = false
                        showHealthPicker = false
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Save

    private func saveEntry() {
        let entry = JournalEntry(
            title: title.isEmpty ? "Untitled" : title,
            body: bodyText,
            mood: selectedMood
        )
        store.addEntry(entry)
        dismiss()
    }
}

#Preview {
    NewEntryView()
        .environment(JournalStore())
}
