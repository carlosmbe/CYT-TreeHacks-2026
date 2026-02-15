//
//  HealthDataProvider.swift
//  CYT
//
//  Fetches biometric data from Apple Watch via HealthKit and formats it for LLM context.
//

import HealthKit

/// Snapshot of all biometric data collected from HealthKit.
struct HealthSnapshot: Sendable {
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var restingHeartRate: Double?
    var hrv: Double?
    var stepCount: Double?
    var respiratoryRate: Double?
    var sleepHours: Double?
    var isSynthetic: Bool = false
}

actor HealthDataProvider {

    private let store = HKHealthStore()

    // MARK: - Authorization

    private static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .stepCount,
            .respiratoryRate,
        ]
        for id in quantityIdentifiers {
            if let qt = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(qt)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.healthDataNotAvailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: Self.readTypes) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Fetch All

    func fetchSnapshot() async -> HealthSnapshot {
        var snap = HealthSnapshot()

        if !HKHealthStore.isHealthDataAvailable() {
            snap.isSynthetic = true
            return Self.syntheticSnapshot
        }

        do {
            try await requestAuthorization()
        } catch {
            snap.isSynthetic = true
            return Self.syntheticSnapshot
        }

        // Fetch all metrics concurrently
        async let hr = fetchLatestQuantity(.heartRate, within: 15 * 60, unit: HKUnit.count().unitDivided(by: .minute()))
        async let avgHR = fetchAverageQuantity(.heartRate, within: 24 * 60 * 60, unit: HKUnit.count().unitDivided(by: .minute()))
        async let resting = fetchLatestQuantity(.restingHeartRate, within: 24 * 60 * 60, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, within: 24 * 60 * 60, unit: .secondUnit(with: .milli))
        async let steps = fetchSumQuantity(.stepCount, within: 24 * 60 * 60, unit: .count())
        async let resp = fetchLatestQuantity(.respiratoryRate, within: 24 * 60 * 60, unit: HKUnit.count().unitDivided(by: .minute()))
        async let sleep = fetchSleepHours(within: 24 * 60 * 60)

        snap.currentHeartRate = await hr
        snap.averageHeartRate = await avgHR
        snap.restingHeartRate = await resting
        snap.hrv = await hrv
        snap.stepCount = await steps
        snap.respiratoryRate = await resp
        snap.sleepHours = await sleep

        let allNil = snap.currentHeartRate == nil && snap.averageHeartRate == nil
            && snap.restingHeartRate == nil && snap.hrv == nil
            && snap.stepCount == nil && snap.respiratoryRate == nil
            && snap.sleepHours == nil

        if allNil {
            snap.isSynthetic = true
            return Self.syntheticSnapshot
        }

        return snap
    }

    // MARK: - Generic Helpers

    private func fetchLatestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        within seconds: TimeInterval,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Date().addingTimeInterval(-seconds)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchAverageQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        within seconds: TimeInterval,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Date().addingTimeInterval(-seconds)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                guard let avg = stats?.averageQuantity() else { cont.resume(returning: nil); return }
                cont.resume(returning: avg.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchSumQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        within seconds: TimeInterval,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Date().addingTimeInterval(-seconds)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                guard let sum = stats?.sumQuantity() else { cont.resume(returning: nil); return }
                cont.resume(returning: sum.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchSleepHours(within seconds: TimeInterval) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Date().addingTimeInterval(-seconds)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }

                // Sum durations for asleep stages only (not inBed)
                var totalSeconds: TimeInterval = 0
                for sample in samples {
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    let isAsleep: Bool
                    switch value {
                    case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                        isAsleep = true
                    default:
                        isAsleep = false
                    }
                    if isAsleep {
                        totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }
                cont.resume(returning: totalSeconds > 0 ? totalSeconds / 3600.0 : nil)
            }
            store.execute(query)
        }
    }

    // MARK: - LLM Context

    func generateLLMContext() async -> String {
        let snap = await fetchSnapshot()
        return Self.formatForLLM(snap)
    }

    static func formatForLLM(_ snap: HealthSnapshot) -> String {
        var lines: [String] = []
        lines.append("Biometric Data")
        if snap.isSynthetic {
            lines.append("(synthetic - no Apple Watch connected)")
        }
        lines.append("")

        // Heart Rate
        if let hr = snap.currentHeartRate {
            lines.append("- Current Heart Rate: \(fmt(hr)) bpm")
        }
        if let avg = snap.averageHeartRate {
            lines.append("- 24h Avg Heart Rate: \(fmt(avg)) bpm")
        }
        if let current = snap.currentHeartRate, let avg = snap.averageHeartRate, avg > 0 {
            let variance = ((current - avg) / avg) * 100
            lines.append("- HR Variance from baseline: \(fmt(variance))%")
        }
        if let resting = snap.restingHeartRate {
            lines.append("- Resting Heart Rate: \(fmt(resting)) bpm")
        }

        // HRV
        if let hrv = snap.hrv {
            lines.append("- Heart Rate Variability (SDNN): \(fmt(hrv)) ms")
        }

        // Respiratory
        if let resp = snap.respiratoryRate {
            lines.append("- Respiratory Rate: \(fmt(resp)) breaths/min")
        }

        // Activity
        if let steps = snap.stepCount {
            lines.append("- Steps (24h): \(Int(steps))")
        }

        // Sleep
        if let sleep = snap.sleepHours {
            let hours = Int(sleep)
            let minutes = Int((sleep - Double(hours)) * 60)
            lines.append("- Sleep (24h): \(hours)h \(minutes)m")
        }

        return lines.joined(separator: "\n")
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Synthetic Fallback

    private static var syntheticSnapshot: HealthSnapshot {
        HealthSnapshot(
            currentHeartRate: 72.0,
            averageHeartRate: 68.0,
            restingHeartRate: 62.0,
            hrv: 42.0,
            stepCount: 6500,
            respiratoryRate: 15.0,
            sleepHours: 7.2,
            isSynthetic: true
        )
    }
}

enum HealthDataError: Error {
    case healthDataNotAvailable
    case invalidQuantityType
}
