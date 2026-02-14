import Foundation

protocol DataSourcePlugin: Sendable {
    var name: String { get }
    var icon: String { get }
    func fetchLatest() async -> [HealthMetric]
    func isAvailable() -> Bool
}

// MARK: - Mock Plugins

struct HealthKitPlugin: DataSourcePlugin {
    let name = "Apple Health"
    let icon = "heart.fill"

    func isAvailable() -> Bool { true }

    func fetchLatest() async -> [HealthMetric] {
        [
            HealthMetric(type: .heartRate, value: 72),
            HealthMetric(type: .hrv, value: 45),
            HealthMetric(type: .steps, value: 8432),
        ]
    }
}

struct OuraPlugin: DataSourcePlugin {
    let name = "Oura Ring"
    let icon = "circle.dotted.circle"

    func isAvailable() -> Bool { true }

    func fetchLatest() async -> [HealthMetric] {
        [
            HealthMetric(type: .sleep, value: 7.2),
            HealthMetric(type: .temperature, value: 98.4),
            HealthMetric(type: .hrv, value: 48),
        ]
    }
}

struct AirPodsPlugin: DataSourcePlugin {
    let name = "AirPods"
    let icon = "airpodspro"

    func isAvailable() -> Bool { true }

    func fetchLatest() async -> [HealthMetric] {
        [
            HealthMetric(type: .stress, value: 3.2),
        ]
    }
}
