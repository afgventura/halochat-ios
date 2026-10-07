#if SWIFT_PACKAGE
import HaloChat
#endif
import Foundation

/// Everything the screen knows about server messages: the live `timeline()` snapshot,
/// older pages loaded on scroll-back, and messages returned by `send`. Merged by `id`.
struct ChatTimelineStore: Equatable, Sendable {
    enum OlderRequest: Equatable, Sendable {
        /// The first scroll-back call: the newest page, to learn the oldest cursor.
        case latest
        case before(String)
    }

    /// The latest timeline snapshot (backfill + realtime). It wins for status updates.
    private(set) var live: [String: HaloChatMessage] = [:]
    /// Older pages and send responses.
    private(set) var extra: [String: HaloChatMessage] = [:]
    private(set) var oldestCursor: String?
    private(set) var reachedStart = false
    private var loadedFirstOlderPage = false

    /// Replaces the live window. A message missing from it is deleted only when it falls inside
    /// the new window's time range; one older than the window (the timeline restarted with a
    /// fresh, shorter backfill) is kept, so reopening the chat never leaves a gap.
    mutating func applyTimeline(_ snapshot: [HaloChatMessage]) {
        var next: [String: HaloChatMessage] = [:]
        for message in snapshot { next[message.id] = message }
        let windowStart = snapshot.map(\.createdAt).min()
        for (id, message) in live where next[id] == nil {
            if let windowStart, message.createdAt >= windowStart {
                extra.removeValue(forKey: id)
            } else {
                extra[id] = message
            }
        }
        live = next
    }

    /// Merges an older page and advances the scroll-back cursor; an empty page ends it.
    mutating func applyOlder(_ page: HaloChatMessagePage) {
        merge(page.messages)
        loadedFirstOlderPage = true
        if page.messages.isEmpty || page.oldestCursor == nil {
            reachedStart = true
        } else {
            oldestCursor = page.oldestCursor
        }
    }

    /// Merges messages from any other source (send responses, re-reads).
    mutating func merge(_ messages: [HaloChatMessage]) {
        for message in messages { extra[message.id] = message }
    }

    /// The next scroll-back call, or nil once the start of the conversation was reached.
    var nextOlderRequest: OlderRequest? {
        if reachedStart { return nil }
        if !loadedFirstOlderPage { return .latest }
        return oldestCursor.map(OlderRequest.before)
    }

    /// Ascending by `createdAt`, ties by `id`, one entry per `id`.
    var messages: [HaloChatMessage] {
        var all = extra
        for (id, message) in live { all[id] = message }
        return all.values.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        }
    }
}
