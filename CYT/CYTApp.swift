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
            TabView {
                HealthTestView()
                    .tabItem {
                        Label("Health Test", systemImage: "heart.text.square")
                    }
                
                ContentView()
                    .tabItem {
                        Label("Camera", systemImage: "camera")
                    }
                
            }
        }
    }
}
