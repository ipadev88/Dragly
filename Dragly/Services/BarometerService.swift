//
//  BarometerService.swift
//  Dragly
//
//  CMAltimeter: relative altitude (~0.1 m precision, far better than GPS
//  vertical) for track slope, and barometric pressure for density altitude.
//

import Foundation
import CoreMotion

@Observable
final class BarometerService {

    @ObservationIgnored private let altimeter = CMAltimeter()
    @ObservationIgnored private var samples: [(t: TimeInterval, alt: Double, hPa: Double)] = []

    private(set) var isRunning = false

    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
    var lastPressureHPa: Double? { samples.last?.hPa }

    func start() {
        guard isAvailable, !isRunning else { return }
        samples.removeAll()
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let d = data else { return }
            // CMAltitudeData.pressure is kPa → hPa.
            samples.append((Date().timeIntervalSince1970,
                            d.relativeAltitude.doubleValue,
                            d.pressure.doubleValue * 10))
            if samples.count > 4000 { samples.removeFirst(samples.count - 3000) }
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }

    /// Relative altitude at unix time `t` (nearest sample within 4 s).
    func relativeAltitude(at t: TimeInterval) -> Double? {
        guard let nearest = samples.min(by: { abs($0.t - t) < abs($1.t - t) }),
              abs(nearest.t - t) < 4 else { return nil }
        return nearest.alt
    }

    /// Track slope in % over [t0, t1] given the distance driven.
    func slopePercent(from t0: TimeInterval, to t1: TimeInterval, distance: Double) -> Double? {
        guard distance > 50,
              let a0 = relativeAltitude(at: t0),
              let a1 = relativeAltitude(at: t1) else { return nil }
        let slope = (a1 - a0) / distance * 100
        return abs(slope) < 20 ? slope : nil
    }
}
