import Foundation

/// Locates the UI kit's resources under SwiftPM (`Bundle.module`) and CocoaPods
/// (the `HaloChatUI.bundle` resource bundle next to this code).
final class HaloChatUIResources {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: HaloChatUIResources.self)
        if let url = host.url(forResource: "HaloChatUI", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return host
        #endif
    }()

    /// The `.lproj` matching the device language (English or Indonesian), picked per bundle so
    /// it follows the device even when the host app itself is not localized into Indonesian.
    static let localizedBundle: Bundle = {
        let available = bundle.localizations.filter { $0 != "Base" }
        let preferred = Bundle.preferredLocalizations(from: available, forPreferences: Locale.preferredLanguages)
        for localization in preferred + ["en"] {
            if let path = bundle.path(forResource: localization, ofType: "lproj"), let lproj = Bundle(path: path) {
                return lproj
            }
        }
        return bundle
    }()
}

/// Localized strings (English + Indonesian).
enum L10n {
    static func string(_ key: String) -> String {
        let value = HaloChatUIResources.localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if value != key { return value }
        // Missing in the device language: fall back to English rather than the raw key.
        if let path = HaloChatUIResources.bundle.path(forResource: "en", ofType: "lproj"), let english = Bundle(path: path) {
            return english.localizedString(forKey: key, value: key, table: "Localizable")
        }
        return key
    }

    static var subtitleCustomerService: String { string("subtitle.customer_service") }
    static var defaultTitle: String { string("title.default") }
    static var emptyMessage: String { string("empty.message") }
    static var bannerReconnecting: String { string("banner.reconnecting") }
    static var bannerRateLimited: String { string("banner.rate_limited") }
    static var bannerSessionExpired: String { string("banner.session_expired") }
    static var dateToday: String { string("date.today") }
    static var dateYesterday: String { string("date.yesterday") }
    static var composerPlaceholder: String { string("composer.placeholder") }
    static var attachTitle: String { string("attach.title") }
    static var attachCamera: String { string("attach.camera") }
    static var attachGallery: String { string("attach.gallery") }
    static var attachDocument: String { string("attach.document") }
    static var cancel: String { string("common.cancel") }
    static var close: String { string("common.close") }
    static var ok: String { string("common.ok") }
    static var errorTitle: String { string("error.title") }
    static var errorTooLarge: String { string("error.too_large") }
    static var errorUnsupportedType: String { string("error.unsupported_type") }
    static var errorSendFailed: String { string("error.send_failed") }
    static var errorFileRead: String { string("error.file_read") }
    static var errorOpenFailed: String { string("error.open_failed") }
    static var errorCameraUnavailable: String { string("error.camera_unavailable") }
    static var messageTapToRetry: String { string("message.tap_to_retry") }
    static var messageRetry: String { string("message.retry") }
    static var messageDelete: String { string("message.delete") }
    static var fileTapToOpen: String { string("file.tap_to_open") }
    static var fileAttachment: String { string("file.attachment") }
    static var statusSending: String { string("status.sending") }
    static var statusFailed: String { string("status.failed") }
    static var statusSent: String { string("status.sent") }
    static var statusRead: String { string("status.read") }
    static var accessibilityAttach: String { string("a11y.attach") }
    static var accessibilitySend: String { string("a11y.send") }
}
