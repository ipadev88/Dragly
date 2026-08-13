//
//  MotionService.swift
//  Dragly
//
//  CMDeviceMotion at 100 Hz → gravity-free horizontal acceleration in the
//  device frame (AccelTick). The phone can sit in any orientation; the engine
//  learns the travel direction itself.
//

import Foundation
import CoreMotion

@Observable
final class MotionService {

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored var onTick: ((AccelTick) -> Void)?

    /// Offset converting CMDeviceMotion's since-boot clock to unix time.
    @ObservationIgnored private let bootEpoch =
        Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime

    private(set) var isAvailable = false
    private(set) var isRunning = false

    // Light low-pass on the horizontal vector (~8 Hz at 100 Hz sample rate)
    // to strip engine/road vibration without lagging real launches.
    @ObservationIgnored private var lpx = 0.0
    @ObservationIgnored private var lpy = 0.0
    @ObservationIgnored private var lpz = 0.0
    @ObservationIgnored private var lpPrimed = false

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        lpPrimed = false
        manager.deviceMotionUpdateInterval = 0.01
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.process(m)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    private func process(_ m: CMDeviceMotion) {
        let g = 9.80665
        // userAcceleration is gravity-free, in g's, device frame.
        let ax = m.userAcceleration.x * g
        let ay = m.userAcceleration.y * g
        let az = m.userAcceleration.z * g
        // Remove any residual component along gravity: horizontal = a − (a·ĝ)ĝ.
        let gx = m.gravity.x, gy = m.gravity.y, gz = m.gravity.z
        let gn = (gx * gx + gy * gy + gz * gz).squareRoot()
        var hx = ax, hy = ay, hz = az
        if gn > 0.5 {
            let ux = gx / gn, uy = gy / gn, uz = gz / gn
            let dot = ax * ux + ay * uy + az * uz
            hx -= dot * ux
            hy -= dot * uy
            hz -= dot * uz
        }
        let alpha = 0.35
        if lpPrimed {
            lpx += alpha * (hx - lpx)
            lpy += alpha * (hy - lpy)
            lpz += alpha * (hz - lpz)
        } else {
            lpx = hx; lpy = hy; lpz = hz
            lpPrimed = true
        }
        onTick?(AccelTick(t: bootEpoch + m.timestamp, hx: lpx, hy: lpy, hz: lpz))
    }
}
