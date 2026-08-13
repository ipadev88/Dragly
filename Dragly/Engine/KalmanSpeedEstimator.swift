//
//  KalmanSpeedEstimator.swift
//  Dragly
//
//  Sensor-fusion core: fuses 1 Hz GPS Doppler speed with 100 Hz longitudinal
//  acceleration into a continuous speed/distance estimate.
//
//  State vector: [v — speed (m/s), b — longitudinal accelerometer bias (m/s²)]
//  Predict (each accel tick):  v += (a_long − b)·dt
//  Update  (each GPS fix):     measurement v_gps with R = speedAccuracy²
//
//  Pure Foundation — no CoreLocation/CoreMotion imports, unit-testable off-device.
//

import Foundation

/// One fused estimate tick.
struct FusedSample {
    /// Unix time, seconds.
    var t: TimeInterval
    /// Fused speed, m/s (never negative).
    var v: Double
    /// Integrated distance since the last `resetDistance()`, meters.
    var d: Double
    /// Longitudinal acceleration used for the last predict, m/s².
    var a: Double
}

/// GPS fix input, framework-agnostic.
struct SpeedFix {
    var t: TimeInterval
    /// Doppler speed, m/s. Negative = invalid.
    var speed: Double
    /// 1-sigma speed accuracy, m/s. Negative = invalid.
    var speedAccuracy: Double
    /// Horizontal position accuracy, m. Negative = invalid.
    var horizontalAccuracy: Double
    /// Optional position/altitude (conditions reporting, not used by the filter).
    var latitude: Double = .nan
    var longitude: Double = .nan
    /// GPS altitude, m. NaN = unknown.
    var altitude: Double = .nan
    /// Vertical accuracy, m. Negative = invalid.
    var verticalAccuracy: Double = -1

    var isValid: Bool {
        speed >= 0 && speedAccuracy >= 0 && horizontalAccuracy >= 0
    }
}

/// Accelerometer input: gravity-free horizontal acceleration in the device
/// frame (the phone is assumed fixed in the car, any orientation).
struct AccelTick {
    var t: TimeInterval
    /// Horizontal acceleration vector components, m/s² (device frame).
    var hx: Double
    var hy: Double
    var hz: Double

    var magnitude: Double { (hx * hx + hy * hy + hz * hz).squareRoot() }
}

final class KalmanSpeedEstimator {

    // MARK: Tuning

    /// White accel noise when integrating real accelerometer data, m/s².
    var accelNoise = 0.35
    /// Process noise when no accelerometer is available (GPS-only), m/s².
    var coastAccelNoise = 3.0
    /// Bias random walk, m/s² per √s.
    var biasRandomWalk = 0.02
    /// Floor for GPS speed sigma, m/s (CoreLocation is often optimistic).
    /// 0.6 won the tuning sweep: real Doppler noise + fix latency exceed the reported sigma.
    var minSpeedSigma = 0.6

    // MARK: State

    private(set) var v: Double = 0
    private(set) var bias: Double = 0
    private(set) var distance: Double = 0
    private(set) var lastTime: TimeInterval?
    private(set) var lastAccel: Double = 0
    private(set) var isInitialized = false
    /// v_gps − v_estimate at the last fix. Strongly negative means the
    /// estimate has run away above GPS — the caller uses this to detect
    /// integration driven by something other than driving (e.g. shaking).
    private(set) var lastInnovation: Double = 0

    // Covariance
    private var p11 = 25.0
    private var p12 = 0.0
    private var p22 = 0.25

    // Short state history for GPS latency compensation: a fix timestamped at
    // t−0.2 s must be compared against the estimate at t−0.2 s, not "now",
    // or the filter is dragged behind truth by a·latency.
    private var history: [(t: TimeInterval, v: Double)] = []

    private func speedInHistory(at t: TimeInterval) -> Double? {
        guard let first = history.first, let last = history.last,
              t >= first.t, t <= last.t else { return nil }
        var lo = 0, hi = history.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if history[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = history[lo], b = history[hi]
        guard b.t > a.t else { return a.v }
        let f = (t - a.t) / (b.t - a.t)
        return a.v + f * (b.v - a.v)
    }

    var current: FusedSample? {
        guard let t = lastTime, isInitialized else { return nil }
        return FusedSample(t: t, v: v, d: distance, a: lastAccel)
    }

    /// Force the estimate back onto a GPS measurement, discarding accumulated
    /// integration error (used when the IMU has clearly been driven by
    /// something other than vehicle motion).
    func snap(to speed: Double, at t: TimeInterval) {
        v = max(0, speed)
        bias = 0
        lastTime = t
        lastAccel = 0
        p11 = 4.0
        p12 = 0
        p22 = 0.25
        history.removeAll()
        history.append((t, v))
    }

    func reset() {
        v = 0; bias = 0; distance = 0
        lastTime = nil; lastAccel = 0
        lastInnovation = 0
        isInitialized = false
        p11 = 25.0; p12 = 0; p22 = 0.25
        history.removeAll()
    }

    func resetDistance() {
        distance = 0
    }

    /// Overwrite speed and distance after a confirmed standing launch, when
    /// the acceleration ramp between streak start and confirmation has been
    /// replayed by the caller (the filter itself sat at v = 0 while the
    /// travel direction was still unknown).
    func seedAfterLaunch(v seedV: Double, distance seedD: Double, at t: TimeInterval) {
        v = max(0, seedV)
        distance = seedD
        lastTime = t
        p11 = max(p11, 1.0)
        history.append((t, v))
    }

    /// Advance the state to time `t`. Pass `aLong` from the accelerometer when
    /// the travel direction is known, `nil` for GPS-only operation.
    /// Returns the fused sample at `t`, or nil if not initialized / t not newer.
    @discardableResult
    func predict(to t: TimeInterval, aLong: Double?) -> FusedSample? {
        guard isInitialized, let t0 = lastTime else { return nil }
        let dt = t - t0
        guard dt > 0 else { return current } // out-of-order tick: keep state
        guard dt < 3.0 else {
            // Data gap too large to bridge — hold value, inflate uncertainty.
            lastTime = t
            p11 += coastAccelNoise * coastAccelNoise * dt * dt
            return current
        }

        let a = (aLong ?? 0) - bias
        let vPrev = v
        v = max(0, v + a * dt)
        distance += (vPrev + v) / 2 * dt
        lastAccel = a
        lastTime = t

        // P = F·P·Fᵀ + Q,  F = [[1, −dt], [0, 1]]
        // White accel noise integrates into speed variance linearly in time
        // (σa² is a PSD): qv = σa²·dt, not σa²·dt².
        let sigmaA = (aLong != nil) ? accelNoise : coastAccelNoise
        let qv = sigmaA * sigmaA * dt
        let qb = biasRandomWalk * biasRandomWalk * dt
        let np11 = p11 - 2 * dt * p12 + dt * dt * p22 + qv
        let np12 = p12 - dt * p22
        p11 = np11
        p12 = np12
        p22 += qb

        history.append((t, v))
        if let first = history.first, t - first.t > 1.5 {
            history.removeAll { $0.t < t - 1.2 }
        }

        return current
    }

    /// Apply a GPS speed measurement. Call `predict(to: fix.t, ...)` first;
    /// if the fix is older than the filter time the innovation is applied
    /// in place (sub-second staleness is absorbed by the filter).
    /// Returns the corrected sample.
    @discardableResult
    func update(fix: SpeedFix, hasAccel: Bool) -> FusedSample? {
        guard fix.isValid else { return current }

        if !isInitialized {
            v = max(0, fix.speed)
            let sigma = max(fix.speedAccuracy, minSpeedSigma)
            p11 = sigma * sigma
            p12 = 0
            p22 = 0.25
            lastTime = fix.t
            isInitialized = true
            return current
        }

        let sigma = max(fix.speedAccuracy, minSpeedSigma)
        let r = sigma * sigma
        let s = p11 + r
        guard s > 0 else { return current }
        let k1 = p11 / s
        let k2 = p12 / s
        // Latency compensation: innovate against the estimate at fix time.
        let vRef = speedInHistory(at: fix.t) ?? v
        let innovation = fix.speed - vRef
        lastInnovation = innovation

        v = max(0, v + k1 * innovation)
        // Shift the history by the same correction so later stale fixes
        // innovate against corrected values.
        if k1 * abs(innovation) > 0.001 {
            for i in history.indices {
                history[i].v = max(0, history[i].v + k1 * innovation)
            }
        }
        if hasAccel {
            bias += k2 * innovation
            bias = min(1.5, max(-1.5, bias))
        }

        p11 *= (1 - k1)
        p22 -= k2 * p12
        p12 *= (1 - k1)
        p22 = max(p22, 1e-6)
        p11 = max(p11, 1e-6)

        return current
    }
}
