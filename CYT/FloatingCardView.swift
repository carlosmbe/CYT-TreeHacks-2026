//
//  FloatingCardView.swift
//  CYT
//
//  Side drawer cards that peek from the right edge. Swipe left to reveal,
//  swipe right or tap action to dismiss. Max 3 visible, auto-retract after 10s.
//

import SwiftUI

struct FloatingCardView: View {
    let card: CarePackageCard
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var revealed = false
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var retractTask: Task<Void, Never>?

    private let peekWidth: CGFloat = 56
    private let fullWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            // Full card content (hidden when peeking)
            if revealed {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(card.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button {
                        onTap()
                    } label: {
                        Text(actionLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(card.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(card.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Icon peek (always visible)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(card.color.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: card.sfSymbol)
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .frame(width: revealed ? fullWidth : peekWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(card.color.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: -2, y: 2)
        .offset(x: appeared ? dragOffset : 100)
        .opacity(appeared ? 1 : 0)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let tx = value.translation.width
                    if revealed {
                        // Swipe right to retract
                        if tx > 0 { dragOffset = tx }
                    } else {
                        // Swipe left to reveal
                        if tx < 0 { dragOffset = tx }
                    }
                }
                .onEnded { value in
                    let tx = value.translation.width
                    if revealed && tx > 60 {
                        // Retract
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            revealed = false
                            dragOffset = 0
                        }
                    } else if !revealed && tx < -30 {
                        // Reveal
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            revealed = true
                            dragOffset = 0
                        }
                        scheduleAutoRetract()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture {
            if !revealed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    revealed = true
                }
                scheduleAutoRetract()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .onDisappear {
            retractTask?.cancel()
        }
    }

    private var actionLabel: String {
        switch card.category {
        case .breathe: return "Start Breathing"
        case .music: return "Open Music"
        case .connect: return "Open Contacts"
        case .move: return "Get Moving"
        case .express: return "Start Writing"
        case .rest: return "Rest Mode"
        case .celebrate: return "Celebrate"
        }
    }

    private func scheduleAutoRetract() {
        retractTask?.cancel()
        retractTask = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        revealed = false
                    }
                }
            }
        }
    }
}

/// Overlay that shows up to 3 side drawer cards stacked on the right edge.
struct FloatingCardStack: View {
    let cards: [CarePackageCard]
    var onTapCard: (CarePackageCard) -> Void
    var onDismissCard: (CarePackageCard) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer()
            ForEach(cards.suffix(3)) { card in
                FloatingCardView(
                    card: card,
                    onTap: { onTapCard(card) },
                    onDismiss: { onDismissCard(card) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cards.map(\.id))
    }
}
