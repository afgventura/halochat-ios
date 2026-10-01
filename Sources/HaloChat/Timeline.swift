import Foundation

/// Merges messages by `id` and keeps them ascending by `createdAt` (ties by `id`).
///
/// The server intentionally re-sends a short overlap on polls and a socket event can
/// repeat a message already fetched, so every source funnels through here.
struct MessageMerger: Sendable {
    private(set) var byId: [String: HaloChatMessage] = [:]
    private(set) var newestCursor: String?

    /// Returns true when the timeline changed.
    mutating func merge(_ messages: [HaloChatMessage]) -> Bool {
        var changed = false
        for message in messages where byId[message.id] != message {
            byId[message.id] = message
            changed = true
        }
        return changed
    }

    mutating func remove(id: String) -> Bool {
        byId.removeValue(forKey: id) != nil
    }

    mutating func advance(cursor: String?) {
        if let cursor { newestCursor = cursor }
    }

    var ordered: [HaloChatMessage] {
        byId.values.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        }
    }
}

/// One realtime frame from `/ws/client`.
enum RealtimeEvent: Equatable {
    case authenticated
    case message(HaloChatMessage)
    case deleted(String)
    case other

    static func decode(_ text: String) -> RealtimeEvent {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return .other }
        switch type {
        case "authenticated":
            return .authenticated
        case "message_deleted":
            return (object["id"] as? String).map(RealtimeEvent.deleted) ?? .other
        case "message":
            guard let message = object["message"],
                  let json = try? JSONSerialization.data(withJSONObject: message),
                  let decoded = try? Transport.decoder.decode(HaloChatMessage.self, from: json)
            else { return .other }
            return .message(decoded)
        default:
            return .other
        }
    }
}

actor TimelineState {
    var merger = MessageMerger()

    func apply(page: HaloChatMessagePage) -> [HaloChatMessage]? {
        let changed = merger.merge(page.messages)
        merger.advance(cursor: page.newestCursor)
        return changed ? merger.ordered : nil
    }

    func apply(event: RealtimeEvent) -> [HaloChatMessage]? {
        switch event {
        case let .message(message):
            return merger.merge([message]) ? merger.ordered : nil
        case let .deleted(id):
            return merger.remove(id: id) ? merger.ordered : nil
        case .authenticated, .other:
            return nil
        }
    }

    func cursor() -> String? { merger.newestCursor }
    func snapshot() -> [HaloChatMessage] { merger.ordered }
}

/// Drives a live timeline: backfill, then socket; on socket loss, catch up and poll
/// until the socket can be re-established.
struct Timeline: Sendable {
    let client: HaloChatClient
    let initialLimit: Int
    let onError: (@Sendable (Error) -> Void)?

    private static let catchUpPageSize = 100
    private static let maxCatchUpPages = 10

    private var pollNanoseconds: UInt64 {
        UInt64(max(1, client.configuration.pollInterval) * 1_000_000_000)
    }

    func stream() -> AsyncStream<[HaloChatMessage]> {
        // Each element is a full snapshot, so only the newest one matters to a slow consumer.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let state = TimelineState()
                var backoff: UInt64 = 1
                do {
                    let page = try await client.latestMessages(limit: initialLimit)
                    _ = await state.apply(page: page)
                    continuation.yield(await state.snapshot())
                } catch {
                    await report(error)
                }
                while !Task.isCancelled {
                    await catchUp(state, continuation)
                    let connected = await runSocket(state, continuation)
                    if Task.isCancelled { break }
                    if connected { backoff = 1 }
                    // Socket unavailable or dropped: poll for a while before retrying it.
                    for _ in 0..<backoff where !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: pollNanoseconds)
                        await catchUp(state, continuation)
                    }
                    backoff = min(backoff * 2, 12)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reports an error; honours the server's Retry-After before the caller continues.
    private func report(_ error: Error) async {
        onError?(error)
        if case let HaloChatError.rateLimited(seconds) = error {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    /// Fetches everything newer than the cursor, page by page (bounded).
    private func catchUp(_ state: TimelineState, _ continuation: AsyncStream<[HaloChatMessage]>.Continuation) async {
        for _ in 0..<Self.maxCatchUpPages where !Task.isCancelled {
            do {
                let page: HaloChatMessagePage
                if let cursor = await state.cursor() {
                    page = try await client.messages(after: cursor, limit: Self.catchUpPageSize)
                } else {
                    page = try await client.latestMessages(limit: initialLimit)
                }
                if let timeline = await state.apply(page: page) { continuation.yield(timeline) }
                // `after` pages include an overlap window, so "full" means strictly new rows filled it.
                if page.messages.count < Self.catchUpPageSize { return }
            } catch {
                await report(error)
                return
            }
        }
    }

    /// Returns whether the socket authenticated before it ended.
    private func runSocket(_ state: TimelineState, _ continuation: AsyncStream<[HaloChatMessage]>.Continuation) async -> Bool {
        let token: String
        do {
            token = try await client.transport.tokens.token()
        } catch {
            await report(error)
            return false
        }
        let socket = client.transport.session.webSocketTask(with: client.configuration.realtimeURL)
        socket.resume()
        var authenticated = false
        await withTaskCancellationHandler {
            do {
                let auth = try JSONSerialization.data(withJSONObject: ["type": "auth", "token": token])
                try await socket.send(.string(String(decoding: auth, as: UTF8.self)))
                while !Task.isCancelled {
                    let frame = try await socket.receive()
                    guard case let .string(text) = frame else { continue }
                    let event = RealtimeEvent.decode(text)
                    if event == .authenticated {
                        authenticated = true
                        // Anything sent between the last poll and subscription is fetched here.
                        await catchUp(state, continuation)
                    }
                    if let timeline = await state.apply(event: event) { continuation.yield(timeline) }
                }
            } catch {
                if socket.closeCode.rawValue == 4001 {
                    // Token refused/expired: re-mint once (single-flight) for the next attempt.
                    _ = try? await client.transport.tokens.refresh(rejected: token)
                }
            }
        } onCancel: {
            // receive() is not cancellation-aware; closing the task ends it immediately.
            socket.cancel(with: .goingAway, reason: nil)
        }
        socket.cancel(with: .goingAway, reason: nil)
        return authenticated
    }
}
