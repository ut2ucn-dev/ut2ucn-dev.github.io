#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view: the app's main window, or an extra
// window (a student's card) running an engine of its own — see
// stemik_windows.h.
class FlutterWindow : public Win32Window {
 public:
  // The main window: closing it closes the extra windows, then quits.
  explicit FlutterWindow(const flutter::DartProject& project);

  // An extra window, known to StemikWindows by |key|.
  FlutterWindow(const flutter::DartProject& project, const std::string& key);

  virtual ~FlutterWindow();

  // Lets the window close (after the extra windows, or an extra window's
  // Dart side, have finished).
  void FinishClosing();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool is_main() const { return key_.empty(); }

  // Handles WM_CLOSE; true when the window may be destroyed now.
  bool OnClose(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // Empty for the main window.
  std::string key_;

  // WM_CLOSE was received and the window is finishing.
  bool closing_ = false;

  // The window may be destroyed on the next WM_CLOSE.
  bool may_close_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
