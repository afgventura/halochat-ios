#if SWIFT_PACKAGE
import HaloChat
#endif
import Foundation

/// The non-blocking banner above the list.
enum ChatBanner: Equatable, Sendable {
    case reconnecting
    case rateLimited
    /// `.unauthorized`: the token provider can no longer mint. The screen stops.
    case sessionExpired

    init(error: Error) {
        switch error {
        case HaloChatError.unauthorized: self = .sessionExpired
        case HaloChatError.rateLimited: self = .rateLimited
        default: self = .reconnecting
        }
    }

    var text: String {
        switch self {
        case .reconnecting: return L10n.bannerReconnecting
        case .rateLimited: return L10n.bannerRateLimited
        case .sessionExpired: return L10n.bannerSessionExpired
        }
    }
}

/// The tick under one of the user's own bubbles.
enum MessageTick: Equatable, Sendable {
    case sending
    case failed
    /// Sent or delivered: one check.
    case sent
    /// Read by an agent: two checks.
    case read

    init(status: HaloChatMessage.Status?) {
        switch status {
        case .read: self = .read
        case .sent, .delivered, nil: self = .sent
        }
    }

    init(pending: PendingMessage.State) {
        switch pending {
        case .sending: self = .sending
        case .failed: self = .failed
        }
    }
}

/// The APNs payload HaloAI sends: `type: "halochat_message"`, `roomId`, `messageId`.
public enum HaloChatNotificationPayload {
    public static let type = "halochat_message"

    public static func isHaloChat(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["type"] as? String) == type
    }

    public static func roomId(_ userInfo: [AnyHashable: Any]) -> String? {
        userInfo["roomId"] as? String
    }

    public static func messageId(_ userInfo: [AnyHashable: Any]) -> String? {
        userInfo["messageId"] as? String
    }
}

/// Whether a chat screen is on screen right now (for `shouldPresentNotification`).
enum HaloChatVisibility {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var visibleCount = 0

    static var isVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return visibleCount > 0
    }

    static func appeared() {
        lock.lock()
        visibleCount += 1
        lock.unlock()
    }

    static func disappeared() {
        lock.lock()
        visibleCount = max(0, visibleCount - 1)
        lock.unlock()
    }
}
