//
//  LocationProvider.swift
//  MeasureGo
//
//  GPS coordinates saved with each project — port of Unity's GPSLocation.cs
//  (start the service, keep the last fix, read it when saving a project).
//

import CoreLocation

final class LocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private(set) var lastLocation: CLLocation?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Asks for permission (first launch) and starts updates. Safe to call
    /// repeatedly — e.g. when the new-project flow opens.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            AppLog.log("Location not authorized: \(manager.authorizationStatus.rawValue)")
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Current coordinates for ProjectData, or zeros when unavailable —
    /// matching Unity, which saves 0,0 if the service isn't running.
    var currentCoordinates: ProjectData.Location {
        guard let coordinate = lastLocation?.coordinate else {
            return ProjectData.Location(latitude: 0, longitude: 0)
        }
        return ProjectData.Location(
            latitude: Float(coordinate.latitude),
            longitude: Float(coordinate.longitude)
        )
    }

    /// Reverse-geocodes the current fix into a postal address for the
    /// new-project form. Returns nil when there is no fix or no network.
    func reverseGeocodeCurrentAddress() async -> ProjectData.Address? {
        guard let location = lastLocation else { return nil }
        do {
            // Always geocode in English: the address is stored in the project
            // file and uploaded to the portal, so it must not come back in
            // whatever language the phone happens to be set to.
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location, preferredLocale: Locale(identifier: "en_US"))
            guard let place = placemarks.first else { return nil }

            var address = ProjectData.Address()
            // "123 Main St" — number + street when both are known.
            let street = [place.subThoroughfare, place.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            address.address1 = street.isEmpty ? (place.name ?? "") : street
            address.city = place.locality ?? place.subAdministrativeArea ?? ""
            address.state = place.administrativeArea ?? ""
            address.postalcode = place.postalCode ?? ""
            address.country = place.country ?? ""
            return address
        } catch {
            AppLog.log("Reverse geocode failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.log("Location error: \(error.localizedDescription)")
    }
}
