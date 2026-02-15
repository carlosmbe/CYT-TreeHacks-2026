//
//  ContentView.swift
//  CYT
//
//  Main UI: audio conversation by default, VLM/vision available as secondary.
//

import SwiftUI

struct ContentView: View {
    @State private var isShowingInfo = false
    @State private var showVision = false

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26.0, *) {
                    ConversationView()
                } else {
                    unsupportedFallback
                }
            }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
            }

            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showVision = true
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
            }
            #endif
        }
        .sheet(isPresented: $isShowingInfo) {
            InfoView()
        }
        .sheet(isPresented: $showVision) {
            VisionView()
        }
        }
    }

    private var unsupportedFallback: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Voice conversation requires iOS 26.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Vision") {
                showVision = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
