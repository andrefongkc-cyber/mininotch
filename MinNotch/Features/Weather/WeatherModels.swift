import Foundation

/// A WMO weather code, which is what Open-Meteo reports, as a symbol and a word.
struct WeatherCondition: Equatable {
    let code: Int

    var title: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms and Hail"
        default: return "Unknown"
        }
    }

    func symbolName(isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

/// Where the weather is for, found by the city search.
struct WeatherPlace: Identifiable, Equatable {
    var name: String
    /// Region and country, for telling apart the several Springfields.
    var detail: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }
}

/// One forecast, as the widget and the pill show it.
struct WeatherReport: Equatable {
    struct Hour: Identifiable, Equatable {
        var time: Date
        var temperature: Double
        var condition: WeatherCondition
        var id: TimeInterval { time.timeIntervalSince1970 }
    }

    struct Day: Identifiable, Equatable {
        /// Short weekday in the place's own time zone, e.g. "Tue", or "Today".
        var label: String
        var high: Double
        var low: Double
        var condition: WeatherCondition
        var id: String { label }
    }

    var placeName: String
    var temperature: Double
    var condition: WeatherCondition
    var isDay: Bool
    var high: Double
    var low: Double
    var usesFahrenheit: Bool
    /// The place's own time zone, so a chosen city's hours read as that city's clock.
    var timeZone: TimeZone = .current
    var hours: [Hour]
    var days: [Day]
    var fetchedAt: Date

    /// "14°". The unit is left off, as the Weather app does: the setting says which it is.
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    /// "3 PM" in the place's own time.
    func hourLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Reads Open-Meteo's forecast and geocoding responses.
///
/// Times are asked for as Unix seconds, so nothing depends on parsing a local time string, and
/// the place's own offset from UTC names the days, so "Tue" is Tuesday where the weather is.
enum OpenMeteo {
    static let forecastHost = "api.open-meteo.com"
    static let geocodingHost = "geocoding-api.open-meteo.com"

    static func forecastURL(latitude: Double, longitude: Double, fahrenheit: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = forecastHost
        components.path = "/v1/forecast"
        components.queryItems = [
            // Rounded to about a kilometre before it leaves the Mac. Weather does not change
            // within that, and a street address has no business in a forecast request.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")
        ]
        return components.url
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = geocodingHost
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
            var is_day: Int
        }
        struct Hourly: Decodable {
            var time: [TimeInterval]
            var temperature_2m: [Double?]
            var weather_code: [Int?]
        }
        struct Daily: Decodable {
            var time: [TimeInterval]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
        }
        var utc_offset_seconds: Int
        var current: Current
        var hourly: Hourly
        var daily: Daily
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
            var admin1: String?
        }
        var results: [Result]?
    }

    /// The forecast in `data`, or nil when it is not one.
    static func report(from data: Data, placeName: String, fahrenheit: Bool, now: Date = Date()) -> WeatherReport? {
        guard let response = try? JSONDecoder().decode(ForecastResponse.self, from: data) else { return nil }

        let zone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? .current
        let weekday = DateFormatter()
        weekday.timeZone = zone
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        var calendar = Calendar.current
        calendar.timeZone = zone

        // The next six hours, starting with the one under way.
        let hourly = response.hourly
        let hours: [WeatherReport.Hour] = hourly.time.indices.compactMap { index in
            let time = Date(timeIntervalSince1970: hourly.time[index])
            guard time > now.addingTimeInterval(-3600),
                  let temperature = hourly.temperature_2m[safe: index] ?? nil,
                  let code = hourly.weather_code[safe: index] ?? nil else { return nil }
            return WeatherReport.Hour(time: time, temperature: temperature, condition: WeatherCondition(code: code))
        }

        let daily = response.daily
        let days: [WeatherReport.Day] = daily.time.indices.compactMap { index in
            guard let high = daily.temperature_2m_max[safe: index] ?? nil,
                  let low = daily.temperature_2m_min[safe: index] ?? nil,
                  let code = daily.weather_code[safe: index] ?? nil else { return nil }
            let date = Date(timeIntervalSince1970: daily.time[index])
            let label = calendar.isDate(date, inSameDayAs: now) ? "Today" : weekday.string(from: date)
            return WeatherReport.Day(label: label, high: high, low: low, condition: WeatherCondition(code: code))
        }

        guard let today = days.first else { return nil }
        return WeatherReport(
            placeName: placeName,
            temperature: response.current.temperature_2m,
            condition: WeatherCondition(code: response.current.weather_code),
            isDay: response.current.is_day != 0,
            high: today.high,
            low: today.low,
            usesFahrenheit: fahrenheit,
            timeZone: zone,
            hours: Array(hours.prefix(6)),
            days: days,
            fetchedAt: now
        )
    }

    static func places(from data: Data) -> [WeatherPlace] {
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
        return (response.results ?? []).map { result in
            WeatherPlace(
                name: result.name,
                detail: [result.admin1, result.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                latitude: result.latitude,
                longitude: result.longitude
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
