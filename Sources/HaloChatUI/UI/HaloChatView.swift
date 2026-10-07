#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// The chat screen for SwiftUI hosts, inside its own navigation bar.
/// Present it (`.sheet` / `.fullScreenCover`, which adds a close button) or use it as a root view.
///
/// ```swift
/// .sheet(isPresented: $showChat) {
///     HaloChatView(widget: ChatManager.shared.widget) { $0.setRoomTitle(title: "Customer Service") }
/// }
/// ```
public struct HaloChatView: UIViewControllerRepresentable {
    private let builder: HaloChatChatBuilder

    public init(widget: HaloChatWidget, configure: (HaloChatChatBuilder) -> HaloChatChatBuilder = { $0 }) {
        builder = configure(widget.initiateChat())
    }

    public init(builder: HaloChatChatBuilder) {
        self.builder = builder
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: builder.makeViewController())
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
#endif
