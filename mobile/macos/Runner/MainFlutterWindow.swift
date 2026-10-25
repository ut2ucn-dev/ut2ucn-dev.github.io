import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
