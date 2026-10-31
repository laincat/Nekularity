import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NekularityKit

/// Downsampling is what keeps a tall comic page from exhausting memory, and it is
/// pure: no Core, no network, no cache.
@Suite("ImageLoader decoding")
struct ImageLoaderDecodeTests {
    /// A solid-colour PNG of the given size.
    private func png(width: Int, height: Int) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A tall page scaled to a width keeps its aspect: shrinking it to a square
    /// would make it unreadable.
    @Test func aTallStripIsScaledByItsWidth() throws {
        let decoded = try #require(ImageLoader.decode(png(width: 40, height: 800), limit: .width(20)))
        #expect(decoded.width == 20)
        #expect(decoded.height == 400)
    }

    @Test func aWideImageIsScaledToTheWidthAskedFor() throws {
        let decoded = try #require(ImageLoader.decode(png(width: 1000, height: 500), limit: .width(500)))
        #expect(decoded.width == 500)
        #expect(decoded.height == 250)
    }

    /// The downsample floor is 64 pixels: asking for less is raised to it, because
    /// a thumbnail smaller than that is not worth the decode. Writing it down here
    /// is the point — it looks like a bug otherwise.
    @Test func aRequestBelowTheFloorIsRaisedToIt() throws {
        let decoded = try #require(ImageLoader.decode(png(width: 100, height: 50), limit: .width(20)))
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
    }

    @Test func theLongerSideLimitAppliesToTheLongerSide() throws {
        let decoded = try #require(ImageLoader.decode(png(width: 400, height: 200), limit: .longerSide(200)))
        #expect(max(decoded.width, decoded.height) == 200)
        #expect(decoded.width == 200)
        #expect(decoded.height == 100)
    }

    /// An image already smaller than the limit is not enlarged.
    @Test func aSmallImageIsNotEnlarged() throws {
        let decoded = try #require(ImageLoader.decode(png(width: 10, height: 10), limit: .width(200)))
        #expect(decoded.width == 10)
        #expect(decoded.height == 10)
    }

    /// Garbage decodes to nothing rather than crashing: a source can answer with
    /// HTML under an image content type.
    @Test func garbageDecodesToNothing() {
        #expect(ImageLoader.decode(Data("not an image".utf8), limit: .width(100)) == nil)
        #expect(ImageLoader.decode(Data(), limit: .width(100)) == nil)
    }
}
