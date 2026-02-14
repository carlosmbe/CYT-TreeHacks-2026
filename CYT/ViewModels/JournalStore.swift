import Foundation
import SwiftUI

@Observable
@MainActor
class JournalStore {

    var entries: [JournalEntry] = []
    var latestMetrics: [HealthMetric] = []
    var plugins: [any DataSourcePlugin] = [
        HealthKitPlugin(),
        OuraPlugin(),
        AirPodsPlugin(),
    ]

    init() {
        loadMockData()
    }

    // MARK: - CRUD

    func addEntry(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
    }

    func updateEntry(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        }
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    // MARK: - Metrics

    func refreshMetrics() async {
        var all: [HealthMetric] = []
        for plugin in plugins where plugin.isAvailable() {
            let metrics = await plugin.fetchLatest()
            all.append(contentsOf: metrics)
        }
        // Deduplicate by type, keeping the most recent
        var seen: [HealthMetricType: HealthMetric] = [:]
        for m in all {
            if let existing = seen[m.type] {
                if m.timestamp > existing.timestamp { seen[m.type] = m }
            } else {
                seen[m.type] = m
            }
        }
        latestMetrics = Array(seen.values).sorted { $0.type.rawValue < $1.type.rawValue }
    }

    var recentEntries: [JournalEntry] {
        Array(entries.prefix(5))
    }

    // MARK: - Mock Data

    private func loadMockData() {
        let calendar = Calendar.current

        entries = [
            JournalEntry(
                title: "Morning Reflection",
                body: "Woke up feeling rested today. Had a good meditation session and feel ready to tackle the day. The weather is beautiful outside.",
                date: calendar.date(byAdding: .hour, value: -2, to: .now)!,
                mood: .happy,
                tags: ["morning", "meditation"]
            ),
            JournalEntry(
                title: "Work Stress",
                body: "Big deadline coming up. Feeling the pressure but trying to stay focused. Need to remember to take breaks and breathe.",
                date: calendar.date(byAdding: .day, value: -1, to: .now)!,
                mood: .stressed,
                tags: ["work", "deadline"]
            ),
            JournalEntry(
                title: "Evening Walk",
                body: "Took a long walk after dinner. The fresh air really helped clear my mind. Listened to a great podcast about mindfulness.",
                date: calendar.date(byAdding: .day, value: -2, to: .now)!,
                mood: .calm,
                tags: ["exercise", "mindfulness"]
            ),
            JournalEntry(
                title: "Feeling Off",
                body: "Not sure why but feeling a bit down today. Maybe it's the weather or just one of those days. Going to try and do something I enjoy.",
                date: calendar.date(byAdding: .day, value: -3, to: .now)!,
                mood: .sad,
                tags: ["reflection"]
            ),
            JournalEntry(
                title: "Great Workout",
                body: "Hit a new personal record at the gym! Feeling strong and energized. Need to keep this momentum going.",
                date: calendar.date(byAdding: .day, value: -4, to: .now)!,
                mood: .happy,
                tags: ["exercise", "achievement"]
            ),
        ]

        latestMetrics = [
            HealthMetric(type: .heartRate, value: 72),
            HealthMetric(type: .stress, value: 3.2),
            HealthMetric(type: .temperature, value: 98.4),
            HealthMetric(type: .hrv, value: 45),
            HealthMetric(type: .sleep, value: 7.2),
            HealthMetric(type: .steps, value: 8432),
        ]
    }
}
