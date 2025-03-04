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
        // Use default values for optional parameters
        self.type = json["type"] as? String ?? "NSWindow"
        self.level = json["level"] as? Int ?? Int(NSWindow.Level.normal.rawValue)
        self.styleMask = json["styleMask"] as? UInt ?? UInt(NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable]).rawValue)
        self.x = json["left"] as? Int ?? 0
        self.y = json["top"] as? Int ?? 0
        self.width = json["width"] as? Int ?? 800
        self.height = json["height"] as? Int ?? 600
        self.title = json["title"] as? String ?? ""
        self.isOpaque = json["isOpaque"] as? Bool ?? true
        self.hasShadow = json["hasShadow"] as? Bool ?? true
        self.isMovable = json["isMovable"] as? Bool ?? true
        self.backing = json["backing"] as? String ?? "buffered"
        
        if let bgColor = json["backgroundColor"] as? [String: Any] {
            self.backgroundColor = WindowOptions.parseColor(from: bgColor) ?? NSColor.windowBackgroundColor
        } else {
            self.backgroundColor = NSColor.windowBackgroundColor
        }
        
        self.windowButtonVisibility = json["windowButtonVisibility"] as? Bool ?? true

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

    static func parseColor(from json: [String: Any]) -> NSColor? {
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
