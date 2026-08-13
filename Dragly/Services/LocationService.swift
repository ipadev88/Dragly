//
//  LocationService.swift
//  Dragly
//
//  CLLocationManager wrapper: Doppler speed fixes → SpeedFix for the engine.
//

import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored var onFix: ((SpeedFix) -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isUpdating = false


    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        requestPermission()
        guard !isUpdating else { return }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stop() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    // MARK: CLLocationManagerDelegate (main run loop — manager created on main)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isUpdating,
           authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            // Discard stale fixes (backlogged after the app was suspended).
            guard Date().timeIntervalSince(loc.timestamp) < 3 else { continue }
            onFix?(SpeedFix(
                t: loc.timestamp.timeIntervalSince1970,
                speed: loc.speed,
                speedAccuracy: loc.speedAccuracy,
                horizontalAccuracy: loc.horizontalAccuracy,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                altitude: loc.verticalAccuracy > 0 ? loc.altitude : .nan,
                verticalAccuracy: loc.verticalAccuracy))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient (kCLErrorLocationUnknown etc.) — the engine's fix gating
        // already degrades gracefully; nothing to do.
    }
}
