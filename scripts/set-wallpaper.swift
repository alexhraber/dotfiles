import AppKit
import Foundation

// The private archive retains typed image options, including NSColor.
let args = CommandLine.arguments
guard args.count == 3, ["capture", "set", "restore"].contains(args[1]) else {
    fputs("Usage: wallpaper capture backup | set image | restore backup\n", stderr)
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
