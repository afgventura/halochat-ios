# HaloChat for iOS

Put your signed-in users in a chat with your team (HaloAI's AI agent + your human
agents) from inside your own iOS app. Core SDK only: networking, auth, realtime,
push, attachments. Your app owns the UI.

You need a HaloAI account with a HaloChat channel; your HaloAI team provides it together with
the integration guide.

## Install

iOS 15+, Swift 5.9+ (Xcode 15+).

- **Swift Package Manager:** Xcode -> File -> Add Package Dependencies ->
  `https://github.com/afgventura/halochat-ios` -> version `0.1.0` -> add the `HaloChat` product.
  In a `Package.swift`: `.package(url: "https://github.com/afgventura/halochat-ios.git", from: "0.1.0")`.
- **CocoaPods:** `pod 'HaloChat', :git => 'https://github.com/afgventura/halochat-ios.git', :tag => '0.1.0'`

## 1. Your backend mints the token

Never put a HaloAI PAT in the app. After your own login succeeds, your server calls
`POST /api/open/inApp/v1/clientToken` with its PAT and returns the `hct_…` token.

## 2. Create the client

```swift
import HaloChat

let chat = HaloChatClient(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
    // forceRefresh == true means HaloAI refused the last token: mint a new one.
    try await MyAPI.haloChatToken(forceRefresh: forceRefresh)
})
```

## 3. Show the conversation

```swift
let task = Task {
    let stream = chat.timeline(onError: { error in
        // Offline / rate limited: the stream keeps retrying by itself.
        // HaloChatError.unauthorized: your token provider can no longer mint; sign in again.
        Task { @MainActor in self.banner = "\(error)" }
    })
    for await messages in stream {                    // backfill + realtime + polling fallback
        await MainActor.run { self.messages = messages }  // ascending, de-duplicated
    }
}
// On leaving the chat screen:
task.cancel()
```

`message.sender` is `.me` (your user) or `.agent` (AI / human / automation;
see `senderKind`). Older pages: `try await chat.messages(before: oldestCursor)`; keep
them in your own list and merge with the timeline by `id` (the stream carries the
live window only).

## 4. Send

```swift
let id = UUID()                      // keep it until the send succeeds
try await chat.send(text: "Halo", clientMessageId: id)
// Timed out? Retry with the SAME id: it can never create a second message.

try await chat.send(attachment: jpegData, filename: "ktp.jpg", mimeType: "image/jpeg", caption: "KTP saya")
let url = try await chat.mediaURL(for: message.id)   // short-lived download URL
```

## 5. Push (background)

```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    Task { try? await chat.registerPushToken(token) }
}
// On sign-out, before discarding the provider:
try await chat.unregisterPushToken(hexToken)
```

Register after every sign-in. The SDK remembers the token and re-registers it by
itself whenever it re-mints your HaloChat token, so pushes keep flowing.

## 6. Sign out

```swift
try await chat.signOut()   // stops this device's pushes and expires its HaloChat token
```

HaloAI sends pushes with **your** APNs key; share it once through the HaloAI team
(`channel_in_app_set_push_credentials`). Payload `userInfo`:
`{"type":"halochat_message","roomId":…,"messageId":…}`.

## Errors

`HaloChatError`: `.unauthorized` (token refused after one refresh), `.rateLimited(retryAfterSeconds:)`,
`.sendInProgress` (same id still running; re-read then retry), `.rejected(status:code:)`, `.server(status:)`,
`.invalidResponse`. Errors thrown by your token provider are passed through unchanged.

## Coming from Qiscus

| Qiscus | HaloChat |
|---|---|
| `QiscusCore.setup(WithAppID:)` | `HaloChatClient(configuration:tokenProvider:)` |
| `QiscusCore.setUser` / JWT nonce | backend-minted `hct_` token via `tokenProvider` |
| `chatUser` / room list | `conversation()` (one CS room per user) |
| `sendMessage` | `send(text:clientMessageId:)`, `send(attachment:…)` |
| realtime delegates (MQTT) | `timeline()` `AsyncStream` |
| `QiscusCore.shared.register(deviceToken:)` | `registerPushToken(_:)` |
| `QiscusCore.clearUser` | `signOut()` + drop the client |

## Develop

`swift test` (from this directory).
