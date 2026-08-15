// Generates the Glance app icon (graphite gradient, resting eye with lashes)
// into glance/Assets.xcassets/AppIcon.appiconset at all macOS sizes.
//
// The icon is 100% programmatic — to change it, edit this file and re-run:
//   swift packaging/icon/generate-icon.swift
// then `xcodegen generate && ./build.sh`.

import AppKit
import CoreGraphics

let gradientTop: (CGFloat, CGFloat, CGFloat) = (0.29, 0.32, 0.38)
let gradientBottom: (CGFloat, CGFloat, CGFloat) = (0.10, 0.11, 0.15)

func makeContext(_ px: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                     bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func renderIcon(px: Int) -> CGImage {
    let ctx = makeContext(px)
    let s = CGFloat(px) / 1024.0
    ctx.scaleBy(x: s, y: s)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    // Apple icon grid: 824x824 squircle centered on the 1024 canvas
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)

    let mid = CGColor(colorSpace: cs, components: [
        (gradientTop.0 + gradientBottom.0) / 2, (gradientTop.1 + gradientBottom.1) / 2,
        (gradientTop.2 + gradientBottom.2) / 2, 1])!

    // soft drop shadow (fill solid first so the shadow casts, then gradient over it)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24,
                  color: CGColor(colorSpace: cs, components: [0, 0, 0, 0.30]))
    ctx.addPath(squircle)
    ctx.setFillColor(mid)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [gradientTop.0, gradientTop.1, gradientTop.2, 1])!,
        CGColor(colorSpace: cs, components: [gradientBottom.0, gradientBottom.1, gradientBottom.2, 1])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // resting eye: closed lid bowing down, three lashes below.
    // Strokes get an optical bump at small sizes so they don't thin to nothing.
    let strokeScale: CGFloat = px < 40 ? 1.5 : (px < 80 ? 1.25 : 1.0)
    let cx: CGFloat = 512, cy: CGFloat = 512
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!)
    ctx.setLineCap(.round)

    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: cx - 240, y: cy + 80))
    lid.addQuadCurve(to: CGPoint(x: cx + 240, y: cy + 80), control: CGPoint(x: cx, y: cy - 120))
    ctx.addPath(lid)
    ctx.setLineWidth(58 * strokeScale)
    ctx.strokePath()

    let lashes: [(CGPoint, CGPoint)] = [
        (CGPoint(x: cx - 148, y: cy - 8),  CGPoint(x: cx - 200, y: cy - 92)),
        (CGPoint(x: cx,       y: cy - 46), CGPoint(x: cx,       y: cy - 144)),
        (CGPoint(x: cx + 148, y: cy - 8),  CGPoint(x: cx + 200, y: cy - 92)),
    ]
    for (a, b) in lashes {
        ctx.move(to: a)
        ctx.addLine(to: b)
    }
    ctx.setLineWidth(50 * strokeScale)
    ctx.strokePath()

    return ctx.makeImage()!
}

func savePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

// repo root = two levels up from this script's directory when run via
// `swift packaging/icon/generate-icon.swift`; simpler: require cwd = repo root.
let iconsetDir = "glance/Assets.xcassets/AppIcon.appiconset"
let fm = FileManager.default
guard fm.fileExists(atPath: "project.yml") else {
    fatalError("Run from the repo root: swift packaging/icon/generate-icon.swift")
}
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let entries: [(String, Int, Int)] = [  // (size label, scale, pixels)
    ("16x16", 1, 16), ("16x16", 2, 32),
    ("32x32", 1, 32), ("32x32", 2, 64),
    ("128x128", 1, 128), ("128x128", 2, 256),
    ("256x256", 1, 256), ("256x256", 2, 512),
    ("512x512", 1, 512), ("512x512", 2, 1024),
]

var images: [[String: String]] = []
for (label, scale, px) in entries {
    let filename = scale == 1 ? "icon_\(label).png" : "icon_\(label)@2x.png"
    savePNG(renderIcon(px: px), "\(iconsetDir)/\(filename)")
    images.append(["size": label, "idiom": "mac", "scale": "\(scale)x", "filename": filename])
    print("wrote \(filename) (\(px)px)")
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try! JSONSerialization.data(withJSONObject: contents,
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(iconsetDir)/Contents.json"))
print("wrote Contents.json — done")
