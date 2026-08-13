//
//  ContentView.swift
//  Dragly
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppearanceModel.self) private var appearance
    @Environment(\.modelContext) private var context
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Measure", systemImage: "gauge.open.with.lines.needle.67percent.and.arrowtriangle", value: 0) {
                MeasureView()
            }
            Tab("History", systemImage: "list.bullet.rectangle", value: 1) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
        }
        .tint(appearance.accent.color)
        .preferredColorScheme(appearance.scheme.colorScheme)
        .task {
            app.modelContext = context
            #if DEBUG
            // Headless UI testing hooks.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--tab-history") { selectedTab = 1 }
            if args.contains("--tab-settings") { selectedTab = 2 }
            // Arms the real sensor pipeline, as if START had been tapped —
            // lets background behaviour be tested with simulated GPS routes.
            if args.contains("--arm") { app.arm() }
            // Verifies that switching the theme at runtime actually repaints.
            if args.contains("--flip-scheme") {
                try? await Task.sleep(for: .seconds(3))
                appearance.scheme = appearance.scheme == .dark ? .light : .dark
            }
            if args.contains("--sim-standing") {
                app.simulateRun(rolling: false)
            } else if args.contains("--sim-rolling") {
                app.simulateRun(rolling: true)
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .environment(AppearanceModel())
        .modelContainer(for: RunRecord.self, inMemory: true)
        .preferredColorScheme(.dark)
}
