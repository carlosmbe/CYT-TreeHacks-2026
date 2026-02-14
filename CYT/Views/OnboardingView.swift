import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "heart.circle.fill",
            headline: "Welcome to CYT",
            subtitle: "Your private mental health companion",
            effect: .pulse
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            headline: "On-Device Privacy",
            subtitle: "Everything stays on your device.\nNo cloud. No data leaves your phone.",
            effect: .pulse
        ),
        OnboardingPage(
            icon: "camera.fill",
            headline: "Vibe Check",
            subtitle: "We'll check in on how you're feeling — just by looking at you.\nPowered by an on-device vision model.",
            effect: .wiggle
        ),
        OnboardingPage(
            icon: "book.and.wrench.fill",
            headline: "Journal & Track",
            subtitle: "Journal your thoughts with text, voice, photos, and video.\nTrack health metrics from Apple Watch, Oura Ring, and AirPods.",
            effect: .pulse
        ),
        OnboardingPage(
            icon: "sparkles",
            headline: "Ready to Begin?",
            subtitle: "Let's check your vibe and start your journey.",
            effect: .pulse
        ),
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: gradientColors(for: currentPage),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: currentPage)

            VStack {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding()
                    }
                }

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page: page, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Get Started button on last page
                if currentPage == pages.count - 1 {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.4), lineWidth: 1)
                                    )
                            )
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    @ViewBuilder
    private func pageView(page: OnboardingPage, index: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: currentPage == index)
                .shadow(color: .white.opacity(0.3), radius: 20)

            VStack(spacing: 12) {
                Text(page.headline)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
    }

    private func gradientColors(for page: Int) -> [Color] {
        switch page {
        case 0: return [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.15, green: 0.1, blue: 0.4)]
        case 1: return [Color(red: 0.1, green: 0.15, blue: 0.35), Color(red: 0.1, green: 0.2, blue: 0.4)]
        case 2: return [Color(red: 0.15, green: 0.1, blue: 0.35), Color(red: 0.2, green: 0.1, blue: 0.45)]
        case 3: return [Color(red: 0.1, green: 0.2, blue: 0.35), Color(red: 0.1, green: 0.15, blue: 0.4)]
        case 4: return [Color(red: 0.15, green: 0.1, blue: 0.4), Color(red: 0.25, green: 0.1, blue: 0.5)]
        default: return [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.15, green: 0.1, blue: 0.4)]
        }
    }

    private func completeOnboarding() {
        hasSeenOnboarding = true
        onComplete()
    }
}

private struct OnboardingPage {
    let icon: String
    let headline: String
    let subtitle: String
    let effect: SymbolEffectType

    enum SymbolEffectType {
        case pulse, wiggle
    }
}

#Preview {
    OnboardingView { }
}
