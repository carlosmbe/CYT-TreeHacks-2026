//
//  CarePackageModels.swift
//  CYT
//
//  Core data types for the Care Package experience.
//

import SwiftUI

// MARK: - Card Category

enum CardCategory: String, CaseIterable, Identifiable, Hashable {
    case breathe
    case music
    case connect
    case move
    case express
    case rest
    case celebrate

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .breathe:   return "wind"
        case .music:     return "music.note.list"
        case .connect:   return "phone.fill"
        case .move:      return "figure.walk"
        case .express:   return "pencil.line"
        case .rest:      return "moon.stars.fill"
        case .celebrate: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .breathe:   return .cyan
        case .music:     return .purple
        case .connect:   return .blue
        case .move:      return .green
        case .express:   return .orange
        case .rest:      return .indigo
        case .celebrate: return .yellow
        }
    }
}

// MARK: - Check-In Signals

struct CheckInSignals {
    var emotionLabel: String          // e.g. "sad", "angry", "happy", "neutral"
    var emotionConfidence: Float      // 0...1
    var facialAnalysis: String        // one-sentence description
    var healthSnapshot: HealthSnapshot
}

// MARK: - Care Package Card

struct CarePackageCard: Identifiable {
    let id = UUID()
    var title: String                 // e.g. "Breathe With Me"
    var subtitle: String              // e.g. "Low HRV detected"
    var category: CardCategory

    var sfSymbol: String { category.sfSymbol }
    var color: Color { category.color }
}

// MARK: - DJ Playlist Item

struct DJTrack: Identifiable {
    let id = UUID()
    var title: String
    var artist: String
}

// MARK: - DJ Session Info

struct DJSession {
    var moodLabel: String             // e.g. "Calm & Reflective"
    var genre: String                 // e.g. "Lo-fi"
    var tracks: [DJTrack]
}

// MARK: - Care Package

struct CarePackage: Identifiable {
    let id = UUID()
    var personalNote: String          // Lumen's note to the user
    var cards: [CarePackageCard]
    var djSession: DJSession
    var signals: CheckInSignals
    var followUpQuestion: String      // Guiding question after recording
    var timestamp: Date
}

// MARK: - Journal Entry

struct JournalEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var timestamp: Date
    var emotionLabel: String
    var personalNote: String
    var cardTitles: [String]
    var photoData: Data?              // JPEG from selfie capture
}
