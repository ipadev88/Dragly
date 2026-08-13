//
//  Theme.swift
//  Dragly
//
//  Appearance: light/dark palettes, the user-chosen accent, and the type
//  scale. Colors are dynamic (resolved per interface style), so one palette
//  definition serves both schemes.
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Accent

enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case lime, cyan, blue, violet, magenta, orange, amber, red

    var id: String { rawValue }

    /// Dark-scheme color paired with a darkened light-scheme variant, so the
    /// accent keeps contrast against white panels.
    private var components: (dark: (Double, Double, Double), light: (Double, Double, Double)) {
        switch self {
        case .lime:    ((0.62, 0.96, 0.26), (0.31, 0.62, 0.05))
        case .cyan:    ((0.20, 0.90, 0.85), (0.00, 0.51, 0.51))
        case .blue:    ((0.29, 0.62, 1.00), (0.02, 0.38, 0.86))
        case .violet:  ((0.65, 0.55, 1.00), (0.38, 0.25, 0.85))
        case .magenta: ((1.00, 0.42, 0.78), (0.78, 0.10, 0.50))
        case .orange:  ((1.00, 0.58, 0.20), (0.80, 0.36, 0.00))
        case .amber:   ((1.00, 0.80, 0.20), (0.66, 0.47, 0.00))
        case .red:     ((1.00, 0.36, 0.32), (0.80, 0.11, 0.09))
        }
    }

    var color: Color {
        let c = components
        return Color.dynamic(dark: c.dark, light: c.light)
    }

    /// Readable foreground for text sitting on top of the accent.
    var onAccent: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
        #else
        .black
        #endif
    }

    var title: LocalizedStringKey {
        switch self {
        case .lime: "Lime"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .violet: "Violet"
        case .magenta: "Magenta"
        case .orange: "Orange"
        case .amber: "Amber"
        case .red: "Red"
        }
    }
}

// MARK: - Scheme

enum AppearanceChoice: String, CaseIterable, Identifiable, Codable {
    case system, dark, light

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

// MARK: - Observable appearance settings

@Observable
final class AppearanceModel {
    static let accentKey = "accentChoice"
    static let schemeKey = "appearanceChoice"

    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey) }
    }
    var scheme: AppearanceChoice {
        didSet { UserDefaults.standard.set(scheme.rawValue, forKey: Self.schemeKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        accent = AccentChoice(rawValue: defaults.string(forKey: Self.accentKey) ?? "") ?? .lime
        scheme = AppearanceChoice(rawValue: defaults.string(forKey: Self.schemeKey) ?? "") ?? .dark
    }

    func reset() {
        accent = .lime
        scheme = .dark
    }
}

// MARK: - Palette

extension Color {
    /// A color that resolves per interface style, keeping both palettes in
    /// one place instead of scattering `colorScheme` checks through views.
    static func dynamic(dark: (Double, Double, Double), light: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(red: dark.0, green: dark.1, blue: dark.2)
        #endif
    }

    /// White-on-dark / black-on-light overlay at a given opacity.
    static func level(_ opacity: Double) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: opacity)
                : UIColor(white: 0, alpha: opacity)
        })
        #else
        Color.white.opacity(opacity)
        #endif
    }
}

enum Theme {
    static let background = Color.dynamic(dark: (0.043, 0.047, 0.062),
                                          light: (0.949, 0.953, 0.965))
    static let panel = Color.dynamic(dark: (0.090, 0.098, 0.125),
                                     light: (1.0, 1.0, 1.0))
    static let panelStroke = Color.level(0.09)
    static let danger = Color.dynamic(dark: (1.0, 0.30, 0.26), light: (0.83, 0.11, 0.09))
    static let warning = Color.dynamic(dark: (1.0, 0.78, 0.20), light: (0.72, 0.51, 0.0))
    static let textPrimary = Color.dynamic(dark: (1, 1, 1), light: (0.07, 0.08, 0.10))
    static let textSecondary = Color.level(0.55)
    static let textTertiary = Color.level(0.32)
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

// MARK: - Type scale

extension Font {
    /// The big instrument readout: SF Pro Expanded Black — wide, muscular
    /// numerals like a performance-car cluster. Expanded runs much wider than
    /// the default face, so sizes here are deliberately smaller.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
        .width(.expanded)
    }

    /// Result times and other numbers that should read as performance:
    /// same expanded cut as the readout, tabular so columns stay aligned.
    static func figureAccent(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default)
        .width(.expanded)
        .monospacedDigit()
    }

    /// Neutral numbers — labels, chips, secondary values. Upright, tabular.
    static func figure(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
        .monospacedDigit()
    }

    /// Body and control labels.
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Small uppercase section headers.
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension SpeedUnit {
    var symbol: LocalizedStringKey { self == .kmh ? "km/h" : "mph" }
    var symbolText: String { String(localized: self == .kmh ? "km/h" : "mph") }
}

func formatTime(_ t: TimeInterval) -> String {
    String(format: "%.2f", t)
}
