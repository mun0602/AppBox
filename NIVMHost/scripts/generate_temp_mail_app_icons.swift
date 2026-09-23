#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconSpec {
  let filename: String
  let pixels: Int
}

private let specs: [IconSpec] = [
  .init(filename: "TempMail-AppIcon-20x20@1x.png", pixels: 20),
  .init(filename: "TempMail-AppIcon-20x20@2x.png", pixels: 40),
  .init(filename: "TempMail-AppIcon-20x20@3x.png", pixels: 60),
  .init(filename: "TempMail-AppIcon-29x29@1x.png", pixels: 29),
  .init(filename: "TempMail-AppIcon-29x29@2x.png", pixels: 58),
  .init(filename: "TempMail-AppIcon-29x29@3x.png", pixels: 87),
  .init(filename: "TempMail-AppIcon-40x40@1x.png", pixels: 40),
  .init(filename: "TempMail-AppIcon-40x40@2x.png", pixels: 80),
  .init(filename: "TempMail-AppIcon-40x40@3x.png", pixels: 120),
  .init(filename: "TempMail-AppIcon-50x50@1x.png", pixels: 50),
  .init(filename: "TempMail-AppIcon-50x50@2x.png", pixels: 100),
  .init(filename: "TempMail-AppIcon-57x57@1x.png", pixels: 57),
  .init(filename: "TempMail-AppIcon-57x57@2x.png", pixels: 114),
  .init(filename: "TempMail-AppIcon-60x60@2x.png", pixels: 120),
  .init(filename: "TempMail-AppIcon-60x60@3x.png", pixels: 180),
  .init(filename: "TempMail-AppIcon-72x72@1x.png", pixels: 72),
  .init(filename: "TempMail-AppIcon-72x72@2x.png", pixels: 144),
  .init(filename: "TempMail-AppIcon-76x76@1x.png", pixels: 76),
  .init(filename: "TempMail-AppIcon-76x76@2x.png", pixels: 152),
  .init(filename: "TempMail-AppIcon-83.5x83.5@2x.png", pixels: 167),
  .init(filename: "TempMail-AppIcon-1024x1024@1x.png", pixels: 1024),
]

private func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    components: [
      CGFloat(red) / 255,
      CGFloat(green) / 255,
      CGFloat(blue) / 255,
      alpha,
    ]
  )!
}

private func renderIcon(pixels: Int) throws -> Data {
  guard let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: pixels * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    throw CocoaError(.fileWriteUnknown)
  }
  let scale = CGFloat(pixels) / 1024
  context.scaleBy(x: scale, y: scale)
  context.setShouldAntialias(true)
  context.setAllowsAntialiasing(true)

  let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(29, 207, 148), color(8, 155, 119)] as CFArray,
    locations: [0, 1]
  )!
  context.setFillColor(color(13, 177, 128))
  context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
  context.drawLinearGradient(
    background,
    start: CGPoint(x: -512, y: 1536),
    end: CGPoint(x: 1536, y: -512),
    options: []
  )

  context.setFillColor(color(178, 247, 220, alpha: 0.20))
  context.fillEllipse(in: CGRect(x: 70, y: 555, width: 550, height: 550))
  context.setFillColor(color(4, 112, 88, alpha: 0.10))
  context.fillEllipse(in: CGRect(x: 510, y: -170, width: 650, height: 650))

  let envelopeRect = CGRect(x: 164, y: 246, width: 696, height: 500)
  let envelope = CGPath(
    roundedRect: envelopeRect,
    cornerWidth: 92,
    cornerHeight: 92,
    transform: nil
  )
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: color(0, 88, 65, alpha: 0.24))
  context.addPath(envelope)
  context.setFillColor(color(248, 255, 252))
  context.fillPath()
  context.restoreGState()

  context.addPath(envelope)
  context.setStrokeColor(color(255, 255, 255, alpha: 0.78))
  context.setLineWidth(8)
  context.strokePath()

  let lowerFolds = CGMutablePath()
  lowerFolds.move(to: CGPoint(x: 196, y: 296))
  lowerFolds.addLine(to: CGPoint(x: 408, y: 492))
  lowerFolds.move(to: CGPoint(x: 828, y: 296))
  lowerFolds.addLine(to: CGPoint(x: 616, y: 492))
  context.addPath(lowerFolds)
  context.setStrokeColor(color(197, 237, 225))
  context.setLineWidth(18)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()

  let flap = CGMutablePath()
  flap.move(to: CGPoint(x: 204, y: 698))
  flap.addLine(to: CGPoint(x: 512, y: 462))
  flap.addLine(to: CGPoint(x: 820, y: 698))
  context.addPath(flap)
  context.setStrokeColor(color(14, 174, 124))
  context.setLineWidth(30)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()

  let badgeRect = CGRect(x: 626, y: 600, width: 238, height: 238)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -13), blur: 26, color: color(0, 88, 65, alpha: 0.22))
  context.setFillColor(color(250, 255, 253))
  context.fillEllipse(in: badgeRect)
  context.restoreGState()

  context.setStrokeColor(color(16, 192, 135))
  context.setLineWidth(24)
  context.strokeEllipse(in: badgeRect.insetBy(dx: 29, dy: 29))

  let hands = CGMutablePath()
  hands.move(to: CGPoint(x: 745, y: 719))
  hands.addLine(to: CGPoint(x: 745, y: 776))
  hands.move(to: CGPoint(x: 745, y: 719))
  hands.addLine(to: CGPoint(x: 795, y: 687))
  context.addPath(hands)
  context.setStrokeColor(color(8, 139, 105))
  context.setLineWidth(22)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()

  context.setFillColor(color(8, 139, 105))
  context.fillEllipse(in: CGRect(x: 731, y: 705, width: 28, height: 28))

  guard let image = context.makeImage() else {
    throw CocoaError(.fileWriteUnknown)
  }
  let data = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(
    data,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    throw CocoaError(.fileWriteUnknown)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return data as Data
}

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let assetDirectory = projectRoot
  .appendingPathComponent("Runner/Assets.xcassets/TempMailAppIcon.appiconset", isDirectory: true)
let masterURL = projectRoot.appendingPathComponent("Design/Branding/TempMail-AppIcon-Master.png")

try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: masterURL.deletingLastPathComponent(), withIntermediateDirectories: true)

for spec in specs {
  let data = try renderIcon(pixels: spec.pixels)
  try data.write(to: assetDirectory.appendingPathComponent(spec.filename), options: .atomic)
  if spec.pixels == 1024 {
    try data.write(to: masterURL, options: .atomic)
  }
}

print("TEMP_MAIL_APP_ICONS_GENERATED count=\(specs.count)")
