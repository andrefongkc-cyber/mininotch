import AppKit
import AuthenticationServices
import CryptoKit
import Observation
import Security

/// The user's Spotify account, signed in once, for the one thing the Spotify app will not tell
/// other apps: what plays next.
///
/// Spotify's scripting dictionary has the current track and nothing about the queue, and the
/// Chrome web player only shows it while its queue panel is open. Spotify's Web API does answer
/// (`GET /v1/me/player/queue`), for whichever device is playing, desktop app or browser, once the
/// user has signed in. The user chose that over a peek that only worked for Apple Music
/// (2026-10-19).
///
/// Signing in is OAuth's authorization code flow with PKCE, the one Spotify offers apps that
/// cannot keep a secret: no client secret is shipped or asked for. The Client ID is the user's
/// own, from an app they register at developer.spotify.com with the redirect URI
/// `mininotch://spotify-callback`, because an app in Spotify's development mode only signs in the
/// people its owner lists. `ASWebAuthenticationSession` shows Spotify's own sign-in page and
/// catches the redirect, so the scheme needs no entry in the Info.plist. The refresh token is
/// kept in the login keychain; the access token, which lasts an hour, only in memory.
///
/// Requests go through `BoundedHTTPClient`, allowed only Spotify's two hosts (and its image host
/// for covers), and only while the Up Next peek is open: nothing polls Spotify in the background.
@Observable
@MainActor
final class SpotifyAccount: NSObject {
    enum Status: Equatable {
        case notConnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status

    /// The Client ID from Settings > Music, read when signing in and refreshing.
    @ObservationIgnored var clientID: () -> String = { "" }

    static let redirectURI = "mininotch://spotify-callback"
    private static let scopes = "user-read-playback-state user-read-currently-playing"

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry = Date.distantPast
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?

    @ObservationIgnored private let http = BoundedHTTPClient(
        maxBytes: 3_000_000,
        allowedHosts: ["accounts.spotify.com", "api.spotify.com"],
        timeout: 10
    )
    @ObservationIgnored private let imageHTTP = BoundedHTTPClient(
        maxBytes: 2_000_000,
        allowedHosts: ["i.scdn.co"],
        timeout: 8
    )

    override init() {
        status = SpotifyKeychain.refreshToken() == nil ? .notConnected : .connected
        super.init()
    }

    var isConnected: Bool { status == .connected }

    // MARK: Signing in

    func connect() {
        let clientID = clientID().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            status = .failed("Paste your Spotify app's Client ID first.")
            return
        }
        authSession?.cancel()

        let verifier = Self.makeVerifier()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { return }

        status = .connecting
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mininotch") { @Sendable [weak self] callback, error in
            Task { @MainActor in
                self?.finishSignIn(callback: callback, error: error, verifier: verifier, state: state, clientID: clientID)
            }
        }
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            status = .failed("Spotify's sign-in page could not be opened.")
        }
    }

    func disconnect() {
        authSession?.cancel()
        SpotifyKeychain.deleteRefreshToken()
        accessToken = nil
        accessTokenExpiry = .distantPast
        status = .notConnected
    }

    private func finishSignIn(callback: URL?, error: Error?, verifier: String, state: String, clientID: String) {
        authSession = nil
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            status = .notConnected
            return
        }
        guard let callback,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else {
            let reason = URLComponents(url: callback ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            status = .failed(reason == "access_denied" ? "Spotify sign-in was cancelled." : "Spotify did not sign you in. Check the Client ID and the redirect URI.")
            return
        }

        requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]) { [weak self] token in
            guard let self else { return }
            guard let token, let refresh = token.refreshToken else {
                self.status = .failed("Spotify did not hand over a sign-in. Try again.")
                return
            }
            SpotifyKeychain.saveRefreshToken(refresh)
            self.store(token)
            self.status = .connected
        }
    }

    // MARK: Tokens

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.accessToken
        // A minute early, so a request never sets off with a token about to lapse.
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(max(token.expiresIn - 60, 0)))
    }

    private func requestToken(_ form: [String: String], completion: @escaping @MainActor (TokenResponse?) -> Void) {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        let body = form
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
        http.fetch(url, headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data(body.utf8)) { data in
            let token = data.flatMap { try? JSONDecoder().decode(TokenResponse.self, from: $0) }
            Task { @MainActor in completion(token) }
        }
    }

    /// The access token, refreshed first if it has lapsed. Nil when not signed in or Spotify
    /// cannot be reached.
    private func withAccessToken(_ body: @escaping @MainActor (String?) -> Void) {
        if let accessToken, Date() < accessTokenExpiry {
            body(accessToken)
            return
        }
        guard let refresh = SpotifyKeychain.refreshToken() else {
            body(nil)
            return
        }
        requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID().trimmingCharacters(in: .whitespacesAndNewlines),
        ]) { [weak self] token in
            guard let self, let token else { body(nil); return }
            // Spotify may hand back a new refresh token, in which case the old one is spent.
            if let newRefresh = token.refreshToken { SpotifyKeychain.saveRefreshToken(newRefresh) }
            self.store(token)
            body(token.accessToken)
        }
    }

    // MARK: The queue

    private struct QueueResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Image: Decodable { let url: String; let width: Int? }
            struct Album: Decodable { let images: [Image]? }
            struct Show: Decodable { let name: String; let images: [Image]? }
            let name: String
            let artists: [Artist]?
            let album: Album?
            let show: Show?
        }
        let queue: [Item]?
    }

    /// The next few songs, or why they cannot be listed. Calls back on the main actor.
    func fetchQueue(limit: Int, completion: @escaping @MainActor (UpNextState) -> Void) {
        guard isConnected else {
            completion(.unavailable("Connect Spotify in Settings > Music to see what's next."))
            return
        }
        withAccessToken { [weak self] token in
            guard let self, let token, let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
                completion(.unavailable("Couldn't reach Spotify."))
                return
            }
            self.http.fetch(url, headers: ["Authorization": "Bearer \(token)"]) { data in
                let response = data.flatMap { try? JSONDecoder().decode(QueueResponse.self, from: $0) }
                Task { @MainActor in
                    guard let response else {
                        completion(.unavailable("Couldn't reach Spotify."))
                        return
                    }
                    let items = (response.queue ?? []).prefix(limit).map { item in
                        let images = item.album?.images ?? item.show?.images ?? []
                        // The smallest cover that is still sharp at the peek's size.
                        let image = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
                            .first { ($0.width ?? 0) >= 64 } ?? images.last
                        return UpNextItem(
                            title: item.name,
                            artist: item.artists?.map(\.name).joined(separator: ", ") ?? item.show?.name ?? "",
                            artworkURL: image.flatMap { URL(string: $0.url) }
                        )
                    }
                    completion(items.isEmpty ? .unavailable("Nothing queued in Spotify.") : .loaded(Array(items)))
                }
            }
        }
    }

    /// A cover from Spotify's image host. Calls back on the main actor.
    func loadImage(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) {
        imageHTTP.fetch(url) { data in
            Task { @MainActor in completion(data.flatMap(NSImage.init(data:))) }
        }
    }

    // MARK: PKCE

    /// 64 characters from the set the PKCE specification allows.
    private static func makeVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension SpotifyAccount: ASWebAuthenticationPresentationContextProviding {
    /// The window the sign-in sheet hangs from: Settings, where Connect was clicked.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) ?? ASPresentationAnchor()
        }
    }
}

/// The Spotify refresh token, in the login keychain. The only secret MiniNotch keeps.
enum SpotifyKeychain {
    private static let service = "com.minnotch.MinNotch.spotify"
    private static let account = "refresh-token"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func refreshToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveRefreshToken(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "MiniNotch Spotify sign-in"
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func deleteRefreshToken() {
        SecItemDelete(query as CFDictionary)
    }
}
