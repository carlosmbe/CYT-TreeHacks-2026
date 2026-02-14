import SwiftUI

struct HomeView: View {
    @Environment(JournalStore.self) private var store

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader
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
    HomeView()
        .environment(JournalStore())
}
