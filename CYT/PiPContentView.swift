//
//  PiPContentView.swift
//  CYT
//
//  SwiftUI view rendered into the PiP window.
//  Shows waveform, session timer, status text, and mood color.
//

import SwiftUI

struct PiPContentView: View {
    let isRecording: Bool
    let audioLevel: Int
    let moodColor: String
    let statusText: String
    let sessionStart: Date
    let latestCardTitle: String?
    let latestCardIcon: String?

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 10) {
                Text("Vera")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 20) {
                    PiPWaveformBars(
                        level: audioLevel,
                        isActive: isRecording,
                        color: moodColorValue
                    )
                    .frame(width: 40, height: 24)

                    Text(sessionStart, style: .timer)
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(moodColorValue)
                }

                if let title = latestCardTitle {
                    HStack(spacing: 4) {
                        if let icon = latestCardIcon {
                            Image(systemName: icon)
                                .font(.caption2)
                        }
                        Text(title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())
                }

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(moodColorValue.gradient)
                    .frame(height: 3)
                    .padding(.horizontal, 24)
            }
            .padding(16)
        }
        .frame(width: 320, height: 180)
    }

    private var moodColorValue: Color {
        switch moodColor {
        case "sad": return .blue
        case "angry": return .red
        case "happy": return .yellow
        default: return .cyan
        }
    }
}

// MARK: - Waveform Bars (PiP version)

struct PiPWaveformBars: View {
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
            return maxHeight * 0.25
        }

        let minH = maxHeight * 0.2
        let maxH = maxHeight

        let patterns: [[CGFloat]] = [
            [0.25, 0.35, 0.3, 0.25],
            [0.4, 0.6, 0.5, 0.35],
            [0.5, 0.85, 0.7, 0.55],
            [0.7, 1.0, 0.9, 0.75],
        ]

        let clampedLevel = min(max(level, 0), 3)
        let fraction = patterns[clampedLevel][index]
        return max(minH, maxH * fraction)
    }
}
