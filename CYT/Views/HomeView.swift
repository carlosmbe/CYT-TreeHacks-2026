import SwiftUI

struct HomeView: View {
    @Environment(JournalStore.self) private var store
    var vibeCheckMood: MoodLevel?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader

                    if let mood = vibeCheckMood {
                        vibeCheckCard(mood: mood)
                    }

                    insightCard
                    metricsGrid
                    recentEntriesSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CYT")
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.title2)
                .fontWeight(.bold)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    // MARK: - Vibe Check Card

    private func vibeCheckCard(mood: MoodLevel) -> some View {
        HStack(spacing: 14) {
            Text(mood.emoji)
                .font(.system(size: 44))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Vibe")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("You're feeling \(mood.rawValue.lowercased())")
                    .font(.headline)
                Text("Detected by on-device vision AI")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Circle()
                .fill(Color(mood.color).opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(Color(mood.color))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(mood.color).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(mood.color).opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Insight Card

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your Week at a Glance", systemImage: "sparkles")
                .font(.headline)

            Text("You've logged \(store.entries.count) entries this week. Your average mood has been positive. Keep it up!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Metrics")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.latestMetrics) { metric in
                    MetricCard(metric: metric)
                }
            }
        }
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Entries")
                .font(.headline)

            if store.recentEntries.isEmpty {
                Text("No entries yet. Tap + to start journaling.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(store.recentEntries) { entry in
                    NavigationLink(value: entry.id) {
                        EntryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: UUID.self) { entryId in
            if let entry = store.entries.first(where: { $0.id == entryId }) {
                EntryDetailView(entry: entry)
            }
        }
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.type.icon)
                .font(.title2)
                .foregroundStyle(metric.type.color)

            Spacer()

            Text(metric.formattedValue)
                .font(.title)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            Text("\(metric.type.rawValue) \(metric.type.unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .frame(height: 130)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Entry Card

struct EntryCard: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.mood.emoji)
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(entry.date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HomeView(vibeCheckMood: .happy)
        .environment(JournalStore())
}
