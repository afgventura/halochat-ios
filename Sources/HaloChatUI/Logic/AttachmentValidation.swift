#if SWIFT_PACKAGE
import HaloChat
#endif
import Foundation
import UniformTypeIdentifiers

/// Why an attachment cannot be sent. Client-side checks and the server's
/// `upload_too_large` / `upload_type` errors map to the same cases (and messages).
public enum HaloChatAttachmentRejection: Error, Equatable, Sendable {
    case tooLarge
    case unsupportedType

    /// Maps a server error code from `HaloChatError.rejected(status:code:)`.
    public init?(serverCode: String?) {
        switch serverCode {
        case "upload_too_large": self = .tooLarge
        case "upload_type": self = .unsupportedType
        default: return nil
        }
    }

    /// Maps any error thrown by `HaloChatClient.send(attachment:…)`.
    public init?(error: Error) {
        guard case let HaloChatError.rejected(_, code) = error else { return nil }
        self.init(serverCode: code)
    }

    /// The localized message shown to the user.
    public var localizedMessage: String {
        switch self {
        case .tooLarge: return L10n.errorTooLarge
        case .unsupportedType: return L10n.errorUnsupportedType
        }
    }
}

/// Client-side attachment checks, mirroring the server (`halochat-in-app-api.md`).
public enum HaloChatAttachmentValidator {
    /// 25 MB.
    public static let maxBytes = 25 * 1024 * 1024

    public static let allowedMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/gif", "image/heic",
        "video/mp4", "video/quicktime",
        "audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/ogg",
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/plain",
    ]

    /// Non-canonical spellings pickers and OS versions produce for allowed types.
    static let aliases: [String: String] = [
        "image/jpg": "image/jpeg",
        "image/pjpeg": "image/jpeg",
        "audio/mp3": "audio/mpeg",
        "audio/x-mp3": "audio/mpeg",
        "audio/mpeg3": "audio/mpeg",
        "audio/x-mpeg": "audio/mpeg",
        "audio/m4a": "audio/x-m4a",
        "audio/x-aac": "audio/aac",
        "audio/aacp": "audio/aac",
        "application/ogg": "audio/ogg",
        "audio/x-ogg": "audio/ogg",
        "video/mov": "video/quicktime",
    ]

    /// Deterministic extension table, used when the OS type database has no allowed answer.
    static let extensionMIMETypes: [String: String] = [
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp",
        "gif": "image/gif", "heic": "image/heic",
        "mp4": "video/mp4", "mov": "video/quicktime",
        "mp3": "audio/mpeg", "m4a": "audio/x-m4a", "aac": "audio/aac", "ogg": "audio/ogg", "oga": "audio/ogg",
        "pdf": "application/pdf",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "txt": "text/plain",
    ]

    /// Values that say nothing about the content; the extension decides instead.
    static let genericMIMETypes: Set<String> = [
        "application/octet-stream", "application/binary", "binary/octet-stream",
        "application/unknown", "application/x-unknown", "*/*",
    ]

    /// Lowercases, drops parameters (`; charset=…`) and canonicalizes aliases.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let base = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? raw
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return aliases[trimmed] ?? trimmed
    }

    /// The MIME type for a filename's extension (UniformTypeIdentifiers first, then a fixed table).
    public static func mimeType(forFilename filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        let system = normalize(UTType(filenameExtension: ext)?.preferredMIMEType)
        if let system, allowedMIMETypes.contains(system) { return system }
        return extensionMIMETypes[ext] ?? system
    }

    /// The picker's MIME type when it is specific; otherwise the one implied by the extension.
    public static func resolveMIMEType(provided: String?, filename: String) -> String? {
        if let provided = normalize(provided), !genericMIMETypes.contains(provided) {
            return provided
        }
        return mimeType(forFilename: filename)
    }

    /// Validates before any upload. Returns the MIME type to send.
    public static func validate(
        sizeBytes: Int,
        mimeType provided: String?,
        filename: String
    ) -> Result<String, HaloChatAttachmentRejection> {
        guard sizeBytes <= maxBytes else { return .failure(.tooLarge) }
        guard let mime = resolveMIMEType(provided: provided, filename: filename),
              allowedMIMETypes.contains(mime)
        else { return .failure(.unsupportedType) }
        return .success(mime)
    }
}
