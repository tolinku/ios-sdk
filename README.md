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

### Ecommerce

Track purchases, cart activity, and product events with built-in revenue analytics. Available on paid plans.

```swift
tolinku.setUserId("user_123")

// Track a product view
await tolinku.ecommerce.viewItem(
    items: [TolinkuItem(itemId: "sku_1", itemName: "T-Shirt", price: 24.99)]
)

// Track a purchase
await tolinku.ecommerce.purchase(
    transactionId: "order_456",
    revenue: 49.99,
    currency: "USD",
    items: [TolinkuItem(itemId: "sku_1", itemName: "T-Shirt", price: 24.99, quantity: 2)]
)

// Flush ecommerce events
await tolinku.ecommerce.flush()
```

The SDK supports 13 event types covering the full shopping journey. Money values use Swift `Decimal` for precision. Cart IDs are managed automatically via `UserDefaults` and cleared after purchase. Events auto-flush when the app enters the background.

### Deferred Deep Links

Recover deep link context for users who installed your app after clicking a link. Deferred deep linking lets you route users to specific content even when the app was not installed at the time of the click.

```swift
let deferred = tolinku.deferred

// Claim by referrer token
if let link = try await deferred.claimByToken("abc123") {
    print(link.deepLinkPath) // e.g. "/merchant/xyz"
}

// Claim by device signal matching. Timezone, language, screen size, pixel ratio and
// OS version are collected for you.
if let link = try await deferred.claimBySignals(appspaceId: "64f0a1b2c3d4e5f60718") {
    navigateTo(link.deepLinkPath)
}
```

`appspaceId` is your Appspace ID, not your subdomain or slug. Copy it from the dashboard
under **Integrate** or **Settings**. It looks like `64f0a1b2c3d4e5f60718`.


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

// Only messages for one event or milestone (plus those that name none)
await tolinku.messages.show(trigger: "event", triggerValue: "purchase", from: viewController)

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

### Resolving a Link

Short links open your app but arrive as an opaque code, `/s7k2p9q/4821`.
Nothing in that URL says which route it is, and nothing on the device can work
it out, so an app parsing the path itself does nothing and the link appears to
fail with no error and no screen.

`resolve` asks Tolinku, which answers with the route, the token and the
canonical path. A readable URL comes back unchanged, so you can resolve
everything rather than guessing which kind you have. It never throws: a link it
cannot resolve is one to fall back to your own handling for.

```swift
if let link = await Tolinku.shared?.links.resolve(url) {
    // link.deepLinkPath -> "/order/4821/receipt"
    // link.token        -> "4821"
    // link.route.prefix -> "order/{token}/receipt"
    route(link.deepLinkPath)
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

### `tolinku.ecommerce`

| Method | Description |
|--------|-------------|
| `viewItem(items:)` | Track a product view |
| `addToCart(items:)` | Track item added to cart |
| `removeFromCart(items:)` | Track item removed from cart |
| `addToWishlist(items:)` | Track item added to wishlist |
| `viewCart()` | Track cart view |
| `addPaymentInfo()` | Track payment info entered |
| `beginCheckout()` | Track checkout started |
| `purchase(transactionId:revenue:currency:items:)` | Track a purchase |
| `refund(transactionId:revenue:)` | Track a refund |
| `search(searchTerm:)` | Track a product search |
| `share(itemId:)` | Track a product share |
| `rate(itemId:rating:maxRating:)` | Track a product rating |
| `spendCredits(revenue:currency:)` | Track loyalty credits spent |
| `flush()` | Send all queued ecommerce events |

### `tolinku.deferred`

| Method | Description |
|--------|-------------|
| `claimByToken(_:)` | Claim a deferred link by token |
| `claimBySignals(appspaceId:)` | Claim a deferred link by device signals |

### `tolinku.messages`

| Method | Description |
|--------|-------------|
| `fetch(trigger:triggerValue:)` | Fetch messages with optional trigger and event or milestone name |
| `renderToken(messageId:)` | Get a render token for a message |
| `show(trigger:triggerValue:from:onAction:onDismiss:)` | Show the highest-priority message |

## Privacy

The package ships `PrivacyInfo.xcprivacy`. Swift Package Manager copies it into
a bundle your app embeds, and Xcode folds it into the privacy report it
generates when you archive, so there is nothing to add on your side.

### Required reason API

It declares one: `NSPrivacyAccessedAPICategoryUserDefaults`, with reason
`CA92.1`. The SDK stores three things in `UserDefaults.standard`, all read and
written only by your app, with no app group and no shared container:

| What | Where | Why |
|---|---|---|
| Dismissal state, impression counts, last-shown timestamps | `MessagePresenter` | Honours a message's `dismiss_days` suppression window and its display cap |
| Cart id | `tolinku.ecommerce` | Ties cart events together across launches |
| Claim once marker | `tolinku.deferred` | Stops a deferred link being claimed twice |

Nothing else in the package touches a required reason API. If that changes,
`PrivacyManifestTests` fails before the release does.

### Tracking

`NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty. The SDK
never reads the advertising identifier, never calls App Tracking Transparency,
and never joins a person's activity to data from another company's apps or
sites. You do not need to add an ATT prompt on our account.

### Collected data types, and which of your calls cause them

The manifest declares the SDK's whole surface, which is almost certainly more
than your integration uses. Use this to narrow your own App Store privacy label
to what you actually call. Nothing here is sent on your behalf: `links.resolve`
makes no analytics call, and `trackLinkOpen` is something you invoke.

| Declared type | Triggered by | What is sent |
|---|---|---|
| Other Data Types | `tolinku.deferred.claimBySignals` | IANA timezone, BCP-47 language with region, screen size in points, pixel ratio, OS version. Compared against the signals recorded at click time, then discarded. Not linked to an identity. |
| Product Interaction | `trackLinkOpen`, `track`, and the ecommerce interaction events (`viewItem`, `addToCart`, `removeFromCart`, `viewCart`, `addToWishlist`, `share`, `rate`) | The event name and whatever properties you attach |
| Search History | `tolinku.ecommerce.search(term:)` | The term you pass |
| Purchase History | `purchase`, `refund`, `beginCheckout` | Transaction id, revenue, currency, line items |
| User ID | `setUserId`, and the referral calls | Your own identifier for the person. The SDK never derives one |
| Name | The optional `userName` on `referrals.create` and `referrals.complete` | A display name for a referral leaderboard. Omit it and nothing in this category is sent |

Everything above except Other Data Types is declared as linked to identity,
because once you call `setUserId` the SDK attaches `user_id` to every event. If
you never call it, those flows carry no identifier from us.

If you integrate only universal link handling and `links.resolve`, none of the
six apply to you.

## Documentation

Full documentation is available at [tolinku.com/docs](https://tolinku.com/docs).

## Community

- [GitHub](https://github.com/tolinku)
- [X (Twitter)](https://x.com/trytolinku)
- [Facebook](https://facebook.com/trytolinku)
- [Instagram](https://www.instagram.com/trytolinku/)

## License

MIT
