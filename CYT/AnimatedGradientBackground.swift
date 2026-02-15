//
//  AnimatedGradientBackground.swift
//  CYT
//
//  Animated gradient background driven by mood.
//  Uses 5 drifting radial blobs at high opacity for a vivid, wavy feel.
//  Neutral is a rich teal-blue ocean. Mood changes swap the palette instantly.
//

import SwiftUI

struct AnimatedGradientBackground: View {
    var mood: String
    var hasMoodDetected: Bool = false
    var rippleCenter: CGPoint = CGPoint(x: 0.5, y: 0.55)

    @State private var rippleScale: CGFloat = 0
    @State private var rippleComplete = false
    @State private var displayColors: [Color] = neutralPalette

    private static let baseColor = Color(red: 0.08, green: 0.15, blue: 0.25)

    // Rich teal-blue ocean for neutral — vivid enough to see movement
    private static let neutralPalette: [Color] = [
        Color(red: 0.10, green: 0.35, blue: 0.55),
        Color(red: 0.15, green: 0.45, blue: 0.65),
        Color(red: 0.05, green: 0.25, blue: 0.50),
        Color(red: 0.20, green: 0.50, blue: 0.70),
        Color(red: 0.08, green: 0.30, blue: 0.52)
    ]

    private func paletteFor(_ mood: String) -> [Color] {
        switch mood.lowercased() {
        case "sad":
            return [
                Color(red: 0.10, green: 0.12, blue: 0.30),
                Color(red: 0.18, green: 0.22, blue: 0.42),
                Color(red: 0.12, green: 0.15, blue: 0.35),
                Color(red: 0.22, green: 0.28, blue: 0.48),
                Color(red: 0.08, green: 0.10, blue: 0.28)
            ]
        case "angry":
            return [
                Color(red: 0.50, green: 0.10, blue: 0.08),
                Color(red: 0.60, green: 0.18, blue: 0.12),
                Color(red: 0.45, green: 0.08, blue: 0.10),
                Color(red: 0.55, green: 0.22, blue: 0.15),
                Color(red: 0.40, green: 0.12, blue: 0.08)
            ]
        case "happy":
            return [
                Color(red: 0.90, green: 0.75, blue: 0.20),
                Color(red: 0.85, green: 0.65, blue: 0.15),
                Color(red: 0.70, green: 0.82, blue: 0.30),
                Color(red: 0.95, green: 0.80, blue: 0.25),
                Color(red: 0.80, green: 0.70, blue: 0.18)
            ]
        default:
            return Self.neutralPalette
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let diagonal = sqrt(size.width * size.width + size.height * size.height)

            ZStack {
                Self.baseColor

                if rippleComplete {
                    moodGradientCanvas(size: size, colors: displayColors)
                } else if hasMoodDetected {
                    moodGradientCanvas(size: size, colors: displayColors)
                        .clipShape(
                            Circle()
                                .scale(rippleScale)
                                .offset(
                                    x: size.width * (rippleCenter.x - 0.5),
                                    y: size.height * (rippleCenter.y - 0.5)
                                )
                        )
                } else {
                    // Show animated neutral even before mood is detected
                    moodGradientCanvas(size: size, colors: displayColors)
                }
            }
            .onChange(of: hasMoodDetected) { _, detected in
                if detected && !rippleComplete {
                    displayColors = paletteFor(mood)
                    let targetScale = diagonal / min(size.width, size.height) * 1.2
                    withAnimation(.easeOut(duration: 1.5)) {
                        rippleScale = targetScale
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        rippleComplete = true
                    }
                }
            }
            .onChange(of: mood) { _, newMood in
                displayColors = paletteFor(newMood)
            }
        }
        .ignoresSafeArea()
    }

    private func moodGradientCanvas(size: CGSize, colors: [Color]) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height

                // Layer 1: 7 large drifting blobs — fast, wide movement for dramatic waves
                for i in 0..<7 {
                    let fi = Double(i)

                    // Varied speeds — some fast, some slow for layered motion
                    let speed = 0.25 + fi * 0.08
                    let phaseX = fi * 2.1 + 0.7
                    let phaseY = fi * 1.7 + 1.3

                    // Wide drift range: blobs travel across most of the screen
                    let cx = w * (0.05 + 0.9 * (0.5 + 0.5 * sin(t * speed + phaseX)))
                    let cy = h * (0.05 + 0.9 * (0.5 + 0.5 * cos(t * (speed * 0.7) + phaseY)))

                    // Radius breathes significantly — creates expanding/contracting wave feel
                    let breatheSpeed = 0.15 + fi * 0.06
                    let baseRadius = max(w, h) * (0.35 + 0.25 * sin(t * breatheSpeed + fi * 1.5))

                    let color = colors[i % colors.count]
                    let gradient = Gradient(colors: [
                        color.opacity(0.9),
                        color.opacity(0.5),
                        color.opacity(0.15),
                        color.opacity(0.0)
                    ])

                    context.fill(
                        Path(CGRect(origin: .zero, size: canvasSize)),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: baseRadius
                        )
                    )
                }

                // Layer 2: 4 smaller, faster accent blobs for surface shimmer
                for i in 0..<4 {
                    let fi = Double(i)
                    let speed = 0.5 + fi * 0.15
                    let cx = w * (0.1 + 0.8 * (0.5 + 0.5 * sin(t * speed + fi * 3.1)))
                    let cy = h * (0.1 + 0.8 * (0.5 + 0.5 * cos(t * (speed * 1.2) + fi * 2.7)))
                    let radius = max(w, h) * (0.15 + 0.1 * sin(t * 0.3 + fi * 2.0))

                    let color = colors[(i + 2) % colors.count]
                    let gradient = Gradient(colors: [
                        color.opacity(0.6),
                        color.opacity(0.2),
                        color.opacity(0.0)
                    ])

                    context.fill(
                        Path(CGRect(origin: .zero, size: canvasSize)),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
            .background(colors[0].opacity(0.6))
        }
        .frame(width: size.width, height: size.height)
    }
}
