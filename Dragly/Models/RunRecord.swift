//
//  RunRecord.swift
//  Dragly
//
//  SwiftData persistence for finished runs. The full RunResult (all mark
//  crossings + speed curve) is stored as JSON so history can resolve any
//  interval later; a few scalar columns are kept for fast list display.
//

import Foundation
import SwiftData

@Model
final class RunRecord {
    var date: Date
    var standingStart: Bool
    var peakSpeedMS: Double
    var peakAccelG: Double
    var usedMotion: Bool
    var payload: Data

    init(result: RunResult) {
        self.date = result.date
        self.standingStart = result.standingStart
        self.peakSpeedMS = result.peakSpeedMS
        self.peakAccelG = result.peakAccelG
        self.usedMotion = result.usedMotion
        self.payload = (try? JSONEncoder().encode(result)) ?? Data()
    }

    var result: RunResult? {
        try? JSONDecoder().decode(RunResult.self, from: payload)
    }

    /// Mutate stored conditions (e.g. when the async temperature fetch lands).
    func updateConditions(_ mutate: (inout RunConditions) -> Void) {
        guard var r = result else { return }
        var cond = r.conditions ?? RunConditions()
        mutate(&cond)
        r.conditions = cond
        payload = (try? JSONEncoder().encode(r)) ?? payload
    }

    /// Headline segment for the history list.
    func headline(unit: SpeedUnit) -> String? {
        guard let r = result else { return nil }
        let segs = r.speedSegments(unit: unit)
        if standingStart {
            let target: Double = unit == .kmh ? 100 / 3.6 : 60 / 2.23693629
            if let s = segs.first(where: { $0.fromMS == 0 && abs($0.toMS - target) < 0.1 }) {
                return "\(s.title) · \(String(format: "%.2f s", s.time))"
            }
        }
        // Prefer the widest resolved interval.
        if let s = segs.max(by: { ($0.toMS - $0.fromMS) < ($1.toMS - $1.fromMS) }) {
            return "\(s.title) · \(String(format: "%.2f s", s.time))"
        }
        if let d = r.distanceSegments.last {
            return "\(d.title) · \(String(format: "%.2f s", d.time))"
        }
        return nil
    }
}
