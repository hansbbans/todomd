import Foundation
import Security
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum GoogleCalendarServiceError: LocalizedError {
    case missingClientID
    case unavailableOnPlatform
    case cancelled
    case invalidAuthResponse
    case missingAuthorizationCode
    case tokenUnavailable
    case tokenRefreshFailed
    case invalidServerResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing Google OAuth Client ID."
        case .unavailableOnPlatform:
            return "Google sign-in is unavailable on this platform."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidAuthResponse:
            return "Received an invalid authentication response."
        case .missingAuthorizationCode:
            return "Google sign-in did not return an authorization code."
        case .tokenUnavailable:
            return "Google access token is unavailable."
        case .tokenRefreshFailed:
            return "Google token refresh failed."
        case .invalidServerResponse:
            return "Google Calendar returned an invalid response."
        case .serverError(let message):
            return message
        }
    }
}

@MainActor
final class GoogleCalendarService {
    fileprivate struct OAuthToken: Codable {
        var accessToken: String
        var refreshToken: String?
        var tokenType: String
        var scope: String?
        var expiresAt: Date
    }

    private struct OAuthTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        let scope: String?
        let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
            case tokenType = "token_type"
        }
    }

    private struct GoogleCalendarListResponse: Decodable {
        struct CalendarItem: Decodable {
            let id: String
            let summary: String?
            let backgroundColor: String?
            let selected: Bool?
        }

        let items: [CalendarItem]?
    }

    private struct GoogleEventsResponse: Decodable {
        struct EventDate: Decodable {
            let dateTime: String?
            let date: String?
        }

        struct EventItem: Decodable {
            let id: String
            let summary: String?
            let status: String?
            let start: EventDate?
            let end: EventDate?
        }

        let items: [EventItem]?
    }

    private let tokenStore = GoogleCalendarTokenStore()
    private let urlSession: URLSession
    private let isoDateFormatter = ISO8601DateFormatter()
    private let isoFractionDateFormatter: ISO8601DateFormatter
    private let plainDateFormatter: DateFormatter
#if canImport(AuthenticationServices)
    private var authSession: ASWebAuthenticationSession?
    private let authPresentationProvider = OAuthPresentationProvider()
#endif

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.plainDateFormatter = formatter
        let fractionFormatter = ISO8601DateFormatter()
        fractionFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFractionDateFormatter = fractionFormatter
    }

    var isConnected: Bool {
        (try? tokenStore.loadToken()) != nil
    }

    func disconnect() {
        try? tokenStore.clear()
    }

    func connect(clientID: String, redirectURI: String) async throws {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else { throw GoogleCalendarServiceError.missingClientID }
        guard !normalizedRedirectURI.isEmpty else { throw GoogleCalendarServiceError.invalidAuthResponse }

        let callbackScheme = URL(string: normalizedRedirectURI)?.scheme
        guard let callbackScheme, !callbackScheme.isEmpty else {
            throw GoogleCalendarServiceError.invalidAuthResponse
        }

        let codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.makeCodeChallenge(verifier: codeVerifier)
        let scope = [
            "openid",
            "email",
            "profile",
            "https://www.googleapis.com/auth/calendar.readonly"
        ].joined(separator: " ")
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: normalizedClientID),
            URLQueryItem(name: "redirect_uri", value: normalizedRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components?.url else {
            throw GoogleCalendarServiceError.invalidAuthResponse
        }

        let callbackURL = try await beginAuthorizationSession(authURL: authURL, callbackScheme: callbackScheme)
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarServiceError.invalidAuthResponse
        }

        if let authError = callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value {
            if authError == "access_denied" {
                throw GoogleCalendarServiceError.cancelled
            }
            throw GoogleCalendarServiceError.serverError("Google sign-in failed: \(authError)")
        }

        guard let authCode = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              !authCode.isEmpty else {
            throw GoogleCalendarServiceError.missingAuthorizationCode
        }

        let token = try await exchangeAuthorizationCode(
            clientID: normalizedClientID,
            redirectURI: normalizedRedirectURI,
            code: authCode,
            codeVerifier: codeVerifier
        )
        try tokenStore.saveToken(token)
    }

    func fetchUpcomingEvents(
        clientID: String,
        redirectURI: String,
        startDate: Date,
        endDate: Date,
        allowedCalendarIDs: Set<String>? = nil
    ) async throws -> (sources: [CalendarSource], events: [CalendarEventItem]) {
        guard startDate < endDate else { return ([], []) }
        let accessToken = try await validAccessToken(clientID: clientID, redirectURI: redirectURI)
        let calendars = try await fetchCalendarList(accessToken: accessToken)
        let sources = calendars.map {
            CalendarSource(
                id: $0.id,
                name: $0.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Calendar",
                colorHex: $0.backgroundColor ?? "#3B82F6",
                isDefaultSelected: $0.selected ?? true
            )
        }

        let selectedCalendars: [GoogleCalendarListResponse.CalendarItem]
        if let allowedCalendarIDs {
            selectedCalendars = calendars.filter { allowedCalendarIDs.contains($0.id) }
        } else {
            selectedCalendars = calendars
        }

        guard !selectedCalendars.isEmpty else { return (sources, []) }

        var results: [CalendarEventItem] = []
        results.reserveCapacity(200)

        for calendar in selectedCalendars {
            let events = try await fetchEvents(
                accessToken: accessToken,
                calendarID: calendar.id,
                calendarName: calendar.summary ?? "Calendar",
                calendarColorHex: calendar.backgroundColor ?? "#3B82F6",
                startDate: startDate,
                endDate: endDate
            )
            results.append(contentsOf: events)
        }

        return (sources, results.sorted(by: Self.eventSort))
    }

    private func validAccessToken(clientID: String, redirectURI: String) async throws -> String {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else { throw GoogleCalendarServiceError.missingClientID }
        guard !normalizedRedirectURI.isEmpty else { throw GoogleCalendarServiceError.invalidAuthResponse }

        var token = try tokenStore.loadToken()
        let refreshWindow = Date().addingTimeInterval(60)
        if token.expiresAt <= refreshWindow {
            guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
                throw GoogleCalendarServiceError.tokenRefreshFailed
            }
            token = try await refreshAccessToken(
                refreshToken: refreshToken,
                clientID: normalizedClientID,
                redirectURI: normalizedRedirectURI,
                existing: token
            )
            try tokenStore.saveToken(token)
        }

        return token.accessToken
    }

    private func fetchCalendarList(accessToken: String) async throws -> [GoogleCalendarListResponse.CalendarItem] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
        components?.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "showDeleted", value: "false")
        ]
        guard let url = components?.url else { throw GoogleCalendarServiceError.invalidServerResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        return decoded.items ?? []
    }

    private func fetchEvents(
        accessToken: String,
        calendarID: String,
        calendarName: String,
        calendarColorHex: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [CalendarEventItem] {
        let escapedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(escapedCalendarID)/events")
        components?.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: isoDateFormatter.string(from: startDate)),
            URLQueryItem(name: "timeMax", value: isoDateFormatter.string(from: endDate)),
            URLQueryItem(name: "maxResults", value: "2500"),
            URLQueryItem(name: "showDeleted", value: "false")
        ]
        guard let url = components?.url else { throw GoogleCalendarServiceError.invalidServerResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
        let events = decoded.items ?? []

        return events.compactMap { event in
            guard event.status != "cancelled",
                  let start = event.start,
                  let end = event.end,
                  let parsedStart = parseGoogleDate(start),
                  let parsedEnd = parseGoogleDate(end) else {
                return nil
            }

            let isAllDay = (start.date != nil)
            return CalendarEventItem(
                id: "\(calendarID)::\(event.id)",
                calendarID: calendarID,
                calendarName: calendarName,
                calendarColorHex: calendarColorHex,
                title: event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Event",
                startDate: parsedStart,
                endDate: parsedEnd,
                isAllDay: isAllDay
            )
        }
    }

    private func parseGoogleDate(_ payload: GoogleEventsResponse.EventDate) -> Date? {
        if let dateTime = payload.dateTime {
            if let parsed = isoDateFormatter.date(from: dateTime) {
                return parsed
            }
            return isoFractionDateFormatter.date(from: dateTime)
        }
        if let date = payload.date, let parsed = plainDateFormatter.date(from: date) {
            return parsed
        }
        return nil
    }

    private func exchangeAuthorizationCode(
        clientID: String,
        redirectURI: String,
        code: String,
        codeVerifier: String
    ) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            tokenType: decoded.tokenType,
            scope: decoded.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }

    private func refreshAccessToken(
        refreshToken: String,
        clientID: String,
        redirectURI: String,
        existing: OAuthToken
    ) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "refresh_token": refreshToken,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? existing.refreshToken,
            tokenType: decoded.tokenType,
            scope: decoded.scope ?? existing.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarServiceError.invalidServerResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let payload = String(data: data, encoding: .utf8), !payload.isEmpty {
                throw GoogleCalendarServiceError.serverError("Google API error (\(http.statusCode)): \(payload)")
            }
            throw GoogleCalendarServiceError.serverError("Google API error (\(http.statusCode)).")
        }
    }

    private func formEncodedBody(_ fields: [String: String]) -> Data? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields
            .map { key, value -> String in
                let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(escapedKey)=\(escapedValue)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }

    private static func eventSort(lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func makeCodeVerifier() -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<96).compactMap { _ in charset.randomElement() })
    }

    private static func makeCodeChallenge(verifier: String) -> String {
#if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let data = Data(digest)
        return data.base64URLEncodedString()
#else
        return verifier
#endif
    }

    private func beginAuthorizationSession(authURL: URL, callbackScheme: String) async throws -> URL {
#if canImport(AuthenticationServices)
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleCalendarServiceError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleCalendarServiceError.invalidAuthResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = authPresentationProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: GoogleCalendarServiceError.invalidAuthResponse)
            }
        }
#else
        throw GoogleCalendarServiceError.unavailableOnPlatform
#endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        let base64 = base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class GoogleCalendarTokenStore {
    private let service = "com.hans.todomd.google-calendar"
    private let account = "oauth-token"

    func loadToken() throws -> GoogleCalendarService.OAuthToken {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw GoogleCalendarServiceError.tokenUnavailable
        }

        return try JSONDecoder().decode(GoogleCalendarService.OAuthToken.self, from: data)
    }

    func saveToken(_ token: GoogleCalendarService.OAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GoogleCalendarServiceError.tokenUnavailable
            }
            return
        }

        throw GoogleCalendarServiceError.tokenUnavailable
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#if canImport(AuthenticationServices) && canImport(UIKit)
private final class OAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
#endif

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
