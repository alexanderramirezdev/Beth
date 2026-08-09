//
//  LocationTool.swift
//  Beth
//
//  WHERE AM I.
//
//  The static line in BethBrain's instructions works and costs
//  nothing, but it is a hardcoded fact. It is wrong the moment you
//  drive to Santa Fe, and it stays wrong until you edit the source.
//
//  This asks the device instead. Same Tool pattern as WeatherTool:
//  the model decides it needs a location, calls this, ordinary Swift
//  goes and finds out.
//
//  Worth noticing that the two tools compose. Ask "do I need a jacket"
//  and the model has to call getCurrentLocation, take the city name
//  back, then call getWeather with it. Two dependent tool calls to
//  answer one casual question. That chaining is where small models
//  start to struggle, so it is a good thing to watch fail.
//
//  SETUP REQUIRED, two steps:
//
//  1. Info tab -> add `Privacy - Location When In Use Usage Description`
//     with a value like "Beth uses your location for weather and
//     nearby places." Missing this crashes the app on first request.
//
//  2. Signing and Capabilities -> App Sandbox -> check `Location`.
//     Without it the request silently returns nothing.
//

import Foundation
import FoundationModels
import CoreLocation

struct LocationTool: Tool {

    let name = "getCurrentLocation"
    let description = """
    Get the user's current city and state. Use this whenever the user \
    asks about weather, nearby places, or anything location dependent \
    without naming a specific place. Call this first, then use the city \
    it returns for any follow-up lookup.
    """

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let place = try await LocationProvider.shared.currentPlace()
        return "The user is currently in \(place)."
    }
}

/// Wraps CoreLocation's delegate-based API in async/await.
///
/// CoreLocation predates Swift concurrency, so it still reports results
/// by calling delegate methods. `withCheckedThrowingContinuation` is the
/// standard bridge: it hands you a continuation, you stash it, and you
/// resume it once from whichever delegate callback fires.
///
/// Resuming a continuation twice is a crash, which is why the stored
/// property is cleared the moment it is used.
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<String, Error>?

    /// Cached so repeated questions in one session do not re-trigger
    /// a GPS fix, which is slow and drains battery.
    private var cachedPlace: String?
    private var cachedAt: Date?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentPlace() async throws -> String {
        // Reuse a fix from the last 10 minutes.
        if let cachedPlace, let cachedAt,
           Date().timeIntervalSince(cachedAt) < 600 {
            return cachedPlace
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // The delegate callback below requests the location
                // once the user answers the prompt.
            case .restricted, .denied:
                finish(.failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .restricted, .denied:
            finish(.failure(LocationError.denied))
        default:
            break // still waiting on the user
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            finish(.failure(LocationError.unavailable))
            return
        }

        // Coordinates are useless to a language model. Turn them into
        // a place name it can actually pass to the weather tool.
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }

            guard let placemark = placemarks?.first else {
                self.finish(.failure(LocationError.unavailable))
                return
            }

            let city = placemark.locality ?? placemark.subAdministrativeArea
            let region = placemark.administrativeArea

            let description = [city, region]
                .compactMap { $0 }
                .joined(separator: ", ")

            guard !description.isEmpty else {
                self.finish(.failure(LocationError.unavailable))
                return
            }

            self.cachedPlace = description
            self.cachedAt = Date()
            self.finish(.success(description))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        finish(.failure(error))
    }

    // MARK: - Continuation safety

    /// Resumes exactly once and clears the stored continuation.
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access was denied. Enable it in System Settings, Privacy and Security, Location Services."
            case .unavailable:
                return "Could not determine the current location."
            }
        }
    }
}
