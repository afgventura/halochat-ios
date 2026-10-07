#if SWIFT_PACKAGE
import HaloChat
#endif
import Foundation

/// An attachment waiting to be (re)sent. The bytes are kept so a retry sends the same file.
struct PendingAttachment: Equatable, Sendable {
    let data: Data
    let filename: String
    let mimeType: String
    let caption: String?
}

/// Why a send failed, as shown on the failed bubble.
enum SendFailure: Equatable, Sendable {
    case tooLarge
    case unsupportedType
    case sessionExpired
    case network

    init(error: Error) {
        if let rejection = HaloChatAttachmentRejection(error: error) {
            self = rejection == .tooLarge ? .tooLarge : .unsupportedType
        } else if case HaloChatError.unauthorized = error {
            self = .sessionExpired
        } else {
            self = .network
        }
    }

    var localizedMessage: String {
        switch self {
        case .tooLarge: return L10n.errorTooLarge
        case .unsupportedType: return L10n.errorUnsupportedType
        case .sessionExpired: return L10n.bannerSessionExpired
        case .network: return L10n.errorSendFailed
        }
    }
}

/// One outgoing message rendered before the server confirms it.
struct PendingMessage: Equatable, Identifiable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String)
        case attachment(PendingAttachment)
    }

    enum State: Equatable, Sendable {
        case sending
        case failed(SendFailure)
    }

    /// The idempotency key. It never changes across retries.
    let clientMessageId: UUID
    let content: Content
    let createdAt: Date
    var state: State

    var id: String { "pending-\(clientMessageId.uuidString.lowercased())" }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

/// The outgoing queue: enqueue → (success: removed) | (failure: failed → retry → sending …).
struct PendingQueue: Equatable, Sendable {
    private(set) var items: [PendingMessage] = []

    @discardableResult
    mutating func enqueue(_ content: PendingMessage.Content, now: Date = Date(), id: UUID = UUID()) -> PendingMessage {
        let item = PendingMessage(clientMessageId: id, content: content, createdAt: now, state: .sending)
        items.append(item)
        return item
    }

    /// The server accepted it; its real message replaces the pending bubble.
    mutating func succeeded(_ id: UUID) {
        items.removeAll { $0.clientMessageId == id }
    }

    mutating func failed(_ id: UUID, _ failure: SendFailure) {
        guard let index = items.firstIndex(where: { $0.clientMessageId == id }) else { return }
        items[index].state = .failed(failure)
    }

    /// Marks a failed item as sending again and returns it, unchanged otherwise:
    /// same `clientMessageId`, same text or bytes. Nil when it is not failed.
    mutating func retry(_ id: UUID) -> PendingMessage? {
        guard let index = items.firstIndex(where: { $0.clientMessageId == id }), items[index].isFailed else { return nil }
        items[index].state = .sending
        return items[index]
    }

    mutating func remove(_ id: UUID) {
        items.removeAll { $0.clientMessageId == id }
    }

    func item(_ id: UUID) -> PendingMessage? {
        items.first { $0.clientMessageId == id }
    }
}

/// Runs one send with the `.sendInProgress` rule: wait 2 s, re-read, retry once with the same id.
enum SendPerformer {
    static let inProgressDelayNanoseconds: UInt64 = 2_000_000_000

    static func perform(
        clientMessageId: UUID,
        send: (UUID) async throws -> HaloChatMessage,
        reread: () async -> Void,
        wait: (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) async -> Result<HaloChatMessage, Error> {
        do {
            return .success(try await send(clientMessageId))
        } catch HaloChatError.sendInProgress {
            await wait(inProgressDelayNanoseconds)
            await reread()
            do {
                return .success(try await send(clientMessageId))
            } catch {
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }
}
