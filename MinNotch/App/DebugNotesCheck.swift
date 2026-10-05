#if DEBUG
import Foundation

/// Checks that a note is written to disk after typing stops, and read back by the next launch.
///
/// Run with `MiniNotch --check-notes`. Uses a file in a scratch folder, never the real note.
@MainActor
enum DebugNotesCheck {
    static let flag = "--check-notes"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        var failures = 0
        func check(_ passed: Bool, _ what: String) {
            print((passed ? "ok   " : "FAIL ") + what)
            if !passed { failures += 1 }
        }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func onDisk(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("minnotch-notes-check-\(UUID().uuidString)")
        let file = folder.appendingPathComponent("Notes.txt")
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = NotesService(fileURL: file)
        first.load()
        check(first.text.isEmpty, "a first launch starts with an empty note")

        first.text = "Buy limes"
        check(onDisk(file) == nil, "nothing is written while typing")
        wait(1.2)
        check(onDisk(file) == "Buy limes", "written a moment after typing stops")

        first.text = "Buy limes and coffee"
        first.saveNow()
        check(onDisk(file) == "Buy limes and coffee", "quitting writes at once, without waiting")

        let next = NotesService(fileURL: file)
        next.load()
        check(next.text == "Buy limes and coffee", "the next launch reads it back")

        let sample = NotesService(fileURL: file)
        sample.applySample()
        wait(1.2)
        check(onDisk(file) == "Buy limes and coffee", "a capture's sample note never overwrites the real one")

        // A note from before the rename, in the old folder, moves to the new one.
        let renamedRoot = folder.appendingPathComponent("support")
        let oldFile = renamedRoot.appendingPathComponent("MinNotch/Notes.txt")
        let newFile = renamedRoot.appendingPathComponent("MiniNotch/Notes.txt")
        try? FileManager.default.createDirectory(at: oldFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "Written by MinNotch".write(to: oldFile, atomically: true, encoding: .utf8)
        let migrated = NotesService(fileURL: newFile)
        migrated.load()
        check(migrated.text == "Written by MinNotch" && !FileManager.default.fileExists(atPath: oldFile.path),
              "a note in the old MinNotch folder moves to the MiniNotch one")

        print(failures == 0 ? "ok   notes are kept" : "FAIL \(failures) checks")
        return true
    }
}
#endif
