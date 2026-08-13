//
//  DraglyApp.swift
//  Dragly
//

import SwiftUI
import SwiftData

@main
struct DraglyApp: App {
    @State private var appModel = AppModel()
    @State private var appearance = AppearanceModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(appearance)
                .preferredColorScheme(appearance.scheme.colorScheme)
        }
        .modelContainer(for: RunRecord.self)
    }
}
