//
//  JournalStore.swift
//  CYT
//
//  Simple JSON-file persistence for journal entries.
//

import Foundation

@Observable
final class JournalStore {

    private(set) var entries: [JournalEntry] = []

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal_entries.json")
    }

    init() {
        load()
    }

    func save(_ entry: JournalEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func loadAll() -> [JournalEntry] {
        entries
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        entries = (try? JSONDecoder().decode([JournalEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
