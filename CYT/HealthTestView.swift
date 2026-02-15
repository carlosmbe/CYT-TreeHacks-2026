//
//  HealthTestView.swift
//  CYT
//
//  Test view to visualise live HealthKit data from HealthDataProvider.
//

import SwiftUI

struct HealthTestView: View {
    @State private var healthProvider = HealthDataProvider()

    @State private var snapshot = HealthSnapshot()
    @State private var llmContext: String = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var lastRefresh: Date?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if snapshot.isSynthetic && lastRefresh != nil {
                    Section {
                        Label("Showing synthetic data - no Apple Watch data found", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Heart Rate") {
                    row("Current HR", value: snapshot.currentHeartRate, unit: "bpm")
                    row("24h Average HR", value: snapshot.averageHeartRate, unit: "bpm")
                    row("Resting HR", value: snapshot.restingHeartRate, unit: "bpm")

                    if let current = snapshot.currentHeartRate, let avg = snapshot.averageHeartRate, avg > 0 {
                        let variance = ((current - avg) / avg) * 100
                        HStack {
                            Text("Variance")
                            Spacer()
                            Text("\(String(format: "%.1f", variance))%")
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(abs(variance) > 20 ? .red : .green)
                        }
                    }
                }

                Section("Stress Indicators") {
                    if let hrv = snapshot.hrv {
                        HStack {
                            Text("HRV (SDNN)")
                            Spacer()
                            Text("\(String(format: "%.1f", hrv)) ms")
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(hrv < 30 ? .red : hrv < 50 ? .orange : .green)
                        }
                    } else {
                        row("HRV (SDNN)", value: nil, unit: "ms")
                    }

                    row("Respiratory Rate", value: snapshot.respiratoryRate, unit: "br/min")
                }

                Section("Activity & Sleep") {
                    if let steps = snapshot.stepCount {
                        HStack {
                            Text("Steps (24h)")
                            Spacer()
                            Text("\(Int(steps))")
                                .monospacedDigit()
                                .bold()
                        }
                    } else {
                        row("Steps (24h)", value: nil, unit: "")
                    }

                    if let sleep = snapshot.sleepHours {
                        let hours = Int(sleep)
                        let minutes = Int((sleep - Double(hours)) * 60)
                        HStack {
                            Text("Sleep (24h)")
                            Spacer()
                            Text("\(hours)h \(minutes)m")
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(sleep < 6 ? .red : sleep < 7 ? .orange : .green)
                        }
                    } else {
                        row("Sleep (24h)", value: nil, unit: "")
                    }
                }

                Section("LLM Context String") {
                    Text(llmContext.isEmpty ? "Loading..." : llmContext)
                        .font(.caption)
                        .monospaced()
                }

                Section {
                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack {
                            Text("Refresh")
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading)

                    if let lastRefresh {
                        Text("Last updated: \(lastRefresh.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Health Data Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await refresh()
            }
        }
    }

    private func row(_ label: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let value {
                Text("\(String(format: "%.1f", value)) \(unit)")
                    .monospacedDigit()
                    .bold()
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        snapshot = await healthProvider.fetchSnapshot()
        llmContext = HealthDataProvider.formatForLLM(snapshot)
        lastRefresh = Date()
    }
}

#Preview {
    HealthTestView()
}
