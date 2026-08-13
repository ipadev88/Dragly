//
//  SignalBars.swift
//  Dragly
//
//  GPS quality as a four-step ladder. iOS exposes no satellite count — the
//  only public quality signals are horizontal and speed accuracy, so the
//  ladder is derived from those.
//

import SwiftUI

struct SignalQuality {
    /// 0 = no fix, 1…4 = bars lit.
    let level: Int
    let color: Color
    let title: LocalizedStringKey

    static func from(horizontalAccuracy: Double?, speedAccuracy: Double?) -> SignalQuality {
        guard let h = horizontalAccuracy, h > 0 else {
            return SignalQuality(level: 0, color: Theme.danger, title: "No signal")
        }
        // Speed accuracy matters more than position accuracy here: the
        // measurement runs on Doppler speed, not on coordinates.
        var level: Int
        switch h {
        case ..<6: level = 4
        case ..<10: level = 3
        case ..<20: level = 2
        default: level = 1
        }
        if let s = speedAccuracy, s > 0 {
            if s > 2.0 { level = min(level, 1) }
            else if s > 1.0 { level = min(level, 2) }
            else if s > 0.6 { level = min(level, 3) }
        }
        switch level {
        case 4: return SignalQuality(level: 4, color: Theme.textPrimary, title: "Excellent")
        case 3: return SignalQuality(level: 3, color: Theme.textPrimary, title: "Good")
        case 2: return SignalQuality(level: 2, color: Theme.warning, title: "Fair")
        default: return SignalQuality(level: 1, color: Theme.danger, title: "Weak")
        }
    }
}

/// Four rising bars; lit ones take the quality color, the rest stay dim.
struct SignalBars: View {
    let level: Int
    var color: Color = Theme.textPrimary
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 14
    var spacing: CGFloat = 2.5

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(i <= level ? color : Theme.textTertiary.opacity(0.45))
                    .frame(width: barWidth,
                           height: maxHeight * (0.4 + 0.2 * Double(i - 1)))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .animation(.easeOut(duration: 0.25), value: level)
    }
}

/// The status-bar chip: bars + a word, or a searching state.
struct GPSStatusChip: View {
    let quality: SignalQuality
    let isSearching: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textSecondary)
                Text("Searching…")
                    .font(.label(13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                SignalBars(level: quality.level, color: quality.color)
                Text(quality.title)
                    .font(.label(13))
                    .foregroundStyle(quality.color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.panelStroke, lineWidth: 1))
    }
}

#Preview {
    VStack(spacing: 12) {
        GPSStatusChip(quality: .from(horizontalAccuracy: 4, speedAccuracy: 0.4), isSearching: false)
        GPSStatusChip(quality: .from(horizontalAccuracy: 8, speedAccuracy: 0.8), isSearching: false)
        GPSStatusChip(quality: .from(horizontalAccuracy: 15, speedAccuracy: 1.5), isSearching: false)
        GPSStatusChip(quality: .from(horizontalAccuracy: 40, speedAccuracy: 3), isSearching: false)
        GPSStatusChip(quality: .from(horizontalAccuracy: nil, speedAccuracy: nil), isSearching: true)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
