//
//  VeraLiveActivityLiveActivity.swift
//  VeraLiveActivity
//
//  Live Activity + Dynamic Island UI for Vera voice conversations.
//  Displays recording state, mood color, and latest card suggestion.
//  The main app pushes updates via Activity.update().
//

import ActivityKit
import WidgetKit
import SwiftUI

struct VeraLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConversationActivityAttributes.self) { context in
            // Lock Screen / Banner
            VeraLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    WaveformBars(level: context.state.audioLevel, isActive: context.state.isRecording, color: moodColor(context.state.moodColor))
                        .frame(width: 24, height: 20)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Vera")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if let cardTitle = context.state.latestCardTitle {
                            HStack(spacing: 3) {
                                if let icon = context.state.latestCardIcon {
                                    Image(systemName: icon)
                                        .font(.caption2)
                                }
                                Text(cardTitle)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        } else {
                            Text(context.state.isRecording ? "Listening..." : "In conversation")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.sessionStart, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(moodColor(context.state.moodColor).gradient)
                        .frame(height: 2)
                        .padding(.horizontal, 16)
                }
            } compactLeading: {
                WaveformBars(level: context.state.audioLevel, isActive: context.state.isRecording, color: moodColor(context.state.moodColor))
                    .frame(width: 16, height: 12)
            } compactTrailing: {
                Text(context.attributes.sessionStart, style: .timer)
                    .monospacedDigit()
                    .font(.caption2)
                    .foregroundStyle(moodColor(context.state.moodColor))
                    .frame(minWidth: 32)
            } minimal: {
                WaveformBars(level: context.state.audioLevel, isActive: context.state.isRecording, color: moodColor(context.state.moodColor))
                    .frame(width: 14, height: 10)
            }
        }
    }

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "sad": return .blue
        case "angry": return .red
        case "happy": return .yellow
        default: return .green
        }
    }
}

// MARK: - Waveform Bars

/// Animated waveform bars that respond to audio level. Uses 4 bars with varying heights.
struct WaveformBars: View {
    let level: Int       // 0-3
    let isActive: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let barCount = 4
            let spacing: CGFloat = geo.size.width * 0.1
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(barCount)

            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(for: index, in: geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard isActive else {
            // Not recording — show small idle dots
            return maxHeight * 0.25
        }

        let minH = maxHeight * 0.2
        let maxH = maxHeight

        // Each bar gets a different height pattern based on level
        let patterns: [[CGFloat]] = [
            [0.25, 0.35, 0.3, 0.25],   // level 0 (silent)
            [0.4, 0.6, 0.5, 0.35],     // level 1 (low)
            [0.5, 0.85, 0.7, 0.55],    // level 2 (mid)
            [0.7, 1.0, 0.9, 0.75],     // level 3 (high)
        ]

        let clampedLevel = min(max(level, 0), 3)
        let fraction = patterns[clampedLevel][index]
        return max(minH, maxH * fraction)
    }
}

// MARK: - Lock Screen Banner

struct VeraLockScreenView: View {
    let context: ActivityViewContext<ConversationActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Left: waveform bars
            ZStack {
                Circle()
                    .fill(moodColor(context.state.moodColor).opacity(0.2))
                    .frame(width: 40, height: 40)

                WaveformBars(
                    level: context.state.audioLevel,
                    isActive: context.state.isRecording,
                    color: moodColor(context.state.moodColor)
                )
                .frame(width: 20, height: 16)
            }

            // Center: status info
            VStack(alignment: .leading, spacing: 2) {
                Text("Talking to Vera")
                    .font(.headline)

                if let cardTitle = context.state.latestCardTitle {
                    HStack(spacing: 4) {
                        if let icon = context.state.latestCardIcon {
                            Image(systemName: icon)
                                .font(.caption2)
                        }
                        Text(cardTitle)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(context.state.isRecording ? "Listening..." : "In conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: timer
            Text(context.attributes.sessionStart, style: .timer)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(moodColor(context.state.moodColor).opacity(0.1))
    }

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "sad": return .blue
        case "angry": return .red
        case "happy": return .yellow
        default: return .cyan
        }
    }
}

// MARK: - Preview

#Preview("Notification", as: .content, using: ConversationActivityAttributes(sessionStart: Date())) {
    VeraLiveActivityLiveActivity()
} contentStates: {
    ConversationActivityAttributes.ContentState(
        isRecording: true,
        latestCardTitle: nil,
        latestCardIcon: nil,
        moodColor: "neutral",
        audioLevel: 2
    )
    ConversationActivityAttributes.ContentState(
        isRecording: false,
        latestCardTitle: "Call Someone",
        latestCardIcon: "phone.fill",
        moodColor: "sad",
        audioLevel: 0
    )
}
