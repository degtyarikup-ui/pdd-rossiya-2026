import ImageIO
import UniformTypeIdentifiers
import UserNotifications

/// Adds the picture of an admin push before iOS shows it. The server sends
/// `mutable-content: 1` and the address in `fcm_options.image`
/// (`buildPushMessage` in server/install-notifier/notifications.js).
/// Any failure delivers the push as is, without the picture.
final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?
  private var download: URLSessionDownloadTask?

  override func didReceive(_ request: UNNotificationRequest,
                           withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
          let url = Self.imageURL(content.userInfo) else {
      contentHandler(request.content)
      return
    }
    // The downloaded file is removed when the completion block returns.
    let task = URLSession.shared.downloadTask(with: url) { file, response, _ in
      self.finish(with: file.flatMap { Self.attachment(from: $0) })
    }
    lock.lock()
    self.contentHandler = contentHandler
    self.content = content
    download = task
    lock.unlock()
    task.resume()
  }

  /// iOS gives the extension about 30 seconds; after that the text goes alone.
  override func serviceExtensionTimeWillExpire() {
    lock.lock()
    let task = download
    lock.unlock()
    task?.cancel()
    finish(with: nil)
  }

  private func finish(with attachment: UNNotificationAttachment?) {
    lock.lock()
    let handler = contentHandler, content = self.content
    contentHandler = nil
    lock.unlock()
    guard let handler, let content else { return }
    if let attachment { content.attachments = [attachment] }
    handler(content)
  }

  /// `fcm_options.image` is the FCM field; `imageUrl` is its copy in the data fields.
  private static func imageURL(_ userInfo: [AnyHashable: Any]) -> URL? {
    let options = userInfo["fcm_options"] as? [String: Any]
    guard let raw = options?["image"] as? String ?? userInfo["imageUrl"] as? String,
          let url = URL(string: raw), url.scheme == "https" else { return nil }
    return url
  }

  /// Attachments take JPEG, PNG and GIF up to 10 MB. Other pictures (WebP from
  /// the admin panel) and larger files are re-encoded as JPEG up to 1200 px.
  private static func attachment(from file: URL) -> UNNotificationAttachment? {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let identifier = CGImageSourceGetType(source) as String?,
          let type = UTType(identifier) else { return nil }
    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
      return nil
    }
    var target = folder.appendingPathComponent("image.jpg")
    if [UTType.jpeg, .png, .gif].contains(type) && size <= 10_000_000 {
      target = folder.appendingPathComponent("image").appendingPathExtension(type.preferredFilenameExtension ?? "jpg")
      guard (try? FileManager.default.moveItem(at: file, to: target)) != nil else { return nil }
    } else {
      let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                     kCGImageSourceCreateThumbnailWithTransform: true,
                     kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
            let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
      else { return nil }
      CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
      guard CGImageDestinationFinalize(output) else { return nil }
    }
    // On success iOS moves the file into its own attachment store.
    return try? UNNotificationAttachment(identifier: "image", url: target)
  }
}
