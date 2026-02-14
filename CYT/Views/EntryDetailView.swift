import SwiftUI

struct EntryDetailView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var entry: JournalEntry
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                moodBadge

                if isEditing {
                    editableContent
                } else {
                    readOnlyContent
                }

                if !entry.healthSnapshot.isEmpty {
                    healthSnapshotSection
                }

                if let transcript = entry.audioTranscript, !transcript.isEmpty {
                    audioTranscriptSection(transcript)
                }

                if !entry.tags.isEmpty {
                    tagsSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isEditing ? "Edit Entry" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Done") {
                        store.updateEntry(entry)
                        isEditing = false
                    }
                    .fontWeight(.semibold)
                } else {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete Entry", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                store.deleteEntry(entry)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this entry? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Title", text: $entry.title)
                    .font(.title)
                    .fontWeight(.bold)
            } else {
                Text(entry.title)
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text(entry.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mood Badge

    private var moodBadge: some View {
        HStack(spacing: 6) {
            if isEditing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MoodLevel.allCases, id: \.self) { mood in
                            Button {
                                entry.mood = mood
                            } label: {
                                HStack(spacing: 4) {
                                    Text(mood.emoji)
                                    Text(mood.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(entry.mood == mood ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text(entry.mood.emoji)
                Text(entry.mood.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Content

    private var readOnlyContent: some View {
        Text(entry.body)
            .font(.body)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editableContent: some View {
        TextEditor(text: $entry.body)
            .frame(minHeight: 200)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Health Snapshot

    private var healthSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Snapshot")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.healthSnapshot) { metric in
                    HStack(spacing: 8) {
                        Image(systemName: metric.type.icon)
                            .foregroundStyle(metric.type.color)
                        VStack(alignment: .leading) {
                            Text(metric.formattedValue + " " + metric.type.unit)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(metric.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Audio Transcript

    private func audioTranscriptSection(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Voice Transcript", systemImage: "mic.fill")
                .font(.headline)

            Text(transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(entry.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

#Preview {
    NavigationStack {
        EntryDetailView(
            entry: JournalEntry(
                title: "Morning Reflection",
                body: "Woke up feeling rested today. Had a good meditation session and feel ready to tackle the day.",
                mood: .happy,
                tags: ["morning", "meditation"]
            )
        )
    }
    .environment(JournalStore())
}
