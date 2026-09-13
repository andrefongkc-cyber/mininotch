import Foundation

/// Outbound HTTP that refuses to be surprised.
///
/// This app reaches the network in exactly two places, and in both of them the thing being
/// fetched is named by somebody who is not the user: LRCLIB answers a lyrics query, and the
/// artwork URL is whatever string the running media player hands back over Apple Events.
/// Neither of those should be able to make an unsandboxed app read a local file, follow a
/// redirect somewhere else, hang indefinitely, or buffer an unbounded response into memory.
/// `Data(contentsOf:)` and a bare `URLSession` allow all four.
///
/// So every request goes through here, and every request states its limits up front:
///
/// - **HTTPS only, and a host is required.** This is the important one. `URL(string:)` will
///   happily produce `file:///etc/passwd` from a player's reply, and `Data(contentsOf:)` will
///   read it. Transport security does not apply to `file:`, so nothing else catches this.
/// - **A byte cap, enforced while the body arrives** rather than after. Checked against the
///   declared length first, then against what actually turns up, because a server is free to
///   lie about the former or omit it.
/// - **Redirects only within the same host.** A lyrics query names what the user is
///   listening to. An off-host redirect would hand that to a third party they never opted
///   into, which matters for a lookup that is off by default precisely so it stays a choice.
/// - **A timeout**, so a stalled fetch cannot pin the serial queue it was started from.
///
/// Cookies and credentials are refused outright. Nothing here is ever authenticated, so
/// there is no reason to keep state that could be replayed or leaked between requests.
final class BoundedHTTPClient: NSObject {
    private let maxBytes: Int
    private let allowedHosts: Set<String>?
    private var session: URLSession!

    /// Per-task buffer and completion, guarded because `fetch` registers on the caller's
    /// thread while the delegate callbacks arrive on the session's own queue.
    private struct Pending {
        var buffer = Data()
        var host: String
        var completion: (Data?) -> Void
    }
    private var pending: [Int: Pending] = [:]
    private let lock = NSLock()

    /// - Parameters:
    ///   - maxBytes: hard ceiling on one response body.
    ///   - allowedHosts: lower-cased hosts this client may talk to, or nil for any HTTPS host.
    ///   - timeout: seconds before a request is abandoned.
    init(maxBytes: Int, allowedHosts: Set<String>? = nil, timeout: TimeInterval = 8) {
        self.maxBytes = maxBytes
        self.allowedHosts = allowedHosts
        super.init()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// True when `url` is something this client is willing to fetch at all.
    func accepts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty
        else { return false }

        guard let allowedHosts else { return true }
        return allowedHosts.contains(host)
    }

    /// Fetches `url`, calling back with nil for every failure.
    ///
    /// The callers cannot act on the difference between a refusal, a 503, and an empty
    /// result, so the distinction is deliberately not offered.
    func fetch(_ url: URL, headers: [String: String] = [:], completion: @escaping (Data?) -> Void) {
        guard accepts(url), let host = url.host?.lowercased() else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

        let task = session.dataTask(with: request)
        lock.lock()
        pending[task.taskIdentifier] = Pending(host: host, completion: completion)
        lock.unlock()
        task.resume()
    }

    /// Blocking form, for the one caller that already blocks.
    ///
    /// Artwork is read on `AppleScriptRunner`'s serial queue, which is synchronous by nature
    /// and was already blocking on `Data(contentsOf:)` with no timeout at all. Waiting here
    /// is strictly better than that, and cannot deadlock: the delegate callbacks run on this
    /// client's own queue, never on the caller's.
    func fetchSynchronously(_ url: URL, headers: [String: String] = [:]) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        fetch(url, headers: headers) { data in
            result = data
            semaphore.signal()
        }
        // Bounded even if the session never calls back, so a wedged fetch cannot strand the
        // queue that every media read shares.
        _ = semaphore.wait(timeout: .now() + 20)
        return result
    }

    private func finish(_ identifier: Int, with data: Data?) {
        lock.lock()
        let entry = pending.removeValue(forKey: identifier)
        lock.unlock()
        entry?.completion(data)
    }
}

extension BoundedHTTPClient: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            return
        }
        // A declared length over the cap is refused before a single byte of body is read.
        // `expectedContentLength` is -1 when the server does not say, which is not an error.
        guard response.expectedContentLength <= Int64(maxBytes) else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let identifier = dataTask.taskIdentifier

        lock.lock()
        guard var entry = pending[identifier] else { lock.unlock(); return }
        entry.buffer.append(data)
        let overflowed = entry.buffer.count > maxBytes
        pending[identifier] = entry
        lock.unlock()

        // Checked again as it arrives, because a server that omits or understates its
        // content length can still send an endless body.
        if overflowed { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let origin = pending[task.taskIdentifier]?.host
        lock.unlock()

        guard let url = request.url,
              accepts(url),
              let host = url.host?.lowercased(),
              host == origin
        else {
            // nil declines the redirect and completes the task with what it has, which is
            // nothing, so this surfaces as an ordinary failure.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let identifier = task.taskIdentifier

        lock.lock()
        let entry = pending[identifier]
        lock.unlock()

        guard error == nil, let entry, !entry.buffer.isEmpty, entry.buffer.count <= maxBytes else {
            finish(identifier, with: nil)
            return
        }
        finish(identifier, with: entry.buffer)
    }
}
