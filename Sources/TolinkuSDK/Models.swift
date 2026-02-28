import Foundation

// MARK: - Analytics

/// Request body for tracking custom events.
public struct TrackEventRequest: Codable, Sendable {
    public let eventType: String
    public let properties: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case properties
    }

    public init(eventType: String, properties: [String: AnyCodableValue]? = nil) {
        self.eventType = eventType
        self.properties = properties
    }
}

/// A type-erased Codable value for use in property dictionaries.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        // Try keyed container (object) first.
        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict = [String: AnyCodableValue]()
            for key in keyedContainer.allKeys {
                dict[key.stringValue] = try keyedContainer.decode(AnyCodableValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        // Try unkeyed container (array).
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var arr = [AnyCodableValue]()
            while !unkeyedContainer.isAtEnd {
                arr.append(try unkeyedContainer.decode(AnyCodableValue.self))
            }
            self = .array(arr)
            return
        }

        let container = try decoder.singleValueContainer()
        // Decode Int before Bool to avoid integer 0/1 being misinterpreted as Bool.
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported type"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// A dynamic coding key for decoding arbitrary JSON object keys.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Referrals

/// Request body for creating a referral.
public struct CreateReferralRequest: Codable, Sendable {
    public let userId: String
    public let metadata: [String: AnyCodableValue]?
    public let userName: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case metadata
        case userName = "user_name"
    }

    public init(userId: String, metadata: [String: AnyCodableValue]? = nil, userName: String? = nil) {
        self.userId = userId
        self.metadata = metadata
        self.userName = userName
    }
}

/// Response from creating a referral.
public struct CreateReferralResponse: Codable, Sendable {
    public let referralCode: String
    public let referralUrl: String?
    public let referralId: String

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
        case referralUrl = "referral_url"
        case referralId = "referral_id"
    }
}

/// Response from getting a referral by code.
public struct ReferralDetails: Codable, Sendable {
    public let referrerId: String
    public let status: String
    public let milestone: String?
    public let milestoneHistory: [AnyCodableValue]?
    public let rewardType: String?
    public let rewardValue: String?
    public let rewardClaimed: Bool?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case referrerId = "referrer_id"
        case status
        case milestone
        case milestoneHistory = "milestone_history"
        case rewardType = "reward_type"
        case rewardValue = "reward_value"
        case rewardClaimed = "reward_claimed"
        case createdAt = "created_at"
    }
}

/// Request body for completing a referral.
public struct CompleteReferralRequest: Codable, Sendable {
    public let referralCode: String
    public let referredUserId: String
    public let milestone: String?
    public let referredUserName: String?

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
        case referredUserId = "referred_user_id"
        case milestone
        case referredUserName = "referred_user_name"
    }

    public init(referralCode: String, referredUserId: String, milestone: String? = nil, referredUserName: String? = nil) {
        self.referralCode = referralCode
        self.referredUserId = referredUserId
        self.milestone = milestone
        self.referredUserName = referredUserName
    }
}

/// The nested referral object returned from the complete endpoint.
public struct CompletedReferral: Codable, Sendable {
    public let id: String
    public let referrerId: String
    public let referredUserId: String
    public let status: String
    public let milestone: String?
    public let completedAt: String?
    public let rewardType: String?
    public let rewardValue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case referrerId = "referrer_id"
        case referredUserId = "referred_user_id"
        case status
        case milestone
        case completedAt = "completed_at"
        case rewardType = "reward_type"
        case rewardValue = "reward_value"
    }
}

/// Response from completing a referral.
public struct CompleteReferralResponse: Codable, Sendable {
    public let referral: CompletedReferral
}

/// Request body for updating a milestone.
public struct MilestoneRequest: Codable, Sendable {
    public let referralCode: String
    public let milestone: String

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
        case milestone
    }

    public init(referralCode: String, milestone: String) {
        self.referralCode = referralCode
        self.milestone = milestone
    }
}

/// The nested referral object returned from the milestone endpoint.
public struct MilestoneReferral: Codable, Sendable {
    public let id: String
    public let referralCode: String
    public let milestone: String
    public let status: String
    public let rewardType: String?
    public let rewardValue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case referralCode = "referral_code"
        case milestone
        case status
        case rewardType = "reward_type"
        case rewardValue = "reward_value"
    }
}

/// Response from updating a milestone.
public struct MilestoneResponse: Codable, Sendable {
    public let referral: MilestoneReferral
}

/// Request body for claiming a reward.
public struct ClaimRewardRequest: Codable, Sendable {
    public let referralCode: String

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
    }

    public init(referralCode: String) {
        self.referralCode = referralCode
    }
}

/// Response from claiming a reward.
public struct ClaimRewardResponse: Codable, Sendable {
    public let success: Bool
    public let referralCode: String
    public let rewardClaimed: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case referralCode = "referral_code"
        case rewardClaimed = "reward_claimed"
    }
}

/// A single entry in the referral leaderboard.
public struct LeaderboardEntry: Codable, Sendable {
    public let referrerId: String
    public let referrerName: String?
    public let total: Int
    public let completed: Int
    public let pending: Int
    public let totalRewardValue: String?

    enum CodingKeys: String, CodingKey {
        case referrerId = "referrer_id"
        case referrerName = "referrer_name"
        case total
        case completed
        case pending
        case totalRewardValue = "total_reward_value"
    }
}

/// Wrapper for the leaderboard endpoint response.
public struct LeaderboardResponse: Codable, Sendable {
    public let leaderboard: [LeaderboardEntry]
}

// MARK: - Deferred Deep Links

/// Response from claiming a deferred deep link.
public struct DeferredDeepLinkResponse: Codable, Sendable {
    public let deepLinkPath: String
    public let appspaceId: String
    public let referrerId: String?
    public let referralCode: String?

    enum CodingKeys: String, CodingKey {
        case deepLinkPath = "deep_link_path"
        case appspaceId = "appspace_id"
        case referrerId = "referrer_id"
        case referralCode = "referral_code"
    }
}

/// Request body for claiming a deferred link by device signals.
public struct ClaimBySignalsRequest: Codable, Sendable {
    public let appspaceId: String
    public let timezone: String
    public let language: String
    public let screenWidth: Int
    public let screenHeight: Int

    enum CodingKeys: String, CodingKey {
        case appspaceId = "appspace_id"
        case timezone
        case language
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
    }

    public init(appspaceId: String, timezone: String, language: String, screenWidth: Int, screenHeight: Int) {
        self.appspaceId = appspaceId
        self.timezone = timezone
        self.language = language
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

// MARK: - Messages

/// A message returned by the messages endpoint.
public struct Message: Codable, Sendable {
    public let id: String
    public let name: String
    public let title: String
    public let body: String?
    public let trigger: String
    public let triggerValue: String?
    public let content: AnyCodableValue?
    public let backgroundColor: String
    public let priority: Int
    public let dismissDays: Int?
    public let maxImpressions: Int?
    public let minIntervalHours: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case body
        case trigger
        case triggerValue = "trigger_value"
        case content
        case backgroundColor = "background_color"
        case priority
        case dismissDays = "dismiss_days"
        case maxImpressions = "max_impressions"
        case minIntervalHours = "min_interval_hours"
    }
}

/// Wrapper for the messages endpoint response.
public struct MessagesResponse: Codable, Sendable {
    public let messages: [Message]
}

/// Response for the render-token endpoint.
public struct RenderTokenResponse: Codable, Sendable {
    public let token: String
}

/// Empty request body for POST requests that require no payload.
struct EmptyBody: Codable, Sendable {}

// MARK: - Generic API Error

/// Error response body from the Tolinku API.
public struct APIErrorResponse: Codable, Sendable {
    public let error: String?
    public let message: String?
    public let code: String?
}
