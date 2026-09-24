import CoreLocation
import SwiftUI

/// Settings > Weather.
///
/// Where the forecast is for, and in what. The location is the Mac's own, through Location
/// Services, unless a city is chosen here, which needs no permission at all. Either way the
/// footer says what leaves the Mac and where it goes.
struct WeatherSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    @State private var query = ""

    private var service: WeatherService { environment.weather }

    var body: some View {
        @Bindable var settings = settings
        let enabled = settings.weather.enabled

        SettingsPane(
            title: "Weather",
            subtitle: "The forecast in its own tab, and the temperature in the closed pill if you place it there in Layout."
        ) {
            SettingsCard(
                header: "Weather",
                footer: "Forecasts come from Open-Meteo, which is free and needs no account. MinNotch sends it a location rounded to about a kilometre, and nothing else."
            ) {
                SettingsRow(
                    title: "Show Weather",
                    subtitle: statusSubtitle,
                    systemImage: "cloud.sun",
                    badge: FeatureFlag.weather.badge
                ) {
                    SettingsToggle(isOn: $settings.weather.enabled)
                }

                SettingsDivider()

                SettingsRow(title: "Temperature Units", systemImage: "thermometer.medium", isEnabled: enabled) {
                    InlinePicker(selection: $settings.weather.units) {
                        ForEach(WeatherUnits.allCases) { units in
                            Text(units.title).tag(units)
                        }
                    }
                }
            }

            SettingsCard(header: "Location") {
                SettingsRow(
                    title: "Use My Location",
                    subtitle: locationSubtitle,
                    systemImage: "location",
                    isEnabled: enabled
                ) {
                    HStack(spacing: 8) {
                        if enabled, settings.weather.useCurrentLocation, service.locationAuthorization == .notDetermined {
                            Button("Allow") { service.requestLocationAccess() }
                                .controlSize(.small)
                        }
                        SettingsToggle(isOn: $settings.weather.useCurrentLocation)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "City",
                    subtitle: citySubtitle,
                    systemImage: "mappin.and.ellipse",
                    isEnabled: enabled
                ) {
                    HStack(spacing: 6) {
                        TextField("Search for a city", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .onSubmit { service.search(query) }
                        Button("Find") { service.search(query) }
                            .controlSize(.small)
                            .disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                }

                if enabled, !service.searchResults.isEmpty {
                    ForEach(service.searchResults) { place in
                        SettingsDivider()
                        Button {
                            service.choose(place)
                            query = ""
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin")
                                    .foregroundStyle(Palette.secondaryText)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(place.name)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.primaryText)
                                    Text(place.detail)
                                        .font(Typography.helper)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                                Spacer()
                                Text("Use")
                                    .font(Typography.helper)
                                    .foregroundStyle(Palette.controlAccent)
                            }
                            .padding(.horizontal, Metrics.cardHorizontalPadding)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var statusSubtitle: String {
        guard settings.weather.enabled else {
            return "Off. Nothing is fetched and no location is read."
        }
        if let report = service.report, service.status == .ready {
            let time = report.fetchedAt.formatted(date: .omitted, time: .shortened)
            return "\(report.placeName): \(WeatherReport.degrees(report.temperature)), \(report.condition.title.lowercased()). Updated at \(time), and every half hour."
        }
        return service.status.message ?? "Loading the forecast…"
    }

    private var locationSubtitle: String {
        switch service.locationAuthorization {
        case .notDetermined:
            return "Uses Location Services, which macOS asks you about first. Or choose a city below instead."
        case .denied, .restricted:
            return "Not allowed. Allow MinNotch in Privacy & Security > Location Services, or choose a city below."
        default:
            return "The forecast follows the Mac. Turn this off to use the city below."
        }
    }

    private var citySubtitle: String {
        let city = settings.weather.cityName
        if !settings.weather.useCurrentLocation {
            return city.isEmpty ? "Search, then pick one. Used instead of your location." : "Showing \(city)."
        }
        return city.isEmpty
            ? "Search, then pick one, to use a city instead of your location."
            : "\(city) is saved; turn off Use My Location to show it."
    }
}
