//
//  Theme.swift
//  Dragly
//
//  Permanent dark "racing" palette.
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.062)
    static let panel = Color(red: 0.090, green: 0.098, blue: 0.125)
    static let panelStroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.62, green: 0.96, blue: 0.26)   // lime
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.26)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.20)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)
}

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelStyle()) }
}

extension SpeedUnit {
    var symbol: LocalizedStringKey { self == .kmh ? "km/h" : "mph" }
    var symbolText: String { String(localized: self == .kmh ? "km/h" : "mph") }
}

func formatTime(_ t: TimeInterval) -> String {
    String(format: "%.2f", t)
}
