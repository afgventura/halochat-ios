import Foundation

/// One message of the end user's conversation. Mirrors the server's `ClientMessage`.
public struct HaloChatMessage: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Sender: String, Codable, Sendable {
        /// The signed-in app user.
        case me
        /// The business side: AI, a human agent, or an automation.
        case agent
    }

    public enum SenderKind: String, Codable, Sendable {
        case customer, ai, human, system
    }

    public enum Status: String, Codable, Sendable {
        case sent, delivered, read
    }

    public let id: String
    public let text: String?
    public let sender: Sender
    public let senderKind: SenderKind
    public let hasMedia: Bool
    public let mediaType: String?
    public let mediaFilename: String?
    public let createdAt: Date
    public let status: Status?

    private enum CodingKeys: String, CodingKey {
        case id, text, sender, senderKind, hasMedia, mediaType, mediaFilename, createdAt, status
    }

    /// Tolerant decoding: a value added by a newer server never fails a whole page.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        sender = Sender(rawValue: (try? container.decode(String.self, forKey: .sender)) ?? "") ?? .agent
        senderKind = SenderKind(rawValue: (try? container.decode(String.self, forKey: .senderKind)) ?? "") ?? .system
        hasMedia = (try? container.decode(Bool.self, forKey: .hasMedia)) ?? false
        mediaType = try? container.decodeIfPresent(String.self, forKey: .mediaType)
        mediaFilename = try? container.decodeIfPresent(String.self, forKey: .mediaFilename)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = (try? container.decodeIfPresent(String.self, forKey: .status)).flatMap { $0.flatMap(Status.init(rawValue:)) }
    }

    public init(
        id: String,
        text: String?,
        sender: Sender,
        senderKind: SenderKind,
        hasMedia: Bool = false,
        mediaType: String? = nil,
        mediaFilename: String? = nil,
        createdAt: Date,
        status: Status? = nil
    ) {
        self.id = id
        self.text = text
        self.sender = sender
        self.senderKind = senderKind
        self.hasMedia = hasMedia
        self.mediaType = mediaType
        self.mediaFilename = mediaFilename
        self.createdAt = createdAt
        self.status = status
    }
}

/// The end user's single conversation with the business.
public struct HaloChatConversation: Codable, Equatable, Sendable {
    public let roomId: String
    public let title: String?
}

/// One page of history, ascending by time. Cursors are opaque; pass them back verbatim.
public struct HaloChatMessagePage: Codable, Equatable, Sendable {
    public let messages: [HaloChatMessage]
    public let newestCursor: String?
    public let oldestCursor: String?
}

/// Errors surfaced by the SDK.
public enum HaloChatError: Error, Equatable, Sendable {
    /// The token was refused even after one refresh through the token provider.
    case unauthorized
    /// Too many requests; retry after the given number of seconds.
    case rateLimited(retryAfterSeconds: Int)
    /// A send with this idempotency key is still in flight on the server; re-read before retrying.
    case sendInProgress
    /// The server rejected the request (4xx other than 401/409/429).
    case rejected(status: Int, code: String?)
    /// Transient server failure (5xx).
    case server(status: Int)
    /// The response could not be decoded.
    case invalidResponse
}
