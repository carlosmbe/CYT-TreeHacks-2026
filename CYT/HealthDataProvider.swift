//
//  HealthDataProvider.swift
//  CYT
//
//  Fetches biometric data from Apple Watch via HealthKit and formats it for LLM context.
//

import HealthKit

actor HealthDataProvider {

    private let store = HKHealthStore()

    /// Requests read authorization for heart rate data.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.healthDataNotAvailable
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthDataError.invalidQuantityType
        }

        let typesToRead: Set<HKObjectType> = [heartRateType]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: typesToRead) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    /// Fetches the single most recent heart rate sample within the last 15 minutes.
    func fetchCurrentHeartRate() async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let fifteenMinutesAgo = Date().addingTimeInterval(-15 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: fifteenMinutesAgo, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Calculates the discrete average heart rate over the last 24 hours.
    func fetch24hAverageHeartRate() async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: twentyFourHoursAgo, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let statistics = statistics,
                      let average = statistics.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let value = average.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Generates a clean, labeled string block for LLM context with heart rate data.
    /// Uses single dashes for lists and avoids double dashes.
    /// Returns synthetic data when no Apple Watch is connected or HealthKit is unavailable.
    func generateLLMContext() async -> String {
        var current: Double?
        var average: Double?
        var isSynthetic = false

        if HKHealthStore.isHealthDataAvailable() {
            do {
                try await requestAuthorization()
                current = try await fetchCurrentHeartRate()
                average = try await fetch24hAverageHeartRate()
                if current == nil && average == nil {
                    isSynthetic = true
                    (current, average) = Self.syntheticHeartRateValues
                }
            } catch {
                isSynthetic = true
                (current, average) = Self.syntheticHeartRateValues
            }
        } else {
            isSynthetic = true
            (current, average) = Self.syntheticHeartRateValues
        }

        var lines: [String] = []
        lines.append("Heart Rate Data")
        if isSynthetic {
            lines.append("(synthetic - no Apple Watch connected)")
        }
        lines.append("")

        if let current {
            lines.append("- Current (last 15 min): \(String(format: "%.1f", current)) bpm")
        } else {
            lines.append("- Current (last 15 min): No data")
        }

        if let average {
            lines.append("- 24h Average: \(String(format: "%.1f", average)) bpm")
        } else {
            lines.append("- 24h Average: No data")
        }

        if let current, let average, average > 0 {
            let variance = ((current - average) / average) * 100
            lines.append("- Variance from baseline: \(String(format: "%.1f", variance))%")
        }

        return lines.joined(separator: "\n")
    }

    /// Plausible synthetic values when no real heart rate data is available.
    private static var syntheticHeartRateValues: (current: Double, average: Double) {
        (72.0, 68.0)
    }
}

enum HealthDataError: Error {
    case healthDataNotAvailable
    case invalidQuantityType
}
