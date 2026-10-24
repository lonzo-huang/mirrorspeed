import AppKit
import CoreGraphics

// 把方形满幅图标做成 macOS 规范的圆角图标：
//   画布 1024，艺术部分 824 居中（四周留白给系统投影），圆角半径 184（0.2237×824）
// 先按亮度裁出主体（原图四周是大片近黑背景，直接整张缩放会显得主体很小且有双重边框）。

let srcPath = CommandLine.arguments[1]
let outDir  = CommandLine.arguments[2]

guard let src = NSImage(contentsOfFile: srcPath),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fatalError("读不到源图 \(srcPath)")
}
let W = cg.width, H = cg.height

// ── 1) 按亮度求主体包围盒 ────────────────────────────────────────────
var pixels = [UInt8](repeating: 0, count: W * H * 4)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: W * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
  fatalError("建位图上下文失败")
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

let thr = Double(CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 42) : 42)
var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H {
  for x in 0..<W {
    let i = (y * W + x) * 4
    let lum = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i+1]) + 0.114 * Double(pixels[i+2])
    if lum > thr {
      if x < minX { minX = x }; if x > maxX { maxX = x }
      if y < minY { minY = y }; if y > maxY { maxY = y }
    }
  }
}
guard maxX > minX, maxY > minY else { fatalError("没找到主体") }

// 取正方形（以包围盒中心为心，边长取长边），并夹在原图范围内
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
var side = max(maxX - minX, maxY - minY)
side = min(side, min(W, H))
var ox = cx - side / 2, oy = cy - side / 2
ox = max(0, min(ox, W - side)); oy = max(0, min(oy, H - side))
print("主体包围盒 x[\(minX)-\(maxX)] y[\(minY)-\(maxY)] → 裁切 \(side)x\(side) @(\(ox),\(oy))")
guard let cropped = cg.cropping(to: CGRect(x: ox, y: oy, width: side, height: side)) else {
  fatalError("裁切失败")
}

// ── 2) 渲染成圆角图标 ────────────────────────────────────────────────
func render(size: Int) -> CGImage {
  let canvas = CGFloat(size)
  let art    = (canvas * 824.0 / 1024.0).rounded()        // 艺术区占比（Apple 图标栅格）
  let radius = art * 0.2237                                // macOS 圆角比例
  let inset  = ((canvas - art) / 2).rounded()

  guard let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("建输出上下文失败")
  }
  c.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
  let rect = CGRect(x: inset, y: inset, width: art, height: art)
  c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
  c.clip()
  c.interpolationQuality = .high
  c.draw(cropped, in: rect)
  return c.makeImage()!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
  let img = render(size: size)
  let url = URL(fileURLWithPath: "\(outDir)/app_icon_\(size).png")
  let rep = NSBitmapImageRep(cgImage: img)
  rep.size = NSSize(width: size, height: size)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print("✓ \(size)x\(size)")
}
