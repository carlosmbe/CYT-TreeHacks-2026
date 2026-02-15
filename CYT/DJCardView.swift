//
//  DJCardView.swift
//  CYT
//
//  Expanded Smart DJ card showing mood-matched playlist.
//

import SwiftUI

struct DJCardView: View {
    let djSession: DJSession
    @Environment(\.openURL) private var openURL
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(CardCategory.music.color.gradient)
                            .frame(width: 48, height: 48)
                        Image(systemName: "music.note.list")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DJ Session")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(djSession.moodLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    // Genre tag
                    Text(djSession.genre)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CardCategory.music.color.opacity(0.15))
                        .foregroundStyle(CardCategory.music.color)
                        .clipShape(Capsule())

                    // Tracks
                    ForEach(djSession.tracks) { track in
                        HStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(CardCategory.music.color.opacity(0.6))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    // Open in Apple Music
                    Button {
                        let term = djSession.genre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "music://search?term=\(term)") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Open in Apple Music")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(CardCategory.music.color.opacity(0.15))
                        .foregroundStyle(CardCategory.music.color)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CardCategory.music.color.opacity(0.3), lineWidth: 1)
        )
    }
}
