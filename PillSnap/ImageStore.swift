import UIKit

/// Saves reference photos as JPEG files in the app's private storage.
enum ImageStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "PillSnap/Photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ image: UIImage) throws -> String {
        let name = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: directory.appending(path: name), options: .atomic)
        return name
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appending(path: name).path(percentEncoded: false))
    }

    static func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// Redraws the photo upright and no larger than `maxDimension` pixels,
    /// so every photo is analysed the same way.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
