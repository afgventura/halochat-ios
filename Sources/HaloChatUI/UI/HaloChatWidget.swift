#if canImport(UIKit)
#if SWIFT_PACKAGE
import HaloChat
#endif
import UIKit

/// The drop-in customer-service chat (the Qiscus `QiscusMultichannelWidget` equivalent).
///
/// Keep one instance for the app's lifetime, e.g. in a `ChatManager` singleton:
/// ```swift
/// let widget = HaloChatWidget(config: .init(), color: HaloChatColor())
/// widget.setUser(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
///     try await MyAPI.haloChatToken(forceRefresh: forceRefresh)
/// })
/// widget.initiateChat()
///     .setRoomTitle(title: "Customer Service")
///     .startChat { chatViewController in
///         navigationController?.pushViewController(chatViewController, animated: true)
///     }
/// ```
public final class HaloChatWidget: @unchecked Sendable {
    public let config: HaloChatWidgetConfig
    public let color: HaloChatColor

    private let lock = NSLock()
    private var currentClient: HaloChatClient?
    private var deviceToken: String?

    public init(config: HaloChatWidgetConfig = .init(), color: HaloChatColor = .init()) {
        self.config = config
        self.color = color
    }

    /// The core client of the signed-in user, for anything the UI does not cover.
    public var client: HaloChatClient? { locked { currentClient } }

    /// Signs a user in. Your backend mints the `hct_` token (identity, display name and phone
    /// go in the mint). A device token registered earlier is bound to this user right away.
    public func setUser(tokenProvider: HaloChatTokenProvider, configuration: HaloChatConfiguration = .init()) {
        let client = HaloChatClient(configuration: configuration, tokenProvider: tokenProvider)
        let token: String? = locked {
            currentClient = client
            return deviceToken
        }
        if let token {
            Task { try? await client.registerPushToken(token) }
        }
    }

    public func isLoggedIn() -> Bool { locked { currentClient != nil } }

    /// Signs out (core `signOut()`): stops this device's pushes and expires its HaloChat token.
    /// The user is cleared locally even when the server call fails.
    public func clearUser() async throws {
        guard let client = locked({ () -> HaloChatClient? in
            let client = currentClient
            currentClient = nil
            return client
        }) else { return }
        try await client.signOut()
    }

    /// Pass the token from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public func register(deviceToken: Data) {
        register(deviceToken: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    /// The APNs device token as hex. Remembered and re-bound on every `setUser`.
    public func register(deviceToken: String) {
        let client: HaloChatClient? = locked {
            self.deviceToken = deviceToken
            return currentClient
        }
        if let client {
            Task { try? await client.registerPushToken(deviceToken) }
        }
    }

    /// Starts configuring a chat screen; finish with `startChat`.
    public func initiateChat() -> HaloChatChatBuilder {
        HaloChatChatBuilder(widget: self)
    }

    // MARK: Push

    /// Whether a push `userInfo` comes from HaloChat (`type == "halochat_message"`).
    public func isHaloChatNotification(userInfo: [AnyHashable: Any]) -> Bool {
        HaloChatNotificationPayload.isHaloChat(userInfo)
    }

    /// For `userNotificationCenter(_:willPresent:)`: false for a HaloChat push while the chat
    /// screen is on screen (the message is already visible); true otherwise.
    public func shouldPresentNotification(userInfo: [AnyHashable: Any]) -> Bool {
        !(HaloChatNotificationPayload.isHaloChat(userInfo) && HaloChatVisibility.isVisible)
    }

    /// For a tapped HaloChat notification: builds the chat screen and hands it to you on the
    /// main thread (push or present it). Does nothing for other notifications.
    public func tapNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping @MainActor (UIViewController) -> Void
    ) {
        guard HaloChatNotificationPayload.isHaloChat(userInfo) else { return }
        initiateChat().startChat(completion)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Configures one chat screen (Qiscus `initiateChat()` chain). Every setter is chainable.
public final class HaloChatChatBuilder {
    let widget: HaloChatWidget
    private(set) var settings: ChatScreenSettings

    init(widget: HaloChatWidget) {
        self.widget = widget
        settings = ChatScreenSettings(config: widget.config)
    }

    /// Header title (default: the conversation title, i.e. the channel label).
    @discardableResult
    public func setRoomTitle(title: String) -> HaloChatChatBuilder {
        settings.roomTitle = title
        return self
    }

    /// `.enabled`: localized "Customer Service"; `.disabled`: none; `.editable`: `subTitle`.
    @discardableResult
    public func setRoomSubTitle(enableSubtitle: RoomSubtitle, subTitle: String? = nil) -> HaloChatChatBuilder {
        settings.roomSubtitle = enableSubtitle
        settings.roomSubtitleText = subTitle
        return self
    }

    /// Show or hide system messages (`senderKind == system`).
    @discardableResult
    public func setShowSystemMessage(isShowing: Bool) -> HaloChatChatBuilder {
        settings.showSystemMessage = isShowing
        return self
    }

    /// Avatar and sender name on the first bubble of each business-side run.
    @discardableResult
    public func setAvatar(_ avatar: Avatar) -> HaloChatChatBuilder {
        settings.avatar = avatar
        return self
    }

    /// Sent once when the chat opens.
    @discardableResult
    public func automaticSendMessage(textMessage: String) -> HaloChatChatBuilder {
        settings.automaticMessage = textMessage
        return self
    }

    /// Pre-filled in the composer; the user decides whether to send it.
    @discardableResult
    public func manualSendMessage(textMessage: String) -> HaloChatChatBuilder {
        settings.manualMessage = textMessage
        return self
    }

    /// Builds the chat screen and hands it to you on the main thread (synchronously when
    /// called on the main thread). Push it on your navigation controller, or present it
    /// wrapped in a `UINavigationController` (it then shows a close button).
    public func startChat(_ completion: @escaping @MainActor (UIViewController) -> Void) {
        let widget = widget
        let settings = settings
        let work: @MainActor () -> Void = {
            completion(HaloChatViewController(widget: widget, settings: settings))
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }

    /// The chat screen, for hosts that build it directly (e.g. `HaloChatView`).
    @MainActor
    public func makeViewController() -> HaloChatViewController {
        HaloChatViewController(widget: widget, settings: settings)
    }
}
#endif
