import Foundation

/// The header subtitle under the room title (Qiscus `RoomSubtitle`).
public enum RoomSubtitle: Sendable, Equatable {
    /// The localized default ("Customer Service").
    case enabled
    /// No subtitle.
    case disabled
    /// The text passed to `setRoomSubTitle(enableSubtitle:subTitle:)`.
    case editable

    /// Qiscus spelling.
    public static let enable = RoomSubtitle.enabled
}

/// Whether business-side bubbles show an avatar and sender name (Qiscus `Avatar`).
public enum Avatar: Sendable, Equatable {
    case enabled
    case disabled

    /// Qiscus spelling.
    public static let enable = Avatar.enabled
}

/// Widget-wide defaults. Every `initiateChat()` builder starts from these and may override them.
public struct HaloChatWidgetConfig: Sendable, Equatable {
    /// Header title. `nil` uses the conversation title (the channel label) from the server.
    public var roomTitle: String?
    public var roomSubtitle: RoomSubtitle
    /// Used when `roomSubtitle == .editable`.
    public var roomSubtitleText: String?
    /// Show `senderKind == system` messages as centered pills.
    public var showSystemMessage: Bool
    public var avatar: Avatar

    public init(
        roomTitle: String? = nil,
        roomSubtitle: RoomSubtitle = .enabled,
        roomSubtitleText: String? = nil,
        showSystemMessage: Bool = true,
        avatar: Avatar = .enabled
    ) {
        self.roomTitle = roomTitle
        self.roomSubtitle = roomSubtitle
        self.roomSubtitleText = roomSubtitleText
        self.showSystemMessage = showSystemMessage
        self.avatar = avatar
    }
}

/// The resolved settings of one chat screen.
struct ChatScreenSettings: Sendable, Equatable {
    var roomTitle: String?
    var roomSubtitle: RoomSubtitle
    var roomSubtitleText: String?
    var showSystemMessage: Bool
    var avatar: Avatar
    /// Sent once when the chat opens.
    var automaticMessage: String?
    /// Pre-filled in the composer.
    var manualMessage: String?

    init(config: HaloChatWidgetConfig) {
        roomTitle = config.roomTitle
        roomSubtitle = config.roomSubtitle
        roomSubtitleText = config.roomSubtitleText
        showSystemMessage = config.showSystemMessage
        avatar = config.avatar
    }

    /// The subtitle text to show, or nil when hidden.
    var subtitleText: String? {
        switch roomSubtitle {
        case .enabled: return L10n.subtitleCustomerService
        case .disabled: return nil
        case .editable:
            let text = roomSubtitleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }
}

/// Composer limits (mirrors the server's `POST messages` rule: 1–4096 chars after trimming).
enum ComposerRules {
    static let maxCharacters = 4096

    /// The text to send, or nil when it must not be sent.
    static func sendableText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxCharacters else { return nil }
        return trimmed
    }
}
