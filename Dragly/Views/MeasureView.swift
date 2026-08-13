//
//  MeasureView.swift
//  Dragly
//
//  Main screen: live speed, GPS quality, arm/stop, live crossings, results.
//

import SwiftUI
import SwiftData

struct MeasureView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppearanceModel.self) private var appearance
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }
    private var accent: Color { appearance.accent.color }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 14) {
            statusBar
            Spacer(minLength: 0)
            speedometer
            Spacer(minLength: 0)
            stateBanner
            liveList
            armButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $app.pendingResult) { result in
            NavigationStack {
                RunResultView(result: result, unit: unit)
                    .navigationTitle(Text("Result"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { app.pendingResult = nil }
                        }
                    }
            }
            .preferredColorScheme(appearance.scheme.colorScheme)
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            gReadout
            Spacer()
            GPSStatusChip(quality: quality, isSearching: isSearching)
            #if DEBUG
            Menu {
                Button {
                    app.simulateRun(rolling: false)
                } label: {
                    Label("Simulate standing run", systemImage: "flag.checkered")
                }
                Button {
                    app.simulateRun(rolling: true)
                } label: {
                    Label("Simulate rolling run", systemImage: "gauge.open.with.lines.needle.67percent.and.arrowtriangle")
                }
            } label: {
                Image(systemName: "ladybug")
                    .foregroundStyle(Theme.textTertiary)
            }
            #endif
        }
    }

    private var quality: SignalQuality {
        .from(horizontalAccuracy: app.engine.gpsHorizontalAccuracy,
              speedAccuracy: app.engine.gpsSpeedAccuracy)
    }

    /// Armed but no fix yet — the chip shows a spinner instead of empty bars.
    private var isSearching: Bool {
        app.isArmed && app.engine.gpsHorizontalAccuracy == nil
    }

    private func chip(icon: String, text: Text, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            text.font(.label(13))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Readout

    private var speedometer: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(Int(unit.convert(app.engine.speedMS).rounded()))")
                .font(.readout(112))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit.symbol)
                .font(.label(18, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Longitudinal g as a plain number: accent while pulling, red under
    /// braking, muted when the IMU has nothing to say.
    private var gReadout: some View {
        let g = app.engine.accelG
        let color: Color = {
            guard app.motion.isRunning, abs(g) > 0.02 else { return Theme.textTertiary }
            return g > 0 ? accent : Theme.danger
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: String(format: "%+.2f", g))
                .font(.figureAccent(22))
                .contentTransition(.numericText())
            Text(verbatim: "g")
                .font(.label(13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(color)
        .animation(.easeOut(duration: 0.15), value: g)
    }

    // MARK: State

    private var stateBanner: some View {
        Group {
            switch app.engine.state {
            case .idle:
                if app.location.isDenied {
                    banner(Text("Location access denied. Enable it in Settings."), color: Theme.danger)
                } else {
                    banner(Text("Press START to arm"), color: Theme.textSecondary)
                }
            case .waitingForGPS:
                banner(Text("Waiting for GPS…"), color: Theme.warning)
            case .ready:
                banner(Text("Ready — accelerate, the clock starts itself"), color: accent)
            case .running:
                runningBanner
            }
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.danger).frame(width: 9, height: 9)
            Text(app.engine.liveStandingStart ? "Standing start" : "Rolling start")
                .font(.label(15, weight: .bold))
            Spacer()
            if let start = app.engine.runStartDate {
                TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                    Text(verbatim: formatTime(max(0, ctx.date.timeIntervalSince(start))) + " s")
                        .font(.figureAccent(22))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .panel()
    }

    private func banner(_ text: Text, color: Color) -> some View {
        text
            .font(.label(15))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .panel()
    }

    /// Last few crossings while running.
    private var liveList: some View {
        VStack(spacing: 6) {
            // Backfilled marks carry negative times (crossed before the run's
            // zero); they belong in the result table, not in the live ticker.
            let crossings = app.engine.liveSpeedCrossings
                .filter { $0.t >= 0 }
                .suffix(4)
                .reversed()
            ForEach(Array(crossings), id: \.self) { c in
                HStack {
                    Text(verbatim: "\(Int(unit.convert(c.ms).rounded())) \(unit.symbolText)")
                        .font(.figure(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(verbatim: formatTime(c.t) + " s")
                        .font(.figureAccent(16))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .panel()
            }
        }
        .frame(minHeight: 44 * 4 + 18, alignment: .bottom)
        .animation(.snappy(duration: 0.25), value: app.engine.liveSpeedCrossings)
    }

    private var armButton: some View {
        Button {
            if app.isArmed {
                app.disarm()
            } else {
                app.arm()
            }
        } label: {
            Text(app.isArmed ? "STOP" : "START")
                .font(.system(size: 23, weight: .black, design: .rounded))
                .tracking(3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    app.isArmed ? Theme.danger : accent,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(app.isArmed ? Color.white : appearance.accent.onAccent)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: app.isArmed)
    }
}

extension RunResult: Identifiable {
    var id: Date { date }
}
