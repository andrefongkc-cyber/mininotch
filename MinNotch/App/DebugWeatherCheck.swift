#if DEBUG
import Foundation

/// Fetches a real forecast and prints what the widget would show.
///
/// Run with `MinNotch --check-weather London` or `MinNotch --check-weather 51.5 -0.13`.
///
/// Over the network, through the same `BoundedHTTPClient` limits the app uses, so it proves the
/// request is accepted and the response parses: the host allowance, the size cap, the Unix
/// times, and the day names in the place's own time zone. A city goes through the geocoding
/// search first, as the City field in Settings does.
@MainActor
enum DebugWeatherCheck {
    static let flag = "--check-weather"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let rest = Array(arguments.dropFirst(index + 1)).filter { !$0.hasPrefix("--") }

        let client = BoundedHTTPClient(maxBytes: 64 * 1024, allowedHosts: [OpenMeteo.forecastHost, OpenMeteo.geocodingHost])

        var latitude: Double
        var longitude: Double
        var name: String
        if rest.count >= 2, let lat = Double(rest[0]), let lon = Double(rest[1]) {
            (latitude, longitude, name) = (lat, lon, "\(rest[0]), \(rest[1])")
        } else {
            let query = rest.isEmpty ? "London" : rest.joined(separator: " ")
            guard let url = OpenMeteo.searchURL(for: query),
                  let data = client.fetchSynchronously(url) else {
                print("FAIL search for \(query) returned nothing")
                return true
            }
            let places = OpenMeteo.places(from: data)
            print("search \"\(query)\": \(places.count) places")
            for place in places { print("  \(place.name) — \(place.detail)  (\(place.latitude), \(place.longitude))") }
            guard let first = places.first else { return true }
            (latitude, longitude, name) = (first.latitude, first.longitude, first.name)
        }

        let fahrenheit = arguments.contains("--fahrenheit")
        guard let url = OpenMeteo.forecastURL(latitude: latitude, longitude: longitude, fahrenheit: fahrenheit) else { return true }
        print("request \(url.absoluteString)")
        guard let data = client.fetchSynchronously(url) else {
            print("FAIL forecast returned nothing")
            return true
        }
        guard let report = OpenMeteo.report(from: data, placeName: name, fahrenheit: fahrenheit) else {
            print("FAIL forecast did not parse (\(data.count) bytes)")
            return true
        }
        print("\(data.count) bytes")
        print("\(report.placeName): \(WeatherReport.degrees(report.temperature)) \(report.condition.title) [\(report.condition.symbolName(isDay: report.isDay))], H \(WeatherReport.degrees(report.high)) L \(WeatherReport.degrees(report.low))")
        print("hours: " + report.hours.map { "\(report.hourLabel($0.time)) \(WeatherReport.degrees($0.temperature))" }.joined(separator: ", "))
        print("days:  " + report.days.map { "\($0.label) \(WeatherReport.degrees($0.high))/\(WeatherReport.degrees($0.low)) \($0.condition.title)" }.joined(separator: ", "))
        return true
    }
}
#endif
