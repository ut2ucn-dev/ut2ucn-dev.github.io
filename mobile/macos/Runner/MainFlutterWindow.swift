import Cocoa
import FlutterMacOS
import connectivity_plus
import file_selector_macos
import package_info_plus
import share_plus
import shared_preferences_foundation
import sqflite_darwin
import url_launcher_macos

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // The launch intro's navy (lib/ui/intro.dart), so the window never
    // flashes white before the first Flutter frame.
    let navy = NSColor(red: 0x05 / 255.0, green: 0x26 / 255.0, blue: 0x3F / 255.0, alpha: 1)
    flutterViewController.backgroundColor = navy
    self.backgroundColor = navy
    self.contentViewController = flutterViewController

    // Room for the sidebar, a list and a card side by side; the window
    // remembers its size and place between launches.
    self.contentMinSize = NSSize(width: 1040, height: 680)
    self.setContentSize(NSSize(width: 1360, height: 860))
    self.center()
    self.setFrameAutosaveName("StemikAdminMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)
    StemikWindows.shared.attach(main: flutterViewController)

    super.awakeFromNib()
  }

  // The extra windows live off this one's session: they go with it. What
  // they couldn't send is taken over at the next start.
  override func close() {
    StemikWindows.shared.detachMain()
    StemikWindows.shared.closeAll()
    super.close()
  }
}

/// Plugins for an extra window's engine: those its screens use. Not the
/// notifications plugin — registering it again would take the app's
/// notification delegate away from the main window, where reminder taps
/// belong — and not app_links (the window has no login of its own). Keep in
/// step with Flutter/GeneratedPluginRegistrant.swift.
func RegisterWindowPlugins(registry: FlutterPluginRegistry) {
  ConnectivityPlusPlugin.register(with: registry.registrar(forPlugin: "ConnectivityPlusPlugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  SqflitePlugin.register(with: registry.registrar(forPlugin: "SqflitePlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
}

/// Extra windows — a student's card next to the main window. Stable Flutter
/// draws one window per engine, so each runs the app's Dart code again in an
/// engine of its own, started with the entrypoint arguments
/// ["window", <spec>] (lib/desktop/windows.dart). Messages between the main
/// engine and the windows pass through here:
///
///  * "studio.stemik/windows" in the main engine: open, send, broadcast,
///    closeAll from Dart; message and closed back to it;
///  * "studio.stemik/window" in each window's engine: toMain, setTitle,
///    close from Dart; message and willClose to it.
final class StemikWindows: NSObject, NSWindowDelegate {
  static let shared = StemikWindows()

  private final class Entry {
    let key: String
    let window: NSWindow
    let controller: FlutterViewController
    let channel: FlutterMethodChannel
    var closing = false

    init(key: String, window: NSWindow, controller: FlutterViewController, channel: FlutterMethodChannel) {
      self.key = key
      self.window = window
      self.controller = controller
      self.channel = channel
    }
  }

  private var main: FlutterMethodChannel?
  private var entries: [String: Entry] = [:]

  func attach(main controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "studio.stemik/windows", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handleMain(call, result: result)
    }
    main = channel
  }

  func detachMain() {
    main?.setMethodCallHandler(nil)
    main = nil
  }

  func closeAll() {
    for entry in Array(entries.values) {
      entry.window.performClose(nil)
    }
  }

  private func handleMain(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "open":
      guard let key = args["key"] as? String, let spec = args["spec"] as? String else {
        result(FlutterError(code: "args", message: "key and spec are required", details: nil))
        return
      }
      if let entry = entries[key] {
        entry.window.makeKeyAndOrderFront(nil)
        result(false)
        return
      }
      let width = args["width"] as? Double ?? 760
      let height = args["height"] as? Double ?? 840
      open(
        key: key, spec: spec, title: args["title"] as? String ?? "Stemik",
        size: NSSize(width: width, height: height))
      result(true)
    case "send":
      if let key = args["key"] as? String, let entry = entries[key] {
        entry.channel.invokeMethod("message", arguments: args["message"])
      }
      result(nil)
    case "broadcast":
      for entry in entries.values {
        entry.channel.invokeMethod("message", arguments: args["message"])
      }
      result(nil)
    case "closeAll":
      closeAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(key: String, spec: String, title: String, size: NSSize) {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["window", spec]
    let controller = FlutterViewController(project: project)
    controller.backgroundColor = NSColor.windowBackgroundColor
    RegisterWindowPlugins(registry: controller)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = title
    window.tabbingMode = .disallowed
    window.backgroundColor = NSColor.windowBackgroundColor
    window.contentViewController = controller
    window.setContentSize(size)
    window.contentMinSize = NSSize(width: 480, height: 520)
    window.delegate = self
    place(window)

    let channel = FlutterMethodChannel(
      name: "studio.stemik/window", binaryMessenger: controller.engine.binaryMessenger)
    let entry = Entry(key: key, window: window, controller: controller, channel: channel)
    channel.setMethodCallHandler { [weak self, weak entry] call, result in
      guard let self = self, let entry = entry else {
        result(nil)
        return
      }
      switch call.method {
      case "toMain":
        let payload: [String: Any] = ["key": entry.key, "message": call.arguments ?? NSNull()]
        self.main?.invokeMethod("message", arguments: payload)
        result(nil)
      case "setTitle":
        if let title = call.arguments as? String {
          entry.window.title = title
        }
        result(nil)
      case "close":
        entry.window.performClose(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    entries[key] = entry
    window.makeKeyAndOrderFront(nil)
  }

  /// Over the right part of the main window, each further one a step
  /// down and to the right, and always on screen.
  private func place(_ window: NSWindow) {
    guard let main = NSApp.windows.first(where: { $0 is MainFlutterWindow }),
      let screen = main.screen ?? NSScreen.main
    else {
      window.center()
      return
    }
    let step = CGFloat(entries.count % 6) * 26
    let size = window.frame.size
    window.setFrameOrigin(
      NSPoint(
        x: main.frame.maxX - size.width - 40 + step,
        y: main.frame.maxY - size.height - 70 - step))
    window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: false)
  }

  private func entry(for window: NSWindow?) -> Entry? {
    return entries.values.first { $0.window === window }
  }

  /// First lets the window's Dart side finish sending and save what's left
  /// (for at most two seconds), then closes.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let entry = entry(for: sender) else { return true }
    if entry.closing { return true }
    entry.closing = true
    var done = false
    let finish = { [weak sender] in
      if done { return }
      done = true
      sender?.close()
    }
    entry.channel.invokeMethod("willClose", arguments: nil) { _ in finish() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish() }
    return false
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, let entry = entry(for: window) else {
      return
    }
    entries.removeValue(forKey: entry.key)
    entry.channel.setMethodCallHandler(nil)
    main?.invokeMethod("closed", arguments: entry.key)
    // Let AppKit finish closing before the window's engine goes.
    DispatchQueue.main.async {
      window.contentViewController = nil
      entry.controller.engine.shutDownEngine()
    }
  }
}
