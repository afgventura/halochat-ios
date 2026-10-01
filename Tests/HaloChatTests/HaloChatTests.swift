import Foundation
import XCTest
@testable import HaloChat

/// Serves canned responses and records requests. One queue per test (reset in setUp).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Canned {
        let status: Int
        let body: String
        var headers: [String: String] = [:]
    }

    nonisolated(unsafe) static var queue: [Canned] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            recorded.httpBody = data
        }
        Self.requests.append(recorded)
        let canned = Self.queue.isEmpty ? Canned(status: 500, body: "{}") : Self.queue.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: canned.status, httpVersion: nil, headerFields: canned.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

actor TokenCounter {
    var minted = 0
    var forcedRefreshes = 0
    func next(forceRefresh: Bool) -> String {
        if forceRefresh { forcedRefreshes += 1 }
        if forceRefresh || minted == 0 { minted += 1 }
        return "hct_token_\(minted)"
    }
}

final class HaloChatTests: XCTestCase {
    var client: HaloChatClient!
    var tokens: TokenCounter!

    let messageJSON = """
    {"id":"m1","text":"halo","sender":"me","senderKind":"customer","hasMedia":false,"mediaType":null,"mediaFilename":null,"createdAt":"2026-09-29T08:00:00.123Z","status":"read"}
    """

    override func setUp() {
        StubProtocol.queue = []
        StubProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let tokens = TokenCounter()
        self.tokens = tokens
        client = HaloChatClient(
            configuration: HaloChatConfiguration(baseURL: URL(string: "https://example.test")!),
            tokenProvider: HaloChatClosureTokenProvider { force in await tokens.next(forceRefresh: force) },
            session: URLSession(configuration: config)
        )
    }

    func testSendSetsIdempotencyKeyAndDecodesMessage() async throws {
        StubProtocol.queue = [.init(status: 200, body: #"{"status":"ok","data":{"message":\#(messageJSON)}}"#)]
        let key = UUID()
        let message = try await client.send(text: "halo", clientMessageId: key)

        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.sender, .me)
        XCTAssertEqual(message.status, .read)
        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/client/inApp/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString.lowercased())
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hct_token_1")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["text"] as? String, "halo")
    }

    func testUnauthorizedRefreshesTokenOnceAndRetries() async throws {
        StubProtocol.queue = [
            .init(status: 401, body: #"{"status":"error","error":"invalid_token"}"#),
            .init(status: 200, body: #"{"status":"ok","data":{"roomId":"r1","title":"Acme Support"}}"#),
        ]
        let conversation = try await client.conversation()

        XCTAssertEqual(conversation, HaloChatConversation(roomId: "r1", title: "Acme Support"))
        XCTAssertEqual(StubProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer hct_token_1", "Bearer hct_token_2"])
    }

    func testSecondUnauthorizedSurfacesError() async {
        StubProtocol.queue = [.init(status: 401, body: "{}"), .init(status: 401, body: "{}")]
        do {
            _ = try await client.conversation()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? HaloChatError, .unauthorized)
        }
        XCTAssertEqual(StubProtocol.requests.count, 2)
    }

    func testRateLimitAndConflictMapping() async {
        StubProtocol.queue = [.init(status: 429, body: "{}", headers: ["Retry-After": "7"])]
        do { _ = try await client.latestMessages(); XCTFail() } catch {
            XCTAssertEqual(error as? HaloChatError, .rateLimited(retryAfterSeconds: 7))
        }
        StubProtocol.queue = [.init(status: 409, body: "{}")]
        do { _ = try await client.send(text: "x"); XCTFail() } catch {
            XCTAssertEqual(error as? HaloChatError, .sendInProgress)
        }
        StubProtocol.queue = [.init(status: 400, body: #"{"status":"error","error":"invalid_text"}"#)]
        do { _ = try await client.send(text: ""); XCTFail() } catch {
            XCTAssertEqual(error as? HaloChatError, .rejected(status: 400, code: "invalid_text"))
        }
    }

    func testHistoryQueryAndCursorPassThrough() async throws {
        StubProtocol.queue = [.init(status: 200, body: #"{"status":"ok","data":{"messages":[\#(messageJSON)],"newestCursor":"c2","oldestCursor":"c1"}}"#)]
        let page = try await client.messages(after: "c1")

        XCTAssertEqual(page.newestCursor, "c2")
        let url = try XCTUnwrap(StubProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "after" }?.value, "c1")
    }

    func testPushTokenHexEncodingAndDevicesCall() async throws {
        StubProtocol.queue = [.init(status: 200, body: #"{"status":"ok","data":{}}"#)]
        try await client.registerPushToken(Data([0x0a, 0xff]))

        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/client/inApp/v1/devices")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
        XCTAssertEqual(body, ["platform": "ios", "pushToken": "0aff"])
    }

    func testMergerDedupesAndOrders() {
        var merger = MessageMerger()
        let early = HaloChatMessage(id: "b", text: "1", sender: .me, senderKind: .customer, createdAt: Date(timeIntervalSince1970: 10))
        let late = HaloChatMessage(id: "a", text: "2", sender: .agent, senderKind: .ai, createdAt: Date(timeIntervalSince1970: 20))

        XCTAssertTrue(merger.merge([late, early]))
        XCTAssertFalse(merger.merge([early]), "an overlapping re-delivery is not a change")
        XCTAssertEqual(merger.ordered.map(\.id), ["b", "a"])

        let read = HaloChatMessage(id: "b", text: "1", sender: .me, senderKind: .customer, createdAt: early.createdAt, status: .read)
        XCTAssertTrue(merger.merge([read]), "a status update replaces the message")
        XCTAssertEqual(merger.ordered.first?.status, .read)
        XCTAssertTrue(merger.remove(id: "a"))
        XCTAssertEqual(merger.ordered.map(\.id), ["b"])
    }

    func testRealtimeEventDecoding() {
        XCTAssertEqual(RealtimeEvent.decode(#"{"type":"authenticated","roomId":"r"}"#), .authenticated)
        XCTAssertEqual(RealtimeEvent.decode(#"{"type":"message_deleted","id":"m9"}"#), .deleted("m9"))
        guard case let .message(message) = RealtimeEvent.decode(#"{"type":"message","message":\#(messageJSON)}"#) else {
            return XCTFail("expected message")
        }
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(RealtimeEvent.decode(#"{"type":"heartbeat"}"#), .other)
        XCTAssertEqual(RealtimeEvent.decode("not json"), .other)
    }

    func testDateParsingAcceptsFractionalAndPlainSeconds() {
        XCTAssertNotNil(Transport.parseISO8601("2026-09-29T08:00:00.123Z"))
        XCTAssertNotNil(Transport.parseISO8601("2026-09-29T08:00:00Z"))
        XCTAssertNotNil(Transport.parseISO8601("2026-09-29T08:00:00.123456+00:00"))
    }

    func testStorageURLsResolveAgainstBaseURL() {
        XCTAssertEqual(client.resolve("/bff/object-storage/upload?token=x")?.absoluteString, "https://example.test/bff/object-storage/upload?token=x")
        XCTAssertEqual(client.resolve("https://cdn.example/a.png")?.absoluteString, "https://cdn.example/a.png")
    }

    func testConcurrent401sRefreshTheTokenOnce() async throws {
        StubProtocol.queue = [
            .init(status: 401, body: "{}"),
            .init(status: 401, body: "{}"),
            .init(status: 200, body: #"{"status":"ok","data":{"roomId":"r1","title":null}}"#),
            .init(status: 200, body: #"{"status":"ok","data":{"roomId":"r1","title":null}}"#),
        ]
        async let first = client.conversation()
        async let second = client.conversation()
        _ = try await (first, second)

        let refreshes = await tokens.forcedRefreshes
        XCTAssertEqual(refreshes, 1, "two concurrent 401s must mint one new token, not two")
    }

    func testUnknownEnumValuesDoNotFailThePage() async throws {
        let future = #"{"id":"m2","text":"x","sender":"bot_v2","senderKind":"robot","createdAt":"2026-09-29T08:00:00.000Z","status":"seen"}"#
        StubProtocol.queue = [.init(status: 200, body: #"{"status":"ok","data":{"messages":[\#(future)],"newestCursor":"c","oldestCursor":"c"}}"#)]
        let page = try await client.latestMessages()

        XCTAssertEqual(page.messages.first?.sender, .agent)
        XCTAssertEqual(page.messages.first?.senderKind, .system)
        XCTAssertNil(page.messages.first?.status)
    }

    func testSignOutUnregistersThenExpiresTheSession() async throws {
        StubProtocol.queue = [
            .init(status: 200, body: #"{"status":"ok","data":{}}"#),
            .init(status: 200, body: #"{"status":"ok","data":{}}"#),
            .init(status: 200, body: #"{"status":"ok","data":{}}"#),
        ]
        try await client.registerPushToken("abcd1234abcd1234")
        try await client.signOut()

        let calls = StubProtocol.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
        XCTAssertEqual(calls, [
            "POST /api/client/inApp/v1/devices",
            "DELETE /api/client/inApp/v1/devices",
            "DELETE /api/client/inApp/v1/session",
        ])
    }

    func testPushTokenIsReRegisteredAfterAForcedRefresh() async throws {
        StubProtocol.queue = [
            .init(status: 200, body: #"{"status":"ok","data":{}}"#),
            .init(status: 401, body: "{}"),
            .init(status: 200, body: #"{"status":"ok","data":{"roomId":"r1","title":null}}"#),
            .init(status: 200, body: #"{"status":"ok","data":{}}"#),
        ]
        try await client.registerPushToken("abcd1234abcd1234")
        _ = try await client.conversation()
        // The re-registration runs in the background after the refresh.
        for _ in 0..<50 where StubProtocol.requests.count < 4 { try await Task.sleep(nanoseconds: 20_000_000) }

        let last = try XCTUnwrap(StubProtocol.requests.last)
        XCTAssertEqual(last.url?.path, "/api/client/inApp/v1/devices")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer hct_token_2")
    }
}
