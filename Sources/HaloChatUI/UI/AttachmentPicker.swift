#if canImport(UIKit)
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// A picked file that already passed client-side validation.
struct PickedAttachment {
    let data: Data
    let filename: String
    let mimeType: String
}

enum PickFailure: Error {
    case rejected(HaloChatAttachmentRejection)
    case unreadable
    case cameraUnavailable

    var message: String {
        switch self {
        case let .rejected(rejection): return rejection.localizedMessage
        case .unreadable: return L10n.errorFileRead
        case .cameraUnavailable: return L10n.errorCameraUnavailable
        }
    }
}

/// The attach sheet: Camera (photo), Gallery (photo / video), Document (any allowed file).
/// Validates size and type BEFORE reading the bytes into memory.
///
/// Camera needs `NSCameraUsageDescription` in the host app's Info.plist. The Gallery uses
/// `PHPickerViewController`, which needs no photo-library permission.
final class AttachmentPickerCoordinator: NSObject {
    weak var presenter: UIViewController?
    var onResult: ((Result<PickedAttachment, PickFailure>) -> Void)?

    /// The document picker's allow-list, matching the server's MIME types.
    static let documentTypes: [UTType] = {
        var types: [UTType] = [.jpeg, .png, .webP, .gif, .heic, .mpeg4Movie, .quickTimeMovie, .mp3, .mpeg4Audio, .pdf, .plainText]
        for ext in ["aac", "ogg", "docx", "xlsx"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()

    func presentMenu(from source: UIView) {
        guard let presenter else { return }
        let sheet = UIAlertController(title: L10n.attachTitle, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.attachCamera, style: .default) { [weak self] _ in self?.presentCamera() })
        sheet.addAction(UIAlertAction(title: L10n.attachGallery, style: .default) { [weak self] _ in self?.presentGallery() })
        sheet.addAction(UIAlertAction(title: L10n.attachDocument, style: .default) { [weak self] _ in self?.presentDocuments() })
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = source.bounds
        presenter.present(sheet, animated: true)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            finish(.failure(.cameraUnavailable))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    private func presentGallery() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    private func presentDocuments() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.documentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    private func finish(_ result: Result<PickedAttachment, PickFailure>) {
        if Thread.isMainThread {
            onResult?(result)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onResult?(result) }
        }
    }

    /// Validates a file on disk by size and type, then reads it.
    static func readValidated(fileURL: URL, filename: String, mimeType: String?) -> Result<PickedAttachment, PickFailure> {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        switch HaloChatAttachmentValidator.validate(sizeBytes: size, mimeType: mimeType, filename: filename) {
        case let .failure(rejection):
            return .failure(.rejected(rejection))
        case let .success(mime):
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return .failure(.unreadable) }
            // Re-check the actual byte count (the size attribute can be missing).
            if data.count > HaloChatAttachmentValidator.maxBytes { return .failure(.rejected(.tooLarge)) }
            return .success(PickedAttachment(data: data, filename: filename, mimeType: mime))
        }
    }
}

extension AttachmentPickerCoordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) else {
            finish(.failure(.unreadable))
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "photo-\(formatter.string(from: Date())).jpg"
        switch HaloChatAttachmentValidator.validate(sizeBytes: data.count, mimeType: "image/jpeg", filename: filename) {
        case let .failure(rejection): finish(.failure(.rejected(rejection)))
        case let .success(mime): finish(.success(PickedAttachment(data: data, filename: filename, mimeType: mime)))
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension AttachmentPickerCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        // Prefer the original image / movie representation the asset actually has.
        let identifiers = provider.registeredTypeIdentifiers
        let typeIdentifier = identifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? identifiers.first { UTType($0)?.conforms(to: .movie) == true }
            ?? identifiers.first
        guard let typeIdentifier else {
            finish(.failure(.rejected(.unsupportedType)))
            return
        }
        let type = UTType(typeIdentifier)
        let suggested = provider.suggestedName ?? "media"
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
            // The file is deleted when this closure returns: read (or reject) it now.
            guard let self else { return }
            guard let url else {
                finish(.failure(.unreadable))
                return
            }
            var filename = suggested
            if (filename as NSString).pathExtension.isEmpty {
                let ext = type?.preferredFilenameExtension ?? url.pathExtension
                if !ext.isEmpty { filename += ".\(ext)" }
            }
            finish(Self.readValidated(fileURL: url, filename: filename, mimeType: type?.preferredMIMEType))
        }
    }
}

extension AttachmentPickerCoordinator: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.preferredMIMEType
        finish(Self.readValidated(fileURL: url, filename: url.lastPathComponent, mimeType: mime))
    }
}
#endif
