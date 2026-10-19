import Foundation

public enum FixStatus: Equatable {
    case idle
    case running
    case failed
}

/// A short, non-blocking explanation on the suggestion bar. Typing stays available.
public enum FixNotice: Equatable {
    case none
    case fullAccess
    case offline
    case secureField
    case unavailable
    case subscribe
    case consent
    /// The server says this Apple Account has used its free Fixes this month.
    case freeLimit
    /// The server's fair-use cap for Pro was reached today.
    case dailyLimit
    /// Too many Fixes in a short time. Try again shortly.
    case busy

    public var message: String {
        switch self {
        case .none:
            return ""
        case .fullAccess:
            return "Turn on Allow Full Access to use Fix. Typing still works."
        case .offline:
            return "Fix needs a network connection. Typing stays on this device."
        case .secureField:
            return "Passwords are not sent."
        case .unavailable:
            return "Fix isn’t set up in this build. Typing still works."
        case .subscribe:
            return "Get Pro in the access: keyboard app to use Fix. Typing still works."
        case .freeLimit:
            return "You have used your \(SubscriptionConfig.freeFixesPerMonth) free Fixes this month. Get Pro in the app for more. Typing still works."
        case .dailyLimit:
            return "You have reached today’s limit of \(SubscriptionConfig.proFixesPerDay) Fixes. It resets tomorrow. Typing still works."
        case .busy:
            return "Fix is busy. Try again in a minute. Typing still works."
        case .consent:
            return "Fix sends this paragraph to OpenAI, an AI service, to correct it. Each Fix costs us money. Nothing is sent until you tap Allow."
        }
    }

    /// Hints that should disappear on the next keystroke. Consent stays until Allow or Not now.
    public var isTransient: Bool {
        switch self {
        case .fullAccess, .offline, .secureField, .unavailable, .subscribe, .freeLimit, .dailyLimit, .busy:
            return true
        case .none, .consent:
            return false
        }
    }
}

public enum FixError: Error, Equatable {
    case empty
    case secureField
    case unavailable
    case requestFailed
    /// HTTP 429 from the proxy with `{"error":"free_limit"}`.
    case freeLimitReached
    /// HTTP 429 with `{"error":"daily_limit"}`.
    case dailyLimitReached
    /// HTTP 429 with `{"error":"rate_limited"}`.
    case rateLimited

    /// Maps a proxy response that was not a success to an error.
    public static func fromProxy(status: Int, body: Data?) -> FixError {
        guard status == 429 else { return .requestFailed }
        let code = body
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["error"] as? String }
        switch code {
        case "free_limit": return .freeLimitReached
        case "daily_limit": return .dailyLimitReached
        default: return .rateLimited
        }
    }
}

/// Signed StoreKit data the containing app shares with the keyboard so the Fix
/// proxy can check Pro or count free Fixes. These are Apple-signed JWS strings,
/// not secrets: the proxy verifies Apple's signature, so they cannot be forged.
public enum FixCredentials {
    public static let appTransactionKey = "fixSignedAppTransaction"
    public static let transactionKey = "fixSignedTransaction"
    public static let appTransactionHeader = "X-AK-App-Transaction"
    public static let transactionHeader = "X-AK-Transaction"

    public static func write(appTransaction: String?, transaction: String?, to defaults: UserDefaults = KeyboardPreferences.suite) {
        defaults.set(appTransaction, forKey: appTransactionKey)
        defaults.set(transaction, forKey: transactionKey)
    }

    public static func read(from defaults: UserDefaults = KeyboardPreferences.suite) -> (appTransaction: String?, transaction: String?) {
        (defaults.string(forKey: appTransactionKey), defaults.string(forKey: transactionKey))
    }

    /// Headers for one Fix request. Empty values are left out.
    public static func headers(from defaults: UserDefaults = KeyboardPreferences.suite) -> [String: String] {
        let stored = read(from: defaults)
        var headers: [String: String] = [:]
        if let value = stored.appTransaction, !value.isEmpty { headers[appTransactionHeader] = value }
        if let value = stored.transaction, !value.isEmpty { headers[transactionHeader] = value }
        return headers
    }
}

public protocol FixClient: Sendable {
    func fix(_ text: String) async throws -> String
}

public struct URLSessionFixClient: FixClient {
    public let endpoint: URL
    public let secret: String

    public init(endpoint: URL, secret: String) {
        self.endpoint = endpoint
        self.secret = secret
    }

    public static func configuredEndpointString(from bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: "AKFixProxyURL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> URLSessionFixClient? {
        guard let trimmed = configuredEndpointString(from: bundle),
              let endpoint = URL(string: trimmed) else {
            return nil
        }
        guard let rawSecret = bundle.object(forInfoDictionaryKey: "AKFixProxySecret") as? String else {
            return nil
        }
        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            return nil
        }
        return URLSessionFixClient(endpoint: endpoint, secret: secret)
    }

    public func fix(_ text: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        for (name, value) in FixCredentials.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(FixRequestBody(text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FixError.requestFailed
        }
        guard http.statusCode == 200 else {
            throw FixError.fromProxy(status: http.statusCode, body: data)
        }
        let body = try JSONDecoder().decode(FixResponseBody.self, from: data)
        let corrected = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else {
            throw FixError.requestFailed
        }
        return body.text
    }
}

private struct FixRequestBody: Encodable {
    var text: String
}

private struct FixResponseBody: Decodable {
    var text: String
}
