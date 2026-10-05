import AppKit
import Observation

/// The Notes tab's scratchpad: one note, kept between opens and between launches.
///
/// Stored as plain text in Application Support rather than in the defaults, because a note can
/// grow, and a file is what someone would expect to find if they went looking. It is written a
/// moment after typing stops, and once more when the app quits, so a crash costs at most the
/// last second of typing. Nothing here leaves the Mac.
@Observable
@MainActor
final class NotesService {
    var text: String = "" {
        didSet {
            guard text != oldValue, isLoaded else { return }
            scheduleSave()
        }
    }

    /// Set to put the cursor in the note: by the New Quick Note shortcut, which opens the tab
    /// and expects to be able to type straight away. The view takes it, on appearing or at once
    /// if it is already showing, and clears it.
    private(set) var wantsFocus = false

    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = NotesService.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("MiniNotch", isDirectory: true).appendingPathComponent("Notes.txt")
    }

    func load() {
        guard !isLoaded else { return }
        moveNoteFromOldFolder()
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        isLoaded = true
    }

    /// The app was MinNotch until 0.7, and so was its folder in Application Support. A note left
    /// there moves to the new folder the first time this version starts, unless one is there
    /// already, which is never overwritten.
    private func moveNoteFromOldFolder() {
        let manager = FileManager.default
        let old = fileURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MinNotch", isDirectory: true)
            .appendingPathComponent(fileURL.lastPathComponent)
        guard old != fileURL, manager.fileExists(atPath: old.path), !manager.fileExists(atPath: fileURL.path) else { return }
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: old, to: fileURL)
        } catch {
            AppLog.app.error("Could not move the note to its new folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestFocus() {
        wantsFocus = true
    }

    func focusHandled() {
        if wantsFocus { wantsFocus = false }
    }

    /// Writes now, for quitting. A pending save is folded into this one.
    func saveNow() {
        guard saveWork != nil else { return }
        saveWork?.cancel()
        saveWork = nil
        write()
    }

    func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.saveWork = nil
                self?.write()
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func write() {
        guard isLoaded else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            AppLog.app.error("Could not save the note: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    /// A note for captures. Left unloaded, so nothing is ever written over the real one.
    func applySample() {
        isLoaded = false
        text = "Groceries: oat milk, limes, coffee\nCall the dentist before Friday\n\nIdeas\n- a sneak peek for calendar events\n- pin the Shelf open while dragging"
    }
    #endif
}
