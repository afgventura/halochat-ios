#if canImport(UIKit)
#if SWIFT_PACKAGE
import HaloChat
#endif
import ImageIO
import UIKit

/// Downsamples image bytes with ImageIO without decoding the full-size bitmap.
enum ImageDownsampler {
    static func image(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Loads attachment media. Every load asks the server for a fresh short-lived URL
/// (`mediaURL(for:)`, valid 15 minutes); URLs are never stored, decoded images are.
@MainActor
final class HaloChatMediaLoader {
    enum Size: String {
        case thumbnail
        case full
    }

    /// Decoded images keyed by message id (+ size). Shared across chat screens.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private let client: HaloChatClient
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init(client: HaloChatClient) {
        self.client = client
    }

    func cachedImage(for messageId: String, size: Size) -> UIImage? {
        Self.cache.object(forKey: key(messageId, size))
    }

    func image(for messageId: String, size: Size) async -> UIImage? {
        let cacheKey = key(messageId, size)
        if let cached = Self.cache.object(forKey: cacheKey) { return cached }
        if let running = inflight[cacheKey as String] { return await running.value }
        let maxPixel = maxPixelSize(for: size)
        let client = client
        let task = Task<UIImage?, Never> {
            guard let url = try? await client.mediaURL(for: messageId),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return await Task.detached(priority: .userInitiated) {
                ImageDownsampler.image(from: data, maxPixelSize: maxPixel)
            }.value
        }
        inflight[cacheKey as String] = task
        let image = await task.value
        inflight[cacheKey as String] = nil
        if let image { Self.cache.setObject(image, forKey: cacheKey) }
        return image
    }

    /// Downloads an attachment to a temp file named with its original filename (for Quick Look).
    func downloadFile(messageId: String, filename: String) async throws -> URL {
        let url = try await client.mediaURL(for: messageId)
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HaloChatError.server(status: http.statusCode)
        }
        let destination = try Self.temporaryFileURL(folder: messageId, filename: filename)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    /// Writes local bytes (a not-yet-sent attachment) to a temp file for Quick Look.
    static func writeTemporaryFile(data: Data, folder: String, filename: String) throws -> URL {
        let destination = try temporaryFileURL(folder: folder, filename: filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func temporaryFileURL(folder: String, filename: String) throws -> URL {
        let safeFolder = sanitize(folder)
        var safeName = sanitize(filename)
        if safeName.isEmpty { safeName = "attachment" }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HaloChat", isDirectory: true)
            .appendingPathComponent(safeFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        return destination
    }

    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        return name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func key(_ messageId: String, _ size: Size) -> NSString {
        "\(messageId)#\(size.rawValue)" as NSString
    }

    private func maxPixelSize(for size: Size) -> CGFloat {
        let scale = UIScreen.main.scale
        switch size {
        case .thumbnail: return 240 * scale
        case .full:
            let bounds = UIScreen.main.bounds
            return max(bounds.width, bounds.height) * scale * 2
        }
    }
}
#endif
