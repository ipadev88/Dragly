//
//  DraglyApp.swift
//  Dragly
//

import SwiftUI
import SwiftData

@main
struct DraglyApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: RunRecord.self)
    }
}
