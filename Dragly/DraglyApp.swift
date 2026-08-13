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
            // The scheme is applied inside ContentView, not here: observation
            // tracking on App.body does not reliably re-run this closure when
            // the appearance model changes, so switching the theme at runtime
            // had no effect until relaunch.
            ContentView()
                .environment(appModel)
                .environment(appearance)
        }
        .modelContainer(for: RunRecord.self)
    }
}
