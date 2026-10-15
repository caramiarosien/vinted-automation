import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import WerkstattCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
let input = NSMutableData()
let destination = CGImageDestinationCreateWithData(input, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, [
    kCGImagePropertyOrientation: 6,
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 47.66, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 9.17, kCGImagePropertyGPSLongitudeRef: "E"]
] as CFDictionary)
require(CGImageDestinationFinalize(destination), "test input generation")
let clean = try PhotoRendering.jpeg(input as Data)
let cleanSource = CGImageSourceCreateWithData(clean as CFData, nil)!
let props = CGImageSourceCopyPropertiesAtIndex(cleanSource, 0, nil)! as NSDictionary
require(props[kCGImagePropertyGPSDictionary] == nil, "GPS must not be exported")
require(props[kCGImagePropertyPixelWidth] as? Int == 10, "orientation width")
require(props[kCGImagePropertyPixelHeight] as? Int == 20, "orientation height")
let preview = try PhotoRendering.jpeg(input as Data, maximumDimension: 8)
let smallProps = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(preview as CFData,nil)!,0,nil)! as NSDictionary
require(max(smallProps[kCGImagePropertyPixelWidth] as! Int, smallProps[kCGImagePropertyPixelHeight] as! Int) <= 8, "preview bound")
do { _ = try PhotoRendering.jpeg(Data("broken".utf8)); fatalError("invalid image accepted") } catch {}
print("PASS: JPEG export removes GPS, corrects orientation, bounds preview and rejects unreadable input.")

let archivePath = CommandLine.arguments[1]
let entries = try ZIPArchive.read(Data(contentsOf: URL(fileURLWithPath: archivePath)))
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Werkstatt-Native-Test-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for (path,data) in entries {
    let target = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target)
}
let store = try LibraryStore(root: root)
try store.save(store.library)
let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
let original = try decoder.decode(Library.self, from: entries["library.json"]!)
require(store.library.items.count == original.items.count, "migration item count")
require(store.library.photos.count == original.photos.count, "migration photo count")
for p in store.library.photos { _ = try store.imageURL(photoID:p.id); _ = try store.imageURL(photoID:p.id,preview:true) }
print("PASS: Actual Swift ZIP reader and LibraryStore restored \(store.library.items.count) items / \(store.library.photos.count) originals.")
