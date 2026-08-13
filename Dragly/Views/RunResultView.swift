//
//  RunResultView.swift
//  Dragly
//
//  Result table + speed chart. Shared by the post-run sheet and history detail.
//

import SwiftUI
import Charts

struct RunResultView: View {
    let result: RunResult
    let unit: SpeedUnit

    @State private var scrubT: Double?

    /// Debug hook: `--scrub` presets the scrubber so the annotation can be
    /// screenshotted headlessly (the simulator can't be touch-driven here).
    private var debugScrubT: Double? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--scrub"),
              let last = result.curve.last else { return nil }
        return last.t * 0.55
        #else
        return nil
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                conditionsRow
                chart
                speedTable
                if !result.distanceSegments.isEmpty {
                    distanceTable
                }
                statsRow
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var extraPairs: [(Double, Double, SpeedUnit)] {
        AppSettings.customIntervals.map { ($0.fromMS, $0.toMS, $0.unit) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            badge(result.standingStart ? Text("Standing start") : Text("Rolling start"),
                  color: Theme.accent)
            if !result.usedMotion {
                badge(Text("GPS-only"), color: Theme.warning)
            }
            if result.standingStart && result.rolloutApplied {
                badge(Text("1-ft rollout"), color: Theme.textSecondary)
            }
            Spacer()
            Text(result.date, format: .dateTime.day().month().hour().minute())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func badge(_ text: Text, color: Color) -> some View {
        text
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
    }

    // MARK: Conditions (temp / altitude / DA / slope)

    private var conditionsRow: some View {
        Group {
            if let c = result.conditions, !c.isEmpty {
                HStack(spacing: 8) {
                    if let t = c.tempC {
                        conditionChip(icon: "thermometer.medium", text: formatTemp(t))
                    }
                    if let a = c.altitudeM {
                        conditionChip(icon: "mountain.2.fill", text: formatAlt(a))
                    }
                    if let da = c.densityAltitudeM {
                        conditionChip(icon: "gauge.with.dots.needle.bottom.50percent", text: "DA " + formatAlt(da))
                    }
                    if let s = c.slopePercent {
                        conditionChip(icon: "angle", text: String(format: "%+.2f%%", s))
                    }
                    Spacer()
                }
            }
        }
    }

    private func conditionChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(verbatim: text)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.panelStroke, lineWidth: 1))
    }

    private func formatTemp(_ c: Double) -> String {
        unit == .kmh ? "\(Int(c.rounded()))°C" : "\(Int((c * 9 / 5 + 32).rounded()))°F"
    }

    private func formatAlt(_ m: Double) -> String {
        unit == .kmh ? "\(Int(m.rounded())) m" : "\(Int((m / 0.3048).rounded())) ft"
    }

    // MARK: Chart

    private func nearestPoint(to t: Double) -> CurvePoint? {
        result.curve.min { abs($0.t - t) < abs($1.t - t) }
    }

    private func accelG(at p: CurvePoint) -> Double? {
        let c = result.curve
        guard let i = c.firstIndex(of: p) else { return nil }
        let a = c[max(0, i - 1)], b = c[min(c.count - 1, i + 1)]
        guard b.t > a.t else { return nil }
        return (b.v - a.v) / (b.t - a.t) / 9.80665
    }

    private var chart: some View {
        let points = result.curve
        return Group {
            if points.count > 3 {
                Chart {
                    ForEach(points, id: \.t) { p in
                        LineMark(
                            x: .value("Time", p.t),
                            y: .value("Speed", unit.convert(p.v)))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    }
                    if let t = scrubT ?? debugScrubT, let p = nearestPoint(to: t) {
                        RuleMark(x: .value("Time", p.t))
                            .foregroundStyle(Theme.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        PointMark(
                            x: .value("Time", p.t),
                            y: .value("Speed", unit.convert(p.v)))
                        .foregroundStyle(.white)
                        .symbolSize(60)
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            scrubCard(p)
                        }
                    }
                }
                .chartXSelection(value: $scrubT)
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(Theme.panelStroke)
                        AxisValueLabel()
                            .foregroundStyle(Theme.textTertiary)
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(Theme.panelStroke)
                        AxisValueLabel()
                            .foregroundStyle(Theme.textTertiary)
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .frame(height: 190)
                .padding(14)
                .panel()
            }
        }
    }

    /// Values card shown while scrubbing the chart.
    private func scrubCard(_ p: CurvePoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: String(format: "%.2f s", p.t))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: "\(Int(unit.convert(p.v).rounded())) \(unit.symbolText)")
                .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.accent)
            HStack(spacing: 6) {
                if p.d > 0.5 {
                    Text(verbatim: unit == .kmh
                         ? "\(Int(p.d.rounded())) m"
                         : "\(Int((p.d / 0.3048).rounded())) ft")
                }
                if let g = accelG(at: p) {
                    Text(verbatim: String(format: "%+.2f g", g))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.panelStroke, lineWidth: 1))
    }

    // MARK: Tables

    private var speedTable: some View {
        let segs = result.speedSegments(unit: unit, extraPairs: extraPairs)
        return Group {
            if !segs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(Text("Speed intervals"))
                    ForEach(Array(segs.enumerated()), id: \.element.id) { i, seg in
                        HStack {
                            Text(verbatim: seg.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(verbatim: formatTime(seg.time) + " s")
                                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        if i < segs.count - 1 {
                            Divider().overlay(Theme.panelStroke).padding(.leading, 14)
                        }
                    }
                }
                .padding(.vertical, 6)
                .panel()
            }
        }
    }

    private var distanceTable: some View {
        let segs = result.distanceSegments
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle(Text("Distance"))
            ForEach(Array(segs.enumerated()), id: \.element.id) { i, seg in
                HStack {
                    Text(verbatim: seg.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(verbatim: "@ \(Int(unit.convert(seg.trapSpeedMS).rounded())) \(unit.symbolText)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text(verbatim: formatTime(seg.time) + " s")
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 74, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                if i < segs.count - 1 {
                    Divider().overlay(Theme.panelStroke).padding(.leading, 14)
                }
            }
        }
        .padding(.vertical, 6)
        .panel()
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat(title: Text("Top speed"),
                 value: "\(Int(unit.convert(result.peakSpeedMS).rounded())) \(unit.symbolText)")
            stat(title: Text("Peak g"),
                 value: String(format: "%.2f", result.peakAccelG))
            stat(title: Text("GPS accuracy"),
                 value: "±\(Int(result.gpsAccuracy.rounded())) m")
        }
    }

    private func stat(title: Text, value: String) -> some View {
        VStack(spacing: 3) {
            title
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Text(verbatim: value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .panel()
    }
}
