//
//  RunTypes.swift
//  Dragly
//
//  Data types shared by the measurement engine, persistence and UI.
//  Pure Foundation — unit-testable off-device.
//

import Foundation

nonisolated enum SpeedUnit: String, Codable, CaseIterable, Identifiable {
    case kmh
    case mph

    var id: String { rawValue }

    /// m/s → display units
    func convert(_ ms: Double) -> Double {
        switch self {
        case .kmh: ms * 3.6
        case .mph: ms * 2.23693629
        }
    }

    /// display units → m/s
    func toMS(_ value: Double) -> Double {
        switch self {
        case .kmh: value / 3.6
        case .mph: value / 2.23693629
        }
    }
}

// MARK: - Milestones

/// A speed value the engine timestamps when crossed upward during a run.
/// Internally always m/s; `unit` only matters for display.
nonisolated struct SpeedMark: Hashable, Codable {
    var ms: Double

    static func kmh(_ v: Double) -> SpeedMark { SpeedMark(ms: v / 3.6) }
    static func mph(_ v: Double) -> SpeedMark { SpeedMark(ms: v / 2.23693629) }
}

/// A distance value (from launch) the engine timestamps when crossed.
nonisolated struct DistanceMark: Hashable, Codable {
    var meters: Double

    static let sixtyFeet = DistanceMark(meters: 18.288)
    static let hundredMeters = DistanceMark(meters: 100)
    static let eighthMile = DistanceMark(meters: 201.168)
    static let quarterMile = DistanceMark(meters: 402.336)
    static let halfMile = DistanceMark(meters: 804.672)
    static let kilometer = DistanceMark(meters: 1000)

    static let standard: [DistanceMark] = [
        .sixtyFeet, .hundredMeters, .eighthMile, .quarterMile, .halfMile, .kilometer,
    ]
}

// MARK: - Recorded crossings

nonisolated struct SpeedCrossing: Codable, Hashable {
    /// Speed mark, m/s.
    var ms: Double
    /// Seconds since run start (launch for standing, first mark for rolling).
    var t: TimeInterval
}

nonisolated struct DistanceCrossing: Codable, Hashable {
    var meters: Double
    /// Seconds since effective zero (launch + optional 1-ft rollout).
    var t: TimeInterval
    /// Speed at the line, m/s.
    var speedMS: Double
    /// Drag-strip style trap speed: average over the last 20.1 m (66 ft), m/s.
    var trapSpeedMS: Double
}

// MARK: - Segments (display units of measure)

/// A speed interval like 100–200 km/h, resolved from crossings.
nonisolated struct SpeedSegment: Codable, Hashable, Identifiable {
    /// Lower/upper bounds in m/s. from == 0 means "from standstill".
    var fromMS: Double
    var toMS: Double
    /// Elapsed time, seconds.
    var time: TimeInterval
    /// Unit the segment is naturally expressed in (for naming: 60–130 mph).
    var unit: SpeedUnit

    var id: String { "\(fromMS)-\(toMS)-\(unit.rawValue)" }

    var title: String {
        let f = Int(unit.convert(fromMS).rounded())
        let t = Int(unit.convert(toMS).rounded())
        let u = String(localized: unit == .kmh ? "km/h" : "mph")
        return "\(f)–\(t) \(u)"
    }
}

nonisolated struct DistanceSegment: Codable, Hashable, Identifiable {
    var meters: Double
    var time: TimeInterval
    var speedMS: Double
    var trapSpeedMS: Double

    var id: String { "d\(meters)" }

    var title: String {
        switch meters {
        case DistanceMark.sixtyFeet.meters: "60 ft"
        case DistanceMark.hundredMeters.meters: "100 m"
        case DistanceMark.eighthMile.meters: "1/8 mi"
        case DistanceMark.quarterMile.meters: "1/4 mi"
        case DistanceMark.halfMile.meters: "1/2 mi"
        case DistanceMark.kilometer.meters: "1 km"
        default: meters < 1000
            ? "\(Int(meters.rounded())) m"
            : String(format: "%.1f km", meters / 1000)
        }
    }
}

// MARK: - Curve

/// Downsampled speed/distance trace for charts.
nonisolated struct CurvePoint: Codable, Hashable {
    /// Seconds since run start.
    var t: TimeInterval
    /// m/s
    var v: Double
    /// meters since launch (0 for rolling runs until launch semantics apply).
    var d: Double
}

/// One recorded position along a run, for the route map.
nonisolated struct RoutePoint: Codable, Hashable {
    /// Seconds since run start.
    var t: TimeInterval
    var lat: Double
    var lon: Double
    /// Fused speed at this point, m/s.
    var v: Double
}

// MARK: - Run result

/// Ambient conditions captured around a run. Every field is optional —
/// filled in only when the corresponding sensor/service was available.
nonisolated struct RunConditions: Codable, Hashable {
    /// Air temperature, °C (weather service at run location).
    var tempC: Double?
    /// GPS altitude, m.
    var altitudeM: Double?
    /// Barometric pressure, hPa.
    var pressureHPa: Double?
    /// Density altitude, m (pressure + temperature).
    var densityAltitudeM: Double?
    /// Track slope over the run, % (negative = downhill).
    var slopePercent: Double?

    var isEmpty: Bool {
        tempC == nil && altitudeM == nil && pressureHPa == nil
            && densityAltitudeM == nil && slopePercent == nil
    }
}

nonisolated struct RunResult: Codable, Hashable {
    var date: Date
    var standingStart: Bool
    var rolloutApplied: Bool
    /// Raw upward speed crossings (seconds from run start) — lets the UI
    /// resolve any interval, not just preset ones.
    var speedCrossings: [SpeedCrossing]
    var distanceCrossings: [DistanceCrossing]
    /// Curve at ~10 Hz.
    var curve: [CurvePoint]
    /// Peak longitudinal acceleration, g.
    var peakAccelG: Double
    /// Top fused speed reached, m/s.
    var peakSpeedMS: Double
    /// Median GPS horizontal accuracy during the run, m.
    var gpsAccuracy: Double
    /// Whether accelerometer fusion was active (false = GPS-only).
    var usedMotion: Bool
    /// Ambient conditions (filled by the app layer after the run).
    var conditions: RunConditions? = nil
    /// GPS track of the run (≈1 Hz). Optional so runs saved before route
    /// recording existed still decode.
    var route: [RoutePoint]? = nil

    // MARK: Segment resolution

    /// Time from `fromMS` to `toMS`, if both were crossed (from 0 = from launch).
    func time(fromMS: Double, toMS: Double) -> TimeInterval? {
        guard toMS > fromMS else { return nil }
        guard let end = crossingTime(toMS) else { return nil }
        if fromMS <= 0.01 {
            guard standingStart else { return nil }
            return end
        }
        guard let start = crossingTime(fromMS) else { return nil }
        return end - start
    }

    func crossingTime(_ ms: Double) -> TimeInterval? {
        speedCrossings.first { abs($0.ms - ms) < 0.01 }?.t
    }

    /// Resolve all displayable speed segments given the mark grid actually crossed.
    func speedSegments(unit: SpeedUnit, extraPairs: [(Double, Double, SpeedUnit)] = []) -> [SpeedSegment] {
        var pairs: [(Double, Double, SpeedUnit)] = []
        let grid: [Double]
        let stepUnit: SpeedUnit = unit
        switch unit {
        case .kmh: grid = stride(from: 50.0, through: 400.0, by: 50.0).map { $0 / 3.6 }
        case .mph: grid = stride(from: 30.0, through: 250.0, by: 30.0).map { $0 / 2.23693629 }
        }
        // From-zero segments (standing starts).
        if standingStart {
            let zeroTargets: [Double] = unit == .kmh
                ? [60, 100, 150, 200, 250, 300].map { $0 / 3.6 }
                : [30, 60, 100, 130, 150, 180].map { $0 / 2.23693629 }
            for t in zeroTargets { pairs.append((0, t, stepUnit)) }
        }
        // Rolling ladder: consecutive and skip-one grid pairs (100–150, 100–200, 150–200, 200–250, …).
        for i in grid.indices {
            for j in (i + 1)..<min(i + 3, grid.count) {
                pairs.append((grid[i], grid[j], stepUnit))
            }
        }
        // Fine ladder from each anchor: floor it at 190 and every 200–210,
        // 200–220 … 200–240 shows up too (the +50 pair is covered above).
        let (anchorStep, fineStep, fineCount): (Double, Double, Int) =
            unit == .kmh ? (50, 10, 4) : (30, 10, 2)
        let anchorMax = unit == .kmh ? 400.0 : 250.0
        var anchor = anchorStep
        while anchor <= anchorMax {
            for k in 1...fineCount {
                pairs.append((unit.toMS(anchor), unit.toMS(anchor + fineStep * Double(k)), unit))
            }
            anchor += anchorStep
        }
        // Classics.
        pairs.append((SpeedMark.mph(60).ms, SpeedMark.mph(130).ms, .mph))
        pairs.append(contentsOf: extraPairs)

        var seen = Set<String>()
        var out: [SpeedSegment] = []
        for (f, t, u) in pairs {
            guard let dt = time(fromMS: f, toMS: t) else { continue }
            let seg = SpeedSegment(fromMS: f, toMS: t, time: dt, unit: u)
            if seen.insert(seg.id).inserted { out.append(seg) }
        }
        out.sort { a, b in
            if a.fromMS != b.fromMS { return a.fromMS < b.fromMS }
            return a.toMS < b.toMS
        }
        return out
    }

    var distanceSegments: [DistanceSegment] {
        distanceCrossings
            .sorted { $0.meters < $1.meters }
            .map { DistanceSegment(meters: $0.meters, time: $0.t, speedMS: $0.speedMS, trapSpeedMS: $0.trapSpeedMS) }
    }
}
