import SwiftUI

/// Contents of the open panel.
///
/// The panel is anchored to the top of the display, so its first band of pixels sits behind
/// the camera housing. Nothing readable can go there. The layout reserves that band as a top
/// strip exactly the height of the cutout and puts its controls in the flanks either side,
/// which are real screen. Everything else starts below the cutout, where it is visible.
///
/// Adding a V2 widget means adding a case to `NotchTab`, registering it in
/// `NotchWidgetRegistry`, and adding one branch here.
struct ExpandedPanelView: View {
    @Bindable var viewModel: NotchViewModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var tabs: [NotchTab] { viewModel.availableTabs }
    private var geometry: NotchGeometry { viewModel.geometry }

    /// Height of the band that has to stay clear of readable content.
    static func topStripHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.collapsedSize.height
    }

    var body: some View {
        VStack(spacing: 0) {
            topStrip

            widget
                .padding(.horizontal, Metrics.notchPanelPadding + Metrics.notchShoulderRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var widget: some View {
        switch viewModel.selectedTab {
        case .media:
            NowPlayingCardView()
        case .calendar:
            CalendarWidgetView(viewModel: viewModel)
        case .system:
            SystemWidgetView()
        case .shelf:
            ShelfView()
        case .clipboard:
            ClipboardWidgetView()
        case .links:
            LinkShelfWidgetView()
        case .timer:
            TimerWidgetView(viewModel: viewModel)
        }
    }

    // MARK: Top strip

    /// Where each item goes this time, from the user's arrangement and the room available.
    private var topStripLayout: TopStripLayout {
        let battery = environment.battery.status
        return TopStripLayout.make(
            leading: settings.appearance.topStripLeading,
            trailing: settings.appearance.topStripTrailing,
            availableTabs: tabs,
            batteryWidth: battery.isPresent
                ? TopStripLayout.batteryWidth(showPercentage: settings.battery.showPercentage)
                : nil,
            showsDebug: settings.advanced.showDebugButtons,
            panelWidth: viewModel.expandedPanelWidth,
            cutoutWidth: geometry.collapsedSize.width
        )
    }

    /// Items either side of the cutout, as arranged in Settings > Appearance > Top Bar.
    ///
    /// The middle is a fixed-width spacer the exact width of the notch. Because the panel is
    /// centred on the cutout, that spacer lands precisely over it, and a `Spacer` does not
    /// hit-test, so clicks in the dead zone fall through rather than being swallowed. Nothing
    /// is ever placed there: an item that does not fit on its side moves to the other side
    /// instead, which is what keeps a seventh tab from hiding behind the camera housing.
    private var topStrip: some View {
        let layout = topStripLayout

        return HStack(spacing: 0) {
            HStack(spacing: TopStripLayout.itemSpacing) {
                ForEach(layout.leading) { item in
                    view(for: item, buttonWidth: layout.buttonWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, TopStripLayout.outerInset)
            .padding(.trailing, TopStripLayout.cutoutClearance)

            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            HStack(spacing: TopStripLayout.itemSpacing) {
                ForEach(layout.trailing) { item in
                    view(for: item, buttonWidth: layout.buttonWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, TopStripLayout.cutoutClearance)
            .padding(.trailing, TopStripLayout.outerInset)
        }
        .frame(height: Self.topStripHeight(for: geometry))
        .animation(Motion.hover, value: viewModel.selectedTab)
        .animation(Motion.content, value: layout)
    }

    @ViewBuilder
    private func view(for item: TopStripItem, buttonWidth: CGFloat) -> some View {
        if let tab = item.tab {
            NotchIconButton(
                systemImage: tab.symbolName,
                help: tab.title,
                accent: settings.appearance.resolvedAccent,
                isActive: viewModel.selectedTab == tab,
                width: buttonWidth
            ) {
                viewModel.selectedTab = tab
            }
            .accessibilityAddTraits(viewModel.selectedTab == tab ? [.isSelected] : [])
        } else if item == .settings {
            NotchIconButton(
                systemImage: "gearshape",
                help: "MinNotch Settings",
                accent: settings.appearance.resolvedAccent,
                width: buttonWidth
            ) {
                environment.openSettings()
                viewModel.collapse()
            }
        } else if item == .battery {
            battery
        } else if item == .whatsNew {
            NotchIconButton(
                systemImage: item.layoutSymbol,
                help: "Show What's New (debug)",
                accent: settings.appearance.resolvedAccent,
                width: buttonWidth
            ) {
                viewModel.collapse()
                environment.whatsNew.present()
            }
        } else if item == .tutorial {
            NotchIconButton(
                systemImage: item.layoutSymbol,
                help: "Show the tutorial (debug)",
                accent: settings.appearance.resolvedAccent,
                width: buttonWidth
            ) {
                viewModel.collapse()
                // A rerun starts the checklist from the current settings, so looking at it
                // changes nothing unless a box is changed.
                environment.onboarding.present(isRerun: true)
            }
        }
    }

    @ViewBuilder
    private var battery: some View {
        let status = environment.battery.status
        if status.isPresent {
            HStack(spacing: TopStripLayout.batteryLabelSpacing) {
                if settings.battery.showPercentage {
                    Text("\(status.percentage)%")
                        .font(Typography.timecode)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Image(systemName: status.symbolName)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.tint)
                    // A fixed width, so `TopStripLayout` knows exactly how much room it takes.
                    .frame(width: TopStripLayout.batteryIconWidth)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery \(status.percentage) percent")
        }
    }
}

/// A compact icon button for the notch's top strip.
///
/// Uses explicit whites rather than semantic colours because the notch is black in both
/// appearances, and a hover fill rather than a border so the strip stays quiet until
/// pointed at.
struct NotchIconButton: View {
    var systemImage: String
    var help: String
    var accent: Color
    var isActive: Bool = false
    /// Narrowed by `TopStripLayout` when the bar is short of room.
    var width: CGFloat = 28
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: width, height: 21)
                .foregroundStyle(foreground)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(backgroundOpacity))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .animation(Motion.hover, value: isHovering)
    }

    private var foreground: Color {
        if isActive { return accent }
        return .white.opacity(isHovering ? 0.95 : 0.55)
    }

    private var backgroundOpacity: Double {
        if isActive { return 0.14 }
        return isHovering ? 0.08 : 0
    }
}

/// Filled accent button for use inside the notch.
///
/// `.borderedProminent` draws itself in an inactive grey when its window is not key, and the
/// notch panel is deliberately non-activating so it never steals focus. That makes a system
/// prominent button look disabled exactly when it matters, so the notch styles its own.
struct NotchAccentButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(accent.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .contentShape(Capsule())
    }
}
