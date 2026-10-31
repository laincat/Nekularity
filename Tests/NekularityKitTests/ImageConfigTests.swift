import Foundation
import Testing
@testable import NekularityKit

@Suite("Image config callbacks")
struct ImageConfigTests {
    @Test func aConfigKeepsItsCallbacks() throws {
        let json = #"{"url":"https://img.example/1.jpg","method":"get","headers":{"Referer":"https://e/"},"handle":"i7","callbacks":["onResponse","onLoadFailed"]}"#
        let request = try ImageRequest(json: json, fallbackURL: "https://old/1.jpg")
        #expect(request.url == "https://img.example/1.jpg")
        #expect(request.method == "GET")
        #expect(request.headers["Referer"] == "https://e/")
        #expect(request.handle == "i7")
        #expect(request.has("onResponse"))
        #expect(request.has("onLoadFailed"))
        #expect(!request.has("modifyImage"))
    }

    @Test func aPlainConfigHasNoHandle() throws {
        let json = #"{"url":"https://thumb.example/1.jpg"}"#
        let request = try ImageRequest(json: json, fallbackURL: "https://old/1.jpg")
        #expect(request.url == "https://thumb.example/1.jpg")
        #expect(request.handle.isEmpty)
        #expect(request.callbacks.isEmpty)
        #expect(!request.has("onResponse"))
    }

    @Test func anErrorPageIsNotAnImage() {
        #expect(ImageLoader.looksLikeHTML(Data("<!DOCTYPE html><html></html>".utf8)))
        #expect(ImageLoader.looksLikeHTML(Data("\n  <html><body>404</body></html>".utf8)))
        #expect(!ImageLoader.looksLikeHTML(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])))
        // An empty body is a failed load, not an error page: the caller must
        // not spend a mirror hop on it unless the source asked for one.
        #expect(!ImageLoader.looksLikeHTML(Data()))
    }
}

/// The pixel pass is JavaScript text in the config, not a callback, so it has
/// to survive parsing on its own field.
@Test func aConfigCarriesItsPixelScript() throws {
    let json = #"{"url":"https://img.example/1.jpg","modifyImage":"let modifyImage = (image) => image.copyAndRotate90()"}"#
    let request = try ImageRequest(json: json, fallbackURL: "")
    #expect(request.modifyImage.contains("copyAndRotate90"))
    #expect(request.callbacks.isEmpty)
    #expect(request.handle.isEmpty)
}

@Test func aPlainConfigHasNoPixelScript() throws {
    let request = try ImageRequest(json: #"{"url":"https://img.example/1.jpg"}"#, fallbackURL: "")
    #expect(request.modifyImage.isEmpty)
}

/// The pixel pass copies the image three times, so the cap is what keeps a
/// phone from running out of memory on a very tall strip.
@Test func thePixelPassCapCoversALongStripAndRefusesTheRest() {
    #expect(ImageLoader.pixelPassFits(1080, 16384))   // 17.7M pixels: a real strip
    #expect(ImageLoader.pixelPassFits(3000, 8000))   // 24M, exactly at the cap
    #expect(!ImageLoader.pixelPassFits(3000, 8001))
    #expect(!ImageLoader.pixelPassFits(0, 100))
    #expect(!ImageLoader.pixelPassFits(100, 0))
    // A width large enough to overflow a naive product is refused, not wrapped.
    #expect(!ImageLoader.pixelPassFits(Int.max, 2))
}
