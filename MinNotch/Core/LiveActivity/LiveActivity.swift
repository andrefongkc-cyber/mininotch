import SwiftUI

/// An ongoing event worth showing in the collapsed pill or as a transient expansion.
///
/// This is the general-purpose mechanism behind several planned features: AirPods battery,
/// downloads, timers, and the media sneak peek. It is defined and driven now, with the
/// media peek as its first real client, so V2 activities are a matter of pushing a value
/// rather than inventing a presentation layer.
struct LiveActivity: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case media
        case battery
        case bluetoothDevice
        case download
        case timer
        /// A calendar event about to start.
        case meeting
        case focus
        case custom
    }

    let id: String
    var kind: Kind
    var symbolName: String
    /// Short leading text, e.g. a track title.
    var title: String
    /// Optional trailing text, e.g. "2:31".
    var detail: String?
    /// 0...1 for activities that have measurable progress.
    var progress: Double?
    var tint: Color
    /// Removed automatically once this passes, or nil for activities the owner ends.
    var expiresAt: Date?
    /// Higher wins when several activities compete for the pill.
    var priority: Int

    init(
        id: String,
        kind: Kind,
        symbolName: String,
        title: String,
        detail: String? = nil,
        progress: Double? = nil,
        tint: Color = Palette.controlAccent,
        expiresAt: Date? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.progress = progress
        self.tint = tint
        self.expiresAt = expiresAt
        self.priority = priority
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}
