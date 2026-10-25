#include "flutter_window.h"

#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "stemik_windows.h"
#include "utils.h"

namespace {

// An extra window's Dart side gets this long to finish when it closes.
constexpr UINT_PTR kCloseTimer = 1;
constexpr UINT kCloseTimeoutMs = 2000;

// Smallest window sizes, in logical pixels: room for the sidebar, a list
// and a card side by side; a student's card.
constexpr LONG kMainMinWidth = 1040;
constexpr LONG kMainMinHeight = 680;
constexpr LONG kExtraMinWidth = 480;
constexpr LONG kExtraMinHeight = 520;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             const std::string& key)
    : project_(project), key_(key) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::BinaryMessenger* messenger = flutter_controller_->engine()->messenger();
  if (is_main()) {
    StemikWindows::Get().AttachMain(this, messenger);
  } else {
    StemikWindows::Get().AttachWindow(key_, messenger);
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // The channels go before the engine they talk to.
  if (is_main()) {
    StemikWindows::Get().DetachMain();
  } else {
    StemikWindows::Get().WindowDestroyed(key_);
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::FinishClosing() {
  HWND hwnd = GetHandle();
  if (may_close_ || hwnd == nullptr) {
    return;
  }
  may_close_ = true;
  ::KillTimer(hwnd, kCloseTimer);
  ::PostMessage(hwnd, WM_CLOSE, 0, 0);
}

bool FlutterWindow::OnClose(HWND hwnd) {
  if (may_close_) {
    return true;
  }
  if (closing_) {
    return false;
  }
  closing_ = true;
  if (is_main()) {
    SaveWindowPlacement(hwnd);
    // The extra windows first finish sending and save what's left; the
    // main window then closes (StemikWindows calls FinishClosing).
    StemikWindows::Get().MainClosing();
    return false;
  }
  // Lets the window's Dart side finish sending and save what's left, for
  // at most two seconds.
  ::SetTimer(hwnd, kCloseTimer, kCloseTimeoutMs, nullptr);
  StemikWindows::Get().AskToFinish(key_);
  return false;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Closing is the app's own business: handled before Flutter sees it.
  if (message == WM_CLOSE) {
    if (OnClose(hwnd)) {
      ::DestroyWindow(hwnd);
    }
    return 0;
  }
  if (message == WM_TIMER && wparam == kCloseTimer) {
    FinishClosing();
    return 0;
  }
  if (message == StemikWindows::kCleanUpMessage) {
    StemikWindows::Get().CleanUp();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_GETMINMAXINFO: {
      const double scale = FlutterDesktopGetDpiForHWND(hwnd) / 96.0;
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = static_cast<LONG>(
          (is_main() ? kMainMinWidth : kExtraMinWidth) * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(
          (is_main() ? kMainMinHeight : kExtraMinHeight) * scale);
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
