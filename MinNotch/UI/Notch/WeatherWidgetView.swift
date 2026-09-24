import SwiftUI

/// The Weather tab: now on the left, the next hours and the next days on the right.
///
/// Drawn on the notch's black, so every colour is explicit white or the condition symbol's own
/// palette, never a semantic label colour. When there is no forecast yet, the tab says why and,
/// where it can, offers the one thing that fixes it.
struct WeatherWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    static let preferredHeight: CGFloat = 124

    private var service: WeatherService { environment.weather }

    var body: some View {
        Group {
            if let report = service.report {
                forecast(report)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Forecast

    private func forecast(_ report: WeatherReport) -> some View {
        HStack(alignment: .top, spacing: 18) {
            current(report)
                .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(report.hours) { hour in
                        column(
                            label: report.hourLabel(hour.time),
                            symbol: hour.condition.symbolName(),
                            value: WeatherReport.degrees(hour.temperature)
                        )
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                HStack(spacing: 0) {
                    ForEach(report.days) { day in
                        column(
                            label: day.label,
                            symbol: day.condition.symbolName(),
                            value: "\(WeatherReport.degrees(day.high)) \(WeatherReport.degrees(day.low))"
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func current(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: report.condition.symbolName(isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                Text(WeatherReport.degrees(report.temperature))
                    .font(.system(size: 34, weight: .light).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Text(report.condition.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("H \(WeatherReport.degrees(report.high))  L \(WeatherReport.degrees(report.low))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            Label(report.placeName, systemImage: settings.weather.useCurrentLocation ? "location.fill" : "mappin")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .padding(.top, 4)
        }
    }

    private func column(label: String, symbol: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
                .frame(height: 16)
            Text(value)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: No forecast

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.35))
            Text(service.status.message ?? "No forecast yet.")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if service.status == .needsLocationAccess {
                Button("Allow Location") { service.requestLocationAccess() }
                    .buttonStyle(NotchAccentButtonStyle(accent: settings.appearance.resolvedAccent))
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
