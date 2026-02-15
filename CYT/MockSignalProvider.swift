//
//  MockSignalProvider.swift
//  CYT
//
//  Generates realistic mock data for demo scenarios.
//

import Foundation

enum MockScenario: String, CaseIterable, Identifiable {
    case stressedAndTired = "Stressed & Tired"
    case angryAndRestless = "Angry & Restless"
    case happyAndHealthy  = "Happy & Healthy"
    case neutralBaseline  = "Neutral Baseline"

    var id: String { rawValue }
}

struct MockSignalProvider {

    static func carePackage(for scenario: MockScenario) -> CarePackage {
        switch scenario {
        case .stressedAndTired: return stressedAndTired()
        case .angryAndRestless: return angryAndRestless()
        case .happyAndHealthy:  return happyAndHealthy()
        case .neutralBaseline:  return neutralBaseline()
        }
    }

    // MARK: - Scenarios

    static func stressedAndTired() -> CarePackage {
        let signals = CheckInSignals(
            emotionLabel: "sad",
            emotionConfidence: 0.82,
            facialAnalysis: "Drooping eyelids and downturned mouth suggest fatigue and low mood.",
            healthSnapshot: HealthSnapshot(
                currentHeartRate: 88,
                averageHeartRate: 72,
                restingHeartRate: 65,
                hrv: 22,
                stepCount: 1200,
                respiratoryRate: 18,
                sleepHours: 4.1,
                isSynthetic: true
            )
        )

        return CarePackage(
            personalNote: "You sound tired today, and your body agrees — only 4 hours of sleep and your stress levels are elevated. Let's take it easy.",
            cards: [
                CarePackageCard(title: "Breathe With Me", subtitle: "Low HRV detected", category: .breathe),
                CarePackageCard(title: "DJ Session", subtitle: "Calm sounds to unwind", category: .music),
                CarePackageCard(title: "Call Someone", subtitle: "A familiar voice helps", category: .connect),
                CarePackageCard(title: "Rest Mode", subtitle: "You need more sleep", category: .rest),
                CarePackageCard(title: "Write It Out", subtitle: "Journal your thoughts", category: .express),
                CarePackageCard(title: "10-Min Walk", subtitle: "Fresh air helps", category: .move),
                CarePackageCard(title: "Celebrate", subtitle: "Small wins count", category: .celebrate),
            ],
            djSession: DJSession(
                moodLabel: "Calm & Reflective",
                genre: "Lo-fi / Ambient",
                tracks: [
                    DJTrack(title: "Snowfall", artist: "Øneheart & Reidenshi"),
                    DJTrack(title: "Weightless", artist: "Marconi Union"),
                    DJTrack(title: "Intro", artist: "The xx"),
                ]
            ),
            signals: signals,
            followUpQuestion: "What's weighing on you the most right now?",
            timestamp: Date()
        )
    }

    static func angryAndRestless() -> CarePackage {
        let signals = CheckInSignals(
            emotionLabel: "angry",
            emotionConfidence: 0.76,
            facialAnalysis: "Furrowed brows and clenched jaw indicate frustration.",
            healthSnapshot: HealthSnapshot(
                currentHeartRate: 95,
                averageHeartRate: 72,
                restingHeartRate: 64,
                hrv: 28,
                stepCount: 3400,
                respiratoryRate: 20,
                sleepHours: 6.0,
                isSynthetic: true
            )
        )

        return CarePackage(
            personalNote: "I can hear the tension in your voice — your heart rate is up too. Let's channel that energy somewhere useful.",
            cards: [
                CarePackageCard(title: "Write It Out", subtitle: "Get it off your chest", category: .express),
                CarePackageCard(title: "10-Min Walk", subtitle: "Move the frustration out", category: .move),
                CarePackageCard(title: "DJ Session", subtitle: "Music to release energy", category: .music),
                CarePackageCard(title: "Breathe With Me", subtitle: "Slow your heart rate", category: .breathe),
                CarePackageCard(title: "Call Someone", subtitle: "Talk it through", category: .connect),
                CarePackageCard(title: "Rest Mode", subtitle: "Take a breather", category: .rest),
                CarePackageCard(title: "Celebrate", subtitle: "You're handling it", category: .celebrate),
            ],
            djSession: DJSession(
                moodLabel: "Release & Reset",
                genre: "Indie Rock / Electronic",
                tracks: [
                    DJTrack(title: "Run", artist: "AWOLNATION"),
                    DJTrack(title: "Dog Days Are Over", artist: "Florence + The Machine"),
                    DJTrack(title: "Midnight City", artist: "M83"),
                ]
            ),
            signals: signals,
            followUpQuestion: "Did something specific set this off?",
            timestamp: Date()
        )
    }

    static func happyAndHealthy() -> CarePackage {
        let signals = CheckInSignals(
            emotionLabel: "happy",
            emotionConfidence: 0.91,
            facialAnalysis: "Genuine smile with crow's feet — looks like a great day.",
            healthSnapshot: HealthSnapshot(
                currentHeartRate: 68,
                averageHeartRate: 70,
                restingHeartRate: 60,
                hrv: 55,
                stepCount: 8200,
                respiratoryRate: 14,
                sleepHours: 8.1,
                isSynthetic: true
            )
        )

        return CarePackage(
            personalNote: "You're radiating good energy today — 8 hours of sleep and your heart is happy. Let's ride this wave!",
            cards: [
                CarePackageCard(title: "Celebrate", subtitle: "You earned this feeling", category: .celebrate),
                CarePackageCard(title: "DJ Session", subtitle: "Upbeat vibes for you", category: .music),
                CarePackageCard(title: "Call Someone", subtitle: "Share the good mood", category: .connect),
                CarePackageCard(title: "10-Min Walk", subtitle: "Enjoy the sunshine", category: .move),
                CarePackageCard(title: "Write It Out", subtitle: "Capture this feeling", category: .express),
                CarePackageCard(title: "Breathe With Me", subtitle: "Stay centered", category: .breathe),
                CarePackageCard(title: "Rest Mode", subtitle: "Recharge for later", category: .rest),
            ],
            djSession: DJSession(
                moodLabel: "Joyful & Energized",
                genre: "Pop / Feel-Good Indie",
                tracks: [
                    DJTrack(title: "Good Days", artist: "SZA"),
                    DJTrack(title: "Electric Feel", artist: "MGMT"),
                    DJTrack(title: "On Top of the World", artist: "Imagine Dragons"),
                ]
            ),
            signals: signals,
            followUpQuestion: "What's making today a good day?",
            timestamp: Date()
        )
    }

    static func neutralBaseline() -> CarePackage {
        let signals = CheckInSignals(
            emotionLabel: "neutral",
            emotionConfidence: 0.65,
            facialAnalysis: "Relaxed expression, no strong emotional signals.",
            healthSnapshot: HealthSnapshot(
                currentHeartRate: 72,
                averageHeartRate: 70,
                restingHeartRate: 62,
                hrv: 42,
                stepCount: 5000,
                respiratoryRate: 15,
                sleepHours: 7.0,
                isSynthetic: true
            )
        )

        return CarePackage(
            personalNote: "Everything looks steady today — a blank canvas kind of day. What do you want to do with it?",
            cards: [
                CarePackageCard(title: "Write It Out", subtitle: "Capture your thoughts", category: .express),
                CarePackageCard(title: "10-Min Walk", subtitle: "Get the blood flowing", category: .move),
                CarePackageCard(title: "DJ Session", subtitle: "Focus music for flow", category: .music),
                CarePackageCard(title: "Breathe With Me", subtitle: "Center yourself", category: .breathe),
                CarePackageCard(title: "Call Someone", subtitle: "Catch up with a friend", category: .connect),
                CarePackageCard(title: "Rest Mode", subtitle: "Take it slow", category: .rest),
                CarePackageCard(title: "Celebrate", subtitle: "Appreciate the calm", category: .celebrate),
            ],
            djSession: DJSession(
                moodLabel: "Focused & Steady",
                genre: "Lo-fi Hip Hop / Chillwave",
                tracks: [
                    DJTrack(title: "Tadow", artist: "Masego & FKJ"),
                    DJTrack(title: "Affection", artist: "Jinsang"),
                    DJTrack(title: "Best Part", artist: "Daniel Caesar ft. H.E.R."),
                ]
            ),
            signals: signals,
            followUpQuestion: "Anything on your mind you'd like to explore?",
            timestamp: Date()
        )
    }
}
