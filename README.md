# HaloChat for iOS

Put your signed-in users in a chat with your team (HaloAI's AI agent + your human
agents) from inside your own iOS app.

- **HaloChat UI** (`HaloChatUI`, new in 0.2.0): a drop-in customer-service chat screen
  (UIKit, works in UIKit and SwiftUI apps), shaped like the Qiscus Multichannel Widget, so
  migrating is mostly a rename. Bubbles, file pickers, type/size checks, previews, retry states
  and notification taps are handled for you.
- **HaloChat core** (`HaloChat`): networking, auth, realtime, push, attachments, if you
  want to build your own UI (see [Advanced: core SDK without UI](#advanced-core-sdk-without-ui)).

You need a HaloAI account with a HaloChat channel; your HaloAI team provides it together with
the integration guide.

## Install

iOS 15+, Swift 5.9+ (Xcode 15+).

- **Swift Package Manager:** Xcode -> File -> Add Package Dependencies ->
  `https://github.com/afgventura/halochat-ios` -> version `0.2.0` -> add the **`HaloChatUI`** product
  (it brings `HaloChat` with it). In a `Package.swift`:
  ```swift
  .package(url: "https://github.com/afgventura/halochat-ios.git", from: "0.2.0"),
  // target dependency:
  .product(name: "HaloChatUI", package: "halochat-ios"),
  ```
  Then `import HaloChat` and `import HaloChatUI`.
- **CocoaPods:** `pod 'HaloChat/UI', '~> 0.2.0'` (from the git source until the pod is on trunk:
  `pod 'HaloChat/UI', :git => 'https://github.com/afgventura/halochat-ios.git', :tag => '0.2.0'`).
  With CocoaPods everything is in one module: just `import HaloChat`.
  `pod 'HaloChat'` alone is still core-only.

## Quick start

**1. Your backend mints the token.** Never put the channel's HaloChat server key (`hck_…`) in the
app. After your own login succeeds, your server calls `POST /api/open/inApp/v1/clientToken` with
that key (identity, display name and phone go in the mint) and returns the `hct_…` token.

**2. Create the widget once and set the user** (e.g. after your login):

```swift
import HaloChat
import HaloChatUI   // SwiftPM only

final class ChatManager {
    static let shared = ChatManager()
    let widget = HaloChatWidget(config: HaloChatWidgetConfig(), color: HaloChatColor())

    func signIn() {
        widget.setUser(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
            // forceRefresh == true means HaloAI refused the last token: mint a new one.
            try await MyAPI.haloChatToken(forceRefresh: forceRefresh)
        })
    }
}
```

**3. Open the chat:**

```swift
ChatManager.shared.widget.initiateChat()
    .setRoomTitle(title: "Customer Service")
    .setRoomSubTitle(enableSubtitle: .enabled)
    .setShowSystemMessage(isShowing: true)
    .startChat { chatViewController in
        navigationController?.pushViewController(chatViewController, animated: true)
        // or: present(UINavigationController(rootViewController: chatViewController), animated: true)
        //     (presented modally it shows a close button)
    }
```

SwiftUI:

```swift
.sheet(isPresented: $showChat) {
    HaloChatView(widget: ChatManager.shared.widget) { $0.setRoomTitle(title: "Customer Service") }
}
```

**4. Sign out:** `try await widget.clearUser()` (stops this device's pushes and expires its
HaloChat token).

`widget.isLoggedIn()` tells you whether a user is set; `widget.client` is the core
`HaloChatClient` for anything the UI does not cover.

## What the chat screen does

- Header with title (default: the conversation title, i.e. your channel label) and subtitle.
- Live timeline (history + realtime socket + polling fallback), older pages when the user
  scrolls up, date separators (Today / Yesterday / date), time and ticks on the user's messages
  (clock = sending, ! = not sent, ✓ = sent/delivered, ✓✓ = read). It runs only while the screen
  is visible.
- System messages as centered pills; avatar + name on the first bubble of each agent run.
- Composer: growing text field (max 4096 characters), attach sheet with **Camera**,
  **Gallery** (photos and videos) and **Document**.
- Attachments are checked before upload: max 25 MB; JPEG, PNG, WebP, GIF, HEIC, MP4, MOV, MP3,
  M4A, AAC, OGG, PDF, DOCX, XLSX, TXT. The server's `upload_too_large` / `upload_type` errors show
  the same messages.
- Every message appears immediately. If a send fails, the bubble shows "Tap to retry", and
  the retry reuses the same idempotency key (and the same file bytes), so it can never
  duplicate.
- Images: thumbnails and a zoomable full-screen viewer. Other files: a card that downloads and
  opens in Quick Look.
- Errors: a "Reconnecting…" banner while offline or rate limited; "Session expired" when the
  token provider can no longer mint (the screen stops).
- English and Indonesian, following the device language.

## Customization

### Config (`initiateChat()` chain; widget-wide defaults in `HaloChatWidgetConfig`)

| Method | Description |
|---|---|
| `setRoomTitle(title:)` | Header title. Default: the conversation title (channel label). |
| `setRoomSubTitle(enableSubtitle: .enabled)` | Localized "Customer Service" subtitle (default). |
| `setRoomSubTitle(enableSubtitle: .disabled)` | No subtitle. |
| `setRoomSubTitle(enableSubtitle: .editable, subTitle: "…")` | Your own subtitle. |
| `setShowSystemMessage(isShowing:)` | Show/hide system messages (`senderKind == system`). Default shown. |
| `setAvatar(.enabled / .disabled)` | Avatar (title initial) and name on agent bubbles. Default enabled. |
| `automaticSendMessage(textMessage:)` | Sent once when the chat opens. |
| `manualSendMessage(textMessage:)` | Pre-filled in the composer. |

### Colors (`HaloChatColor`, chainable, `UIColor`)

Defaults are neutral and support dark mode. Left = business side, right = your user.

| # | Setter | Applies to |
|---|---|---|
| 1 | `setNavigationColor` | Header background |
| 2 | `setSendContainerColor` | Send and attach icons, accents |
| 3 | `setFieldChatBorderColor` | Text field border, composer top border |
| 4 | `setSendContainerBackgroundColor` | Composer background |
| 5 | `setNavigationTitleColor` | Title, subtitle, back / close button |
| 6 | `setSystemEventTextColor` | System message text and border |
| 7 | `setLeftBubbleColor` | Agent bubbles |
| 8 | `setRightBubbleColor` | User bubbles |
| 9 | `setLeftBubbleTextColor` | Agent bubble text |
| 10 | `setRightBubbleTextColor` | User bubble text |
| 11 | `setTimeLabelTextColor` | Message times, date separator text |
| 12 | `setTimeBackgroundColor` | Date separator background |
| 13 | `setBaseColor` | Chat background |
| 14 | `setEmptyTextColor` | Empty-state text |
| 15 | `setEmptyBackgroundColor` | Empty-state background (`.clear` = base color) |

```swift
let color = HaloChatColor()
    .setNavigationColor(.systemIndigo)
    .setNavigationTitleColor(.white)
    .setRightBubbleColor(.systemIndigo)
    .setRightBubbleTextColor(.white)
let widget = HaloChatWidget(config: HaloChatWidgetConfig(avatar: .disabled), color: color)
```

## Push notifications

HaloAI sends pushes with **your** APNs key; share it once through the HaloAI team
(`channel_in_app_set_push_credentials`). Payload `userInfo`:
`{"type":"halochat_message","roomId":…,"messageId":…}` with `aps.alert {title, body}`.
The UI kit adds no notification dependency of its own:

```swift
import UserNotifications

final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Remembered and re-bound on every setUser / token re-mint.
        ChatManager.shared.widget.register(deviceToken: deviceToken)
    }

    // Foreground: hide HaloChat pushes while the chat is already on screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let show = ChatManager.shared.widget.shouldPresentNotification(userInfo: notification.request.content.userInfo)
        completionHandler(show ? [.banner, .sound] : [])
    }

    // Tap: open the chat (the completion runs on the main thread).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        ChatManager.shared.widget.tapNotification(userInfo: userInfo) { chat in
            myNavigationController.pushViewController(chat, animated: true)
        }
        completionHandler()
    }
}
```

`widget.isHaloChatNotification(userInfo:)` tells you whether a push is from HaloChat, if you
route your own pushes too.

## Host app Info.plist

| Key | Why |
|---|---|
| `NSCameraUsageDescription` | **Required**: the attach sheet's Camera option. Without it the app crashes on tap. |
| `NSPhotoLibraryUsageDescription` | Not needed by the UI kit (the Gallery uses `PHPickerViewController`); add it only if your app reads the library itself. |

Enable the **Push Notifications** capability for pushes.

## Coming from Qiscus Multichannel Widget

| Qiscus Multichannel Widget | HaloChat UI |
|---|---|
| `pod 'QiscusMultichannelWidget'` | `pod 'HaloChat/UI'` / SwiftPM `HaloChatUI` |
| `QiscusMultichannelWidget(appID:)` | `HaloChatWidget(config:color:)` (no app id: the channel comes from the token) |
| `setUser(id:displayName:avatarUrl:userProperties:)` | `setUser(tokenProvider:)`: your backend mints the `hct_` token (identity, name, phone go in the mint) |
| `isLoggedIn()` | `isLoggedIn()` |
| `initiateChat()…startChat { vc in }` | `initiateChat()…startChat { vc in }` |
| `setRoomTitle(title:)` | `setRoomTitle(title:)` |
| `setRoomSubTitle(enableSubtitle: .enable, subTitle:)` | `setRoomSubTitle(enableSubtitle: .enabled, subTitle:)` (`.enable` also accepted) |
| `setShowSystemMessage(isShowing:)` / `setHideUIEvent` | `setShowSystemMessage(isShowing:)` |
| `setAvatar(.enable / .disabled)` | `setAvatar(.enabled / .disabled)` (`.enable` also accepted) |
| `automaticSendMessage(textMessage:)` | `automaticSendMessage(textMessage:)` |
| `manualSendMessage(textMessage:)` | `manualSendMessage(textMessage:)` |
| `register(deviceToken:isDevelopment:onSuccess:onError:)` | `register(deviceToken:)` (`Data` or hex `String`) |
| `tapNotification(userInfo:)` | `tapNotification(userInfo:) { vc in … }` (you decide how to show it) |
| `setEnableNotification` + foreground handling | `shouldPresentNotification(userInfo:)` in `willPresent` |
| `clearUser()` | `try await clearUser()` |
| 15 color setters | the same 15 names on `HaloChatColor` |
| `setChannelId` | not needed (one token = one channel) |

Interactive components (buttons, product cards) arrive as their text fallback; typing
indicators and voice-note recording are not part of 0.2.

## Sample app

`Example/` is a small UIKit app (with a SwiftUI sheet variant) that opens the widget, plus a
stand-in backend that mints tokens with the channel's server key. See `Example/README.md`.

## Advanced: core SDK without UI

Use the `HaloChat` product (SwiftPM) or `pod 'HaloChat'` (CocoaPods) and build your own screen.

### Create the client

```swift
import HaloChat

let chat = HaloChatClient(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
    try await MyAPI.haloChatToken(forceRefresh: forceRefresh)
})
```

### Show the conversation

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

### Send

```swift
let id = UUID()                      // keep it until the send succeeds
try await chat.send(text: "Halo", clientMessageId: id)
// Timed out? Retry with the SAME id: it can never create a second message.

try await chat.send(attachment: jpegData, filename: "ktp.jpg", mimeType: "image/jpeg", caption: "KTP saya")
let url = try await chat.mediaURL(for: message.id)   // short-lived download URL
```

### Push (background)

```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    Task { try? await chat.registerPushToken(token) }
}
// On sign-out, before discarding the provider:
try await chat.unregisterPushToken(hexToken)
```

Register after every sign-in. The SDK remembers the token and re-registers it by
itself whenever it re-mints your HaloChat token, so pushes keep flowing.

### Sign out

```swift
try await chat.signOut()   // stops this device's pushes and expires its HaloChat token
```

### Errors

`HaloChatError`: `.unauthorized` (token refused after one refresh), `.rateLimited(retryAfterSeconds:)`,
`.sendInProgress` (same id still running; re-read then retry), `.rejected(status:code:)`, `.server(status:)`,
`.invalidResponse`. Errors thrown by your token provider are passed through unchanged.

### Coming from the Qiscus core SDK

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

`swift test` (from this directory) runs the core tests on macOS; build the UI for the
simulator with `xcodebuild -scheme HaloChatUI -destination 'generic/platform=iOS Simulator' build`.
`xcodebuild -scheme HaloChatUI -destination 'generic/platform=iOS Simulator' build` builds the UI kit.

## License

Copyright 2026 HaloAI. Licensed under the [Apache License 2.0](LICENSE): free to use,
modify and ship in your own (including closed-source) app. The SDK holds no secrets;
it only talks to the HaloAI service your business is subscribed to.
