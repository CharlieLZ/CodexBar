import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite("Codex weekly reset source transitions")
struct CodexWeeklyResetSourceTransitionTests {
    @Test
    func `exact oauth zero-credit evidence replaces a stale cli baseline`() async throws {
        let email = "stale-cli-baseline@example.com"
        let now = Date()
        let previousReset = now.addingTimeInterval(4 * 24 * 60 * 60)
        let currentReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(
            email: email,
            weeklyUsedPercent: 100,
            weeklyReset: previousReset,
            updatedAt: now.addingTimeInterval(-120))
        let initial = self.snapshot(
            email: email,
            weeklyUsedPercent: 1,
            weeklyReset: currentReset,
            updatedAt: now.addingTimeInterval(-60),
            resetCredits: self.emptyResetCredits(capturedAt: now.addingTimeInterval(-60)),
            dataConfidence: .exact)
        let confirmation = self.snapshot(
            email: email,
            weeklyUsedPercent: 1,
            weeklyReset: currentReset.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(-59),
            resetCredits: self.emptyResetCredits(capturedAt: now.addingTimeInterval(-59)),
            dataConfidence: .exact)

        let admission = await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: self.fetchOutcome(initial),
            previousSnapshot: previous,
            previousSourceLabel: "codex-cli",
            missingWindowBackfillSnapshot: nil,
            fetchConfirmation: { self.fetchOutcome(confirmation) })
        let outcome = try #require(admission.outcome)
        let result = try outcome.result.get()

        #expect(result.usage.secondary?.usedPercent == 1)
        #expect(result.usage.secondary?.resetsAt == confirmation.secondary?.resetsAt)
        #expect(admission.pendingCandidate == nil)
    }

    @Test
    func `stale cli baseline stays private when confirmation omits credit evidence`() async {
        let email = "incomplete-credit-evidence@example.com"
        let now = Date()
        let previousReset = now.addingTimeInterval(4 * 24 * 60 * 60)
        let currentReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let previous = self.snapshot(
            email: email,
            weeklyUsedPercent: 100,
            weeklyReset: previousReset,
            updatedAt: now.addingTimeInterval(-120))
        let initial = self.snapshot(
            email: email,
            weeklyUsedPercent: 1,
            weeklyReset: currentReset,
            updatedAt: now.addingTimeInterval(-60),
            resetCredits: self.emptyResetCredits(capturedAt: now.addingTimeInterval(-60)),
            dataConfidence: .exact)
        let confirmation = self.snapshot(
            email: email,
            weeklyUsedPercent: 1,
            weeklyReset: currentReset.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(-59),
            dataConfidence: .exact)

        let admission = await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: self.fetchOutcome(initial),
            previousSnapshot: previous,
            previousSourceLabel: "codex-cli",
            missingWindowBackfillSnapshot: nil,
            fetchConfirmation: { self.fetchOutcome(confirmation) })

        #expect(admission.outcome == nil)
        #expect(admission.pendingCandidate == nil)
    }

    private func snapshot(
        email: String,
        weeklyUsedPercent: Double,
        weeklyReset: Date,
        updatedAt: Date,
        resetCredits: CodexRateLimitResetCreditsSnapshot? = nil,
        dataConfidence: UsageDataConfidence = .unknown) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: updatedAt.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: weeklyUsedPercent,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil),
            codexResetCredits: resetCredits,
            updatedAt: updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "Pro"),
            dataConfidence: dataConfidence)
    }

    private func emptyResetCredits(capturedAt: Date) -> CodexRateLimitResetCreditsSnapshot {
        CodexRateLimitResetCreditsSnapshot(
            credits: [],
            availableCount: 0,
            updatedAt: capturedAt)
    }

    private func fetchOutcome(_ snapshot: UsageSnapshot) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: snapshot,
                credits: nil,
                dashboard: nil,
                sourceLabel: "oauth",
                strategyID: "weekly-reset-source-transition-test",
                strategyKind: .oauth)),
            attempts: [])
    }
}
