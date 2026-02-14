import Foundation
import SwiftUI

enum HealthMetricType: String, CaseIterable, Codable, Sendable {
    case heartRate = "Heart Rate"
    case stress = "Stress Level"
    case temperature = "Temperature"
    case hrv = "HRV"
    case sleep = "Sleep"
    case steps = "Steps"

    var unit: String {
        switch self {
        case .heartRate: "BPM"
        case .stress: "/10"
        case .temperature: "°F"
        case .hrv: "ms"
        case .sleep: "hrs"
        case .steps: ""
        }
    }

    var icon: String {
        switch self {
        case .heartRate: "heart.fill"
        case .stress: "brain.head.profile"
        case .temperature: "thermometer.medium"
        case .hrv: "waveform.path.ecg"
        case .sleep: "moon.zzz.fill"
        case .steps: "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: .red
        case .stress: .orange
        case .temperature: .yellow
        case .hrv: .purple
        case .sleep: .indigo
        case .steps: .green
        }
    }
}

struct HealthMetric: Identifiable, Codable, Sendable {
    let id: UUID
    let type: HealthMetricType
    let value: Double
    let timestamp: Date

    init(id: UUID = UUID(), type: HealthMetricType, value: Double, timestamp: Date = .now) {
        self.id = id
        self.type = type
        self.value = value
        self.timestamp = timestamp
    }

    var formattedValue: String {
        switch type {
        case .heartRate: "\(Int(value))"
        case .stress: String(format: "%.1f", value)
        case .temperature: String(format: "%.1f", value)
        case .hrv: "\(Int(value))"
        case .sleep: String(format: "%.1f", value)
        case .steps: "\(Int(value))"
        }
    }
}
