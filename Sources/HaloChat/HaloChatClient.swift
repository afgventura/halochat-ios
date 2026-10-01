import Foundation

/// Where the SDK talks to. Defaults are HaloAI production.
public struct HaloChatConfiguration: Sendable {
    public var baseURL: URL
    public var realtimeURL: URL
    /// Foreground polling interval used when the realtime socket is unavailable.
    public var pollInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "https://www.haloai.co.id")!,
        realtimeURL: URL = URL(string: "wss://conn3.haloai.co.id/ws/client")!,
        pollInterval: TimeInterval = 5
    ) {
        self.baseURL = baseURL
        self.realtimeURL = realtimeURL
        self.pollInterval = pollInterval
    }
}

/// The HaloChat client for one signed-in app user.
///
/// ```swift
/// let chat = HaloChatClient(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
///     try await myBackend.haloChatToken(forceRefresh: forceRefresh)
/// })
/// for await timeline in chat.timeline() { render(timeline) }
/// try await chat.send(text: "Halo")
/// ```
public final class HaloChatClient: Sendable {
    let transport: Transport
    let push = PushRegistration()
    public let configuration: HaloChatConfiguration

    public init(
        configuration: HaloChatConfiguration = HaloChatConfiguration(),
        tokenProvider: HaloChatTokenProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        transport = Transport(baseURL: configuration.baseURL, session: session, tokenProvider: tokenProvider)
        // Every mint is a new server session; re-bind this device's push token to it.
        let transport = transport
        let push = push
        Task {
            await transport.tokens.setOnRefreshed {
                guard let token = await push.token else { return }
                _ = try? await transport.perform(
                    transport.jsonRequest(
                        transport.url("devices"),
                        method: "POST",
                        body: DeviceRequest(platform: "ios", pushToken: token)
                    )
                )
            }
        }
    }

    /// The user's conversation with the business.
    public func conversation() async throws -> HaloChatConversation {
        try await transport.decode(HaloChatConversation.self, transport.jsonRequest(transport.url("conversation"), method: "GET"))
    }

    /// The newest page of history (ascending).
    public func latestMessages(limit: Int = 50) async throws -> HaloChatMessagePage {
        try await page([URLQueryItem(name: "limit", value: String(limit))])
    }

    /// Messages newer than `cursor`. The server re-sends a few seconds of overlap; merge by `id`.
    public func messages(after cursor: String, limit: Int = 100) async throws -> HaloChatMessagePage {
        try await page([URLQueryItem(name: "after", value: cursor), URLQueryItem(name: "limit", value: String(limit))])
    }

    /// Messages older than `cursor` (scroll back).
    public func messages(before cursor: String, limit: Int = 50) async throws -> HaloChatMessagePage {
        try await page([URLQueryItem(name: "before", value: cursor), URLQueryItem(name: "limit", value: String(limit))])
    }

    /// Sends a text message.
    ///
    /// `clientMessageId` is the idempotency key: retrying with the SAME id after a timeout
    /// can never create a second message. Use a new id only for a new message.
    @discardableResult
    public func send(text: String, clientMessageId: UUID = UUID()) async throws -> HaloChatMessage {
        try await sendMessage(SendBody(text: text, uploadId: nil), clientMessageId: clientMessageId)
    }

    /// Uploads an attachment and sends it, optionally with a caption.
    @discardableResult
    public func send(
        attachment data: Data,
        filename: String,
        mimeType: String,
        caption: String? = nil,
        clientMessageId: UUID = UUID()
    ) async throws -> HaloChatMessage {
        let upload: UploadTicket = try await transport.decode(
            UploadTicket.self,
            transport.jsonRequest(
                transport.url("uploads"),
                method: "POST",
                body: UploadRequest(filename: filename, mimeType: mimeType, sizeBytes: data.count)
            )
        )
        guard let uploadURL = resolve(upload.uploadUrl) else { throw HaloChatError.invalidResponse }
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        for (name, value) in upload.uploadHeaders { put.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await transport.session.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HaloChatError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try await sendMessage(SendBody(text: caption, uploadId: upload.uploadId), clientMessageId: clientMessageId)
    }

    /// A short-lived URL for a media message's file.
    public func mediaURL(for messageId: String) async throws -> URL {
        let media: MediaLink = try await transport.decode(
            MediaLink.self,
            transport.jsonRequest(transport.url("media/\(messageId)"), method: "GET")
        )
        guard let url = resolve(media.url) else { throw HaloChatError.invalidResponse }
        return url
    }

    /// Registers this device's APNs token (hex string) for push while the app is in the background.
    /// The SDK remembers it and re-registers automatically whenever it re-mints its token.
    public func registerPushToken(_ apnsToken: String) async throws {
        await push.set(apnsToken)
        _ = try await transport.perform(
            transport.jsonRequest(
                transport.url("devices"),
                method: "POST",
                body: DeviceRequest(platform: "ios", pushToken: apnsToken)
            )
        )
    }

    /// Converts the `Data` from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public func registerPushToken(_ deviceToken: Data) async throws {
        try await registerPushToken(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    /// Signs this device out: stops its pushes and expires its HaloChat token on the server.
    /// Call it before discarding the client (the Qiscus `clearUser` equivalent).
    public func signOut() async throws {
        if let token = await push.token {
            try? await unregisterPushToken(token)
        }
        _ = try await transport.perform(transport.jsonRequest(transport.url("session"), method: "DELETE"))
        await transport.tokens.clear()
    }

    /// Stops push to this device without signing out.
    public func unregisterPushToken(_ apnsToken: String) async throws {
        await push.set(nil)
        _ = try await transport.perform(
            transport.jsonRequest(
                transport.url("devices", query: [URLQueryItem(name: "pushToken", value: apnsToken)]),
                method: "DELETE"
            )
        )
    }

    /// A live, de-duplicated, ascending timeline: history backfill, then realtime socket
    /// events, falling back to polling. Cancel the consuming task to stop it.
    ///
    /// Only the newest snapshot is buffered for a slow consumer. `onError` reports failures
    /// the stream recovers from itself (offline, rate limited) and ones it cannot
    /// (`.unauthorized`: the token provider can no longer mint), so the UI can show them.
    /// Older pages from `messages(before:)` are not part of the stream; merge them by `id`.
    public func timeline(
        initialLimit: Int = 50,
        onError: (@Sendable (Error) -> Void)? = nil
    ) -> AsyncStream<[HaloChatMessage]> {
        Timeline(client: self, initialLimit: initialLimit, onError: onError).stream()
    }

    /// Storage URLs may be absolute or app-relative (a proxy path); resolve against `baseURL`.
    func resolve(_ raw: String) -> URL? {
        URL(string: raw, relativeTo: configuration.baseURL)?.absoluteURL
    }

    private func page(_ query: [URLQueryItem]) async throws -> HaloChatMessagePage {
        try await transport.decode(HaloChatMessagePage.self, transport.jsonRequest(transport.url("messages", query: query), method: "GET"))
    }

    private func sendMessage(_ body: SendBody, clientMessageId: UUID) async throws -> HaloChatMessage {
        var request = try transport.jsonRequest(transport.url("messages"), method: "POST", body: body)
        request.setValue(clientMessageId.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        return try await transport.decode(SentMessage.self, request).message
    }
}

struct SendBody: Encodable {
    let text: String?
    let uploadId: String?
}

struct SentMessage: Decodable {
    let message: HaloChatMessage
}

struct UploadRequest: Encodable {
    let filename: String
    let mimeType: String
    let sizeBytes: Int
}

struct UploadTicket: Decodable {
    let uploadId: String
    let uploadUrl: String
    let uploadHeaders: [String: String]
}

struct MediaLink: Decodable {
    let url: String
}

struct DeviceRequest: Encodable {
    let platform: String
    let pushToken: String
}

/// The APNs token the app registered, remembered so it can be re-bound after a re-mint.
actor PushRegistration {
    private(set) var token: String?

    func set(_ token: String?) {
        self.token = token
    }
}
