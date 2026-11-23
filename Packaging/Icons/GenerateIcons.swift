import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 原创矢量源：菜单面板 + 光标，逐尺寸渲染并自动导出标准 macOS 图标。
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func render(pixels: Int, logicalSize: CGFloat = 1024, draw: (CGContext) -> Void) throws -> CGImage {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "Icons", code: 1)
    }
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / logicalSize, y: CGFloat(pixels) / logicalSize)
    context.translateBy(x: 0, y: logicalSize)
    context.scaleBy(x: 1, y: -1)
    draw(context)
    return context.makeImage()!
}
func save(_ image: CGImage, to url: URL) throws {
    guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "Icons", code: 2) }
    let origin = "Origin: original MiaoRight menu-and-cursor vector artwork in Packaging/Icons/GenerateIcons.swift. Rendered with CoreGraphics; no sourced or AI-generated imagery."
    let metadata: [CFString: Any] = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: origin]]
    CGImageDestinationAddImage(writer, image, metadata as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { throw NSError(domain: "Icons", code: 3) }
    // PNG 中保留来源信息；与设计工具的 provenance 扫描使用同一 tEXt 字段。
    var png = try Data(contentsOf: url)
    let body = Data("impeccable:prompt".utf8) + Data([0]) + Data(origin.utf8)
    let type = Data("tEXt".utf8)
    var crc: UInt32 = 0xffffffff
    for byte in type + body {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
    }
    func bigEndian(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    let chunk = bigEndian(UInt32(body.count)) + type + body + bigEndian(~crc)
    png.insert(contentsOf: chunk, at: png.count - 12)
    try png.write(to: url, options: .atomic)
}
func cursor() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 520, y: 436))
    for point in [CGPoint(x: 520, y: 774), CGPoint(x: 608, y: 690), CGPoint(x: 672, y: 816), CGPoint(x: 744, y: 780), CGPoint(x: 678, y: 658), CGPoint(x: 800, y: 650)] { path.addLine(to: point) }
    path.closeSubpath()
    return path
}
func drawApp(_ context: CGContext) {
    let tile = rounded(CGRect(x: 80, y: 80, width: 864, height: 864), 192)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 25, color: CGColor(gray: 0, alpha: 0.18))
    context.setFillColor(CGColor(srgbRed: 0.10, green: 0.37, blue: 0.84, alpha: 1))
    context.addPath(tile); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(tile); context.clip()
    let colors = [CGColor(srgbRed: 0.23, green: 0.63, blue: 1, alpha: 1), CGColor(srgbRed: 0.035, green: 0.28, blue: 0.79, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 240, y: 80), end: CGPoint(x: 780, y: 944), options: [])
    context.restoreGState()
    context.addPath(tile); context.setStrokeColor(CGColor(gray: 1, alpha: 0.30)); context.setLineWidth(2); context.strokePath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: CGColor(gray: 0, alpha: 0.14))
    context.addPath(rounded(CGRect(x: 244, y: 228, width: 476, height: 402), 66))
    context.setFillColor(CGColor(gray: 1, alpha: 0.97)); context.fillPath(); context.restoreGState()
    context.setFillColor(CGColor(srgbRed: 0.12, green: 0.40, blue: 0.80, alpha: 0.95))
    for (y, width) in [(CGFloat(320), CGFloat(266)), (CGFloat(406), CGFloat(208)), (CGFloat(492), CGFloat(144))] {
        context.addPath(rounded(CGRect(x: 324, y: y, width: width, height: 30), 15)); context.fillPath()
    }
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: CGColor(gray: 0, alpha: 0.20))
    context.addPath(cursor()); context.setLineJoin(.round); context.setLineWidth(30)
    context.setStrokeColor(CGColor(gray: 1, alpha: 1)); context.setFillColor(CGColor(srgbRed: 0.10, green: 0.32, blue: 0.72, alpha: 1))
    context.drawPath(using: .fillStroke); context.restoreGState()
}
func drawTemplate(_ context: CGContext) {
    context.setLineWidth(1.5); context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.addPath(rounded(CGRect(x: 1.5, y: 2, width: 11.5, height: 11), 2)); context.strokePath()
    context.setLineCap(.round)
    for y in [CGFloat(5), CGFloat(8)] {
        context.move(to: CGPoint(x: 4.5, y: y)); context.addLine(to: CGPoint(x: 9.5, y: y)); context.strokePath()
    }
    let pointer = CGMutablePath(); pointer.move(to: CGPoint(x: 10, y: 8))
    for point in [CGPoint(x: 10, y: 16), CGPoint(x: 12, y: 14), CGPoint(x: 14, y: 17), CGPoint(x: 15.5, y: 16), CGPoint(x: 13.5, y: 13), CGPoint(x: 17, y: 13)] { pointer.addLine(to: point) }
    pointer.closeSubpath()
    context.setBlendMode(.clear); context.setLineWidth(2); context.addPath(pointer); context.strokePath()
    context.setBlendMode(.normal); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.addPath(pointer); context.fillPath()
}
for name in ["AppIcon", "FinderIcon"] {
    let iconset = destination.appendingPathComponent(name + ".iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let image = try render(pixels: size * scale, draw: drawApp)
            try save(image, to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
        }
    }
    try save(try render(pixels: 1024, draw: drawApp), to: destination.appendingPathComponent(name + ".png"))
}
for scale in [1, 2] {
    try save(try render(pixels: 18 * scale, logicalSize: 18, draw: drawTemplate),
             to: destination.appendingPathComponent("MenuBarTemplate\(scale == 2 ? "@2x" : "").png"))
}
print("Exported menu-and-cursor AppIcon/FinderIcon sizes and 18/36 px menu bar templates.")
