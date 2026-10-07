#if canImport(UIKit)
import UIKit

/// Chat screen colors, with the same 15 setter names as the Qiscus Multichannel Widget.
/// Left = business side (AI / human / automation), right = the app user.
///
/// Defaults are neutral and adapt to dark mode. Setters are chainable:
/// ```swift
/// let color = HaloChatColor()
///     .setNavigationColor(.systemTeal)
///     .setRightBubbleColor(.systemTeal)
///     .setRightBubbleTextColor(.white)
/// ```
public final class HaloChatColor: @unchecked Sendable {
    public private(set) var navigationColor: UIColor
    public private(set) var navigationTitleColor: UIColor
    public private(set) var sendContainerColor: UIColor
    public private(set) var sendContainerBackgroundColor: UIColor
    public private(set) var fieldChatBorderColor: UIColor
    public private(set) var systemEventTextColor: UIColor
    public private(set) var leftBubbleColor: UIColor
    public private(set) var rightBubbleColor: UIColor
    public private(set) var leftBubbleTextColor: UIColor
    public private(set) var rightBubbleTextColor: UIColor
    public private(set) var timeLabelTextColor: UIColor
    public private(set) var timeBackgroundColor: UIColor
    public private(set) var baseColor: UIColor
    public private(set) var emptyTextColor: UIColor
    public private(set) var emptyBackgroundColor: UIColor

    public init() {
        let accent = Self.dynamic(light: 0x0A7E8C, dark: 0x38B6C6)
        navigationColor = Self.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
        navigationTitleColor = .label
        sendContainerColor = accent
        sendContainerBackgroundColor = Self.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
        fieldChatBorderColor = Self.dynamic(light: 0xD1D1D6, dark: 0x3A3A3C)
        systemEventTextColor = .secondaryLabel
        leftBubbleColor = Self.dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
        rightBubbleColor = Self.dynamic(light: 0xD3F1F5, dark: 0x0B5560)
        leftBubbleTextColor = .label
        rightBubbleTextColor = .label
        timeLabelTextColor = .secondaryLabel
        timeBackgroundColor = Self.dynamic(light: 0xFFFFFF, dark: 0x2C2C2E, lightAlpha: 0.92, darkAlpha: 0.92)
        baseColor = Self.dynamic(light: 0xEEF0F2, dark: 0x0B0B0C)
        emptyTextColor = .secondaryLabel
        emptyBackgroundColor = .clear
    }

    /// Header background.
    @discardableResult public func setNavigationColor(_ color: UIColor) -> HaloChatColor { navigationColor = color; return self }
    /// Room title, subtitle and back / close button.
    @discardableResult public func setNavigationTitleColor(_ color: UIColor) -> HaloChatColor { navigationTitleColor = color; return self }
    /// Send and attach icons.
    @discardableResult public func setSendContainerColor(_ color: UIColor) -> HaloChatColor { sendContainerColor = color; return self }
    /// Composer bar background.
    @discardableResult public func setSendContainerBackgroundColor(_ color: UIColor) -> HaloChatColor { sendContainerBackgroundColor = color; return self }
    /// Text field border.
    @discardableResult public func setFieldChatBorderColor(_ color: UIColor) -> HaloChatColor { fieldChatBorderColor = color; return self }
    /// System message text and border.
    @discardableResult public func setSystemEventTextColor(_ color: UIColor) -> HaloChatColor { systemEventTextColor = color; return self }
    /// Business-side bubbles.
    @discardableResult public func setLeftBubbleColor(_ color: UIColor) -> HaloChatColor { leftBubbleColor = color; return self }
    /// The app user's bubbles.
    @discardableResult public func setRightBubbleColor(_ color: UIColor) -> HaloChatColor { rightBubbleColor = color; return self }
    @discardableResult public func setLeftBubbleTextColor(_ color: UIColor) -> HaloChatColor { leftBubbleTextColor = color; return self }
    @discardableResult public func setRightBubbleTextColor(_ color: UIColor) -> HaloChatColor { rightBubbleTextColor = color; return self }
    /// Message times and the date separator text.
    @discardableResult public func setTimeLabelTextColor(_ color: UIColor) -> HaloChatColor { timeLabelTextColor = color; return self }
    /// Date separator background.
    @discardableResult public func setTimeBackgroundColor(_ color: UIColor) -> HaloChatColor { timeBackgroundColor = color; return self }
    /// Chat background.
    @discardableResult public func setBaseColor(_ color: UIColor) -> HaloChatColor { baseColor = color; return self }
    @discardableResult public func setEmptyTextColor(_ color: UIColor) -> HaloChatColor { emptyTextColor = color; return self }
    /// Empty state background (`.clear` shows the base color).
    @discardableResult public func setEmptyBackgroundColor(_ color: UIColor) -> HaloChatColor { emptyBackgroundColor = color; return self }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark, alpha: darkAlpha) : rgb(light, alpha: lightAlpha)
        }
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
