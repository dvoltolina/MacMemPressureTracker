import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  fputs("usage: IconFactory <iconset-dir>\n", stderr)
  exit(2)
}

let iconsetURL = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let slots: [(base: Int, scale: Int, name: String)] = [
  (16, 1, "icon_16x16.png"),
  (16, 2, "icon_16x16@2x.png"),
  (32, 1, "icon_32x32.png"),
  (32, 2, "icon_32x32@2x.png"),
  (128, 1, "icon_128x128.png"),
  (128, 2, "icon_128x128@2x.png"),
  (256, 1, "icon_256x256.png"),
  (256, 2, "icon_256x256@2x.png"),
  (512, 1, "icon_512x512.png"),
  (512, 2, "icon_512x512@2x.png")
]

func drawIcon(pixelSize: Int) -> NSImage {
  let size = CGFloat(pixelSize)
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()

  let rect = NSRect(x: 0, y: 0, width: size, height: size)
  NSColor.clear.setFill()
  rect.fill()

  let inset = size * 0.065
  let plateRect = rect.insetBy(dx: inset, dy: inset)
  let radius = size * 0.19
  let plate = NSBezierPath(roundedRect: plateRect, xRadius: radius, yRadius: radius)
  let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.22, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.14, alpha: 1.0)
  ])
  gradient?.draw(in: plate, angle: 90)

  NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
  plate.lineWidth = max(1, size * 0.012)
  plate.stroke()

  let inner = plateRect.insetBy(dx: size * 0.17, dy: size * 0.18)
  let barWidth = inner.width * 0.19
  let gap = inner.width * 0.07
  let colors = [
    NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.50, alpha: 1.0),
    NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.22, alpha: 1.0),
    NSColor(calibratedRed: 0.92, green: 0.24, blue: 0.25, alpha: 1.0)
  ]
  let heights = [inner.height * 0.42, inner.height * 0.64, inner.height * 0.88]

  for index in 0..<3 {
    let x = inner.minX + CGFloat(index) * (barWidth + gap)
    let y = inner.minY
    let barRect = NSRect(x: x, y: y, width: barWidth, height: heights[index])
    let bar = NSBezierPath(roundedRect: barRect, xRadius: barWidth * 0.35, yRadius: barWidth * 0.35)
    colors[index].setFill()
    bar.fill()
  }

  let wave = NSBezierPath()
  let waveY = inner.minY + inner.height * 0.78
  wave.move(to: NSPoint(x: inner.minX, y: waveY))
  wave.curve(
    to: NSPoint(x: inner.midX, y: waveY + inner.height * 0.13),
    controlPoint1: NSPoint(x: inner.minX + inner.width * 0.18, y: waveY + inner.height * 0.18),
    controlPoint2: NSPoint(x: inner.minX + inner.width * 0.31, y: waveY + inner.height * 0.02)
  )
  wave.curve(
    to: NSPoint(x: inner.maxX, y: waveY - inner.height * 0.02),
    controlPoint1: NSPoint(x: inner.minX + inner.width * 0.68, y: waveY + inner.height * 0.26),
    controlPoint2: NSPoint(x: inner.minX + inner.width * 0.77, y: waveY - inner.height * 0.10)
  )
  NSColor(calibratedWhite: 1.0, alpha: 0.86).setStroke()
  wave.lineWidth = max(2, size * 0.035)
  wave.lineCapStyle = .round
  wave.stroke()

  image.unlockFocus()
  return image
}

func writePNG(image: NSImage, to url: URL) throws {
  guard let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
  else {
    throw NSError(domain: "IconFactory", code: 1)
  }
  try png.write(to: url)
}

for slot in slots {
  let pixels = slot.base * slot.scale
  let image = drawIcon(pixelSize: pixels)
  try writePNG(image: image, to: iconsetURL.appendingPathComponent(slot.name))
}
