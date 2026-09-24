import AppKit
import CoreLocation
import Observation

/// The forecast for where the Mac is, or for a chosen city, from Open-Meteo.
///
/// Open-Meteo is free and needs no key or account. Every request goes through
/// `BoundedHTTPClient`, limited to Open-Meteo's two hosts, and the location is rounded to about a
/// kilometre first (`OpenMeteo.forecastURL`). Nothing else is sent. It refreshes every half hour
/// while switched on, because weather does not change faster than that and the closed pill can
/// show it, so it cannot wait for the widget to be opened.
@Observable
@MainActor
final class WeatherService {
    enum Status: Equatable {
        case off
        case locating
        case loading
        case ready
        /// Current location is on and nobody has been asked yet.
        case needsLocationAccess
        /// Refused, restricted, or Location Services is off for the whole Mac.
        case locationUnavailable(String)
        /// Current location is off and no city has been chosen.
        case needsCity
        case failed(String)

        /// What to say about it, or nil when the forecast speaks for itself.
        var message: String? {
            switch self {
            case .off, .ready: return nil
            case .locating: return "Finding where you are…"
            case .loading: return "Loading the forecast…"
            case .needsLocationAccess: return "Allow MinNotch to use your location, or choose a city in Settings > Weather."
            case .locationUnavailable(let reason), .failed(let reason): return reason
            case .needsCity: return "Choose a city in Settings > Weather."
            }
        }
    }

    private(set) var report: WeatherReport?
    private(set) var status: Status = .off
    private(set) var searchResults: [WeatherPlace] = []
    private(set) var isSearching = false
    private(set) var locationAuthorization: CLAuthorizationStatus

    @ObservationIgnored private var settings: SettingsStore?
    /// The weather settings the last refresh was for. Every settings change in the app reaches
    /// `settingsChanged`, and only a change to these is a reason to ask the network again.
    @ObservationIgnored private var appliedSettings: WeatherSettings?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private let client = BoundedHTTPClient(
        maxBytes: 64 * 1024,
        allowedHosts: [OpenMeteo.forecastHost, OpenMeteo.geocodingHost]
    )
    @ObservationIgnored private let locator = WeatherLocator()
    /// Bumped per request, so a slow answer to an old one cannot replace a newer one.
    @ObservationIgnored private var generation = 0

    init() {
        locationAuthorization = locator.authorization
        locator.onAuthorizationChange = { [weak self] status in
            self?.locationAuthorization = status
            self?.refresh()
        }
    }

    // MARK: Lifecycle

    func start(settings: SettingsStore) {
        self.settings = settings
        settingsChanged()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func settingsChanged() {
        guard let settings else { return }
        let weather = settings.weather
        guard weather != appliedSettings else { return }
        appliedSettings = weather

        guard weather.enabled, FeatureFlag.weather.isEnabled else {
            stop()
            report = nil
            status = .off
            return
        }
        if refreshTimer == nil {
            refreshTimer = Timer.onMain(every: 30 * 60) { [weak self] in self?.refresh() }
        }
        refresh()
    }

    /// Asks for the forecast again, for wherever the settings say.
    func refresh() {
        guard let settings, settings.weather.enabled, FeatureFlag.weather.isEnabled else { return }
        let weather = settings.weather

        guard weather.useCurrentLocation else {
            guard let city = weather.cityCoordinate else {
                status = .needsCity
                return
            }
            fetch(latitude: city.latitude, longitude: city.longitude, placeName: weather.cityName)
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            status = .locationUnavailable("Location Services is off for this Mac. Turn it on in Privacy & Security, or choose a city in Settings > Weather.")
            return
        }
        switch locator.authorization {
        case .notDetermined:
            status = .needsLocationAccess
            return
        case .denied, .restricted:
            status = .locationUnavailable("MinNotch is not allowed to use your location. Allow it in Privacy & Security > Location Services, or choose a city in Settings > Weather.")
            return
        default:
            break
        }

        if report == nil { status = .locating }
        locator.requestLocation { [weak self] result in
            guard let self else { return }
            switch result {
            case .found(let latitude, let longitude, let placeName):
                self.fetch(latitude: latitude, longitude: longitude, placeName: placeName)
            case .failed(let message):
                if self.report == nil { self.status = .failed(message) }
            }
        }
    }

    /// Asks macOS for Location Services, from the foreground. Only in answer to the user.
    func requestLocationAccess() {
        locator.requestAuthorization()
    }

    private func fetch(latitude: Double, longitude: Double, placeName: String) {
        guard let settings else { return }
        let fahrenheit = settings.weather.units.usesFahrenheit
        guard let url = OpenMeteo.forecastURL(latitude: latitude, longitude: longitude, fahrenheit: fahrenheit) else { return }

        if report == nil { status = .loading }
        generation += 1
        let expected = generation
        client.fetch(url) { [weak self] data in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                guard let data, let report = OpenMeteo.report(from: data, placeName: placeName, fahrenheit: fahrenheit) else {
                    // A forecast already showing is kept; half an hour old is better than nothing.
                    if self.report == nil {
                        self.status = .failed("The forecast could not be loaded. MinNotch will try again in half an hour.")
                    }
                    return
                }
                self.report = report
                self.status = .ready
            }
        }
    }

    // MARK: City search

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let url = OpenMeteo.searchURL(for: trimmed) else {
            searchResults = []
            return
        }
        isSearching = true
        client.fetch(url) { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.isSearching = false
                self.searchResults = data.map(OpenMeteo.places(from:)) ?? []
            }
        }
    }

    /// Uses `place` from now on, instead of the Mac's location.
    func choose(_ place: WeatherPlace) {
        guard let settings else { return }
        settings.weather.cityName = place.name
        settings.weather.cityLatitude = place.latitude
        settings.weather.cityLongitude = place.longitude
        settings.weather.useCurrentLocation = false
        searchResults = []
    }

    #if DEBUG
    /// A fixed forecast for `--capture-notch --tab weather --sample-weather`.
    func applySample() {
        let now = Date()
        let hours = (0..<6).map { offset in
            WeatherReport.Hour(
                time: now.addingTimeInterval(Double(offset) * 3600),
                temperature: 17 - Double(offset) * 0.6,
                condition: WeatherCondition(code: [2, 2, 3, 61, 61, 3][offset])
            )
        }
        let days = [("Today", 18.0, 11.0, 2), ("Fri", 16.0, 10.0, 61), ("Sat", 14.0, 9.0, 80), ("Sun", 19.0, 12.0, 1), ("Mon", 21.0, 13.0, 0)]
            .map { WeatherReport.Day(label: $0.0, high: $0.1, low: $0.2, condition: WeatherCondition(code: $0.3)) }
        report = WeatherReport(
            placeName: "Toronto", temperature: 17, condition: WeatherCondition(code: 2), isDay: true,
            high: 18, low: 11, usesFahrenheit: false, hours: hours, days: days, fetchedAt: now
        )
        status = .ready
    }
    #endif
}

/// Where the Mac is, once, when asked.
///
/// Core Location calls its delegate on the run loop of the thread the manager was made on, and
/// this is made on main, so the callbacks assume the main actor honestly. The place name comes
/// from Apple's reverse geocoder, not from the weather service, so Open-Meteo only ever sees two
/// rounded numbers.
@MainActor
final class WeatherLocator: NSObject, CLLocationManagerDelegate {
    enum Result {
        case found(latitude: Double, longitude: Double, placeName: String)
        case failed(String)
    }

    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var waiting: [(Result) -> Void] = []
    private var isPrompting = false

    override init() {
        super.init()
        manager.delegate = self
        // A forecast is for a town, not a street.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else {
            onAuthorizationChange?(manager.authorizationStatus)
            return
        }
        // Shown only to the active app, like every other permission here.
        isPrompting = true
        ForegroundPrompt.begin()
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation(_ completion: @escaping (Result) -> Void) {
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        manager.requestLocation()
    }

    private func finish(_ result: Result) {
        let callbacks = waiting
        waiting.removeAll()
        callbacks.forEach { $0(result) }
    }

    private func located(latitude: Double, longitude: Double) {
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)) { [weak self] placemarks, _ in
            let name = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Current Location"
            Task { @MainActor in
                self?.finish(.found(latitude: latitude, longitude: longitude, placeName: name))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            if isPrompting, status != .notDetermined {
                isPrompting = false
                ForegroundPrompt.end()
            }
            onAuthorizationChange?(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        MainActor.assumeIsolated { located(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { finish(.failed("Your location could not be found. \(message)")) }
    }
}
