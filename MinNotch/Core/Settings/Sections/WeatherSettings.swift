import Foundation

/// What the temperatures are shown in.
enum WeatherUnits: String, Codable, CaseIterable, Identifiable {
    /// Fahrenheit where the Mac's region measures in US units, Celsius everywhere else.
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    var usesFahrenheit: Bool {
        switch self {
        case .automatic: return Locale.current.measurementSystem == .us
        case .celsius: return false
        case .fahrenheit: return true
        }
    }
}

/// Settings > Weather.
///
/// Off by default, because it sends a location to a web service. The location is this Mac's,
/// through Location Services, unless a city has been chosen instead, which needs no permission.
struct WeatherSettings: Codable, Equatable {
    var enabled: Bool = false
    var useCurrentLocation: Bool = true
    /// The chosen city, as the search named it, with its coordinates.
    var cityName: String = ""
    var cityLatitude: Double?
    var cityLongitude: Double?
    var units: WeatherUnits = .automatic

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, false)
        useCurrentLocation = c.value(.useCurrentLocation, true)
        cityName = c.value(.cityName, "")
        // Optional, so bounded by hand: a coordinate off the globe is dropped rather than
        // clamped, since a clamped one is a real place that is not the one chosen.
        let latitude = c.value(.cityLatitude, nil as Double?)
        let longitude = c.value(.cityLongitude, nil as Double?)
        if let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) {
            cityLatitude = latitude
            cityLongitude = longitude
        }
        units = c.value(.units, WeatherUnits.automatic)
    }

    /// The chosen city's coordinates, when there is a complete pair.
    var cityCoordinate: (latitude: Double, longitude: Double)? {
        guard let cityLatitude, let cityLongitude else { return nil }
        return (cityLatitude, cityLongitude)
    }
}
