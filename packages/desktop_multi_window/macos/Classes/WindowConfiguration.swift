import Foundation
import Cocoa


struct WindowConfiguration: Codable {
 
    let arguments: String
    
    let title: String
    let frame: WindowFrame
    let resizable: Bool
    let hideTitleBar: Bool
    let hiddenAtLaunch: Bool
    
    enum CodingKeys: String, CodingKey {
        case arguments
        case title
        case frame
        case resizable
        case hideTitleBar
        case hiddenAtLaunch
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        frame = try container.decodeIfPresent(WindowFrame.self, forKey: .frame) ?? WindowFrame(left: 0, top: 0, width: 800, height: 400)
        resizable = try container.decodeIfPresent(Bool.self, forKey: .resizable) ?? true
        hideTitleBar = try container.decodeIfPresent(Bool.self, forKey: .hideTitleBar) ?? false
        hiddenAtLaunch = try container.decodeIfPresent(Bool.self, forKey: .hiddenAtLaunch) ?? false
    }
    
    init(arguments: String, title: String, frame: WindowFrame, resizable: Bool, hideTitleBar: Bool, hiddenAtLaunch: Bool) {
        self.arguments = arguments
        self.title = title
        self.frame = frame
        self.resizable = resizable
        self.hideTitleBar = hideTitleBar
        self.hiddenAtLaunch = hiddenAtLaunch
    }

    struct WindowFrame: Codable {
        let left: Double
        let top: Double
        let width: Double
        let height: Double
        
        func toTopLeftPoint() -> NSPoint {
            return NSPoint(x: left, y: top)
        }
        
        func toContentSize() -> NSSize {
            return NSSize(width: width, height: height)
        }
    }
    
    static let defaultConfiguration = WindowConfiguration(
        arguments: "",
        title: "",
        frame: WindowFrame(left: 0, top: 0, width: 800, height: 400),
        resizable: true,
        hideTitleBar: true,
        hiddenAtLaunch: false
    )
    
    static func fromJson(_ jsonString: String) -> WindowConfiguration {
        guard !jsonString.isEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            debugPrint("invalid json string: \(jsonString)")
            return defaultConfiguration
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WindowConfiguration.self, from: jsonData)
        } catch {
            debugPrint("Failed to parse window configuration: \(error)")
            return defaultConfiguration
        }
    }
    
    func getStyleMask() -> NSWindow.StyleMask {
        var styleMask: NSWindow.StyleMask = [.miniaturizable, .closable, .titled]
        
        if hideTitleBar {
            styleMask.insert(.fullSizeContentView)
        }
        
        if resizable {
            styleMask.insert(.resizable)
        }
        
        return styleMask
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(title, forKey: .title)
        try container.encode(frame, forKey: .frame)
        try container.encode(resizable, forKey: .resizable)
        try container.encode(hideTitleBar, forKey: .hideTitleBar)
        try container.encode(hiddenAtLaunch, forKey: .hiddenAtLaunch)
    }
}
