//
//  JournalEntryView.swift
//  CYT
//
//  In-app journal: shows check-in context, writing area, and care plan.
//

import SwiftUI

struct JournalEntryView: View {
    let package: CarePackage
    @Environment(JournalStore.self) private var journalStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var saved = false
    @FocusState private var isWriting: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Context Recap
                contextSection

                Divider()

                // MARK: - Writing Area
                writingSection

                Divider()

                // MARK: - Your Care Plan
                carePlanSection

                // MARK: - Save
                saveButton
            }
            .padding(20)
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How you're doing", systemImage: "sparkle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(package.personalNote)
                .font(.body)
                .lineSpacing(3)

            HStack(spacing: 12) {
                emotionBadge
                vitalsSummary
            }
        }
    }

    private var emotionBadge: some View {
        let signals = package.signals
        return HStack(spacing: 4) {
            Circle()
                .fill(emotionColor(signals.emotionLabel))
                .frame(width: 8, height: 8)
            Text("\(signals.emotionLabel) (\(Int(signals.emotionConfidence * 100))%)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(emotionColor(signals.emotionLabel).opacity(0.1))
        .clipShape(Capsule())
    }

    private var vitalsSummary: some View {
        let h = package.signals.healthSnapshot
        var parts: [String] = []
        if let sleep = h.sleepHours { parts.append("\(Int(sleep))h sleep") }
        if let hrv = h.hrv { parts.append("HRV \(Int(hrv))ms") }
        if let steps = h.stepCount { parts.append("\(Int(steps)) steps") }

        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Writing

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(package.followUpQuestion)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .focused($isWriting)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write what's on your mind...")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Care Plan

    private var carePlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your self-care plan for today")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(package.cards) { card in
                    HStack(spacing: 6) {
                        Image(systemName: card.sfSymbol)
                            .font(.caption2)
                            .foregroundStyle(card.color)
                        Text(card.title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(card.color.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            let entry = JournalEntry(
                text: text,
                timestamp: Date(),
                emotionLabel: package.signals.emotionLabel,
                personalNote: package.personalNote,
                cardTitles: package.cards.map(\.title)
            )
            journalStore.save(entry)
            saved = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                Text(saved ? "Saved" : "Save Entry")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(saved ? Color.green.gradient : Color.blue.gradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(saved)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func emotionColor(_ label: String) -> Color {
        switch label {
        case "happy":   return .green
        case "sad":     return .blue
        case "angry":   return .red
        case "neutral": return .gray
        default:        return .secondary
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for care plan chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

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
            totalHeight = y + rowHeight
        }

        return ArrangeResult(positions: positions, size: CGSize(width: maxWidth, height: totalHeight))
    }
}
