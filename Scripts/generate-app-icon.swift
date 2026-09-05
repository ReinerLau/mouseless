import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: generate-app-icon.swift <appiconset-directory>\n", stderr)
  exit(EXIT_FAILURE)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

for pixelSize in iconSizes {
  let dimension = CGFloat(pixelSize)
  let canvasBounds = NSRect(x: 0, y: 0, width: dimension, height: dimension)
  let canvas = NSImage(size: canvasBounds.size)
  canvas.lockFocus()

  NSColor.systemBlue.setFill()
  NSBezierPath(
    roundedRect: canvasBounds.insetBy(dx: dimension * 0.04, dy: dimension * 0.04),
    xRadius: dimension * 0.20,
    yRadius: dimension * 0.20
  ).fill()

  let symbolConfiguration = NSImage.SymbolConfiguration(
    pointSize: dimension * 0.56,
    weight: .regular
  ).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
  guard let symbol = NSImage(
    systemSymbolName: "computermouse",
    accessibilityDescription: "Keyveer"
  )?.withSymbolConfiguration(symbolConfiguration) else {
    fputs("could not load the computermouse SF Symbol\n", stderr)
    exit(EXIT_FAILURE)
  }

  let maxSymbolDimension = dimension * 0.56
  let symbolScale = min(
    maxSymbolDimension / symbol.size.width,
    maxSymbolDimension / symbol.size.height
  )
  let symbolSize = NSSize(
    width: symbol.size.width * symbolScale,
    height: symbol.size.height * symbolScale
  )
  let symbolRect = NSRect(
    x: (dimension - symbolSize.width) / 2,
    y: (dimension - symbolSize.height) / 2,
    width: symbolSize.width,
    height: symbolSize.height
  )
  symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
  canvas.unlockFocus()

  guard
    let tiffData = canvas.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
  else {
    fputs("could not encode icon_\(pixelSize).png\n", stderr)
    exit(EXIT_FAILURE)
  }

  try pngData.write(to: outputDirectory.appendingPathComponent("icon_\(pixelSize).png"))
}
