import AppKit

// A plain AppKit entry point rather than a SwiftUI `App`.
//
// MinNotch has no SwiftUI scenes: the notch is a borderless non-activating panel and
// Settings is an `NSWindow`, both created on demand. Declaring an `App` would force a
// scene to exist that the app would immediately have to hide.

#if DEBUG
// Offscreen render mode for design review. Exits before any UI is created.
if MainActor.assumeIsolated({ DebugPreviewRenderer.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugLyricsCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugWindowCapture.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugStatsCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugPermissionsCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugAudioCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugGlowCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugSettingsCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugSettingsCapture.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugOnboardingCapture.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugMediaCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugKeysCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugLinksCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugWhatsNewCapture.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugLyricSyncCheck.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugLayoutCapture.runIfRequested() }) { exit(0) }
if MainActor.assumeIsolated({ DebugDownloadsCheck.runIfRequested() }) { exit(0) }
#endif

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
