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
    @AppStorage(AppSettings.unitKey) private var unitRaw = SpeedUnit.kmh.rawValue

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 14) {
            statusBar
            Spacer(minLength: 0)
            speedometer
            gMeter
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
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Pieces

    private var statusBar: some View {
        HStack(spacing: 8) {
            gpsChip
            if app.motion.isRunning {
                chip(icon: "gyroscope", text: Text("IMU"), color: Theme.accent)
            }
            Spacer()
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

    private var gpsChip: some View {
        let (color, label): (Color, Text) = {
            guard app.isArmed else { return (Theme.textTertiary, Text("GPS")) }
            guard let acc = app.engine.gpsHorizontalAccuracy else {
                return (Theme.danger, Text("No GPS"))
            }
            let text = Text(verbatim: "±\(Int(acc.rounded())) m")
            if acc <= 8 { return (Theme.accent, text) }
            if acc <= 20 { return (Theme.warning, text) }
            return (Theme.danger, text)
        }()
        return chip(icon: "location.fill", text: label, color: color)
    }

    private func chip(icon: String, text: Text, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            text.font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var speedometer: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(Int(unit.convert(app.engine.speedMS).rounded()))")
                .font(.system(size: 132, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit.symbol)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var gMeter: some View {
        let g = app.engine.accelG
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let clamped = min(1.5, max(-1.5, g))
                let x = w * (clamped + 1.5) / 3.0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel).frame(height: 6)
                    Rectangle()
                        .fill(Theme.textTertiary)
                        .frame(width: 1, height: 12)
                        .offset(x: w / 2)
                    Circle()
                        .fill(g >= -0.05 ? Theme.accent : Theme.danger)
                        .frame(width: 12, height: 12)
                        .offset(x: x - 6)
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            Text(verbatim: String(format: "%+.2f g", g))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 32)
    }

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
                banner(Text("Ready — accelerate, the clock starts itself"), color: Theme.accent)
            case .running:
                runningBanner
            }
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.danger).frame(width: 9, height: 9)
            Text(app.engine.liveStandingStart ? "Standing start" : "Rolling start")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            if let start = app.engine.runStartDate {
                TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                    Text(verbatim: formatTime(max(0, ctx.date.timeIntervalSince(start))))
                        .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
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
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .panel()
    }

    /// Last few crossings while running.
    private var liveList: some View {
        VStack(spacing: 6) {
            let crossings = app.engine.liveSpeedCrossings.suffix(4).reversed()
            ForEach(Array(crossings), id: \.self) { c in
                HStack {
                    Text(verbatim: "\(Int(unit.convert(c.ms).rounded())) \(unit.symbolText)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(verbatim: formatTime(c.t) + " s")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.accent)
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
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    app.isArmed ? Theme.danger : Theme.accent,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: app.isArmed)
    }
}

extension RunResult: Identifiable {
    var id: Date { date }
}
