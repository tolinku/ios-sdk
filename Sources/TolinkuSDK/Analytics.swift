import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A single queued analytics event.
private struct QueuedEvent: Sendable {
    let eventType: String
    let properties: [String: AnyCodableValue]?
}

/// Request body for sending a batch of analytics events.
struct BatchEventsRequest: Codable, Sendable {
    let events: [BatchEvent]
}

/// A single event within a batch request.
struct BatchEvent: Codable, Sendable {
    let eventType: String
    let properties: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case properties
    }
}

/// An actor that manages the analytics event queue with thread-safe access.
/// Events are queued in memory and flushed when the queue reaches 10 events,
/// after 5 seconds since the first queued event, or when flush() is called manually.
///
/// If a batch fails to send after all retries are exhausted, the events are
/// re-queued so they can be retried on the next flush. The queue is capped at
/// 1000 events to prevent unbounded memory growth; when the cap is exceeded,
/// the oldest events are dropped.
private actor EventQueue {
    private var events: [QueuedEvent] = []
    private var flushTask: Task<Void, Never>?
    private let maxBatchSize = 10
    private let maxQueueSize = 1000
    private let flushInterval: TimeInterval = 5.0

    /// The callback invoked to send a batch of events to the server.
    /// Returns true on success, false on failure.
    private let sendBatch: @Sendable ([QueuedEvent]) async -> Bool

    init(sendBatch: @escaping @Sendable ([QueuedEvent]) async -> Bool) {
        self.sendBatch = sendBatch
    }

    /// Add an event to the queue. Triggers a flush if the queue reaches the batch size limit.
    /// Starts a timer-based flush if this is the first event in the queue.
    func enqueue(eventType: String, properties: [String: AnyCodableValue]?) async {
        let event = QueuedEvent(eventType: eventType, properties: properties)
        events.append(event)
        enforceMaxQueueSize()

        if events.count >= maxBatchSize {
            await drainAndSend()
        } else if events.count == 1 {
            // First event in the queue; start a timer to flush after the interval
            startFlushTimer()
        }
    }

    /// Flush all queued events immediately.
    func flush() async {
        cancelFlushTimer()
        guard !events.isEmpty else { return }
        await drainAndSend()
    }

    /// Returns the current number of queued events (for testing).
    func count() -> Int {
        return events.count
    }

    /// Cancels the flush timer. Called during shutdown.
    func cancelTimer() {
        cancelFlushTimer()
    }

    // MARK: - Private

    private func drainAndSend() async {
        cancelFlushTimer()
        let batch = events
        events.removeAll()
        let success = await sendBatch(batch)

        if !success {
            // Re-queue failed events at the front so they are retried on the next flush.
            events.insert(contentsOf: batch, at: 0)
            enforceMaxQueueSize()
        }
    }

    /// Drops the oldest events if the queue exceeds the maximum allowed size.
    private func enforceMaxQueueSize() {
        if events.count > maxQueueSize {
            events.removeFirst(events.count - maxQueueSize)
        }
    }

    private func startFlushTimer() {
        cancelFlushTimer()
        let interval = flushInterval
        flushTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.flush()
        }
    }

    private func cancelFlushTimer() {
        flushTask?.cancel()
        flushTask = nil
    }
}

/// Provides event tracking via the Tolinku analytics API.
///
/// Events are batched in memory and sent to the server in groups for efficiency.
/// The queue flushes automatically when it reaches 10 events, after 5 seconds
/// since the first queued event, or when ``flush()`` is called.
/// Events are also flushed when the app moves to the background.
public final class Analytics: Sendable {

    private let client: Client
    private let eventQueue: EventQueue

    #if canImport(UIKit)
    /// The notification observer token, stored so we can remove it on shutdown.
    private nonisolated(unsafe) let backgroundObserver: NSObjectProtocol?
    #endif

    init(client: Client) {
        self.client = client

        // Capture client reference for the sendBatch closure
        let capturedClient = client
        self.eventQueue = EventQueue(sendBatch: { events in
            return await Analytics.sendBatch(events, client: capturedClient)
        })

        #if canImport(UIKit)
        self.backgroundObserver = registerForBackgroundNotification()
        #endif
    }

    deinit {
        #if canImport(UIKit)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    /// Track a custom event.
    ///
    /// The event is queued in memory and sent as part of a batch. The queue
    /// flushes automatically when it reaches 10 events, after 5 seconds, or
    /// when the app backgrounds. Call ``flush()`` to send queued events immediately.
    ///
    /// - Parameters:
    ///   - eventType: The event name. Should follow the "custom.xxx" convention.
    ///   - properties: Optional dictionary of additional properties to attach to the event.
    public func track(_ eventType: String, properties: [String: AnyCodableValue]? = nil) async {
        var normalizedType = eventType
        if !normalizedType.hasPrefix("custom.") {
            normalizedType = "custom.\(normalizedType)"
        }

        let pattern = #"^custom\.[a-z0-9_]+$"#
        guard normalizedType.range(of: pattern, options: .regularExpression) != nil else {
            assertionFailure("Tolinku: event type \"\(normalizedType)\" is invalid. Must match pattern \"custom.[a-z0-9_]+\"")
            return
        }

        await eventQueue.enqueue(eventType: normalizedType, properties: properties)
    }

    /// Flush all queued events to the server immediately.
    ///
    /// This is called automatically when the queue is full or the timer fires.
    /// You can also call it manually before the app terminates or at other
    /// critical points.
    public func flush() async {
        await eventQueue.flush()
    }

    // MARK: - Private

    /// Converts queued events to the batch request format and sends them to the server.
    ///
    /// - Returns: `true` if the batch was sent successfully, `false` if it failed
    ///   (so the caller can re-queue the events for a later retry).
    private static func sendBatch(_ events: [QueuedEvent], client: Client) async -> Bool {
        guard !events.isEmpty else { return true }

        let batchEvents = events.map { event in
            BatchEvent(
                eventType: event.eventType,
                properties: event.properties
            )
        }

        let body = BatchEventsRequest(events: batchEvents)
        do {
            try await client.postVoid(path: "/v1/api/analytics/batch", body: body)
            return true
        } catch {
            // The batch failed after the Client's own retry logic was exhausted.
            // Return false so the EventQueue re-queues these events for a later attempt.
            return false
        }
    }

    #if canImport(UIKit)
    /// Registers for the willResignActive notification to flush events when the app backgrounds.
    /// Returns the observer token so it can be removed on shutdown.
    private func registerForBackgroundNotification() -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.flush()
            }
        }
    }
    #endif

    /// Shuts down analytics by flushing remaining events, canceling the flush timer,
    /// and removing notification observers.
    ///
    /// This is called automatically when ``Tolinku/shutdown()`` is invoked.
    internal func shutdown() async {
        // Flush any remaining events
        await eventQueue.flush()

        // Cancel the flush timer
        await eventQueue.cancelTimer()

        // Remove the notification observer
        #if canImport(UIKit)
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }
}
