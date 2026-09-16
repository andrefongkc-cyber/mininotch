#if DEBUG
import AppKit

/// Adds links to a throwaway Link Shelf and prints what came back: title, icon, and what was refused.
///
/// Run with `MinNotch --check-links "<url or text>" ...`. Uses its own defaults suite, so the
/// real shelf is untouched. The title and icon are real network reads from each site.
@MainActor
enum DebugLinksCheck {
    static let flag = "--check-links"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let inputs = Array(arguments.dropFirst(index + 1))

        let suite = "com.minnotch.debug-links"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = DebugSupport.makeEnvironment().settings
        let service = LinkShelfService(defaults: defaults)
        service.start(settings: settings)

        for input in inputs {
            let added: Int
            if let url = URL(string: input), url.scheme != nil, !input.contains(" ") {
                let before = service.items.count
                service.add(url)
                added = service.items.count - before
            } else {
                added = service.add(fromText: input)
            }
            report("input \(input.debugDescription): \(added == 0 ? "refused" : "added \(added)")")
        }

        RunLoop.main.run(until: Date().addingTimeInterval(9))

        report("")
        for item in service.items {
            let icon = service.icons[item.host].map { "icon \(Int($0.size.width))pt" } ?? "no icon"
            report("\(item.url.absoluteString)\n    title: \(item.title ?? "(none)")   \(icon)")
        }

        // Persistence: a second service on the same suite must read the same list back.
        let reloaded = LinkShelfService(defaults: defaults)
        reloaded.start(settings: settings)
        report("")
        report("reloaded from disk: \(reloaded.items.count) of \(service.items.count) links, titles kept: \(reloaded.items.filter { $0.title != nil }.count)")

        defaults.removePersistentDomain(forName: suite)
        exit(0)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
