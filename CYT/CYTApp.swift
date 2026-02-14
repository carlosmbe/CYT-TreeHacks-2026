//
//  CYTApp.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//

import SwiftUI

@main
struct CYTApp: App {
    @State private var store = JournalStore()
    @State private var showNewEntry = false

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house.fill") {
                    HomeView()
                }

                Tab("New Entry", systemImage: "plus.circle.fill") {
                    NewEntryView()
                }
            }
            .environment(store)
        }
    }
}
