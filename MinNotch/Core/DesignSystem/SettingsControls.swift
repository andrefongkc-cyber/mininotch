import SwiftUI

/// Slider with the numeric value shown beside it, the way System Settings shows a value
/// for anything continuous.
struct ValueSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.05
    /// Formats the number shown to the right, e.g. "0.25 s".
    var format: (Double) -> String
    var width: CGFloat = 150

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range, step: step)
                .frame(width: width)
                .controlSize(.small)

            Text(format(value))
                .font(Typography.timecode)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// Menu picker sized to its content rather than stretched across the row.
struct InlinePicker<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    @ViewBuilder var content: Content

    var body: some View {
        Picker("", selection: $selection) { content }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.regular)
    }
}

/// Standard switch, so every toggle in the app is the same size and style.
struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}

/// A row whose control is disabled because the feature is not built yet.
///
/// Renders the real control bound to the real setting, so the value the user picks is kept,
/// but greys it out and badges it. When the feature lands, deleting the modifier is the
/// only change needed.
extension View {
    func comingSoon(_ isComingSoon: Bool = true) -> some View {
        disabled(isComingSoon)
            .opacity(isComingSoon ? 0.55 : 1)
    }
}
