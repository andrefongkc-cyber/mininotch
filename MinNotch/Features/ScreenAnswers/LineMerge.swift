import Foundation

/// Joins what one read of a window saw to what earlier reads saw, keeping each line once.
///
/// Scrolling moves the page under a window that also shows things that never move (a toolbar,
/// a header), so two reads share some lines at the top and a run where the scroll overlapped.
/// The two are lined up by their longest common subsequence of lines, compared loosely (case,
/// spacing and punctuation that text recognition varies between reads), and merged as a diff
/// is: lines both share once, lines only one has in the place it had them. Scrolling back up
/// works the same way, since lines only the new read has before the overlap go before it.
enum LineMerge {
    /// Past this many lines a side, only the end of what is kept is lined up with the new read,
    /// so the work stays bounded on a very long page.
    static let window = 400

    static func merge(_ kept: [String], _ new: [String]) -> [String] {
        guard !kept.isEmpty else { return new }
        guard !new.isEmpty else { return kept }

        // Line the new read up against the end of what is kept: a read is a screen, so it can
        // only overlap the part gathered most recently, or the top, which never scrolls.
        let headCount = max(0, kept.count - window)
        let head = Array(kept[..<headCount])
        let tail = Array(kept[headCount...])

        let a = tail.map(key), b = new.map(key)
        let n = a.count, m = b.count
        // lengths[i][j]: the longest common run of a[i...] and b[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] && !a[i].isEmpty
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        // Nothing in common: the user jumped further than a screen. Keep both, new after.
        guard lengths[0][0] > 0 else { return kept + new }

        var merged = head
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j], !a[i].isEmpty {
                merged.append(tail[i]); i += 1; j += 1
            } else if i < n, j == m || lengths[i + 1][j] >= lengths[i][j + 1] {
                merged.append(tail[i]); i += 1
            } else {
                merged.append(new[j]); j += 1
            }
        }
        return merged
    }

    /// A line as compared: lowercased, letters and digits only, so "Question 3." and
    /// "Question 3" read twice are the same line.
    static func key(_ line: String) -> String {
        String(line.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
