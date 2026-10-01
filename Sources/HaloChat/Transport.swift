import Foundation

/// Supplies HaloChat client tokens (`hct_…`), minted by YOUR backend with its PAT.
///
/// `forceRefresh` is `true` after the server refused the current token: mint a new one.
/// Never embed a HaloAI PAT in the app.
public protocol HaloChatTokenProvider: Sendable {
    func token(forceRefresh: Bool) async throws -> String
}

/// A token provider backed by a closure.
public struct HaloChatClosureTokenProvider: HaloChatTokenProvider {
    private let fetch: @Sendable (Bool) async throws -> String

    public init(_ fetch: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String) {
        self.fetch = fetch
    }

    public func token(forceRefresh: Bool) async throws -> String {
        try await fetch(forceRefresh)
    }
}

/// One token for all concurrent calls, and at most one refresh at a time: N calls that
/// all hit 401 with the same token trigger a single mint (each mint is a server session).
actor TokenGate {
    private let provider: HaloChatTokenProvider
    private var current: String?
    private var refreshing: Task<String, Error>?
    private var onRefreshed: (@Sendable () async -> Void)?

    init(provider: HaloChatTokenProvider) {
        self.provider = provider
    }

    func setOnRefreshed(_ callback: @escaping @Sendable () async -> Void) {
        onRefreshed = callback
    }

    func token() async throws -> String {
        if let current { return current }
        if let refreshing { return try await refreshing.value }
        let fresh = try await provider.token(forceRefresh: false)
        current = fresh
        return fresh
    }

    /// `rejected` is the token the server refused. If another caller already replaced
    /// it, the replacement is returned without minting again.
    func refresh(rejected: String) async throws -> String {
        if let current, current != rejected { return current }
        if let refreshing { return try await refreshing.value }
        let task = Task { [provider] in try await provider.token(forceRefresh: true) }
        refreshing = task
        defer { refreshing = nil }
        let fresh = try await task.value
        current = fresh
        if let onRefreshed { Task { await onRefreshed() } }
        return fresh
    }

    func clear() {
        current = nil
    }
}

struct Envelope<T: Decodable>: Decodable {
    let data: T
}

struct ErrorEnvelope: Decodable {
    let error: String?
}

/// HTTP plumbing shared by every call: bearer auth with one refresh on 401,
/// error mapping, and JSON coding with ISO-8601 (fractional seconds) dates.
final class Transport: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokens: TokenGate

    init(baseURL: URL, session: URLSession, tokenProvider: HaloChatTokenProvider) {
        self.baseURL = baseURL
        self.session = session
        tokens = TokenGate(provider: tokenProvider)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }
        return decoder
    }()

    // ISO8601DateFormatter is thread-safe for parsing; build each once.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseISO8601(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/client/inApp/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        return components?.url ?? baseURL
    }

    /// Performs `request` with the current token; on 401 refreshes the token once and retries.
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = request
        let token = try await tokens.token()
        attempt.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await send(attempt)
        if response.statusCode == 401 {
            attempt.setValue("Bearer \(try await tokens.refresh(rejected: token))", forHTTPHeaderField: "Authorization")
            (data, response) = try await send(attempt)
        }
        try Self.check(data: data, response: response)
        return (data, response)
    }

    func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let (data, _) = try await perform(request)
        do {
            return try Self.decoder.decode(Envelope<T>.self, from: data).data
        } catch {
            throw HaloChatError.invalidResponse
        }
    }

    func jsonRequest(_ url: URL, method: String, body: Encodable? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HaloChatError.invalidResponse }
        return (data, http)
    }

    static func check(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw HaloChatError.unauthorized
        case 409:
            throw HaloChatError.sendInProgress
        case 429:
            let retryAfter = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1
            throw HaloChatError.rateLimited(retryAfterSeconds: max(1, retryAfter))
        case 400..<500:
            let code = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error
            throw HaloChatError.rejected(status: response.statusCode, code: code ?? nil)
        default:
            throw HaloChatError.server(status: response.statusCode)
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
