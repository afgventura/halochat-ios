import Foundation

/// A JSON value. `HaloChatMessage.extras` and `send(text:extras:)` use it for the free-form
/// `extras` object (the Qiscus `extras` field).
///
/// Numbers are `Double`, so an integer above 2^53 loses precision. Send such an id as a string.
public enum HaloChatJSON: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([HaloChatJSON])
    case object([String: HaloChatJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HaloChatJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: HaloChatJSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
