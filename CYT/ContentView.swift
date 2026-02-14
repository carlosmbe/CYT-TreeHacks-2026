//
//  ContentView.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var llmService = LLMService()
    @State private var prompt = ""
    @State private var response = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Foundation Model")
                .font(.title2.weight(.semibold))

            Text("Status: \(statusText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Load Apple Model") {
                    Task {
                        await llmService.loadModel()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    llmService.cancel()
                }
                .buttonStyle(.bordered)
            }

            TextField("Enter a prompt...", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

            Button("Generate") {
                Task {
                    response = await llmService.generate(prompt: prompt)
                }
            }
            .buttonStyle(.bordered)

            ScrollView {
                Text(response.isEmpty ? "Response will appear here." : response)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
    }

    private var statusText: String {
        switch llmService.state {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading model..."
        case .ready:
            return "Ready"
        case .generating:
            return "Generating..."
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

#Preview {
    ContentView()
}
