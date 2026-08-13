//
//  RouteMapView.swift
//  Dragly
//
//  The run's GPS track drawn on Apple Maps: a glow-backed accent line with
//  start and finish markers, framed to the track.
//

import SwiftUI
import MapKit

struct RouteMapView: View {
    let route: [RoutePoint]
    let unit: SpeedUnit
    let accent: Color

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Map rect covering the track, padded so the line never touches the edge.
    private var framing: MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for c in coordinates.dropFirst() {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        // A dead-straight run has zero height or width — give it something to show.
        let minSide = max(rect.size.width, rect.size.height, 200) * 0.35
        return .rect(rect.insetBy(dx: -max(minSide, rect.size.width * 0.2),
                                  dy: -max(minSide, rect.size.height * 0.2)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Route")
                    .font(.caption())
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Text(verbatim: distanceText)
                    .font(.figure(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Map(initialPosition: framing, interactionModes: [.pan, .zoom]) {
                // Wide translucent pass under the line reads as a glow and
                // keeps the track visible over busy map tiles.
                MapPolyline(coordinates: coordinates)
                    .stroke(accent.opacity(0.28),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: coordinates)
                    .stroke(accent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                if let start = coordinates.first {
                    Annotation("", coordinate: start) {
                        marker(fill: Theme.panel, ring: accent)
                    }
                }
                if let finish = coordinates.last {
                    Annotation("", coordinate: finish) {
                        marker(fill: accent, ring: accent, icon: "flag.checkered")
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .panel()
    }

    private func marker(fill: Color, ring: Color, icon: String? = nil) -> some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(ring, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.black)
            }
        }
    }

    private var distanceText: String {
        var meters = 0.0
        for i in 1..<max(1, route.count) {
            let a = CLLocation(latitude: route[i - 1].lat, longitude: route[i - 1].lon)
            let b = CLLocation(latitude: route[i].lat, longitude: route[i].lon)
            meters += b.distance(from: a)
        }
        switch unit {
        case .kmh:
            return meters < 1000
                ? "\(Int(meters.rounded())) m"
                : String(format: "%.2f km", meters / 1000)
        case .mph:
            let miles = meters / 1609.344
            return miles < 0.2
                ? "\(Int((meters / 0.3048).rounded())) ft"
                : String(format: "%.2f mi", miles)
        }
    }
}
