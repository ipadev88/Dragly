//
//  SimulatedDriveService.swift
//  Dragly
//
//  DEBUG-only synthetic drive: feeds the engine a realistic accelerating car
//  (noisy GPS at 1 Hz with fix latency + noisy biased accelerometer at 100 Hz)
//  so the whole flow can be demoed in the simulator without a car.
//

#if DEBUG
import Foundation

@Observable
final class SimulatedDriveService {

    @ObservationIgnored var onAccel: ((AccelTick) -> Void)?
    @ObservationIgnored var onFix: ((SpeedFix) -> Void)?

    private(set) var isRunning = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var simT = 0.0
    @ObservationIgnored private var base = 0.0
    @ObservationIgnored private var v = 0.0
    @ObservationIgnored private var rolling = false
    @ObservationIgnored private var braking = false
    @ObservationIgnored private var nextFix = 1.0
    @ObservationIgnored private var vHistory: [(t: Double, v: Double)] = []
    @ObservationIgnored private var dist = 0.0

    func start(rolling: Bool) {
        stop()
        self.rolling = rolling
        simT = 0
        base = Date().timeIntervalSince1970
        v = rolling ? 25.3 : 0 // ~91 km/h cruise or standstill
        braking = false
        nextFix = 1.0
        vHistory.removeAll()
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func tick() {
        simT += 0.01
        let idle = rolling ? 4.0 : 3.0
        let vTop = rolling ? 58.0 : 64.0 // ~209 / 230 km/h (past the 1/4-mile line)
        var a = 0.0
        if simT >= idle {
            if v >= vTop { braking = true }
            a = braking ? (v > 0 ? -6.0 : 0) : max(0.8, 8.2 - 0.055 * v)
        }
        v = max(0, v + a * 0.01)
        dist += v * 0.01
        vHistory.append((simT, v))
        if vHistory.count > 200 { vHistory.removeFirst(vHistory.count - 200) }

        // Accelerometer: bias + noise, forward = fixed device-frame direction.
        let aMeas = a + 0.15 + Double.random(in: -0.5...0.5) * 0.5
        let lat = Double.random(in: -0.3...0.3) * 0.5
        onAccel?(AccelTick(
            t: base + simT,
            hx: aMeas * 0.77 - lat * 0.64,
            hy: aMeas * 0.64 + lat * 0.77,
            hz: 0))

        // GPS at 1 Hz, timestamped 0.15 s in the past (delivery latency).
        if simT >= nextFix {
            nextFix += 1.0
            let tMeas = simT - 0.15
            let vMeas = max(0, (vHistory.last { $0.t <= tMeas }?.v ?? v)
                + Double.random(in: -0.6...0.6) * 0.4)
            onFix?(SpeedFix(
                t: base + tMeas,
                speed: vMeas,
                speedAccuracy: 0.5,
                horizontalAccuracy: 4.0,
                latitude: 55.751 + dist / 111_000,   // creeping north from Moscow
                longitude: 37.617,
                altitude: 152 - 0.004 * dist,        // −0.4 % grade demo
                verticalAccuracy: 6))
        }

        if braking && v <= 0.01 && simT > idle + 5 {
            // Let the engine see a couple of standstill fixes, then stop.
            if simT > nextFix + 2 { stop() }
        }
    }
}
#endif
