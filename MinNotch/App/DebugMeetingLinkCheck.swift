#if DEBUG
import Foundation

/// Checks which links in an invitation count as a meeting to join.
///
/// Run with `MinNotch --check-meeting-links`.
///
/// A calendar invitation is text anyone can send, and the link found in it is opened with one
/// click, so the refusals matter as much as the finds: a `file:` link, a custom scheme, plain
/// http, and a host that merely contains a meeting service's name must all come back empty.
@MainActor
enum DebugMeetingLinkCheck {
    static let flag = "--check-meeting-links"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let cases: [(String, String?)] = [
            ("Join Zoom Meeting https://us02web.zoom.us/j/81234567890?pwd=abc", "us02web.zoom.us"),
            ("Meeting ID 812 3456 7890\nhttps://zoom.us/j/81234567890", "zoom.us"),
            ("Video call link: https://meet.google.com/abc-defg-hij", "meet.google.com"),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc", "teams.microsoft.com"),
            ("https://acme.webex.com/meet/pat", "acme.webex.com"),
            ("https://facetime.apple.com/join#v=1&p=abc", "facetime.apple.com"),
            ("Room 4B, https://example.com/agenda then https://meet.google.com/xyz-abcd-efg", "meet.google.com"),
            ("file:///Users/someone/zoom.us/j/1", nil),
            ("zoommtg://zoom.us/join?confno=123", nil),
            ("http://zoom.us/j/123", nil),
            ("https://zoom.us.evil.example/j/123", nil),
            ("https://notzoom.us/j/123", nil),
            ("Lunch at the usual place", nil)
        ]

        var failures = 0
        for (text, expectedHost) in cases {
            let found = MeetingLink.find(in: [text])
            let passed = found?.host == expectedHost
            if !passed { failures += 1 }
            print("\(passed ? "ok  " : "FAIL") \(expectedHost ?? "refused") <- \(text.replacingOccurrences(of: "\n", with: " "))")
        }
        print(failures == 0 ? "all \(cases.count) passed" : "\(failures) of \(cases.count) FAILED")
        return true
    }
}
#endif
