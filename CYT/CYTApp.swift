//
//  CYTApp.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//

import SwiftUI

enum AppPhase {
    case onboarding
    case vibeCheck
    case main
}

@main
struct CYTApp: App {
    @State private var store = JournalStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var appPhase: AppPhase = .onboarding
    @State private var detectedMood: MoodLevel?

    var body: some Scene {
        WindowGroup {
            Group {
                switch appPhase {
                case .onboarding:
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appPhase = .vibeCheck
                        }
                    }

                case .vibeCheck:
                    VibeCheckView { mood in
                        detectedMood = mood
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appPhase = .main
                        }
                    }

                case .main:
                    TabView {
                        Tab("Home", systemImage: "house.fill") {
                            HomeView(vibeCheckMood: detectedMood)
                        }

                        Tab("New Entry", systemImage: "plus.circle.fill") {
                            NewEntryView(initialMood: detectedMood)
                        }

                        Tab("Insights", systemImage: "chart.bar.xaxis") {
                            InsightsView()
                        }
                    }
                }
            }
            .environment(store)
            .onAppear {
                if hasSeenOnboarding {
                    appPhase = .vibeCheck
                }
            }
        }
    }
}
