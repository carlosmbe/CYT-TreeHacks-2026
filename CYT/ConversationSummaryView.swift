//
//  ConversationSummaryView.swift
//  CYT
//
//  End-of-session summary after "End Exchange". Shows Vera's note,
//  all suggested cards, DJ session, and Start New Conversation.
//

import SwiftUI

struct ConversationSummaryView: View {
    let summary: ConversationSummary
    var onStartNew: () -> Void

    @State private var appeared = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AnimatedGradientBackground(mood: summary.mood)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    veraNote
                    statsRow
                    cardCarousel
                    djSection
                    startNewButton
                }
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Your Exchange")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    // MARK: - Vera's Note

    private var veraNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vera's Note", systemImage: "sparkle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))

            Text(summary.veraNote)
                .font(.title3)
                .fontWeight(.medium)
                .lineSpacing(4)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 16) {
            statPill(icon: "bubble.left.and.bubble.right", value: "\(summary.messageCount)", label: "messages")
            statPill(icon: "rectangle.stack", value: "\(summary.cards.count)", label: "cards")
            statPill(icon: "face.smiling", value: summary.mood.capitalized, label: "mood")
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Card Carousel

    private var cardCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Care Package")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 20)

            if summary.cards.isEmpty {
                Text("No cards were suggested during this exchange.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(summary.cards.enumerated()), id: \.element.id) { index, card in
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
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - DJ Section

    private var djSection: some View {
        DJCardView(djSession: summary.djSession)
            .padding(.horizontal, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: appeared)
    }

    // MARK: - Start New

    private var startNewButton: some View {
        Button {
            onStartNew()
        } label: {
            Label("Start New Conversation", systemImage: "arrow.counterclockwise")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Card Actions

    private func handleCardTap(_ card: CarePackageCard) {
        switch card.category {
        case .breathe, .rest:
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        case .connect:
            if let url = URL(string: "tel://") { openURL(url) }
        case .move:
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        case .music:
            let term = summary.djSession.genre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "music://search?term=\(term)") { openURL(url) }
        case .celebrate, .express:
            break
        }
    }
}
