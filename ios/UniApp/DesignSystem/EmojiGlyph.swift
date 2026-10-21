import SwiftUI
import UIKit

struct EmojiGlyph: View {
    let emoji: String
    var size: CGFloat = 22

    var body: some View {
        if let image = EmojiRenderer.image(emoji, size: size) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .contentTransition(.opacity)
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

@MainActor
enum EmojiRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(_ emoji: String, size: CGFloat) -> UIImage? {
        let key = "\(emoji)|\(size)"
        if let cached = cache[key] { return cached }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 2)]
        let text = emoji as NSString
        let canvas = text.size(withAttributes: attributes)
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            text.draw(at: .zero, withAttributes: attributes)
        }
        guard let cgImage = rendered.cgImage, let bounds = opaqueBounds(of: cgImage), let cropped = cgImage.cropping(to: bounds) else {
            return nil
        }
        let image = UIImage(cgImage: cropped, scale: format.scale, orientation: .up)
        cache[key] = image
        return image
    }

    private static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
