#if DEBUG
import AppKit
import SwiftUI

/// Captures every page of the first-launch tutorial from a real window.
///
/// Run with `MinNotch --capture-onboarding <dir> [--rerun]`.
///
/// Builds the window through `OnboardingCoordinator.makeWindow`, the same function the app
/// uses, so the capture is the window people see rather than a copy assembled for the tool.
/// The tutorial draws in plain colours instead of materials precisely so this works; the
/// Settings window uses materials and captures as a blank white rectangle.
///
/// Uses a throwaway settings store, so walking through the checklist cannot change the real
/// configuration.
@MainActor
enum DebugOnboardingCapture {
    static let flag = "--capture-onboarding"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let directory = arguments.indices.contains(index + 1)
            ? arguments[index + 1]
            : NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        let isRerun = arguments.contains("--rerun")

        let selection = isRerun
            ? Set(OnboardingFeature.available.filter { $0.isOn(in: settings) })
            : OnboardingPreset.recommended.features
        let model = OnboardingModel(
            selection: selection,
            preset: OnboardingPreset.allCases.first { $0.features == selection }
        )

        let window = OnboardingCoordinator.makeWindow(
            model: model, environment: environment, onSkip: {}, onFinish: { _ in }
        )
        window.setFrameOrigin(CGPoint(x: 80, y: 80))
        window.orderFrontRegardless()

        report("available features: \(OnboardingFeature.available.count), recommended on: \(OnboardingPreset.recommended.features.count)")

        for page in OnboardingModel.Page.allCases {
            model.page = page
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))

            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                report("Could not capture \(page)"); continue
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            let path = (directory as NSString).appendingPathComponent("onboarding-\(page.rawValue)-\(page).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            report("Captured \(page) -> \(path)")
        }

        // The apply step, checked against the store rather than the screen: after confirming
        // the checklist, every feature should read back exactly as it was ticked.
        model.apply(to: settings)
        let mismatched = OnboardingFeature.available.filter {
            $0.isOn(in: settings) != model.selection.contains($0)
        }
        report(mismatched.isEmpty
            ? "apply: every feature reads back as ticked"
            : "apply: MISMATCH for \(mismatched.map(\.rawValue))")

        exit(0)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
