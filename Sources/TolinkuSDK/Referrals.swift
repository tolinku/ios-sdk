import Foundation

/// Provides referral management (create, get, complete, milestone, leaderboard, claim reward).
public final class Referrals: Sendable {

    private let client: Client

    init(client: Client) {
        self.client = client
    }

    /// Create a new referral for the given user.
    ///
    /// - Parameters:
    ///   - userId: The ID of the referring user.
    ///   - metadata: Optional metadata to attach to the referral.
    ///   - userName: Optional display name for the referring user.
    /// - Returns: The created referral details.
    public func create(
        userId: String,
        metadata: [String: AnyCodableValue]? = nil,
        userName: String? = nil
    ) async throws -> CreateReferralResponse {
        let body = CreateReferralRequest(userId: userId, metadata: metadata, userName: userName)
        return try await client.post(path: "/v1/api/referral/create", body: body)
    }

    /// Get information about an existing referral.
    ///
    /// - Parameter code: The referral code.
    /// - Returns: The referral details.
    public func get(code: String) async throws -> ReferralDetails {
        // Use urlPathAllowed minus characters that would break path routing (/, +, =, &, #, %)
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/+=#&?")
        guard let encodedCode = code.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw TolinkuError.invalidURL("Could not URL-encode referral code: \(code)")
        }
        return try await client.get(path: "/v1/api/referral/\(encodedCode)")
    }

    /// Complete a referral (mark a referred user as converted).
    ///
    /// - Parameters:
    ///   - code: The referral code.
    ///   - referredUserId: The ID of the referred (new) user.
    ///   - milestone: Optional milestone to record at the same time.
    ///   - referredUserName: Optional display name for the referred user.
    /// - Returns: The completion result.
    public func complete(
        code: String,
        referredUserId: String,
        milestone: String? = nil,
        referredUserName: String? = nil
    ) async throws -> CompleteReferralResponse {
        let body = CompleteReferralRequest(
            referralCode: code,
            referredUserId: referredUserId,
            milestone: milestone,
            referredUserName: referredUserName
        )
        return try await client.post(path: "/v1/api/referral/complete", body: body)
    }

    /// Update a milestone on a referral.
    ///
    /// - Parameters:
    ///   - code: The referral code.
    ///   - milestone: The milestone identifier (e.g. "first_purchase").
    /// - Returns: The milestone update result.
    public func milestone(code: String, milestone: String) async throws -> MilestoneResponse {
        let body = MilestoneRequest(referralCode: code, milestone: milestone)
        return try await client.post(path: "/v1/api/referral/milestone", body: body)
    }

    /// Fetch the referral leaderboard.
    ///
    /// - Parameter limit: Maximum number of entries to return (default determined by server).
    /// - Returns: An array of leaderboard entries.
    public func leaderboard(limit: Int? = nil) async throws -> [LeaderboardEntry] {
        var queryItems: [URLQueryItem]? = nil
        if let limit {
            queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        }
        let response: LeaderboardResponse = try await client.get(
            path: "/v1/api/referral/leaderboard",
            queryItems: queryItems
        )
        return response.leaderboard
    }

    /// Claim a reward for a referral.
    ///
    /// - Parameter code: The referral code to claim the reward for.
    /// - Returns: The claim result.
    public func claimReward(code: String) async throws -> ClaimRewardResponse {
        let body = ClaimRewardRequest(referralCode: code)
        return try await client.post(path: "/v1/api/referral/claim-reward", body: body)
    }
}
