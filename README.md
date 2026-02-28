# TolinkuSDK

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-lightgrey.svg)](https://developer.apple.com/ios/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The official [Tolinku](https://tolinku.com) SDK for iOS. Add deep linking, analytics, referral tracking, deferred deep links, and in-app messages to your iOS app. Supports Universal Links out of the box.

## What is Tolinku?

[Tolinku](https://tolinku.com) is a deep linking platform for mobile and web apps. It handles Universal Links (iOS), App Links (Android), deferred deep linking, referral programs, analytics, and smart banners. Tolinku provides a complete toolkit for user acquisition, attribution, and engagement across platforms.

Get your API key at [tolinku.com](https://tolinku.com) and check out the [documentation](https://tolinku.com/docs) to get started.

## Installation

Add TolinkuSDK using Swift Package Manager:

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/tolinku/ios-sdk`
3. Select your version rule and add the package to your target

**Requirements:** iOS 15+

## Quick Start

```swift
import TolinkuSDK

// Configure the SDK (typically in AppDelegate or App init)
let tolinku = try Tolinku.configure(apiKey: "tolk_pub_your_api_key")

// Identify a user
tolinku.setUserId("user_123")

// Track a custom event
await tolinku.track("purchase", properties: ["plan": .string("growth")])
```

## Features

### Analytics

Track custom events with automatic batching. Events are queued and sent in batches of 10, or every 5 seconds. Events are also flushed when the app moves to the background.

```swift
await tolinku.track("signup_completed", properties: [
    "source": .string("landing_page"),
    "trial": .bool(true),
])

// Flush queued events immediately
await tolinku.flush()
```

### Referrals

Create and manage referral programs with leaderboards and reward tracking.

```swift
let referrals = tolinku.referrals

// Create a referral
let result = try await referrals.create(userId: "user_123", userName: "Alice")
let code = result.referralCode

// Look up a referral
let details = try await referrals.get(code: code)

// Complete a referral
let completion = try await referrals.complete(
    code: code,
    referredUserId: "user_456",
    referredUserName: "Bob"
)

// Update milestone
let milestone = try await referrals.milestone(code: code, milestone: "first_purchase")

// Claim reward
let reward = try await referrals.claimReward(code: code)

// Fetch leaderboard
let entries = try await referrals.leaderboard(limit: 10)
```

### Deferred Deep Links

Recover deep link context for users who installed your app after clicking a link. Deferred deep linking lets you route users to specific content even when the app was not installed at the time of the click.

```swift
let deferred = tolinku.deferred

// Claim by referrer token
if let link = try await deferred.claimByToken("abc123") {
    print(link.deepLinkPath) // e.g. "/merchant/xyz"
}

// Claim by device signal matching (auto-collects timezone, language, screen size)
if let link = try await deferred.claimBySignals(appspaceId: "your_appspace_id") {
    navigateTo(link.deepLinkPath)
}
```

### Universal Link Handling

Parse incoming Universal Links with a simple utility method (no SDK configuration required).

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    guard let url = userActivity.webpageURL,
          let result = Tolinku.handleUniversalLink(url) else {
        return false
    }
    // result.path - the deep link path
    // result.queryItems - any query parameters
    navigateTo(result.path, queryItems: result.queryItems)
    return true
}
```

### In-App Messages

Display server-configured messages as modal overlays using `TolinkuMessagePresenter`. Create and manage messages from the Tolinku dashboard without shipping app updates.

```swift
// Show the highest-priority message matching a trigger
await tolinku.messages.show(trigger: "milestone", from: viewController)

// With action and dismiss callbacks
await tolinku.messages.show(
    trigger: "milestone",
    from: viewController,
    onAction: { action in
        print("Button tapped: \(action)")
    },
    onDismiss: {
        print("Message dismissed")
    }
)
```

You can also fetch and present messages manually:

```swift
let messages = try await tolinku.messages.fetch(trigger: "milestone")
if let message = messages.first {
    TolinkuMessagePresenter.show(message: message, from: viewController)
}
```

## Configuration Options

```swift
// Full configuration
let tolinku = try Tolinku.configure(
    apiKey: "tolk_pub_your_api_key",    // Required. Your Tolinku publishable API key.
    baseURL: "https://api.tolinku.com" // Optional. API base URL.
)

// Set user identity at any time
tolinku.setUserId("user_123")

// Shut down the SDK when done
await Tolinku.shutdown()
```

## API Reference

### `Tolinku`

| Method | Description |
|--------|-------------|
| `configure(apiKey:baseURL:)` | Initialize the SDK (static) |
| `shared` | Access the configured instance (static, optional) |
| `requireShared()` | Access the configured instance or throw (static) |
| `setUserId(_:)` | Set or clear the current user ID |
| `track(_:properties:)` | Track a custom event |
| `flush()` | Flush queued analytics events |
| `handleUniversalLink(_:)` | Parse a Universal Link URL (static) |
| `shutdown()` | Release all resources (static) |

### `tolinku.referrals`

| Method | Description |
|--------|-------------|
| `create(userId:metadata:userName:)` | Create a new referral |
| `get(code:)` | Get referral details by code |
| `complete(code:referredUserId:milestone:referredUserName:)` | Mark a referral as converted |
| `milestone(code:milestone:)` | Update a referral milestone |
| `claimReward(code:)` | Claim a referral reward |
| `leaderboard(limit:)` | Fetch the referral leaderboard |

### `tolinku.deferred`

| Method | Description |
|--------|-------------|
| `claimByToken(_:)` | Claim a deferred link by token |
| `claimBySignals(appspaceId:)` | Claim a deferred link by device signals |

### `tolinku.messages`

| Method | Description |
|--------|-------------|
| `fetch(trigger:)` | Fetch messages with optional trigger filter |
| `renderToken(messageId:)` | Get a render token for a message |
| `show(trigger:from:onAction:onDismiss:)` | Show the highest-priority message |

## Documentation

Full documentation is available at [tolinku.com/docs](https://tolinku.com/docs).

## Community

- [GitHub](https://github.com/tolinku)
- [X (Twitter)](https://x.com/trytolinku)
- [Facebook](https://facebook.com/trytolinku)
- [Instagram](https://www.instagram.com/trytolinku/)

## License

MIT
