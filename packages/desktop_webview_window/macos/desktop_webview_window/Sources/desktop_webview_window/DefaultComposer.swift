import Cocoa
#if SWIFT_PACKAGE
import desktop_webview_window_composer
#endif

/// The default composer: navigation buttons, the page title and its host in
/// the window's unified title bar, the WebView below. It uses only the public
/// composer API.
enum DefaultComposer {
  private static var titleBars: [Int64: TitleBar] = [:]

  static func install() {
    var composer = DWWComposer(
      user: nil,
      compose: { _, request in DefaultComposer.compose(request!.pointee) },
      navigation_changed: { _, state in DefaultComposer.update(state!.pointee) },
      layout: nil,
      closing: { _, browser in DefaultComposer.titleBars[browser] = nil })
    dww_darwin_set_default_composer(&composer)
  }

  private static func compose(_ request: DWWComposeRequest) -> DWWComposeResult {
    let window = Unmanaged<NSWindow>.fromOpaque(request.window).takeUnretainedValue()
    let webView = Unmanaged<NSView>.fromOpaque(request.webview_view).takeUnretainedValue()
    guard let root = window.contentView else { return DWW_COMPOSE_HANDLED }
    webView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      webView.topAnchor.constraint(equalTo: root.topAnchor),
      webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    titleBars[request.browser] = TitleBar(
      browser: request.browser, window: window, items: request.title_bar)
    return DWW_COMPOSE_HANDLED
  }

  private static func update(_ state: DWWNavigationState) {
    titleBars[state.browser]?.update(state)
  }

  private final class TitleBar: NSObject, NSToolbarDelegate {
    private static let back = NSToolbarItem.Identifier("back")
    private static let forward = NSToolbarItem.Identifier("forward")
    private static let reload = NSToolbarItem.Identifier("reload")

    private let browser: Int64
    private weak var window: NSWindow?
    private let items: UInt32
    /// CreateConfiguration.title, shown while the page has no title.
    private let fallbackTitle: String
    private var buttons: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var isLoading = false

    init(browser: Int64, window: NSWindow, items: UInt32) {
      self.browser = browser
      self.window = window
      self.items = items
      fallbackTitle = window.title
      super.init()
      if has(DWW_TITLE_BAR_NAVIGATION) || has(DWW_TITLE_BAR_RELOAD) {
        // A per-browser identifier: toolbars sharing one sync their items.
        let toolbar = NSToolbar(identifier: "desktop_webview_window.\(browser)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
      }
      if #available(macOS 11.0, *) {
        window.toolbarStyle = .unified
      }
      window.titleVisibility =
        has(DWW_TITLE_BAR_TITLE) || has(DWW_TITLE_BAR_HOST) ? .visible : .hidden
    }

    private func has(_ item: DWWTitleBarItem) -> Bool {
      items & item.rawValue != 0
    }

    func update(_ state: DWWNavigationState) {
      buttons[Self.back]?.isEnabled = state.can_go_back != 0
      buttons[Self.forward]?.isEnabled = state.can_go_forward != 0
      isLoading = state.is_loading != 0
      if let reload = buttons[Self.reload] {
        reload.image = Self.image(isLoading ? .stop : .reload)
      }
      guard let window = window else { return }
      let title = state.title.map { String(cString: $0) } ?? ""
      let host = state.url.flatMap { URL(string: String(cString: $0))?.host } ?? ""
      let pageTitle = title.isEmpty ? fallbackTitle : title
      // The window title also names the window in the Dock and Window menu,
      // so it follows the page even when the title bar hides it.
      window.title = has(DWW_TITLE_BAR_TITLE) || !has(DWW_TITLE_BAR_HOST) ? pageTitle : host
      if #available(macOS 11.0, *) {
        window.subtitle = has(DWW_TITLE_BAR_TITLE) && has(DWW_TITLE_BAR_HOST) ? host : ""
      }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      var identifiers: [NSToolbarItem.Identifier] = []
      if has(DWW_TITLE_BAR_NAVIGATION) { identifiers += [Self.back, Self.forward] }
      if has(DWW_TITLE_BAR_RELOAD) { identifiers.append(Self.reload) }
      return identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
      let item = NSToolbarItem(itemIdentifier: identifier)
      switch identifier {
      case Self.back:
        item.image = Self.image(.back)
        item.action = #selector(goBack)
      case Self.forward:
        item.image = Self.image(.forward)
        item.action = #selector(goForward)
      default:
        item.image = Self.image(isLoading ? .stop : .reload)
        item.action = #selector(reloadOrStop)
      }
      item.target = self
      // Enabled from the navigation state, not by responder validation.
      item.autovalidates = false
      item.isEnabled = identifier == Self.reload
      if #available(macOS 11.0, *) {
        item.isBordered = true
        // Leading, before the title, like Finder's back and forward.
        item.isNavigational = true
      }
      buttons[identifier] = item
      return item
    }

    private enum Symbol { case back, forward, reload, stop }

    private static func image(_ symbol: Symbol) -> NSImage? {
      if #available(macOS 11.0, *) {
        let name: String
        switch symbol {
        case .back: name = "chevron.left"
        case .forward: name = "chevron.right"
        case .reload: name = "arrow.clockwise"
        case .stop: name = "xmark"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
      }
      switch symbol {
      case .back: return NSImage(named: NSImage.goLeftTemplateName)
      case .forward: return NSImage(named: NSImage.goRightTemplateName)
      case .reload: return NSImage(named: NSImage.refreshTemplateName)
      case .stop: return NSImage(named: NSImage.stopProgressTemplateName)
      }
    }

    @objc private func goBack() { dww_browser_go_back(browser) }
    @objc private func goForward() { dww_browser_go_forward(browser) }
    @objc private func reloadOrStop() {
      if isLoading { dww_browser_stop(browser) } else { dww_browser_reload(browser) }
    }
  }
}
