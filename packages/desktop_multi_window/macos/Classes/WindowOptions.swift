import Cocoa
import Foundation

struct WindowOptions {
    // Common properties for both NSWindow and NSPanel.
    let type: String
    let level: Int
    let styleMask: UInt
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let title: String
    let isOpaque: Bool
    let hasShadow: Bool
    let isMovable: Bool
    let backing: String
    let backgroundColor: NSColor
    let windowButtonVisibility: Bool

    // NSWindow-only properties.
    let isModal: Bool?
    let titleVisibility: String?
    let titlebarAppearsTransparent: Bool?
    let collectionBehavior: Int?
    let ignoresMouseEvents: Bool?
    let acceptsMouseMovedEvents: Bool?
    let animationBehavior: String?

    init?(json: [String: Any]) {
        // Parse common properties.
        guard let type = json["type"] as? String,
            let level = json["level"] as? Int,
            let styleMask = json["styleMask"] as? UInt,
            let x = json["x"] as? Int,
            let y = json["y"] as? Int,
            let width = json["width"] as? Int,
            let height = json["height"] as? Int,
            let title = json["title"] as? String,
            let isOpaque = json["isOpaque"] as? Bool,
            let hasShadow = json["hasShadow"] as? Bool,
            let isMovable = json["isMovable"] as? Bool,
            let backing = json["backing"] as? String,
            let backgroundColor = json["backgroundColor"] as? [String: Any],
            let windowButtonVisibility = json["windowButtonVisibility"] as? Bool
        else {
            return nil
        }

        self.type = type
        self.level = level
        self.styleMask = styleMask
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.title = title
        self.isOpaque = isOpaque
        self.hasShadow = hasShadow
        self.isMovable = isMovable
        self.backing = backing
        self.backgroundColor = WindowOptions.parseColor(from: backgroundColor) ?? NSColor.clear
        self.windowButtonVisibility = windowButtonVisibility

        // NSWindow-specific properties.
        if type == "NSWindow" {
            self.isModal = json["isModal"] as? Bool
            self.titleVisibility = json["titleVisibility"] as? String
            self.titlebarAppearsTransparent = json["titlebarAppearsTransparent"] as? Bool
            self.collectionBehavior = json["collectionBehavior"] as? Int
            self.ignoresMouseEvents = json["ignoresMouseEvents"] as? Bool
            self.acceptsMouseMovedEvents = json["acceptsMouseMovedEvents"] as? Bool
            self.animationBehavior = json["animationBehavior"] as? String
        } else {
            self.isModal = nil
            self.titleVisibility = nil
            self.titlebarAppearsTransparent = nil
            self.collectionBehavior = nil
            self.ignoresMouseEvents = nil
            self.acceptsMouseMovedEvents = nil
            self.animationBehavior = nil
        }
    }

    private static func parseColor(from json: [String: Any]) -> NSColor? {
        // Expect red, green, blue as integers, and optionally alpha.
        guard let redValue = json["red"] as? Int,
            let greenValue = json["green"] as? Int,
            let blueValue = json["blue"] as? Int
        else {
            return nil
        }
        // Alpha is optional, defaulting to 255 (fully opaque)
        let alphaValue = json["alpha"] as? Int ?? 255

        // Convert the 0...255 integer values into CGFloats in the 0.0...1.0 range.
        let red = CGFloat(redValue) / 255.0
        let green = CGFloat(greenValue) / 255.0
        let blue = CGFloat(blueValue) / 255.0
        let alpha = CGFloat(alphaValue) / 255.0

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func printOptions() {
        print("Window Options:")
        print("  Type: \(type)")
        print("  Level: \(level)")
        print("  StyleMask: \(String(format: "0x%X", styleMask))")
        print("  Position: (\(x), \(y))")
        print("  Size: \(width) x \(height)")
        print("  Title: \(title)")
        print("  isOpaque: \(isOpaque)")
        print("  hasShadow: \(hasShadow)")
        print("  isMovable: \(isMovable)")
        print("  Backing: \(backing)")

        if type == "NSWindow" {
            print("  NSWindow Specific:")
            print("    isModal: \(isModal != nil ? "\(isModal!)" : "nil")")
            print("    titleVisibility: \(titleVisibility ?? "nil")")
            print(
                "    titlebarAppearsTransparent: \(titlebarAppearsTransparent != nil ? "\(titlebarAppearsTransparent!)" : "nil")"
            )
            print(
                "    collectionBehavior: \(collectionBehavior != nil ? "\(collectionBehavior!)" : "nil")"
            )
            print(
                "    ignoresMouseEvents: \(ignoresMouseEvents != nil ? "\(ignoresMouseEvents!)" : "nil")"
            )
            print(
                "    acceptsMouseMovedEvents: \(acceptsMouseMovedEvents != nil ? "\(acceptsMouseMovedEvents!)" : "nil")"
            )
            print("    animationBehavior: \(animationBehavior ?? "nil")")
        }
    }
}
