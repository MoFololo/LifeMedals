//
//  EvidenceImageProcessor.swift
//  LifeMedals
//

import AppKit
import Foundation
import ImageIO

enum EvidenceImageProcessor {
    // Four Base64-encoded copies stay below the Worker's 6 MiB request cap.
    static let maximumStoredBytes = 1_000_000

    /// Creates the app-owned evidence copy. The original Photos item or camera
    /// file is never retained; SwiftData stores only this compressed JPEG.
    static func compressedJPEG(from sourceData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw EvidenceImageProcessingError.unreadableImage
        }

        let pixelSizes = [1_800, 1_500, 1_200, 960]
        let qualities: [CGFloat] = [0.78, 0.66, 0.54, 0.42, 0.32]
        var smallestData: Data?

        for pixelSize in pixelSizes {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                continue
            }

            let representation = NSBitmapImageRep(cgImage: image)
            for quality in qualities {
                guard let data = representation.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: quality]
                ) else {
                    continue
                }
                if smallestData == nil || data.count < smallestData!.count {
                    smallestData = data
                }
                if data.count <= maximumStoredBytes {
                    return data
                }
            }
        }

        guard let smallestData, smallestData.count <= maximumStoredBytes else {
            throw EvidenceImageProcessingError.cannotCompress
        }
        return smallestData
    }
}

enum EvidenceImageProcessingError: LocalizedError {
    case unreadableImage
    case cannotCompress

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "无法读取这张图片，请选择其他图片。"
        case .cannotCompress:
            return "图片内容过大，无法压缩到安全上传大小，请选择其他图片。"
        }
    }
}
