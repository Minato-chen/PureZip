import Foundation
import AppKit
import ImageIO

public enum ImagePreviewHelper {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif",
        "gif", "bmp", "ico", "webp",
        // Camera RAW & Professional Formats
        "raw", "dng", "cr2", "cr3", "nef", "nrw", "arw",
        "orf", "raf", "rw2", "pef", "srw"
    ]

    public static func isSupportedImage(ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    /// Fast, memory-efficient thumbnail decoding using ImageIO.
    /// Prefers embedded camera Exif thumbnails (RAW/JPEG) or decodes with hardware subsampling.
    public static func createThumbnail(at url: URL, maxPixelSize: CGFloat = 1600) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        return NSImage(contentsOf: url)
    }
}
