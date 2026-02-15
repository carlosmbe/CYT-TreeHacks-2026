//
//  CYTApp.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//

import SwiftUI

@main
struct CYTApp: App {
    var body: some Scene {
        WindowGroup {
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
        }
    }
}
