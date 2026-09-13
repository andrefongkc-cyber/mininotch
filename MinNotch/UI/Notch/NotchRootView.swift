import SwiftUI
import UniformTypeIdentifiers

/// Applies the panel shadow only when it is wanted.
///
/// A modifier rather than a `.shadow` with a zero-alpha colour: a zero-alpha shadow still
/// forces an offscreen compositing pass, which fringes the pill's edges on a transparent
/// window.
private struct PanelShadow: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        } else {
            content
        }
    }
}

/// Root of a notch surface. Draws the shape, swaps between the collapsed and expanded
/// content, and owns hover and click handling.
///
/// Everything outside the shape is `Spacer`, never a clear colour, because a clear colour
/// hit-tests and would swallow clicks aimed at the desktop behind the window.
struct NotchRootView: View {
    @Bindable var viewModel: NotchViewModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var isExpanded: Bool { viewModel.state == .expanded || viewModel.state == .peeking }

    /// True from the moment the surface starts growing or shrinking until it has settled.
    ///
    /// Only the glow reads it. See `AmbientGlowView.isTransitioning` for why it exists.
    @State private var isTransitioning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                surface
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Surface

    private var surface: some View {
        // Only `content` draws. A bare `Shape` used as a `View` fills itself with the
        // current foreground style, which resolves to white in a dark appearance, so
        // putting `shape` in this stack laid a white silhouette under the panel. It showed
        // through wherever the black fill's antialiasing did not cover it exactly, which is
        // every curved edge: the bottom corners and the two top fillets.
        ZStack(alignment: .top) {
            content
        }
        .frame(width: surfaceWidth, height: surfaceHeight)
        // No `GeometryReader` here. It aligns its content top-leading, and the glow's layer
        // is deliberately larger than the outline it traces, so the whole thing was pushed
        // down and right by the spill and the light no longer sat on the panel. A plain
        // overlay centres it, which is what puts the outline back on the edge it traces.
        .overlay(ambientGlow(outlineSize: CGSize(width: surfaceWidth, height: surfaceHeight)))
        .overlay(debugOverlay)
        .contentShape(shape)
        .onHover { viewModel.hoverChanged($0) }
        .onTapGesture { viewModel.clicked() }
        .onDrop(of: [.fileURL], isTargeted: dragEnteredBinding) { _ in false }
        // One animation keyed to the whole geometry. Animating width and height off
        // separate values with separate curves is what made the box grow unevenly: the
        // width would arrive before the height and the shape would visibly shear.
        .animation(Motion.notch, value: surfaceMetrics)
        .onChange(of: surfaceMetrics) {
            isTransitioning = true
            let generation = UUID()
            transitionGeneration = generation
            Task { @MainActor in
                // Slightly past the spring, so the glow does not resume onto a box that is
                // still settling. A later change supersedes this one rather than racing it.
                try? await Task.sleep(for: .milliseconds(600))
                guard transitionGeneration == generation else { return }
                isTransitioning = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isExpanded ? "MinNotch panel" : "MinNotch")
    }

    /// Opens the notch on the Shelf tab when a file is dragged over the closed pill.
    ///
    /// The drop itself is refused here and left to `ShelfView`, which is the thing that
    /// actually holds files. This target exists only to notice the drag arriving, because a
    /// collapsed pill is far too small a target to drop onto accurately.
    private var dragEnteredBinding: Binding<Bool> {
        Binding(
            get: { environment.shelf.isDropTargeted },
            set: { isTargeted in
                guard isTargeted,
                      settings.shelf.enabled,
                      settings.shelf.expandOnDragEnter,
                      FeatureFlag.shelf.isEnabled else { return }

                viewModel.selectedTab = .shelf
                viewModel.expand()
            }
        )
    }

    /// Identifies the most recent transition, so an earlier one cannot clear the flag for it.
    @State private var transitionGeneration = UUID()

    private var shapeStyle: NotchShape {
        NotchShape(
            shoulderRadius: Metrics.notchShoulderRadius,
            bottomRadius: isExpanded
                ? CGFloat(settings.appearance.panelCornerRadius)
                : min(CGFloat(settings.appearance.panelCornerRadius), geometry.collapsedSize.height / 2)
        )
    }

    private var shape: some Shape { shapeStyle }

    /// The surface fill.
    ///
    /// Deliberately independent of whether the panel is open. When the material was applied
    /// only to the expanded state, opening swapped a black fill for a lighter translucent
    /// one part-way through the growth, which read as a flash of light rather than as a box
    /// getting bigger. Constant fill means the only thing that changes is the size.
    @ViewBuilder
    private var background: some View {
        if settings.appearance.useVibrancy {
            ZStack {
                Palette.notchFill
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(0.55)
            }
        } else {
            Palette.notchFill
        }
    }

    /// Fill and content in one stack, clipped exactly once.
    ///
    /// Clipping the fill and the content separately puts two independently antialiased
    /// edges on top of each other. Each one leaves partial-coverage pixels along every
    /// curve, and on a transparent window the compositor blends those against the desktop
    /// rather than against the panel, which shows as a pale seam tracing the bottom corners
    /// and the top fillets. One clip means one edge.
    private var content: some View {
        ZStack(alignment: .top) {
            background
            contentLayer
        }
        .clipShape(shape)
        .modifier(PanelShadow(isActive: isExpanded && settings.appearance.showPanelShadow))
    }

    /// The collapsed or expanded content, clipped to the surface.
    ///
    /// The clip is what keeps the transition black. The panel's content is white text on
    /// black, and it holds its full size for the length of its fade while the box is still
    /// growing or shrinking around it. Unclipped, that text is drawn outside the black fill
    /// on a transparent window, which is the pale smear that trails the box on both open and
    /// close. Clipped, nothing can ever be visible outside the shape.
    private var contentLayer: some View {
        Group {
            if isExpanded {
                ZStack(alignment: .top) {
                    artworkTint
                    ExpandedPanelView(viewModel: viewModel)
                        .padding(.bottom, Metrics.notchPanelPadding)
                }
                .transition(Self.contentTransition)
            } else if let reading = environment.hud.current {
                HUDView(
                    reading: reading,
                    geometry: geometry,
                    style: settings.huds.style,
                    showsNumericValue: settings.huds.showNumericValue,
                    accent: settings.appearance.resolvedAccent
                )
                .transition(Self.contentTransition)
            } else {
                CollapsedPillView(geometry: geometry, content: pillContent)
                    .transition(Self.contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A wash of the album's dominant colour across the top of the panel.
    ///
    /// Deliberately part of the content rather than the fill. A fill that changes when the
    /// panel opens appears part-way through the growth and reads as a flash; as content it
    /// fades in with everything else. It sits behind the panel and bleeds to the edges,
    /// which is why it lives here rather than inside the media card, where that card's own
    /// horizontal padding would inset it.
    @ViewBuilder
    private var artworkTint: some View {
        if settings.media.tintFromArtwork,
           viewModel.selectedTab == .media,
           environment.nowPlaying.artwork != nil {
            LinearGradient(
                colors: [
                    environment.nowPlaying.palette.primary.opacity(0.30),
                    environment.nowPlaying.palette.primary.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    /// Colour spilling from the notch's edge.
    ///
    /// Overlaid on the surface rather than placed inside it, because the content layer is
    /// clipped to the shape and a glow that cannot bleed past the edge is just a border.
    ///
    /// Placement is a separate setting from style, so the closed pill and the open panel are
    /// independently switchable and only the one currently on screen is ever drawn.
    @ViewBuilder
    private func ambientGlow(outlineSize: CGSize) -> some View {
        let glow = settings.appearance.ambientGlow
        let placement: AmbientGlowPlacement = isExpanded ? .expandedPanel : .collapsedNotch

        if glow.isActive(isLowPower: environment.battery.status.isLowPowerMode),
           glow.placements.contains(placement) {
            AmbientGlowView(
                pathBuilder: AmbientGlowGeometry.notchPath(shapeStyle),
                settings: glow,
                palette: environment.nowPlaying.palette,
                isPlaying: environment.nowPlaying.track?.isPlaying ?? false,
                audio: environment.audioAnalyzer.current == nil ? nil : environment.audioAnalyzer,
                showsLevelReadout: settings.advanced.showDebugOverlay,
                outlineSize: outlineSize,

                // Only as much room as this radius actually needs. The constant is the
                // ceiling, for the widest radius the slider offers; asking for all of it at
                // the default radius made the rasterised layer twice the area for a falloff
                // that had already reached nothing.
                spill: min(CGFloat(glow.glowRadius) * 2, Metrics.notchGlowSpill),
                isTransitioning: isTransitioning
            )
        }
    }

    /// Outlines the surface and prints its geometry, for diagnosing placement and hit-testing.
    ///
    /// Never hit-tests, so switching it on cannot change the behaviour being investigated.
    @ViewBuilder
    private var debugOverlay: some View {
        if settings.advanced.showDebugOverlay {
            ZStack(alignment: .bottomLeading) {
                shape.stroke(
                    Color(nsColor: .systemGreen),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )

                Text(debugSummary)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .padding(3)
                    .background(Color.black.opacity(0.65))
                    .padding(4)
            }
            .allowsHitTesting(false)
        }
    }

    private var debugSummary: String {
        let surface = String(format: "%.0f x %.0f", surfaceWidth, surfaceHeight)
        let notch = String(
            format: "%.0f x %.0f",
            geometry.collapsedSize.width,
            geometry.collapsedSize.height
        )
        let kind = geometry.hasPhysicalNotch ? "physical" : "virtual"
        return "surface \(surface)   notch \(notch) \(kind)   display \(geometry.displayID)"
    }

    /// A plain fade, the same in both directions.
    ///
    /// It can afford to be symmetric because `contentLayer` is clipped to the shape: the
    /// fade happens strictly inside the black box, so there is nothing to see outside it at
    /// any point in the transition and no need to choreograph the two states apart.
    private static let contentTransition = AnyTransition.opacity
        .animation(.easeInOut(duration: 0.2))

    // MARK: Sizing

    private var geometry: NotchGeometry { viewModel.geometry }

    /// Artwork is only worth the space in the pill when something is actually playing.
    private var collapsedArtwork: NSImage? {
        guard settings.media.enabled, environment.nowPlaying.track?.isPlaying == true else { return nil }
        return environment.nowPlaying.artwork
    }

    private var pillContent: CollapsedPillContent {
        CollapsedPillContent(
            artwork: collapsedArtwork,
            activity: environment.liveActivities.current,
            isPlaying: environment.nowPlaying.track?.isPlaying ?? false,
            battery: environment.battery.status,
            showPercentage: settings.battery.showPercentage,
            // A display with no physical notch always carries its indicators, whatever the
            // setting says. The setting exists because on notched hardware the closed pill
            // sits behind the camera housing and is invisible, so widening it is a real
            // choice with a real cost. A virtual notch has no housing to hide behind: it is
            // already a black tab stuck to the top of the screen, and leaving it empty is
            // all of the cost and none of the benefit.
            isExtended: settings.general.extendPillForIndicators || !geometry.hasPhysicalNotch,
            leadingLayout: settings.general.pillLeading,
            trailingLayout: settings.general.pillTrailing
        )
    }

    /// Everything that changes the surface's size, in one comparable value.
    private var surfaceMetrics: SurfaceMetrics {
        SurfaceMetrics(width: surfaceWidth, height: surfaceHeight, isExpanded: isExpanded)
    }

    private struct SurfaceMetrics: Equatable {
        var width: CGFloat
        var height: CGFloat
        var isExpanded: Bool
    }

    private var surfaceWidth: CGFloat {
        guard !isExpanded else {
            return min(CGFloat(settings.appearance.expandedWidth), geometry.expandedSize.width)
        }
        // A HUD takes over the closed surface entirely, and needs both flanks to show an
        // icon and a level rather than the pill's narrower strips.
        if environment.hud.current != nil { return HUDView.width(for: geometry) }
        return pillContent.width(for: geometry)
    }

    /// Explicit heights per tab rather than intrinsic sizing.
    ///
    /// The panel animates between two states, and animating from a known height to another
    /// known height is stable, whereas animating to an intrinsic height makes the shape jump
    /// on the first frame while the content lays itself out. Each widget owns its own number,
    /// so a new widget brings its height with it.
    private var surfaceHeight: CGFloat {
        guard isExpanded else {
            guard environment.hud.current == nil else {
                return HUDView.height(for: geometry, style: settings.huds.style)
            }
            return geometry.collapsedSize.height
        }

        var height: CGFloat
        switch viewModel.selectedTab {
        case .media:
            height = NowPlayingCardView.preferredHeight(showingLyrics: settings.media.showLyrics)
        case .calendar:
            height = CalendarWidgetView.preferredHeight(
                mode: settings.calendar.viewMode,
                showsQuickAdd: settings.calendar.enabled && settings.calendar.enableQuickAdd
            )
        case .system:
            height = SystemWidgetView.preferredHeight(
                bluetoothDeviceCount: environment.bluetooth.devices.count
            )
        case .shelf:
            height = ShelfView.preferredHeight
        case .clipboard:
            height = ClipboardWidgetView.preferredHeight
        case .timer:
            height = TimerWidgetView.preferredHeight
        }

        // The top strip is the band hidden behind the camera housing, so it is added at
        // full height and only the bottom gets padding. Adding padding at the top instead
        // would push the content down by that much again for no reason.
        height += ExpandedPanelView.topStripHeight(for: geometry)
        return min(height + Metrics.notchPanelPadding, geometry.expandedSize.height)
    }
}
