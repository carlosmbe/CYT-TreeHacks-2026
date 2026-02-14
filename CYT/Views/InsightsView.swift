import SwiftUI

struct InsightsView: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    moodTrendSection
                    healthCorrelationsSection
                    journalPatternsSection
                    weeklySummarySection
                    recommendationsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
        }
    }

    // MARK: - Mood Trend

    private var moodTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mood Trend", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            let distribution = moodDistribution
            if distribution.isEmpty {
                Text("No entries yet to analyze.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(distribution, id: \.mood) { item in
                            HStack(spacing: 6) {
                                Text(item.mood.emoji)
                                Text("\(item.count)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(item.mood.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(item.mood.color).opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Visual bar chart
                VStack(spacing: 6) {
                    ForEach(distribution, id: \.mood) { item in
                        HStack(spacing: 8) {
                            Text(item.mood.emoji)
                                .frame(width: 30)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(item.mood.color))
                                    .frame(width: max(20, geo.size.width * item.fraction))
                            }
                            .frame(height: 20)
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Health Correlations

    private var healthCorrelationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Health Correlations", systemImage: "heart.text.clipboard")
                .font(.headline)

            let correlations = computeHealthCorrelations()
            if correlations.isEmpty {
                Text("Log more entries to see health patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(correlations, id: \.self) { text in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.teal)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Journal Patterns

    private var journalPatternsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Journal Patterns", systemImage: "text.book.closed")
                .font(.headline)

            let patterns = computeJournalPatterns()
            ForEach(patterns, id: \.self) { pattern in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(pattern)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Weekly Summary

    private var weeklySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weekly Summary", systemImage: "calendar")
                .font(.headline)

            Text(generateWeeklySummary())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recommendations", systemImage: "sparkles")
                .font(.headline)

            let tips = generateRecommendations()
            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Computed Data

    private struct MoodCount {
        let mood: MoodLevel
        let count: Int
        let fraction: CGFloat
    }

    private var moodDistribution: [MoodCount] {
        let total = store.entries.count
        guard total > 0 else { return [] }

        var counts: [MoodLevel: Int] = [:]
        for entry in store.entries {
            counts[entry.mood, default: 0] += 1
        }

        return counts
            .sorted { $0.value > $1.value }
            .map { MoodCount(mood: $0.key, count: $0.value, fraction: CGFloat($0.value) / CGFloat(total)) }
    }

    private func computeHealthCorrelations() -> [String] {
        var results: [String] = []
        let metrics = store.latestMetrics

        if let hr = metrics.first(where: { $0.type == .heartRate }) {
            results.append("Your current heart rate is \(hr.formattedValue) BPM. Elevated heart rate can indicate stress.")
        }
        if let hrv = metrics.first(where: { $0.type == .hrv }) {
            results.append("Your HRV is \(hrv.formattedValue) ms. Higher HRV generally indicates better stress recovery.")
        }
        if let sleep = metrics.first(where: { $0.type == .sleep }) {
            let hours = sleep.value
            if hours < 7 {
                results.append("You slept \(sleep.formattedValue) hours — below the recommended 7-9 hours. This may affect mood.")
            } else {
                results.append("You slept \(sleep.formattedValue) hours — great rest supports positive mood.")
            }
        }
        if let stress = metrics.first(where: { $0.type == .stress }) {
            results.append("Your stress level reads \(stress.formattedValue)/10 from connected sensors.")
        }

        return results
    }

    private func computeJournalPatterns() -> [String] {
        var patterns: [String] = []

        let entries = store.entries
        guard !entries.isEmpty else {
            return ["Start journaling to discover your patterns."]
        }

        // Time of day analysis
        let hours = entries.map { Calendar.current.component(.hour, from: $0.date) }
        let avgHour = hours.reduce(0, +) / max(hours.count, 1)
        let timeOfDay: String
        switch avgHour {
        case 5..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        default: timeOfDay = "evening"
        }
        patterns.append("You tend to journal most in the \(timeOfDay).")

        // Tag analysis
        let allTags = entries.flatMap(\.tags)
        if !allTags.isEmpty {
            var tagCounts: [String: Int] = [:]
            for tag in allTags { tagCounts[tag, default: 0] += 1 }
            let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(3).map { "#\($0.key)" }
            patterns.append("Your most common tags: \(topTags.joined(separator: ", "))")
        }

        // Entry length
        let avgLength = entries.map(\.body.count).reduce(0, +) / max(entries.count, 1)
        if avgLength > 200 {
            patterns.append("You write detailed entries — averaging \(avgLength) characters. Deep reflection is great for self-awareness.")
        } else {
            patterns.append("Your entries are concise — averaging \(avgLength) characters. Even short reflections are valuable.")
        }

        return patterns
    }

    private func generateWeeklySummary() -> String {
        let entries = store.entries
        guard !entries.isEmpty else {
            return "No entries this week yet. Start journaling to get weekly insights."
        }

        let moodCounts = Dictionary(grouping: entries, by: \.mood)
        let dominant = moodCounts.max(by: { $0.value.count < $1.value.count })?.key ?? .neutral

        return "This week you logged \(entries.count) journal entries. Your dominant mood was \(dominant.rawValue.lowercased()) \(dominant.emoji). You've been consistent with your check-ins, which helps build a clearer picture of your mental health patterns. Keep it up — regular journaling is one of the best tools for self-awareness."
    }

    private func generateRecommendations() -> [String] {
        var tips: [String] = []

        let moodCounts = Dictionary(grouping: store.entries, by: \.mood)
        let stressCount = (moodCounts[.stressed]?.count ?? 0) + (moodCounts[.anxious]?.count ?? 0)

        if stressCount > 1 {
            tips.append("You've had \(stressCount) stressed/anxious entries. Consider a short walk or breathing exercise when tension rises.")
        }

        if let sleep = store.latestMetrics.first(where: { $0.type == .sleep }), sleep.value < 7 {
            tips.append("Your sleep is below 7 hours. Try winding down with evening journaling — it may improve sleep quality.")
        }

        if store.entries.count < 3 {
            tips.append("Journal more frequently to unlock deeper insights. Aim for at least one entry per day.")
        }

        tips.append("Review your mood trends weekly to spot patterns early.")

        if let hr = store.latestMetrics.first(where: { $0.type == .heartRate }), hr.value > 80 {
            tips.append("Your resting heart rate is elevated. Physical activity and mindfulness can help bring it down.")
        }

        return tips
    }
}

#Preview {
    InsightsView()
        .environment(JournalStore())
}
