import Cocoa
#if SWIFT_PACKAGE
import desktop_webview_window_composer
#endif

/// The default composer: an icon-only toolbar above the WebView. It uses only
/// the public composer API.
enum DefaultComposer {
  private static var toolbars: [Int64: Toolbar] = [:]

  static func install() {
    var composer = DWWComposer(
      user: nil,
      compose: { _, request in DefaultComposer.compose(request!.pointee) },
      navigation_changed: { _, state in DefaultComposer.update(state!.pointee) },
      layout: nil,
      closing: { _, browser in DefaultComposer.toolbars[browser] = nil })
    dww_darwin_set_default_composer(&composer)
  }

  private static func compose(_ request: DWWComposeRequest) -> DWWComposeResult {
    let window = Unmanaged<NSWindow>.fromOpaque(request.window).takeUnretainedValue()
    let webView = Unmanaged<NSView>.fromOpaque(request.webview_view).takeUnretainedValue()
    guard let root = window.contentView else { return DWW_COMPOSE_HANDLED }
    webView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(webView)
    var constraints = [
      webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ]
    if request.show_toolbar != 0 {
      let toolbar = Toolbar(browser: request.browser)
      toolbars[request.browser] = toolbar
      toolbar.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(toolbar)
      constraints += [
        toolbar.topAnchor.constraint(equalTo: root.topAnchor),
        toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      ]
    } else {
      constraints.append(webView.topAnchor.constraint(equalTo: root.topAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    return DWW_COMPOSE_HANDLED
  }

  private static func update(_ state: DWWNavigationState) {
    toolbars[state.browser]?.update(
      canGoBack: state.can_go_back != 0,
      canGoForward: state.can_go_forward != 0,
      isLoading: state.is_loading != 0,
      title: state.title.map { String(cString: $0) } ?? "")
  }

  private final class Toolbar: NSView {
    private let browser: Int64
    private let back: NSButton
    private let forward: NSButton
    private let reload: NSButton
    private let title = NSTextField(labelWithString: "")
    private var isLoading = false

    init(browser: Int64) {
      self.browser = browser
      back = Self.button(NSImage.goLeftTemplateName)
      forward = Self.button(NSImage.goRightTemplateName)
      reload = Self.button(NSImage.refreshTemplateName)
      super.init(frame: .zero)
      back.target = self
      back.action = #selector(goBack)
      forward.target = self
      forward.action = #selector(goForward)
      reload.target = self
      reload.action = #selector(reloadOrStop)
      back.isEnabled = false
      forward.isEnabled = false
      title.lineBreakMode = .byTruncatingTail
      title.textColor = .secondaryLabelColor
      title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      let stack = NSStackView(views: [back, forward, reload, title])
      stack.orientation = .horizontal
      stack.spacing = 4
      stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
      stack.setCustomSpacing(10, after: reload)
      stack.translatesAutoresizingMaskIntoConstraints = false
      let separator = NSBox()
      separator.boxType = .separator
      separator.translatesAutoresizingMaskIntoConstraints = false
      addSubview(stack)
      addSubview(separator)
      NSLayoutConstraint.activate([
        heightAnchor.constraint(equalToConstant: 36),
        stack.leadingAnchor.constraint(equalTo: leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        stack.topAnchor.constraint(equalTo: topAnchor),
        stack.bottomAnchor.constraint(equalTo: separator.topAnchor),
        separator.leadingAnchor.constraint(equalTo: leadingAnchor),
        separator.trailingAnchor.constraint(equalTo: trailingAnchor),
        separator.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    private static func button(_ image: NSImage.Name) -> NSButton {
      let button = NSButton(image: NSImage(named: image)!, target: nil, action: nil)
      button.bezelStyle = .texturedRounded
      button.isBordered = false
      button.refusesFirstResponder = true
      return button
    }

    func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool, title: String) {
      back.isEnabled = canGoBack
      forward.isEnabled = canGoForward
      self.isLoading = isLoading
      reload.image = NSImage(
        named: isLoading ? NSImage.stopProgressTemplateName : NSImage.refreshTemplateName)
      self.title.stringValue = title
    }

    @objc private func goBack() { dww_browser_go_back(browser) }
    @objc private func goForward() { dww_browser_go_forward(browser) }
    @objc private func reloadOrStop() {
      if isLoading { dww_browser_stop(browser) } else { dww_browser_reload(browser) }
    }
  }
}
