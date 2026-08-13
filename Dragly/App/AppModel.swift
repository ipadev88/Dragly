//
//  AppModel.swift
//  Dragly
//
//  Wires services → engine → persistence and exposes app-level actions.
//

import Foundation
import SwiftData
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// A custom speed interval defined by the user (values in display units).
struct CustomInterval: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var from: Double
    var to: Double
    var unit: SpeedUnit

    var fromMS: Double { unit.toMS(from) }
    var toMS: Double { unit.toMS(to) }

    var title: String {
        let u = String(localized: unit == .kmh ? "km/h" : "mph")
        return "\(Int(from.rounded()))–\(Int(to.rounded())) \(u)"
    }
}

enum AppSettings {
    static let unitKey = "unitSpeed"
    static let rolloutKey = "rolloutEnabled"
    static let customIntervalsKey = "customIntervals"

    static var unit: SpeedUnit {
        SpeedUnit(rawValue: UserDefaults.standard.string(forKey: unitKey) ?? "") ?? .kmh
    }

    static var rolloutEnabled: Bool {
        UserDefaults.standard.object(forKey: rolloutKey) as? Bool ?? true
    }

    static var customIntervals: [CustomInterval] {
        guard let data = UserDefaults.standard.data(forKey: customIntervalsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomInterval].self, from: data)) ?? []
    }

    static func saveCustomIntervals(_ list: [CustomInterval]) {
        UserDefaults.standard.set((try? JSONEncoder().encode(list)) ?? Data(), forKey: customIntervalsKey)
    }
}

/// Tracks position/altitude from whatever fix source feeds the engine
/// (real GPS or the debug simulator) for conditions reporting.
final class ConditionsTracker {
    private(set) var lastCoordinate: (lat: Double, lon: Double)?
    private(set) var lastAltitude: Double?
    private var altSamples: [(t: TimeInterval, alt: Double, vAcc: Double)] = []

    func ingest(_ fix: SpeedFix) {
        if fix.horizontalAccuracy >= 0, fix.latitude.isFinite, fix.longitude.isFinite {
            lastCoordinate = (fix.latitude, fix.longitude)
        }
        if fix.verticalAccuracy > 0, fix.altitude.isFinite {
            lastAltitude = fix.altitude
            altSamples.append((fix.t, fix.altitude, fix.verticalAccuracy))
            if altSamples.count > 900 { altSamples.removeFirst(300) }
        }
    }

    /// GPS-based slope fallback (used when no barometer): % over [t0, t1].
    func gpsSlopePercent(from t0: TimeInterval, to t1: TimeInterval, distance: Double) -> Double? {
        guard distance > 100 else { return nil }
        func alt(at t: TimeInterval) -> Double? {
            guard let nearest = altSamples.min(by: { abs($0.t - t) < abs($1.t - t) }),
                  abs(nearest.t - t) < 5, nearest.vAcc < 15 else { return nil }
            return nearest.alt
        }
        guard let a0 = alt(at: t0), let a1 = alt(at: t1) else { return nil }
        let slope = (a1 - a0) / distance * 100
        return abs(slope) < 20 ? slope : nil
    }
}

@Observable
final class AppModel {

    let engine = RunEngine()
    let location = LocationService()
    let motion = MotionService()
    let barometer = BarometerService()
    #if DEBUG
    let simulator = SimulatedDriveService()
    #endif

    @ObservationIgnored var modelContext: ModelContext?

    /// Result of the most recently finished run, for the result sheet.
    var pendingResult: RunResult?

    init() {
        location.onFix = { [weak self] fix in
            self?.engine.ingest(fix: fix)
        }
        motion.onTick = { [weak self] tick in
            self?.engine.ingest(accel: tick)
        }
        #if DEBUG
        simulator.onFix = { [weak self] fix in
            self?.engine.ingest(fix: fix)
        }
        simulator.onAccel = { [weak self] tick in
            self?.engine.ingest(accel: tick)
        }
        #endif
        engine.onRunFinished = { [weak self] result in
            self?.save(result)
        }
    }

    var isArmed: Bool { engine.state != .idle }

    func arm() {
        guard engine.state == .idle else { return }
        engine.rolloutEnabled = AppSettings.rolloutEnabled
        engine.customMarks = AppSettings.customIntervals.flatMap { [$0.fromMS, $0.toMS] }
        engine.arm()
        location.start()
        motion.start()
        barometer.start()
        setIdleTimer(disabled: true)
    }

    func disarm() {
        engine.disarm()
        location.stop()
        motion.stop()
        barometer.stop()
        #if DEBUG
        simulator.stop()
        #endif
        setIdleTimer(disabled: false)
    }

    #if DEBUG
    /// Demo: feed a synthetic drive through the real pipeline (simulator only).
    func simulateRun(rolling: Bool) {
        if engine.state == .idle {
            engine.rolloutEnabled = AppSettings.rolloutEnabled
            engine.customMarks = AppSettings.customIntervals.flatMap { [$0.fromMS, $0.toMS] }
            engine.arm()
            setIdleTimer(disabled: true)
        }
        simulator.start(rolling: rolling)
    }
    #endif

    private func save(_ result: RunResult) {
        var enriched = result
        enriched.conditions = captureConditions(for: result)
        pendingResult = enriched
        guard let context = modelContext else { return }
        let record = RunRecord(result: enriched)
        context.insert(record)
        try? context.save()
        fetchTemperature(for: record)
    }

    /// Refine the engine's GPS-based conditions with barometer data
    /// (pressure for DA, and a far more precise slope than GPS altitude).
    private func captureConditions(for result: RunResult) -> RunConditions {
        var cond = result.conditions ?? RunConditions()
        cond.pressureHPa = barometer.lastPressureHPa

        if let first = result.curve.first(where: { $0.t >= 0 }), let last = result.curve.last {
            let base = result.date.timeIntervalSince1970
            if let baroSlope = barometer.slopePercent(
                from: base + first.t, to: base + last.t, distance: last.d - first.d) {
                cond.slopePercent = baroSlope
            }
        }
        return cond
    }

    /// Air temperature via open-meteo (no key needed), then density altitude.
    /// Updates the stored record in place when it arrives.
    private func fetchTemperature(for record: RunRecord) {
        guard let coord = engine.lastCoordinate else { return }
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coord.lat)&longitude=\(coord.lon)&current=temperature_2m"
        guard let url = URL(string: urlString) else { return }
        Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            // Offline or blocked network simply leaves temperature unset.
            guard let (payload, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double else { return }
            guard let self else { return }
            record.updateConditions { cond in
                cond.tempC = temp
                if let p = cond.pressureHPa {
                    cond.densityAltitudeM = Self.densityAltitudeM(pressureHPa: p, tempC: temp)
                }
            }
            try? self.modelContext?.save()
            // Refresh the open result sheet if it is showing this run.
            if self.pendingResult?.date == record.date, let updated = record.result {
                self.pendingResult = updated
            }
        }
    }

    /// Standard DA: pressure altitude corrected by ISA temperature deviation.
    static func densityAltitudeM(pressureHPa p: Double, tempC t: Double) -> Double {
        let paFt = 145366.45 * (1 - pow(p / 1013.25, 0.190284))
        let isaC = 15.0 - 1.98 * paFt / 1000.0
        let daFt = paFt + 118.8 * (t - isaC)
        return daFt * 0.3048
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
