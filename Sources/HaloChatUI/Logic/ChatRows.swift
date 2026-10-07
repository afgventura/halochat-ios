#if SWIFT_PACKAGE
import HaloChat
#endif
import Foundation

enum ChatDateLabel: Equatable, Sendable {
    case today
    case yesterday
    case date(Date)
}

struct ChatMessageRow: Equatable, Sendable {
    let message: HaloChatMessage
    /// First business-side bubble of a run: shows the avatar and sender name.
    let startsAgentRun: Bool
}

/// One row of the chat list.
enum ChatRow: Equatable, Sendable {
    case date(day: Date, label: ChatDateLabel)
    case message(ChatMessageRow)
    case system(HaloChatMessage)
    case pending(PendingMessage)

    /// Stable identity (date rows by calendar day).
    var id: String {
        switch self {
        case let .date(day, _): return "date-\(Int(day.timeIntervalSince1970))"
        case let .message(row): return row.message.id
        case let .system(message): return message.id
        case let .pending(item): return item.id
        }
    }
}

/// Builds the rows: server messages (ascending) then pending ones, a date separator before
/// each new calendar day, system messages as pills (or hidden).
enum ChatRowBuilder {
    static func rows(
        messages: [HaloChatMessage],
        pending: [PendingMessage],
        showSystemMessages: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [ChatRow] {
        enum Item {
            case server(HaloChatMessage)
            case local(PendingMessage)

            var date: Date {
                switch self {
                case let .server(message): return message.createdAt
                case let .local(item): return item.createdAt
                }
            }
        }

        let visible = messages.filter { showSystemMessages || $0.senderKind != .system }
        // Pending items stay after every server message: they are the newest by definition.
        let items = visible.map(Item.server) + pending.map(Item.local)

        var rows: [ChatRow] = []
        var currentDay: Date?
        var previousWasAgent = false
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if day != currentDay {
                rows.append(.date(day: day, label: label(for: day, calendar: calendar, now: now)))
                currentDay = day
                previousWasAgent = false
            }
            switch item {
            case let .server(message) where message.senderKind == .system:
                rows.append(.system(message))
                previousWasAgent = false
            case let .server(message):
                let isAgent = message.sender == .agent
                rows.append(.message(ChatMessageRow(message: message, startsAgentRun: isAgent && !previousWasAgent)))
                previousWasAgent = isAgent
            case let .local(pendingItem):
                rows.append(.pending(pendingItem))
                previousWasAgent = false
            }
        }
        return rows
    }

    static func label(for day: Date, calendar: Calendar, now: Date) -> ChatDateLabel {
        let today = calendar.startOfDay(for: now)
        if day == today { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return .yesterday }
        return .date(day)
    }
}
