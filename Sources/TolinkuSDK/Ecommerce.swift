import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Ecommerce Item

/// A product item for ecommerce event tracking.
public struct TolinkuItem: Codable, Sendable {
    public let itemId: String
    public var itemName: String?
    public var itemCategory: String?
    public var itemBrand: String?
    public var itemVariant: String?
    public var itemListName: String?
    public var itemListId: String?
    public var itemImageUrl: String?
    public var price: Decimal?
    public var quantity: Int
    public var currency: String?
    public var couponCode: String?
    public var discount: Decimal?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case itemName = "item_name"
        case itemCategory = "item_category"
        case itemBrand = "item_brand"
        case itemVariant = "item_variant"
        case itemListName = "item_list_name"
        case itemListId = "item_list_id"
        case itemImageUrl = "item_image_url"
        case price, quantity, currency
        case couponCode = "coupon_code"
        case discount
    }

    public init(
        itemId: String,
        itemName: String? = nil,
        itemCategory: String? = nil,
        itemBrand: String? = nil,
        itemVariant: String? = nil,
        itemListName: String? = nil,
        itemListId: String? = nil,
        itemImageUrl: String? = nil,
        price: Decimal? = nil,
        quantity: Int = 1,
        currency: String? = nil,
        couponCode: String? = nil,
        discount: Decimal? = nil
    ) {
        self.itemId = itemId
        self.itemName = itemName
        self.itemCategory = itemCategory
        self.itemBrand = itemBrand
        self.itemVariant = itemVariant
        self.itemListName = itemListName
        self.itemListId = itemListId
        self.itemImageUrl = itemImageUrl
        self.price = price
        self.quantity = quantity
        self.currency = currency
        self.couponCode = couponCode
        self.discount = discount
    }
}

// MARK: - Queued Event

private struct QueuedEcomEvent: Sendable {
    let eventType: String
    var transactionId: String? = nil
    var revenue: Decimal? = nil
    var currency: String? = nil
    var cartId: String? = nil
    var couponCode: String? = nil
    var discount: Decimal? = nil
    var shipping: Decimal? = nil
    var tax: Decimal? = nil
    var items: [TolinkuItem]? = nil
    var properties: [String: String]? = nil
    var userId: String? = nil
}

// MARK: - Batch Request

struct EcomBatchRequest: Codable, Sendable {
    let events: [EcomBatchEvent]
}

struct EcomBatchEvent: Codable, Sendable {
    let eventType: String
    var transactionId: String? = nil
    var revenue: Decimal? = nil
    var currency: String? = nil
    var cartId: String? = nil
    var couponCode: String? = nil
    var discount: Decimal? = nil
    var shipping: Decimal? = nil
    var tax: Decimal? = nil
    var items: [TolinkuItem]? = nil
    var properties: [String: String]? = nil
    var userId: String? = nil

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case transactionId = "transaction_id"
        case revenue, currency
        case cartId = "cart_id"
        case couponCode = "coupon_code"
        case discount, shipping, tax, items, properties
        case userId = "user_id"
    }
}

// MARK: - Event Queue Actor

private actor EcomEventQueue {
    private var events: [QueuedEcomEvent] = []
    private var flushTask: Task<Void, Never>?
    private let maxBatchSize = 10
    private let maxQueueSize = 500
    private let flushInterval: TimeInterval = 5.0
    private let client: Client
    private let getUserId: @Sendable () -> String?

    init(client: Client, getUserId: @escaping @Sendable () -> String?) {
        self.client = client
        self.getUserId = getUserId
    }

    func enqueue(_ event: QueuedEcomEvent) async {
        var e = event
        if let uid = getUserId() {
            e.userId = uid
        }

        if events.count >= maxQueueSize {
            events.removeFirst()
        }
        events.append(e)

        if events.count >= maxBatchSize {
            await flush()
        } else if events.count == 1 {
            startFlushTimer()
        }
    }

    func flush() async {
        flushTask?.cancel()
        flushTask = nil

        guard !events.isEmpty else { return }

        let batch = events
        events.removeAll()

        let batchEvents = batch.map { e in
            EcomBatchEvent(
                eventType: e.eventType,
                transactionId: e.transactionId,
                revenue: e.revenue,
                currency: e.currency,
                cartId: e.cartId,
                couponCode: e.couponCode,
                discount: e.discount,
                shipping: e.shipping,
                tax: e.tax,
                items: e.items,
                properties: e.properties,
                userId: e.userId
            )
        }

        do {
            let _: BatchResponse = try await client.post(
                path: "/v1/api/analytics/ecommerce/batch",
                body: EcomBatchRequest(events: batchEvents)
            )
        } catch {
            // Re-queue on failure (up to max)
            let spaceLeft = maxQueueSize - events.count
            if spaceLeft > 0 {
                events.insert(contentsOf: batch.prefix(spaceLeft), at: 0)
            }
        }
    }

    func shutdown() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    private func startFlushTimer() {
        flushTask?.cancel()
        let interval = flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }
}

private struct BatchResponse: Codable {
    let ok: Bool
    let accepted: Int?
    let errors: [String]?
}

// MARK: - Cart ID Manager

private actor CartIdManager {
    private let storageKey = "tolinku_ecom_cart_id"
    private var memoryCartId: String?

    func getOrCreate() -> String {
        if let existing = get() { return existing }
        let cartId = UUID().uuidString.lowercased()
        set(cartId)
        return cartId
    }

    func get() -> String? {
        if let stored = UserDefaults.standard.string(forKey: storageKey) {
            return stored
        }
        return memoryCartId
    }

    func set(_ cartId: String) {
        memoryCartId = cartId
        UserDefaults.standard.set(cartId, forKey: storageKey)
    }

    func clear() {
        memoryCartId = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Public Ecommerce Class

/// Ecommerce event tracking: purchases, carts, products, revenue.
///
/// Access via `Tolinku.shared?.ecommerce` after configuring the SDK.
public final class Ecommerce: Sendable {
    private let queue: EcomEventQueue
    private let cartIdManager = CartIdManager()
    #if canImport(UIKit)
    private nonisolated(unsafe) var backgroundObserver: NSObjectProtocol?
    #endif

    init(client: Client, getUserId: @escaping @Sendable () -> String?) {
        self.queue = EcomEventQueue(client: client, getUserId: getUserId)

        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.queue.flush() }
        }
        #endif
    }

    deinit {
        #if canImport(UIKit)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    // MARK: - Public Methods

    public func viewItem(items: [TolinkuItem]) async {
        await queue.enqueue(QueuedEcomEvent(eventType: "view_item", items: items))
    }

    public func addToCart(items: [TolinkuItem], cartId: String? = nil) async {
        let resolvedCartId = cartId ?? await cartIdManager.getOrCreate()
        await queue.enqueue(QueuedEcomEvent(eventType: "add_to_cart", cartId: resolvedCartId, items: items))
    }

    public func removeFromCart(items: [TolinkuItem], cartId: String? = nil) async {
        let resolvedCartId = cartId ?? await cartIdManager.get()
        await queue.enqueue(QueuedEcomEvent(eventType: "remove_from_cart", cartId: resolvedCartId, items: items))
    }

    public func addToWishlist(items: [TolinkuItem]) async {
        await queue.enqueue(QueuedEcomEvent(eventType: "add_to_wishlist", items: items))
    }

    public func viewCart() async {
        let cartId = await cartIdManager.get()
        await queue.enqueue(QueuedEcomEvent(eventType: "view_cart", cartId: cartId))
    }

    public func addPaymentInfo(cartId: String? = nil) async {
        let resolvedCartId = cartId ?? await cartIdManager.get()
        await queue.enqueue(QueuedEcomEvent(eventType: "add_payment_info", cartId: resolvedCartId))
    }

    public func beginCheckout(revenue: Decimal? = nil, currency: String? = nil, cartId: String? = nil, items: [TolinkuItem]? = nil) async {
        let resolvedCartId = cartId ?? await cartIdManager.get()
        await queue.enqueue(QueuedEcomEvent(eventType: "begin_checkout", revenue: revenue, currency: currency, cartId: resolvedCartId, items: items))
    }

    public func purchase(transactionId: String, revenue: Decimal, currency: String, items: [TolinkuItem]? = nil, cartId: String? = nil, couponCode: String? = nil, discount: Decimal? = nil, shipping: Decimal? = nil, tax: Decimal? = nil) async {
        let resolvedCartId = cartId ?? await cartIdManager.get()
        await queue.enqueue(QueuedEcomEvent(
            eventType: "purchase",
            transactionId: transactionId,
            revenue: revenue,
            currency: currency,
            cartId: resolvedCartId,
            couponCode: couponCode,
            discount: discount,
            shipping: shipping,
            tax: tax,
            items: items
        ))
        await cartIdManager.clear()
    }

    public func refund(transactionId: String, revenue: Decimal, currency: String? = nil, items: [TolinkuItem]? = nil) async {
        await queue.enqueue(QueuedEcomEvent(eventType: "refund", transactionId: transactionId, revenue: revenue, currency: currency, items: items))
    }

    public func search(term: String) async {
        await queue.enqueue(QueuedEcomEvent(eventType: "search", properties: ["search_term": term]))
    }

    public func share(itemId: String? = nil, url: String? = nil, method: String? = nil) async {
        var props: [String: String] = [:]
        if let itemId { props["item_id"] = itemId }
        if let url { props["url"] = url }
        if let method { props["method"] = method }
        await queue.enqueue(QueuedEcomEvent(eventType: "share", properties: props))
    }

    public func rate(itemId: String, rating: Double, maxRating: Double? = nil) async {
        var props: [String: String] = ["item_id": itemId, "rating": String(rating)]
        if let maxRating { props["max_rating"] = String(maxRating) }
        await queue.enqueue(QueuedEcomEvent(eventType: "rate", properties: props))
    }

    public func spendCredits(revenue: Decimal, currency: String) async {
        await queue.enqueue(QueuedEcomEvent(eventType: "spend_credits", revenue: revenue, currency: currency))
    }

    // MARK: - Flush & Shutdown

    public func flush() async {
        await queue.flush()
    }

    func shutdown() async {
        #if canImport(UIKit)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        #endif
        await queue.shutdown()
    }
}
