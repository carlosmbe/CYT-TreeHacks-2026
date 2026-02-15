//
//  ContentView.swift
//  CYT
//
//  Minimal STT -> LLM -> TTS voice conversation.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            if #available(iOS 26.0, *) {
                ConversationView()
            } else {
                ContentUnavailableView(
                    "Requires iOS 26",
                    systemImage: "mic.slash",
                    description: Text("Voice conversation requires iOS 26 or later.")
                )
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
