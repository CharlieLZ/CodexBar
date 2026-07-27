import Foundation
import Testing
@testable import CodexBarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexSubscriptionTests {
    @Test
    func `request scopes subscription lookup to the selected account`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.url?.absoluteString ==
                "https://chatgpt.com/backend-api/subscriptions?account_id=account-123")
            #expect(request.httpMethod == "GET")
            #expect(request.timeoutInterval == 6)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://chatgpt.com")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mozilla/5.0") == true)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil))
            return (Data(#"{"active_until":"2026-08-08T09:34:05Z","will_renew":true}"#.utf8), response)
        }

        let metadata = try await CodexSubscriptionFetcher.fetch(
            accessToken: "test-token",
            accountId: "account-123",
            timeout: 6,
            session: transport)

        #expect(metadata?.renewsAt == Self.date("2026-08-08T09:34:05Z"))
        #expect(metadata?.expiresAt == nil)
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `cancelled subscription maps active until to plan expiry`() throws {
        let data = Data(#"{"active_until":"2026-08-24T13:17:48Z","will_renew":false}"#.utf8)

        let metadata = try #require(CodexSubscriptionFetcher._decodeForTesting(data))

        #expect(metadata.renewsAt == nil)
        #expect(metadata.expiresAt == Self.date("2026-08-24T13:17:48Z"))
    }

    @Test
    func `subscription metadata enriches the Codex usage snapshot`() throws {
        let usageJSON = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "secondary_window": {
              "used_percent": 5,
              "reset_at": 1785634177,
              "limit_window_seconds": 604800
            }
          }
        }
        """
        let credentials = CodexOAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: nil,
            accountId: "account-123",
            lastRefresh: nil)
        let renewal = Self.date("2026-08-08T09:34:05Z")

        let result = try CodexOAuthFetchStrategy._mapResultForTesting(
            Data(usageJSON.utf8),
            credentials: credentials,
            subscription: CodexSubscriptionMetadata(activeUntil: renewal, willRenew: true))

        #expect(result.usage.subscriptionRenewsAt == renewal)
        #expect(result.usage.subscriptionExpiresAt == nil)
    }

    @Test
    func `subscription lookup failure does not discard usage refresh`() async throws {
        let credentials = CodexOAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: nil,
            accountId: "account-123",
            lastRefresh: nil)

        let metadata = try await CodexOAuthFetchStrategy._fetchSubscriptionMetadataForTesting(
            credentials: credentials,
            fetcher: { _ in throw URLError(.timedOut) })

        #expect(metadata == nil)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
