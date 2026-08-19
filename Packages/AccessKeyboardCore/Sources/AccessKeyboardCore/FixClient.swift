import Foundation

public enum FixStatus: Equatable {
    case idle
    case running
    case failed
}

public enum FixError: Error, Equatable {
    case empty
    case secureField
    case unavailable
    case requestFailed
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
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(FixRequestBody(text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FixError.requestFailed
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
