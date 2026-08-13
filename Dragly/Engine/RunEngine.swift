//
//  RunEngine.swift
//  Dragly
//
//  Measurement state machine (Draggy-style):
//   - while armed the engine continuously fuses GPS + accelerometer;
//   - a run begins on launch from standstill (accelerometer edge) or, rolling,
//     when speed first crosses an upward mark while accelerating;
//   - every speed mark (10 km/h + 10 mph grid + custom bounds) and distance
//     mark crossed upward is timestamped with sub-tick linear interpolation;
//   - the run keeps recording as long as the car keeps accelerating (200, 250,
//     300 … all get captured) and ends when speed clearly drops;
//   - the result contains all crossings, so any interval can be resolved.
//
//  Pure Foundation — services feed it SpeedFix / AccelTick.
//

import Foundation
import Observation

@Observable
final class RunEngine {

    enum State: Equatable {
        case idle           // not measuring
        case waitingForGPS  // armed, no acceptable fix yet
        case ready          // armed, tracking, waiting for a run to begin
        case running        // a run is in progress
    }

    // MARK: Configuration

    /// Extra speed marks (m/s) to timestamp, e.g. custom interval bounds.
    var customMarks: [Double] = []
    var rolloutEnabled = true
    /// Reject fixes with horizontal accuracy worse than this, m.
    var maxHorizontalAccuracy = 20.0

    /// Hard physical ceiling on longitudinal acceleration, m/s².
    /// Even a slick-shod drag car stays under ~1.6 g; anything above this is
    /// not the car moving (hand shake, phone drop, road impact), so it is
    /// clamped instead of being integrated into speed.
    private static let maxCarAccel = 1.6 * 9.80665
    /// Abort a run when the estimate exceeds GPS speed by this much, m/s.
    private static let maxSpeedDivergence = 6.0
    /// Abort a run after this long without a usable GPS speed, s.
    private static let maxUncorroboratedRun = 3.0

    /// Called on the same thread the engine is fed from when a run completes.
    var onRunFinished: ((RunResult) -> Void)?

    // MARK: Observable outputs (throttled for UI)

    private(set) var state: State = .idle
    private(set) var speedMS: Double = 0
    private(set) var accelG: Double = 0
    private(set) var gpsHorizontalAccuracy: Double?
    /// 1-sigma Doppler speed accuracy of the last fix, m/s (nil = unusable).
    private(set) var gpsSpeedAccuracy: Double?
    private(set) var motionActive = false
    /// Run-start unix time while running (for live elapsed display).
    private(set) var runStartDate: Date?
    /// Live crossings of the current run, for the in-run list.
    private(set) var liveSpeedCrossings: [SpeedCrossing] = []
    private(set) var liveDistanceCrossings: [DistanceCrossing] = []
    private(set) var liveStandingStart = false
    private(set) var lastResult: RunResult?

    var hasGoodFix: Bool {
        guard let acc = gpsHorizontalAccuracy else { return false }
        return acc <= maxHorizontalAccuracy
    }

    // MARK: Internals (not observation-tracked — mutated at 100 Hz)

    // Internal (not private) so tests and tuning harnesses can adjust filter noise.
    @ObservationIgnored let estimator = KalmanSpeedEstimator()

    @ObservationIgnored private var prev: FusedSample?
    @ObservationIgnored private var lastUIPush: TimeInterval = 0

    // Direction-of-travel estimation (device frame).
    @ObservationIgnored private var dirX = 0.0
    @ObservationIgnored private var dirY = 0.0
    @ObservationIgnored private var dirZ = 0.0
    @ObservationIgnored private var dirValid = false
    @ObservationIgnored private var lastGoodFix: SpeedFix?
    /// Last valid coordinate seen (for the weather lookup after a run).
    @ObservationIgnored private(set) var lastCoordinate: (lat: Double, lon: Double)?
    /// Altitude samples during the run: (distance travelled, altitude m).
    @ObservationIgnored private var altSamples: [(d: Double, alt: Double)] = []
    /// GPS track of the current run.
    @ObservationIgnored private var routePoints: [RoutePoint] = []
    @ObservationIgnored private var gpsTrend: Double = 0 // m/s² from consecutive fixes
    @ObservationIgnored private var lastAccelTick: AccelTick?
    @ObservationIgnored private var accelSeen = false

    // Launch detection.
    @ObservationIgnored private var launchStreakStart: TimeInterval?
    /// Unit vector of the first tick in the current launch streak — later
    /// ticks must keep pushing the same way, which shaking never does.
    @ObservationIgnored private var launchStreakDir: (x: Double, y: Double, z: Double)?
    /// Recent accel vectors for replaying the launch ramp (last ~0.8 s).
    @ObservationIgnored private var recentAccel: [AccelTick] = []

    // GPS corroboration of the current run.
    @ObservationIgnored private var runPeakGPSSpeed: Double = 0
    @ObservationIgnored private var lastValidSpeedFixT: TimeInterval?

    // Run session.
    @ObservationIgnored private var runActive = false
    @ObservationIgnored private var runStart: TimeInterval = 0       // unix
    @ObservationIgnored private var standingStart = false
    @ObservationIgnored private var zeroTime: TimeInterval?          // effective t0 (launch + rollout), unix
    @ObservationIgnored private var launchDistanceBase: Double = 0
    @ObservationIgnored private var peakV: Double = 0
    @ObservationIgnored private var peakA: Double = 0
    @ObservationIgnored private var decliningSince: TimeInterval?
    @ObservationIgnored private var runAccuracies: [Double] = []

    // Marks.
    @ObservationIgnored private var cachedMarks: [Double] = []
    @ObservationIgnored private var pendingSpeedMarks: [Double] = []
    @ObservationIgnored private var crossedSpeed: [SpeedCrossing] = []
    @ObservationIgnored private var pendingDistanceMarks: [Double] = []
    @ObservationIgnored private var crossedDistance: [DistanceCrossing] = []

    // Curve: full-rate ring pre-run (last 3 s), decimated during run.
    @ObservationIgnored private var trace: [FusedSample] = []
    @ObservationIgnored private var lastTraceT: TimeInterval = 0

    private static let mphMS = 2.23693629

    // MARK: Mark grid

    private var allSpeedMarks: [Double] {
        var marks = Set<Int>() // milli-m/s, integer keys to dedup
        for kmh in stride(from: 10.0, through: 450.0, by: 10.0) {
            marks.insert(Int((kmh / 3.6 * 1000).rounded()))
        }
        for mph in stride(from: 10.0, through: 280.0, by: 10.0) {
            marks.insert(Int((mph / Self.mphMS * 1000).rounded()))
        }
        for m in customMarks where m > 0.5 {
            marks.insert(Int((m * 1000).rounded()))
        }
        return marks.map { Double($0) / 1000 }.sorted()
    }

    // MARK: Control

    func arm() {
        guard state == .idle else { return }
        resetAll()
        cachedMarks = allSpeedMarks
        state = .waitingForGPS
    }

    func disarm() {
        if runActive { finishRun(aborted: crossedSpeed.isEmpty && crossedDistance.isEmpty) }
        resetAll()
        state = .idle
    }

    private func resetAll() {
        estimator.reset()
        prev = nil
        dirValid = false
        dirX = 0; dirY = 0; dirZ = 0
        lastGoodFix = nil
        gpsTrend = 0
        launchStreakStart = nil
        launchStreakDir = nil
        recentAccel.removeAll()
        lastValidSpeedFixT = nil
        clearRun()
        trace.removeAll()
        speedMS = 0
        accelG = 0
        gpsHorizontalAccuracy = nil
        runStartDate = nil
    }

    private func clearRun() {
        runActive = false
        standingStart = false
        zeroTime = nil
        launchDistanceBase = 0
        peakV = 0
        peakA = 0
        decliningSince = nil
        runAccuracies = []
        runPeakGPSSpeed = 0
        pendingSpeedMarks = []
        crossedSpeed = []
        pendingDistanceMarks = []
        crossedDistance = []
        altSamples = []
        routePoints = []
        liveSpeedCrossings = []
        liveDistanceCrossings = []
        liveStandingStart = false
        runStartDate = nil
    }

    // MARK: Input — accelerometer (≈100 Hz)

    func ingest(accel: AccelTick) {
        guard state != .idle else { return }
        accelSeen = true
        motionActive = true
        lastAccelTick = accel

        updateDirection(with: accel)
        detectLaunch(accel: accel)

        // Until the travel direction is learned the accelerometer carries no
        // longitudinal information. Feeding zero-accel ticks would turn the
        // estimate into a staircase (flat between fixes, jump at each fix) and
        // compress mark-crossing times into the jumps — so stay GPS-only
        // (fix-to-fix interpolation) and let the filter switch to 100 Hz
        // fusion the moment direction is known.
        guard dirValid else { return }
        let raw = accel.hx * dirX + accel.hy * dirY + accel.hz * dirZ
        let aLong = min(Self.maxCarAccel, max(-Self.maxCarAccel, raw))
        if let s = estimator.predict(to: accel.t, aLong: aLong) {
            process(sample: s)
        }
    }

    // MARK: Input — GPS (≈1 Hz)

    func ingest(fix rawFix: SpeedFix) {
        guard state != .idle else { return }

        var fix = rawFix
        gpsHorizontalAccuracy = fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil
        gpsSpeedAccuracy = fix.speedAccuracy >= 0 ? fix.speedAccuracy : nil

        // Stationary iPhones often report an invalid Doppler speed (-1).
        // If the position fix itself is good and we are plausibly at rest,
        // substitute a soft zero so the filter can initialize / stay ready.
        if (fix.speed < 0 || fix.speedAccuracy < 0),
           fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxHorizontalAccuracy,
           !runActive, (!estimator.isInitialized || estimator.v < 1.5) {
            fix.speed = 0
            fix.speedAccuracy = 2.0
        }

        guard fix.isValid, fix.horizontalAccuracy <= maxHorizontalAccuracy else {
            if state == .ready && !runActive { state = .waitingForGPS }
            return
        }

        if state == .waitingForGPS { state = .ready }

        // GPS acceleration trend, used to gate direction learning.
        if let last = lastGoodFix, fix.t > last.t {
            gpsTrend = (fix.speed - last.speed) / (fix.t - last.t)
        }
        lastGoodFix = fix

        if fix.latitude.isFinite, fix.longitude.isFinite {
            lastCoordinate = (fix.latitude, fix.longitude)
        }
        lastValidSpeedFixT = fix.t
        if runActive {
            runAccuracies.append(fix.horizontalAccuracy)
            runPeakGPSSpeed = max(runPeakGPSSpeed, fix.speed)
            if fix.altitude.isFinite, fix.verticalAccuracy > 0, fix.verticalAccuracy < 15 {
                altSamples.append((estimator.distance - launchDistanceBase, fix.altitude))
            }
            if fix.latitude.isFinite, fix.longitude.isFinite {
                routePoints.append(RoutePoint(t: fix.t - runStart,
                                              lat: fix.latitude,
                                              lon: fix.longitude,
                                              v: estimator.v))
            }
        }

        // Advance to fix time with current accel, then correct.
        let aLong: Double? = (dirValid && accelSeen)
            ? lastAccelTick.map {
                let raw = $0.hx * dirX + $0.hy * dirY + $0.hz * dirZ
                return min(Self.maxCarAccel, max(-Self.maxCarAccel, raw))
            }
            : nil
        estimator.predict(to: fix.t, aLong: aLong)
        if let s = estimator.update(fix: fix, hasAccel: dirValid && accelSeen) {
            // The estimate has run far above what GPS measures: the
            // accelerometer was integrating something that isn't driving.
            // Throw the run away and re-anchor on GPS.
            if estimator.lastInnovation < -Self.maxSpeedDivergence {
                abortRun()
                estimator.snap(to: fix.speed, at: fix.t)
                dirValid = false
                prev = nil
                trace.removeAll()
                return
            }
            // GPS-only launch fallback (no accelerometer, e.g. simulator):
            // back-extrapolate the first moving fixes to v = 0.
            if !accelSeen, !runActive, state == .ready,
               let p = prev, p.v < 0.7, s.v > 1.0, s.t > p.t {
                let a = (s.v - p.v) / (s.t - p.t)
                let t0 = a > 0.1 ? max(p.t, s.t - s.v / a) : p.t
                beginRun(standing: true, launchTime: t0, fromSpeed: 0.3)
            }
            process(sample: s)
        }
    }

    // MARK: Direction of travel (device frame)

    private func updateDirection(with accel: AccelTick) {
        let mag = accel.magnitude
        guard mag > 0.8 else { return }
        // Learn direction only while a *fresh* GPS trend confirms the car is
        // speeding up, so the vector points forward by construction.
        guard gpsTrend > 0.4, let fixT = lastGoodFix?.t, accel.t - fixT < 1.4 else { return }
        let nx = accel.hx / mag, ny = accel.hy / mag, nz = accel.hz / mag
        if !dirValid {
            guard gpsTrend > 0.6 else { return }
            dirX = nx; dirY = ny; dirZ = nz
            dirValid = true
        } else {
            // Never flip the axis: braking with a stale positive trend must
            // not rotate "forward" backwards. Only refine within the same
            // hemisphere (slow mount drift).
            guard nx * dirX + ny * dirY + nz * dirZ > 0.2 else { return }
            let alpha = 0.05
            dirX += alpha * (nx - dirX)
            dirY += alpha * (ny - dirY)
            dirZ += alpha * (nz - dirZ)
            let n = (dirX * dirX + dirY * dirY + dirZ * dirZ).squareRoot()
            if n > 0.01 { dirX /= n; dirY /= n; dirZ /= n }
        }
    }

    // MARK: Launch detection (standing start, accelerometer edge)

    private func detectLaunch(accel: AccelTick) {
        guard state == .ready, !runActive else { return }
        guard estimator.isInitialized, estimator.v < 1.0 else {
            launchStreakStart = nil
            return
        }
        recentAccel.append(accel)
        if recentAccel.count > 100 { recentAccel.removeFirst(recentAccel.count - 100) }

        let mag = accel.magnitude
        // A launch pushes the phone one way and keeps pushing. Shaking
        // reverses direction every few ticks, so require the whole streak to
        // stay within a cone around its first tick.
        if let dir = launchStreakDir, mag > 0.01 {
            let cosine = (accel.hx * dir.x + accel.hy * dir.y + accel.hz * dir.z) / mag
            if cosine < 0.5 {
                launchStreakStart = nil
                launchStreakDir = nil
            }
        }

        if mag > 1.2 {
            if launchStreakDir == nil {
                launchStreakDir = (accel.hx / mag, accel.hy / mag, accel.hz / mag)
            }
            if let start = launchStreakStart {
                // 0.3 s of consistent push: long enough that hand movement
                // rarely survives, and free of accuracy cost because the run
                // is timestamped back to the start of the streak.
                if accel.t - start >= 0.3 {
                    // Launch confirmed; direction = launch acceleration vector.
                    let mag = accel.magnitude
                    dirX = accel.hx / mag; dirY = accel.hy / mag; dirZ = accel.hz / mag
                    dirValid = true
                    beginRun(standing: true, launchTime: start, fromSpeed: 0)
                    // Replay the confirmation window through the normal
                    // pipeline. The filter sat at v = 0 while the travel
                    // direction was unknown; replaying it here means the
                    // rollout line, 60 ft and the first speed marks are
                    // interpolated at their true times instead of being
                    // stamped at the moment the launch was confirmed.
                    estimator.seedAfterLaunch(v: 0, distance: 0, at: start)
                    prev = nil
                    for tick in recentAccel where tick.t > start {
                        let raw = tick.hx * dirX + tick.hy * dirY + tick.hz * dirZ
                        let a = min(Self.maxCarAccel, max(-Self.maxCarAccel, raw))
                        if let s = estimator.predict(to: tick.t, aLong: a) {
                            process(sample: s)
                        }
                    }
                    launchStreakStart = nil
                    launchStreakDir = nil
                    recentAccel.removeAll()
                }
            } else {
                launchStreakStart = accel.t
            }
        } else {
            launchStreakStart = nil
            launchStreakDir = nil
        }
    }

    // MARK: Run lifecycle

    private func beginRun(standing: Bool, launchTime: TimeInterval, fromSpeed: Double) {
        runActive = true
        standingStart = standing
        liveStandingStart = standing
        runStart = launchTime
        runStartDate = Date(timeIntervalSince1970: launchTime)
        peakV = estimator.v
        peakA = 0
        decliningSince = nil
        runPeakGPSSpeed = lastGoodFix?.speed ?? 0

        pendingSpeedMarks = cachedMarks.filter { $0 > fromSpeed + 0.001 }
        crossedSpeed = []
        crossedDistance = []
        liveSpeedCrossings = []
        liveDistanceCrossings = []

        if standing {
            estimator.resetDistance()
            launchDistanceBase = 0
            pendingDistanceMarks = DistanceMark.standard.map(\.meters)
            zeroTime = rolloutEnabled ? nil : launchTime // nil → set at rollout line
        } else {
            launchDistanceBase = estimator.distance
            pendingDistanceMarks = []
            zeroTime = launchTime
        }
        state = .running
    }

    private func finishRun(aborted: Bool = false) {
        defer {
            clearRun()
            if state == .running { state = hasGoodFix ? .ready : .waitingForGPS }
        }
        guard runActive, !aborted else { return }

        // GPS is the independent witness. If Doppler speed never corroborated
        // the fused estimate, the run was driven by the accelerometer alone
        // (shaking, a knock, a dropped phone) and must not be saved.
        if peakV > 5, runPeakGPSSpeed < max(2.0, 0.5 * peakV) { return }

        // A run that cannot resolve a single interval is noise — drop it.
        // Rolling runs need ≥ 2 speed crossings; standing runs have t0, so
        // one crossing (or any distance mark) is enough.
        if standingStart {
            guard !(crossedSpeed.isEmpty && crossedDistance.isEmpty) else { return }
        } else {
            guard crossedSpeed.count >= 2 else { return }
        }

        let sortedAcc = runAccuracies.sorted()
        let medianAcc = sortedAcc.isEmpty ? (gpsHorizontalAccuracy ?? 0) : sortedAcc[sortedAcc.count / 2]

        // GPS altitude + track slope over the run (barometer refines this later).
        var conditions = RunConditions()
        conditions.altitudeM = altSamples.first?.alt
        if let a = altSamples.first, let b = altSamples.last, b.d - a.d > 100 {
            let slope = (b.alt - a.alt) / (b.d - a.d) * 100
            if abs(slope) < 20 { conditions.slopePercent = slope }
        }

        // Decimate the trace to ~10 Hz relative to run start.
        var curve: [CurvePoint] = []
        var lastT = -Double.greatestFiniteMagnitude
        for s in trace where s.t >= runStart - 1.5 {
            if s.t - lastT >= 0.1 {
                curve.append(CurvePoint(t: s.t - runStart, v: s.v, d: max(0, s.d - launchDistanceBase)))
                lastT = s.t
            }
        }

        let result = RunResult(
            date: Date(timeIntervalSince1970: runStart),
            standingStart: standingStart,
            rolloutApplied: standingStart && rolloutEnabled,
            speedCrossings: crossedSpeed.sorted { $0.ms < $1.ms },
            distanceCrossings: crossedDistance.sorted { $0.meters < $1.meters },
            curve: curve,
            peakAccelG: peakA / 9.80665,
            peakSpeedMS: peakV,
            gpsAccuracy: medianAcc,
            usedMotion: accelSeen,
            conditions: conditions,
            route: routePoints.count >= 3 ? routePoints : nil
        )
        lastResult = result
        onRunFinished?(result)
    }

    /// Discard the current run without saving it.
    private func abortRun() {
        guard runActive else { return }
        clearRun()
        state = hasGoodFix ? .ready : .waitingForGPS
    }

    /// User-initiated stop while running.
    func stopRun() {
        guard runActive else { return }
        finishRun()
    }

    // MARK: Per-sample processing

    private func process(sample s: FusedSample) {
        defer { prev = s }

        // Trace ring: keep 3 s pre-run, everything (decimated to 50 Hz) in-run.
        if s.t - lastTraceT >= 0.02 {
            trace.append(s)
            lastTraceT = s.t
            if !runActive {
                let cutoff = s.t - 3
                if trace.first.map({ $0.t < cutoff - 2 }) == true {
                    trace.removeAll { $0.t < cutoff }
                }
            }
        }

        pushUI(sample: s)

        guard let p = prev, s.t > p.t else { return }

        // Rolling-start begin: speed crossing any pending mark upward while
        // not in a run (armed at 90, floor it → run starts crossing 100).
        // Gate on real acceleration: fused accel when motion is fused,
        // otherwise a strong GPS trend (~2σ of cruise noise) — occasional
        // false starts are dropped in finishRun (< 2 crossings).
        if !runActive, state == .ready, estimator.isInitialized {
            if let mark = cachedMarks.first(where: { p.v < $0 && s.v >= $0 }),
               (motionActive && dirValid) ? (s.a > 0.5) : (gpsTrend > 0.8) {
                let tCross = interpolateT(p: p, s: s, value: mark, keyPath: \.v)
                // Pending marks start above p.v, so this step's own crossings
                // (incl. `mark` itself at t = 0) are recorded by the mark loop
                // below, even when one GPS jump spans several marks.
                beginRun(standing: false, launchTime: tCross, fromSpeed: p.v)
                // The gate (accel trend) can open a beat after the pull began:
                // backfill marks already crossed during the current rise from
                // the trace, with negative times relative to run start.
                backfillCrossings(below: mark)
                liveSpeedCrossings = crossedSpeed
            }
        }

        guard runActive else { return }

        peakV = max(peakV, s.v)
        peakA = max(peakA, s.a)

        // Rollout line: distance-time zero starts 1 ft after launch.
        if standingStart, zeroTime == nil {
            let d = s.d - launchDistanceBase
            if d >= 0.3048 {
                let pd = p.d - launchDistanceBase
                zeroTime = interpolateT(p: p, s: s, value: launchDistanceBase + 0.3048, keyPath: \.d)
                _ = pd
            }
        }

        // Speed mark crossings. A GPS correction can jump the estimate past a
        // mark within one tick — interpolateT clamps that crossing to p.t.
        while let mark = pendingSpeedMarks.first, s.v >= mark {
            pendingSpeedMarks.removeFirst()
            let tCross = interpolateT(p: p, s: s, value: mark, keyPath: \.v)
            let base = (standingStart ? (zeroTime ?? runStart) : runStart)
            crossedSpeed.append(SpeedCrossing(ms: mark, t: tCross - base))
        }
        if crossedSpeed.count != liveSpeedCrossings.count { liveSpeedCrossings = crossedSpeed }

        // Distance mark crossings (standing starts only).
        if standingStart, let t0 = zeroTime ?? (rolloutEnabled ? nil : runStart) {
            let d = s.d - launchDistanceBase
            while let mark = pendingDistanceMarks.first, d >= mark {
                pendingDistanceMarks.removeFirst()
                let tCross = interpolateT(p: p, s: s, value: launchDistanceBase + mark, keyPath: \.d)
                let vAtLine = interpolateV(p: p, s: s, at: tCross)
                let trap = trapSpeed(beforeDistance: launchDistanceBase + mark)
                crossedDistance.append(DistanceCrossing(
                    meters: mark, t: tCross - t0, speedMS: vAtLine, trapSpeedMS: trap))
            }
            if crossedDistance.count != liveDistanceCrossings.count { liveDistanceCrossings = crossedDistance }
        }

        // End of run: speed clearly dropping, or stopped, or timed out.
        // Grace: with a distance mark close ahead (lifted just before the
        // 1/4-mile line), tolerate a bigger drop so the line still counts.
        var declineLimit = 2.0
        if standingStart, let next = pendingDistanceMarks.first,
           next - (s.d - launchDistanceBase) < 100 {
            declineLimit = 6.0
        }
        if s.v < peakV - declineLimit {
            finishRun()
        } else if s.v < peakV - 0.6 {
            if let since = decliningSince {
                if s.t - since > 3 { finishRun() }
            } else {
                decliningSince = s.t
            }
        } else {
            decliningSince = nil
        }
        // No usable GPS speed for a while: nothing can vouch for the estimate.
        if runActive, let fixT = lastValidSpeedFixT,
           s.t - fixT > Self.maxUncorroboratedRun {
            abortRun()
            return
        }
        if runActive, s.t - runStart > 300 { finishRun() }
        if runActive, standingStart, s.v < 0.3, s.t - runStart > 5 { finishRun() }
    }

    // MARK: Helpers

    /// On a rolling-run start, timestamp marks that were already crossed
    /// during the current monotonic rise (before the start gate opened).
    /// Their times are negative, relative to run start.
    private func backfillCrossings(below startMark: Double) {
        guard trace.count > 1 else { return }
        // Walk back to the start of the rise (small tolerance for jitter).
        var i = trace.count - 1
        let cutoff = trace[i].t - 4
        while i > 0, trace[i - 1].t >= cutoff, trace[i - 1].v <= trace[i].v + 0.05 {
            i -= 1
        }
        let vFloor = trace[i].v
        let marks = cachedMarks.filter { $0 > vFloor + 0.01 && $0 < startMark - 0.001 }
        guard !marks.isEmpty else { return }
        for m in marks {
            var t: TimeInterval?
            for j in (i + 1)..<trace.count {
                let a = trace[j - 1], b = trace[j]
                if a.v < m, b.v >= m {
                    t = interpolateT(p: a, s: b, value: m, keyPath: \.v)
                }
            }
            if let t {
                crossedSpeed.append(SpeedCrossing(ms: m, t: t - runStart))
                pendingSpeedMarks.removeAll { abs($0 - m) < 0.001 }
            }
        }
        crossedSpeed.sort { $0.ms < $1.ms }
    }

    private func interpolateT(p: FusedSample, s: FusedSample, value: Double, keyPath: KeyPath<FusedSample, Double>) -> TimeInterval {
        let a = p[keyPath: keyPath], b = s[keyPath: keyPath]
        guard b > a else { return s.t }
        let f = ((value - a) / (b - a)).clamped01
        return p.t + f * (s.t - p.t)
    }

    private func interpolateV(p: FusedSample, s: FusedSample, at t: TimeInterval) -> Double {
        guard s.t > p.t else { return s.v }
        let f = ((t - p.t) / (s.t - p.t)).clamped01
        return p.v + f * (s.v - p.v)
    }

    /// Average speed over the 66 ft (20.1168 m) before `lineD` — drag trap speed.
    private func trapSpeed(beforeDistance lineD: Double) -> Double {
        let startD = lineD - 20.1168
        var t0: TimeInterval?
        var t1: TimeInterval?
        var last: FusedSample?
        for s in trace {
            if let l = last {
                if t0 == nil, l.d < startD, s.d >= startD {
                    t0 = interpolateT(p: l, s: s, value: startD, keyPath: \.d)
                }
                if t1 == nil, l.d < lineD, s.d >= lineD {
                    t1 = interpolateT(p: l, s: s, value: lineD, keyPath: \.d)
                }
            }
            last = s
        }
        if let t0, let t1, t1 > t0 { return 20.1168 / (t1 - t0) }
        return estimator.v
    }

    private func pushUI(sample s: FusedSample) {
        // Throttle observable churn to ~15 Hz.
        guard s.t - lastUIPush >= 0.066 else { return }
        lastUIPush = s.t
        speedMS = s.v
        accelG = s.a / 9.80665
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
