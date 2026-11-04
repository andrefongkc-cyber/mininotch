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

extension LineMerge {
    /// How many lines two reads share past what stays put at their top and bottom (a toolbar,
    /// a footer): the run a scroll leaves in view. Counted on the loose keys.
    static func movingOverlap(_ a: [String], _ b: [String]) -> Int {
        movingShare(a, b).shared
    }

    /// The moving lines `b` shares with `a`, and how many moving lines `b` has.
    static func movingShare(_ a: [String], _ b: [String]) -> (shared: Int, moving: Int) {
        let a = a.map(key), b = b.map(key)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let x = Array(a[prefix..<(a.count - suffix)]), y = Array(b[prefix..<(b.count - suffix)])
        guard !x.isEmpty, !y.isEmpty else { return (0, y.count) }
        var previous = Array(repeating: 0, count: y.count + 1)
        for i in 0..<x.count {
            var row = Array(repeating: 0, count: y.count + 1)
            for j in 0..<y.count {
                row[j + 1] = x[i] == y[j] && !x[i].isEmpty ? previous[j] + 1 : max(previous[j + 1], row[j])
            }
            previous = row
        }
        return (previous[y.count], y.count)
    }
}

/// A test gathered page by page: each page of a quiz is its own section, and scrolling within
/// a page merges into that page's section.
///
/// Merging every read into one list fused the pages of a quiz, because they repeat lines word
/// for word ("Which choice completes the text…"): the repeat was taken as the overlap and two
/// questions' options ran together (2026-11-03). A scroll keeps a run of the page in view; a new
/// page shares little but the toolbar. So a read that shares at least `scrollOverlap` moving
/// lines with the page it is compared with is that page, scrolled; otherwise it is a new page,
/// unless it matches an earlier one, which is the user going back.
struct PageGatherer {
    private(set) var pages: [[String]] = []
    private(set) var current = 0
    private var lastRead: [String] = []

    static let scrollOverlap = 3

    var lineCount: Int { pages.reduce(0) { $0 + $1.count } }

    mutating func add(_ read: [String]) {
        guard !read.isEmpty else { return }
        defer { lastRead = read }
        guard !pages.isEmpty else {
            pages = [read]
            current = 0
            return
        }
        // The page in front, against the last read of it, and against all of it gathered.
        if isSamePage(read, as: lastRead) || isSamePage(read, as: pages[current]) {
            pages[current] = LineMerge.merge(pages[current], read)
            return
        }
        // Back to an earlier page: the one it shares the most with.
        let best = pages.indices.filter { $0 != current && isSamePage(read, as: pages[$0]) }
            .map { ($0, LineMerge.movingOverlap(pages[$0], read)) }
            .max { $0.1 < $1.1 }
        if let best {
            current = best.0
            pages[current] = LineMerge.merge(pages[current], read)
            return
        }
        pages.append(read)
        current = pages.count - 1
    }

    private func isSamePage(_ read: [String], as page: [String]) -> Bool {
        guard !page.isEmpty else { return false }
        let (overlap, moving) = LineMerge.movingShare(page, read)
        // Nothing left once the top and bottom are matched: the very same screen, read again,
        // which is most reads, since nobody scrolls on every tick.
        if moving == 0 { return true }
        // Enough lines, and enough of what moved: interface repeated mid-page on every page
        // ("Mark for Review", a question navigator) is a few lines of many.
        return overlap >= Self.scrollOverlap && overlap * 4 >= moving
    }
}
