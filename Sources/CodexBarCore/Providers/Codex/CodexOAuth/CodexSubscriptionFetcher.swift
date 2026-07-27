import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexSubscriptionMetadata: Equatable, Sendable {
    public let activeUntil: Date?
    public let willRenew: Bool?

    public init(activeUntil: Date?, willRenew: Bool?) {
        self.activeUntil = activeUntil
        self.willRenew = willRenew
    }

    public var renewsAt: Date? {
        self.willRenew == true ? self.activeUntil : nil
    }

    public var expiresAt: Date? {
        self.willRenew == false ? self.activeUntil : nil
    }
}

public enum CodexSubscriptionFetcher {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/subscriptions")!
    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    public static func fetch(
        accessToken: String,
        accountId: String?,
        timeout: TimeInterval = 8) async throws -> CodexSubscriptionMetadata?
    {
        try await self.fetch(
            accessToken: accessToken,
            accountId: accountId,
            timeout: timeout,
            session: CodexAuthenticatedHTTPTransport.current)
    }

    static func fetch(
        accessToken: String,
        accountId: String?,
        timeout: TimeInterval = 8,
        session transport: any ProviderHTTPTransport) async throws -> CodexSubscriptionMetadata?
    {
        guard let accountId = self.normalizedAccountID(accountId) else { return nil }
        guard var components = URLComponents(url: self.endpoint, resolvingAgainstBaseURL: false) else {
            throw CodexOAuthFetchError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "account_id", value: accountId)]
        guard let url = components.url else {
            throw CodexOAuthFetchError.invalidResponse
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // This is a ChatGPT web endpoint. Its edge protection rejects non-browser requests,
        // even when they carry a valid OAuth token and account scope.
        request.setValue(self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")

        do {
            let response = try await transport.response(for: request)
            switch response.statusCode {
            case 200...299:
                return try self.decode(response.data)
            case 401, 403:
                throw CodexOAuthFetchError.unauthorized
            default:
                let body = String(data: response.data, encoding: .utf8)
                throw CodexOAuthFetchError.serverError(response.statusCode, body)
            }
        } catch let error as CodexOAuthFetchError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw CodexOAuthFetchError.networkError(error)
        }
    }

    private static func decode(_ data: Data) throws -> CodexSubscriptionMetadata? {
        if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
        let response = try decoder.decode(SubscriptionResponse.self, from: data)
        guard response.activeUntil != nil || response.willRenew != nil else { return nil }
        return CodexSubscriptionMetadata(
            activeUntil: response.activeUntil,
            willRenew: response.willRenew)
    }

    private static func normalizedAccountID(_ accountId: String?) -> String? {
        guard let value = accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        seconds.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: raw) ?? seconds.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO-8601 date: \(raw)")
    }

    private struct SubscriptionResponse: Decodable {
        let activeUntil: Date?
        let willRenew: Bool?

        private enum CodingKeys: String, CodingKey {
            case activeUntil = "active_until"
            case willRenew = "will_renew"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.activeUntil = try container.decodeIfPresent(Date.self, forKey: .activeUntil)
            self.willRenew = Self.decodeFlexibleBool(container, forKey: .willRenew)
        }

        private static func decodeFlexibleBool(
            _ container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys) -> Bool?
        {
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value != 0
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    return nil
                }
            }
            return nil
        }
    }
}

#if DEBUG
extension CodexSubscriptionFetcher {
    static func _decodeForTesting(_ data: Data) throws -> CodexSubscriptionMetadata? {
        try self.decode(data)
    }
}
#endif
