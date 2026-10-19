import AppKit
import Foundation

// The private archive retains typed image options, including NSColor.
let args = CommandLine.arguments
// Palette art is drawn locally and reproducibly; it contains no screen capture.
if args.count == 4 && args[1] == "render" {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard let palette = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw CocoaError(.coderReadCorrupt)
        }
        func color(_ key: String, alpha: CGFloat = 1) throws -> CGColor {
            guard let text = palette[key], text.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
                  let rgb = UInt32(text, radix: 16) else { throw CocoaError(.coderReadCorrupt) }
            return CGColor(red: CGFloat((rgb >> 16) & 255)/255,
                green: CGFloat((rgb >> 8) & 255)/255, blue: CGFloat(rgb & 255)/255, alpha: alpha)
        }
        guard let context = CGContext(data: nil, width: 3456, height: 2234, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.coderInvalidValue) }
        context.scaleBy(x: 3456/2560, y: 2234/1655)
        let space = CGColorSpaceCreateDeviceRGB()
        let background = CGGradient(colorsSpace: space,
            colors: try [color("popup"), color("surface"), color("highlight")] as CFArray,
            locations: [0, 0.65, 1])!
        context.drawLinearGradient(background, start: CGPoint(x: 0, y: 1655),
            end: CGPoint(x: 2560, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glow = CGGradient(colorsSpace: space,
            colors: try [color("accent", alpha: 0.13), color("accent", alpha: 0)] as CFArray,
            locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 1850, y: 720), startRadius: 0,
            endCenter: CGPoint(x: 1850, y: 720), endRadius: 1180, options: [])
        // Quiet contour ribbons leave the main working area uncluttered.
        for index in 0..<13 {
            let offset = CGFloat(index) * 38
            context.beginPath()
            context.move(to: CGPoint(x: 1080 + offset, y: -120))
            context.addCurve(to: CGPoint(x: 2800, y: 1270 + offset),
                control1: CGPoint(x: 1290 + offset, y: 620),
                control2: CGPoint(x: 2080, y: 480 + offset))
            context.setStrokeColor(try color(index % 3 == 0 ? "accent" : "secondary", alpha: index % 3 == 0 ? 0.13 : 0.045))
            context.setLineWidth(index % 3 == 0 ? 1.4 : 0.8)
            context.strokePath()
        }
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.coderInvalidValue)
        }
        try png.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: args[3])
        exit(0)
    } catch {
        fputs("Wallpaper rendering failed: \(error)\n", stderr)
        exit(1)
    }
}
guard args.count == 3, ["capture", "set", "restore"].contains(args[1]) else {
    fputs("Usage: wallpaper capture backup | set image | restore backup | render palette.json output.png\n", stderr)
    exit(64)
}
let file = URL(fileURLWithPath: args[2]).standardizedFileURL
let workspace = NSWorkspace.shared
func displayID(_ screen: NSScreen) -> String {
    let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    return CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()) as String
}
let previous = NSScreen.screens.map { screen in
    (screen, workspace.desktopImageURL(for: screen), workspace.desktopImageOptions(for: screen) ?? [:])
}
guard !previous.isEmpty, previous.allSatisfy({ $0.1 != nil }) else {
    fputs("Cannot read every current desktop image; nothing changed.\n", stderr)
    exit(1)
}
do {
    switch args[1] {
    case "capture":
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw NSError(domain: "dotfiles", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to replace an existing wallpaper backup"])
        }
        let records = previous.map { screen, url, options -> [String: Any] in
            ["display": displayID(screen), "image": url!,
             "options": Dictionary(uniqueKeysWithValues: options.map { ($0.key.rawValue, $0.value) })]
        }
        let data = try NSKeyedArchiver.archivedData(withRootObject: records, requiringSecureCoding: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    case "set":
        guard NSImage(contentsOf: file) != nil else {
            throw NSError(domain: "dotfiles", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Wallpaper must be a readable image"])
        }
        for (screen, _, _) in previous {
            try workspace.setDesktopImageURL(file, for: screen,
                options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue])
        }
    default:
        let classes: [AnyClass] = [NSArray.self, NSDictionary.self, NSString.self,
                                  NSURL.self, NSNumber.self, NSColor.self]
        let data = try Data(contentsOf: file)
        guard let records = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data)
            as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        for (screen, _, _) in previous {
            guard let record = records.first(where: { $0["display"] as? String == displayID(screen) }),
                  let image = record["image"] as? URL,
                  let rawOptions = record["options"] as? [String: Any] else { continue }
            let options = Dictionary(uniqueKeysWithValues: rawOptions.map {
                (NSWorkspace.DesktopImageOptionKey(rawValue: $0.key), $0.value)
            })
            try workspace.setDesktopImageURL(image, for: screen, options: options)
        }
    }
} catch {
    if args[1] != "capture" {
        for (screen, image, options) in previous {
            try? workspace.setDesktopImageURL(image!, for: screen, options: options)
        }
    }
    fputs("Wallpaper action failed: \(error)\n", stderr)
    exit(1)
}
