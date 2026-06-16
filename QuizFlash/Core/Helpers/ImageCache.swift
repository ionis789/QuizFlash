//
//  ImageCache.swift
//  QuizFlash
//
//  An in-memory LRU image cache and image compression helpers.
//  Extracted from `ZoneModel.swift` where UI-layer utilities do not belong.
//

import UIKit

// MARK: - Image Cache

/// A thread-safe, memory-pressured in-memory cache for downsampled `UIImage` objects.
///
/// Use `ImageCache.shared` to avoid repeated decoding of the same image data.
/// The cache automatically evicts entries under memory pressure by observing
/// `UIApplication.didReceiveMemoryWarningNotification`.
///
/// ### Architecture note
/// This type lives in `Core/Helpers/` because it is a pure UIKit utility with
/// no dependency on the Domain or Feature layers.
final class ImageCache {

    // MARK: - Shared Instance

    /// The application-wide singleton cache instance.
    static let shared = ImageCache()

    // MARK: - Properties

    private var cache = NSCache<NSString, UIImage>()

    // MARK: - Initializer

    private init() {
        // Limit total decoded pixel data to 50 MB.
        cache.totalCostLimit = 50 * 1024 * 1024

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    // MARK: - Public Interface

    /// Returns a downsampled `UIImage` for the given raw image data, using a
    /// disk-source efficient pipeline that skips full decompression until the
    /// image is actually needed.
    ///
    /// Results are cached keyed by `"\(id)_\(targetSize.width)x\(targetSize.height)"`.
    ///
    /// - Parameters:
    ///   - data: The raw image data (JPEG, PNG, etc.).
    ///   - id: A stable string identifier for the image (e.g. a zone UUID string).
    ///   - targetSize: The point-size at which the image will be rendered.
    ///   - scale: The display scale. Defaults to `UITraitCollection.current.displayScale`,
    ///     the iOS 17+-recommended replacement for the deprecated `UIScreen.main.scale`.
    /// - Returns: A downsampled `UIImage`, or a full-resolution fallback if downsampling fails.
    func image(
        for data: Data,
        id: String,
        targetSize: CGSize,
        scale: CGFloat = UITraitCollection.current.displayScale
    ) -> UIImage? {
        let cacheKey = "\(id)_\(targetSize.width)x\(targetSize.height)" as NSString

        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let downsampledImage = downsample(imageData: data, to: targetSize, scale: scale) else {
            return UIImage(data: data)
        }

        let cost = Int(downsampledImage.size.width * downsampledImage.size.height * 4)
        cache.setObject(downsampledImage, forKey: cacheKey, cost: cost)

        return downsampledImage
    }

    /// Evicts all objects from the cache immediately.
    ///
    /// Called automatically on memory pressure. Safe to call manually (e.g. from tests).
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private Helpers

    /// Downsamples raw image data to a target point size using `ImageIO`, which avoids
    /// loading the full decompressed bitmap into memory.
    ///
    /// - Parameters:
    ///   - imageData: The raw image data.
    ///   - pointSize: The desired output size in points.
    ///   - scale: The display scale used to derive pixel dimensions.
    /// - Returns: A downsampled `UIImage`, or `nil` if the source data cannot be decoded.
    private func downsample(imageData: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledCGImage)
    }
}

// MARK: - Data Image Compression

extension Data {

    /// Returns a JPEG-compressed and optionally downscaled copy of the image represented
    /// by this data, suitable for storage in `ZoneModel.imageData`.
    ///
    /// Uses `UIGraphicsImageRenderer` (the modern, non-deprecated replacement for
    /// `UIGraphicsBeginImageContextWithOptions`) for pixel-perfect scaling.
    ///
    /// - Parameters:
    ///   - maxDimension: The maximum pixel dimension (width or height) of the output. Defaults to `1200`.
    ///   - compressionQuality: JPEG quality in `[0, 1]`. Defaults to `0.7`.
    /// - Returns: Compressed JPEG data, or `nil` if the input cannot be decoded as an image.
    nonisolated func compressedImageData(maxDimension: CGFloat = 1200, compressionQuality: CGFloat = 0.7) -> Data? {
        guard let uiImage = UIImage(data: self) else { return nil }

        let size = uiImage.size
        let scale: CGFloat

        if size.width > size.height {
            scale = size.width > maxDimension ? maxDimension / size.width : 1.0
        } else {
            scale = size.height > maxDimension ? maxDimension / size.height : 1.0
        }

        // No resize needed — compress at original dimensions.
        guard scale < 1.0 else {
            return uiImage.jpegData(compressionQuality: compressionQuality)
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // UIGraphicsImageRenderer replaces the deprecated UIGraphicsBeginImageContextWithOptions.
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }

    /// Returns a JPEG thumbnail copy of the image represented by this data.
    ///
    /// A convenience wrapper around `compressedImageData(maxDimension:compressionQuality:)`
    /// tuned for small previews.
    ///
    /// - Parameter maxDimension: The maximum pixel dimension of the thumbnail. Defaults to `400`.
    /// - Returns: Compressed JPEG thumbnail data, or `nil` if the input cannot be decoded.
    func thumbnailData(maxDimension: CGFloat = 400) -> Data? {
        compressedImageData(maxDimension: maxDimension, compressionQuality: 0.6)
    }
}
