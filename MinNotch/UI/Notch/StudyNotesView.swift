import SwiftUI

/// The Study tab: one scrollable page of notes, read from `StudyNotes.md` in the app's own
/// resources (2026-11-18, the user's "replace the page scanning feature with just like a
/// scrollable page that is embeded into the files"). It took the Answers tab's place; the tab
/// keeps the `.answers` case so saved arrangements and a remembered tab still decode.
///
/// The file is a small Markdown subset, parsed here rather than by `AttributedString`, which
/// does not keep list nesting: `# ` starts a section, `* ` a point, and three more spaces of
/// indent a point under it. A row of the sections sits above the page and jumps to each.
struct StudyNotesView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(SettingsStore.self) private var settings

    static let preferredHeight: CGFloat = 300

    private let notes = StudyNotes.bundled

    #if DEBUG
    /// A section to open on, for `--capture-notch --study --study-jump <n>`.
    nonisolated(unsafe) static var debugJump: Int?
    #endif

    /// The page's rows are named `"line-<n>"`, never the bare number: the chips are a `ForEach`
    /// over the same lines, so they carry those numbers as their own identities, and
    /// `scrollTo(n)` found the chip in the bar above and scrolled the bar instead of the page
    /// (2026-11-18, "pressing the buttons on top doesn't hyperlink"). A plain `VStack`, not a
    /// lazy one, so a section far down has been laid out when it is jumped to.
    private static func anchor(_ id: Int) -> String { "line-\(id)" }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                sectionBar(proxy)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(notes.lines) { line in
                            row(line).id(Self.anchor(line.id))
                        }
                    }
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .scrollIndicators(.automatic)
                .frame(height: Self.preferredHeight - 36)
            }
            #if DEBUG
            .onAppear {
                if let jump = Self.debugJump, notes.sections.indices.contains(jump) {
                    proxy.scrollTo(Self.anchor(notes.sections[jump].id), anchor: .top)
                }
            }
            #endif
        }
        .frame(height: Self.preferredHeight, alignment: .top)
    }

    /// One chip per section, scrolling the page so that section is at the top.
    private func sectionBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(notes.sections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.anchor(section.id), anchor: .top) }
                    } label: {
                        Text(section.shortTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.ink.opacity(0.75))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(NotchElementView(.button, shape: .capsule, emphasis: 0.08))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(section.text)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 24)
    }

    @ViewBuilder
    private func row(_ line: StudyNotes.Line) -> some View {
        switch line.kind {
        case .heading:
            Text(line.text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.accentColor(settings.appearance.resolvedAccent))
                .padding(.top, line.id == 0 ? 0 : 12)
                .padding(.bottom, 2)
        case .point(let level):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(level == 0 ? "•" : "–")
                    .foregroundStyle(theme.ink.opacity(0.4))
                Text(line.text)
                    .foregroundStyle(theme.ink.opacity(level == 0 ? 0.95 : 0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: level == 0 ? 12.5 : 11.5, weight: level == 0 ? .semibold : .regular))
            .padding(.leading, CGFloat(level) * 14)
            .padding(.top, level == 0 ? 4 : 0)
        case .text:
            Text(line.text)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.ink.opacity(0.72))
        }
    }
}

/// The notes file, parsed once.
struct StudyNotes {
    struct Line: Identifiable {
        enum Kind: Equatable { case heading, point(level: Int), text }
        let id: Int
        let kind: Kind
        let text: String
        /// A heading's own chip label, written after it in braces: `# Contextualization Frames {Context}`.
        var label: String? = nil

        /// The label if the heading has one, else "Unit 1–2" from "Unit 1–2: 1491–1754", and the
        /// first word of anything else, so every chip fits the panel.
        var shortTitle: String {
            if let label { return label }
            if let colon = text.firstIndex(of: ":") { return String(text[..<colon]) }
            return text.split(separator: " ").first.map(String.init) ?? text
        }
    }

    let lines: [Line]
    var sections: [Line] { lines.filter { $0.kind == .heading } }

    static let bundled: StudyNotes = {
        guard let url = Bundle.main.url(forResource: "StudyNotes", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return StudyNotes(lines: [Line(id: 0, kind: .text, text: "StudyNotes.md is missing from the app.")]) }
        return parse(text)
    }()

    static func parse(_ text: String) -> StudyNotes {
        var lines: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let kind: Line.Kind
            let body: String
            var label: String?
            if trimmed.hasPrefix("# ") {
                kind = .heading
                var heading = String(trimmed.dropFirst(2))
                if heading.hasSuffix("}"), let open = heading.lastIndex(of: "{") {
                    label = String(heading[heading.index(after: open)..<heading.index(before: heading.endIndex)])
                    heading = String(heading[..<open]).trimmingCharacters(in: .whitespaces)
                }
                body = heading
            } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
                kind = .point(level: min(indent / 3, 3))
                body = String(trimmed.dropFirst(2))
            } else {
                kind = .text
                body = trimmed
            }
            lines.append(Line(id: lines.count, kind: kind, text: body, label: label))
        }
        return StudyNotes(lines: lines)
    }
}
