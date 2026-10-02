import HaloChat
import SwiftUI

@main
struct SampleApp: App {
    @StateObject private var model = ChatModel()

    var body: some Scene {
        WindowGroup {
            ChatView(model: model).task { await model.start() }
        }
    }
}

/// One signed-in app user's chat. In your app, `user` is your own user id and the
/// token comes from YOUR backend after your own login (see backend/server.mjs).
@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [HaloChatMessage] = []
    @Published var status = "Connecting…"
    @Published var draft = ""

    private let client: HaloChatClient

    init(backend: URL = URL(string: "http://127.0.0.1:8791")!, user: String = "sample-user-1") {
        client = HaloChatClient(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
            // forceRefresh == true means HaloAI refused the last token: mint a new one.
            var url = URLComponents(url: backend.appendingPathComponent("halochat-token"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "user", value: user), URLQueryItem(name: "refresh", value: forceRefresh ? "1" : "0")]
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let token = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String
            else { throw URLError(.userAuthenticationRequired) }
            return token
        })
    }

    func start() async {
        do {
            let conversation = try await client.conversation()
            status = conversation.title ?? "Chat"
        } catch {
            status = "Couldn't connect: \(error)"
        }
        // Backfill + realtime + polling fallback; ends when the view's task is cancelled.
        for await snapshot in client.timeline(onError: { error in
            Task { @MainActor in self.status = "Reconnecting… (\(error))" }
        }) {
            messages = snapshot
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let id = UUID() // keep it until the send succeeds; a retry with the same id never duplicates
        Task {
            do { try await client.send(text: text, clientMessageId: id) } catch { status = "Send failed: \(error)" }
        }
    }
}

struct ChatView: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.status).font(.headline).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.messages) { Bubble(message: $0).id($0.id) }
                    }
                    .padding(12)
                }
                .onChange(of: model.messages.count) { _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                TextField("Message", text: $model.draft).textFieldStyle(.roundedBorder)
                Button("Send", action: model.send).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

struct Bubble: View {
    let message: HaloChatMessage

    var body: some View {
        let mine = message.sender == .me
        HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if message.hasMedia { Label(message.mediaFilename ?? "attachment", systemImage: "paperclip").font(.footnote) }
                if let text = message.text, !text.isEmpty { Text(text) }
            }
            .padding(10)
            .background(mine ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !mine { Spacer(minLength: 48) }
        }
    }
}
