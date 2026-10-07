import HaloChat
import HaloChatUI
import SwiftUI
import UIKit
import UserNotifications

/// One widget for the app's lifetime (the Qiscus `ChatManager` pattern).
final class ChatManager {
    static let shared = ChatManager()

    let widget = HaloChatWidget(
        config: HaloChatWidgetConfig(roomSubtitle: .enabled, showSystemMessage: true, avatar: .enabled),
        color: HaloChatColor()
    )

    /// The stand-in backend (backend/server.mjs). Your app calls YOUR backend after your own login.
    private let backend = URL(string: "http://127.0.0.1:8791")!

    func signIn(user: String) {
        guard !widget.isLoggedIn() else { return }
        let backend = backend
        // Defaults to HaloAI production. `-haloBaseURL http://…` points the sample elsewhere.
        var configuration = HaloChatConfiguration()
        if let raw = UserDefaults.standard.string(forKey: "haloBaseURL"), let base = URL(string: raw) {
            configuration.baseURL = base
            configuration.realtimeURL = URL(string: "ws://\(base.host ?? "127.0.0.1"):\(base.port ?? 80)/ws/client")!
        }
        widget.setUser(tokenProvider: HaloChatClosureTokenProvider { forceRefresh in
            // forceRefresh == true means HaloAI refused the last token: mint a new one.
            var url = URLComponents(url: backend.appendingPathComponent("halochat-token"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "user", value: user), URLQueryItem(name: "refresh", value: forceRefresh ? "1" : "0")]
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let token = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String
            else { throw URLError(.userAuthenticationRequired) }
            return token
        }, configuration: configuration)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Your app asks for notification permission when it suits your onboarding.
        application.registerForRemoteNotifications()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ChatManager.shared.widget.register(deviceToken: deviceToken)
    }

    // Foreground push: hide HaloChat pushes while the chat is already on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let show = ChatManager.shared.widget.shouldPresentNotification(userInfo: notification.request.content.userInfo)
        completionHandler(show ? [.banner, .sound] : [])
    }

    // Tapped push: open the chat.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        ChatManager.shared.widget.tapNotification(userInfo: response.notification.request.content.userInfo) { [weak self] chat in
            (self?.window?.rootViewController as? UINavigationController)?.pushViewController(chat, animated: true)
        }
        completionHandler()
    }
}

final class HomeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "HaloChat Sample"
        view.backgroundColor = .systemBackground

        var push = UIButton.Configuration.filled()
        push.title = "Chat with CS"
        push.cornerStyle = .large
        let pushButton = UIButton(configuration: push, primaryAction: UIAction { [weak self] _ in self?.openChat() })

        var sheet = UIButton.Configuration.tinted()
        sheet.title = "Open in a SwiftUI sheet"
        sheet.cornerStyle = .large
        let sheetButton = UIButton(configuration: sheet, primaryAction: UIAction { [weak self] _ in self?.openSwiftUISheet() })

        let stack = UIStackView(arrangedSubviews: [pushButton, sheetButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 260),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if UserDefaults.standard.bool(forKey: "autoOpenChat"), navigationController?.topViewController === self, presentedViewController == nil {
            UserDefaults.standard.removeObject(forKey: "autoOpenChat")
            openChat()
        }
    }

    private func openChat() {
        ChatManager.shared.signIn(user: "sample-user-1")
        ChatManager.shared.widget.initiateChat()
            .setRoomTitle(title: "Customer Service")
            .setRoomSubTitle(enableSubtitle: .editable, subTitle: "We usually reply in a few minutes")
            .setShowSystemMessage(isShowing: true)
            .setAvatar(.enabled)
            .startChat { [weak self] chat in
                self?.navigationController?.pushViewController(chat, animated: true)
            }
    }

    private func openSwiftUISheet() {
        ChatManager.shared.signIn(user: "sample-user-1")
        let host = UIHostingController(rootView: HaloChatView(widget: ChatManager.shared.widget) {
            $0.setRoomTitle(title: "Customer Service")
        })
        present(host, animated: true)
    }
}
