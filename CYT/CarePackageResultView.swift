//
//  CarePackageResultView.swift
//  CYT
//
//  The payoff screen: Lumen's note + tappable card carousel + DJ card.
//

import SwiftUI

struct CarePackageResultView: View {
    let package: CarePackage
    @State private var appeared = false
    @State private var showCelebration = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    personalNoteSection
                    cardCarouselSection
                    djSection
                    timestampFooter
                }
                .padding(.vertical, 24)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    appeared = true
                }
            }

            // Celebrate overlay
            if showCelebration {
                celebrationOverlay
            }
        }
    }

    // MARK: - Personal Note

    private var personalNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lumen's Note", systemImage: "sparkle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(package.personalNote)
                .font(.title3)
                .fontWeight(.medium)
                .lineSpacing(4)
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Card Carousel

    private var cardCarouselSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Care Package")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(package.cards.enumerated()), id: \.element.id) { index, card in
                        cardButton(card: card, index: index)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func cardButton(card: CarePackageCard, index: Int) -> some View {
        if card.category == .express {
            NavigationLink(value: card.category) {
                ActionCardView(card: card)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.1), value: appeared)
        } else {
            Button {
                handleCardTap(card)
            } label: {
                ActionCardView(card: card)
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.1), value: appeared)
        }
    }

    // MARK: - DJ Section

    private var djSection: some View {
        DJCardView(djSession: package.djSession)
            .padding(.horizontal, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: appeared)
    }

    // MARK: - Timestamp

    private var timestampFooter: some View {
        Text(package.timestamp, style: .time)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - Celebration Overlay

    private var celebrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showCelebration = false }

            VStack(spacing: 16) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.bounce, options: .repeating)

                Text("You're doing great!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Keep riding this wave")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Card Actions

    private func handleCardTap(_ card: CarePackageCard) {
        switch card.category {
        case .breathe, .rest:
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        case .connect:
            if let url = URL(string: "tel://") {
                openURL(url)
            }
        case .move:
            // Try Fitness app, fall back to Health
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        case .music:
            let term = package.djSession.genre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "music://search?term=\(term)") {
                openURL(url)
            }
        case .celebrate:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showCelebration = true
            }
        case .express:
            break // Handled by NavigationLink
        }
    }
}

// MARK: - Action Card

struct ActionCardView: View {
    let card: CarePackageCard

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(card.color.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: card.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(card.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(card.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(width: 140, height: 160)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(card.color.opacity(0.2), lineWidth: 1)
        )
    }
}
