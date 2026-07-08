import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Runs the Google OAuth 2.0 Authorization Code flow with PKCE for a public
/// (no client secret) "iOS"-style OAuth client. The user supplies the Client ID
/// at runtime, so nothing is hardcoded here.
///
/// The consent step is driven by `ASWebAuthenticationSession`; the resulting
/// authorization code is exchanged for tokens against Google's token endpoint.
/// The long-lived refresh token and the Client ID are persisted in the login
/// Keychain so the connection survives relaunches; the short-lived access token
/// is only cached in memory and silently refreshed when it nears expiry.
@MainActor
final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthService()

    /// App-bundled Google OAuth Client ID (an "iOS"-type client, PKCE — no secret).
    /// When non-empty, end users connect with one click and never paste an ID; the
    /// per-user "Advanced → Custom OAuth Client ID" field overrides this when set.
    /// Fill in with your Google Cloud iOS OAuth client ID to enable the one-click flow.
    /// The open-source distribution ships empty: each user (or fork) supplies their
    /// own client ID — see README → "Google Calendar setup".
    static let bundledClientID = ""

    private let store = KeychainStore(service: "com.xeneonedgewidgets.googleauth")
    private let refreshTokenKey = "refresh_token"
    private let clientIDKey = "client_id"

    /// Retains the in-flight session so it is not deallocated mid-flow. ASWeb-
    /// AuthenticationSession is cancelled if its owner is released.
    private var activeSession: ASWebAuthenticationSession?
    /// The anchor the consent sheet attaches to for the current flow, resolved on
    /// the main actor *before* the session starts.
    ///
    /// `nonisolated(unsafe)` so the `nonisolated` `presentationAnchor(for:)`
    /// protocol requirement can return it without hopping actors. This is safe in
    /// practice: AuthenticationServices only invokes that callback on the main
    /// thread, and the property is only written on the main actor while a flow is
    /// in progress (set before `session.start()`, cleared after it returns).
    private nonisolated(unsafe) var presentationAnchor: ASPresentationAnchor?

    /// In-memory access token cache. Never persisted — only the refresh token is.
    private var cachedAccessToken: String?
    private var accessTokenExpiry: Date?

    private override init() {
        super.init()
    }

    // MARK: - Contract

    /// `true` when a refresh token is stored, i.e. a Google account has been
    /// connected and the link has not been revoked locally.
    var isConnected: Bool {
        store.read(refreshTokenKey) != nil
    }

    /// Runs the interactive PKCE consent flow, exchanges the authorization code
    /// for tokens, and persists the refresh token + Client ID to the Keychain.
    func connect(clientID: String, presentationAnchor: NSWindow?) async throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw GoogleAuthError.missingClientID
        }

        let scheme = Self.redirectScheme(for: clientID)
        let redirectURI = scheme + ":/oauth2redirect"

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        guard let authURL = Self.makeAuthorizationURL(
            clientID: clientID,
            redirectURI: redirectURI,
            codeChallenge: challenge
        ) else {
            throw GoogleAuthError.invalidAuthorizationURL
        }

        // Resolve the anchor on the main actor now so the nonisolated context
        // provider callback can return it without touching main-actor state.
        let anchor: ASPresentationAnchor = presentationAnchor ?? NSApp.keyWindow ?? ASPresentationAnchor()
        self.presentationAnchor = anchor
        defer {
            self.presentationAnchor = nil
            self.activeSession = nil
        }

        let callbackURL = try await presentConsent(authURL: authURL, callbackScheme: scheme)
        let code = try Self.authorizationCode(from: callbackURL)

        let tokens = try await exchangeAuthorizationCode(
            code: code,
            verifier: verifier,
            clientID: clientID,
            redirectURI: redirectURI
        )

        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            // access_type=offline + prompt=consent should always return one; if it
            // does not we cannot persist the link, so surface a clear failure.
            throw GoogleAuthError.missingRefreshToken
        }

        store.write(refreshToken, for: refreshTokenKey)
        store.write(clientID, for: clientIDKey)
        cacheAccessToken(tokens.accessToken, expiresIn: tokens.expiresIn)
    }

    /// Returns a non-expired access token, transparently refreshing it via the
    /// stored refresh token when the cached one is missing or about to expire.
    func validAccessToken() async throws -> String {
        if let token = cachedAccessToken,
           let expiry = accessTokenExpiry,
           expiry.timeIntervalSinceNow > 60 {
            return token
        }

        guard let refreshToken = store.read(refreshTokenKey) else {
            throw GoogleAuthError.notConnected
        }
        guard let clientID = store.read(clientIDKey) else {
            throw GoogleAuthError.missingClientID
        }

        let tokens: TokenResponse
        do {
            tokens = try await refreshAccessToken(refreshToken: refreshToken, clientID: clientID)
        } catch let error as GoogleAuthError {
            // A 400 invalid_grant means the stored refresh token is revoked/expired
            // (user removed app access, password change, rotation loss, inactivity).
            // It will never succeed again, so clear the stored link — this flips
            // isConnected to false so the UI prompts a fresh re-consent instead of
            // staying falsely "connected" but permanently non-functional.
            if case .tokenRequestFailed(let status, _) = error, status == 400 {
                disconnect()
            }
            throw error
        }

        // Google may rotate the refresh token and return a new one in the refresh
        // response. Persist it so the next refresh uses the current token; otherwise
        // the old token eventually becomes invalid and the connection silently bricks.
        if let rotated = tokens.refreshToken, !rotated.isEmpty {
            store.write(rotated, for: refreshTokenKey)
        }

        cacheAccessToken(tokens.accessToken, expiresIn: tokens.expiresIn)
        return tokens.accessToken
    }

    /// Clears all stored tokens, disconnecting the account. The Google-side grant
    /// is not revoked; the user can do that from their Google account if desired.
    func disconnect() {
        store.delete(refreshTokenKey)
        store.delete(clientIDKey)
        cachedAccessToken = nil
        accessTokenExpiry = nil
    }

    // MARK: - Consent flow

    private func presentConsent(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            // Box the non-Sendable continuation so the @Sendable completion handler can
            // carry it. CRITICAL: this handler must be NONISOLATED and touch no main-actor
            // state. AuthenticationServices may invoke it off the main thread (e.g. on its
            // XPC reply queue during _startDryRun); a main-actor-isolated handler — or even
            // a `Task { @MainActor … }` hop inside it — trips Swift's executor isolation
            // check and crashes (SIGTRAP). Resuming a continuation is safe from any thread,
            // and the awaiting connect() resumes back on the main actor.
            let box = ConsentContinuationBox(continuation: continuation)

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { @Sendable callbackURL, error in
                if let error {
                    box.continuation.resume(throwing: Self.mapConsentError(error))
                } else if let callbackURL {
                    box.continuation.resume(returning: callbackURL)
                } else {
                    box.continuation.resume(throwing: GoogleAuthError.consentFailed("No callback URL returned."))
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session

            if !session.start() {
                activeSession = nil
                continuation.resume(
                    throwing: GoogleAuthError.consentFailed("Could not start the sign-in session.")
                )
            }
        }
    }

    /// Maps an ASWebAuthenticationSession error to a GoogleAuthError. Nonisolated and
    /// static so the off-main completion handler can call it without isolation hops.
    private nonisolated static func mapConsentError(_ error: any Error) -> any Error {
        if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
            return GoogleAuthError.userCancelled
        }
        return GoogleAuthError.consentFailed(error.localizedDescription)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        // Called by AuthenticationServices on the main thread. Return the anchor
        // resolved on the main actor before the session started; the empty-anchor
        // fallback only applies if the callback somehow fires outside a flow, and is
        // built under assumeIsolated since this callback is always on the main thread.
        if let presentationAnchor { return presentationAnchor }
        return MainActor.assumeIsolated { ASPresentationAnchor() }
    }

    // MARK: - Token endpoints

    private func exchangeAuthorizationCode(
        code: String,
        verifier: String,
        clientID: String,
        redirectURI: String
    ) async throws -> TokenResponse {
        try await Self.postTokenRequest(form: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID,
            "redirect_uri": redirectURI
        ])
    }

    private func refreshAccessToken(
        refreshToken: String,
        clientID: String
    ) async throws -> TokenResponse {
        try await Self.postTokenRequest(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
    }

    private func cacheAccessToken(_ token: String, expiresIn: Int?) {
        cachedAccessToken = token
        // Default to Google's typical 3600s lifetime when the server omits it.
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn ?? 3600))
    }

    // MARK: - Networking (off the main actor)

    /// Performs the form-encoded POST against Google's token endpoint. `nonisolated`
    /// + a local `URLSession` keeps the network round-trip off the main actor; the
    /// decoded value is returned to the awaiting `@MainActor` caller.
    private nonisolated static func postTokenRequest(form: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleAuthError.invalidAuthorizationURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 15
        request.httpBody = formEncode(form).data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GoogleAuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GoogleAuthError.tokenRequestFailed(status: -1, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(TokenErrorResponse.self, from: data))?.combinedMessage
            throw GoogleAuthError.tokenRequestFailed(status: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleAuthError.tokenDecodingFailed
        }
    }

    private nonisolated static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    // MARK: - URL construction

    /// For a Client ID like `NNN-XXX.apps.googleusercontent.com` the reversed
    /// scheme is `com.googleusercontent.apps.NNN-XXX`.
    private nonisolated static func redirectScheme(for clientID: String) -> String {
        let suffix = ".apps.googleusercontent.com"
        let identifier: String
        if clientID.hasSuffix(suffix) {
            identifier = String(clientID.dropLast(suffix.count))
        } else {
            identifier = clientID
        }
        return "com.googleusercontent.apps.\(identifier)"
    }

    private nonisolated static func makeAuthorizationURL(
        clientID: String,
        redirectURI: String,
        codeChallenge: String
    ) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.readonly"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }

    private nonisolated static func authorizationCode(from callbackURL: URL) throws -> String {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw GoogleAuthError.consentFailed(error)
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw GoogleAuthError.missingAuthorizationCode
        }
        return code
    }

    // MARK: - PKCE

    /// Generates a 43–128 character URL-safe code verifier per RFC 7636.
    private nonisolated static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fall back to a still-unpredictable source if SecRandom is unavailable.
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
            }
        }
        return base64URLEncode(Data(bytes))
    }

    /// `code_challenge = base64url(SHA256(verifier))`.
    private nonisolated static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private nonisolated static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Continuation box

/// Boxes the non-Sendable `CheckedContinuation` so it can be captured by the
/// `@Sendable` `ASWebAuthenticationSession` completion handler. Safe because the
/// continuation is only ever resumed back on the main actor (in `finishConsent`).
private struct ConsentContinuationBox: @unchecked Sendable {
    let continuation: CheckedContinuation<URL, Error>
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case missingClientID
    case invalidAuthorizationURL
    case userCancelled
    case consentFailed(String)
    case missingAuthorizationCode
    case missingRefreshToken
    case notConnected
    case network(String)
    case tokenRequestFailed(status: Int, message: String?)
    case tokenDecodingFailed

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Enter your Google OAuth Client ID first."
        case .invalidAuthorizationURL:
            return "Could not build the Google sign-in request."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .consentFailed(let detail):
            return "Google sign-in failed: \(detail)"
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .missingRefreshToken:
            return "Google did not return a refresh token. Try removing the app's access in your Google account and connecting again."
        case .notConnected:
            return "No Google account is connected."
        case .network(let detail):
            return "Network error contacting Google: \(detail)"
        case .tokenRequestFailed(let status, let message):
            if let message, !message.isEmpty {
                return "Google rejected the token request (\(status)): \(message)"
            }
            return "Google rejected the token request (HTTP \(status))."
        case .tokenDecodingFailed:
            return "Could not read Google's token response."
        }
    }
}

// MARK: - Token response models

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    var combinedMessage: String? {
        [error, errorDescription]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " — ")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Keychain

/// Minimal Keychain wrapper over `kSecClassGenericPassword`, scoped to a single
/// service. Stores small UTF-8 string secrets (the refresh token and Client ID).
private struct KeychainStore {
    let service: String

    func read(_ account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func write(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func delete(_ account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
