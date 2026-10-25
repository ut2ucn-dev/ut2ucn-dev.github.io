#ifndef RUNNER_STEMIK_WINDOWS_H_
#define RUNNER_STEMIK_WINDOWS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

class FlutterWindow;

// Extra windows — a student's card next to the main window. Each runs the
// app's Dart code again in an engine of its own, started with the
// entrypoint arguments ["window", <spec>] (lib/desktop/windows.dart), the
// same as on the Mac (StemikWindows in macos/Runner/MainFlutterWindow.swift).
// Messages between the main engine and the windows pass through here:
//
//  * "studio.stemik/windows" in the main engine: open, send, broadcast,
//    closeAll, quit from Dart; message and closed back to it;
//  * "studio.stemik/window" in each window's engine: toMain, setTitle,
//    close from Dart; message and willClose to it.
//
// Closing the main window first lets every extra window finish sending
// (each has two seconds), then closes the app.
class StemikWindows {
 public:
  // Posted to the main window to free the extra windows already closed
  // (never from inside their own message handling).
  static constexpr UINT kCleanUpMessage = WM_APP + 1;

  static StemikWindows& Get();

  // The main window's engine is up.
  void AttachMain(FlutterWindow* main, flutter::BinaryMessenger* messenger);
  void DetachMain();

  // The main window was asked to close: the extra windows close first.
  void MainClosing();

  // An extra window's engine is up; the window has gone.
  void AttachWindow(const std::string& key, flutter::BinaryMessenger* messenger);
  void WindowDestroyed(const std::string& key);

  // Asks an extra window's Dart side to finish (send what it can, save the
  // rest); the window then closes.
  void AskToFinish(const std::string& key);

  // Frees the extra windows already closed.
  void CleanUp();

 private:
  using Channel = flutter::MethodChannel<flutter::EncodableValue>;

  struct Entry {
    std::unique_ptr<FlutterWindow> window;
    std::unique_ptr<Channel> channel;
  };

  StemikWindows() = default;

  void HandleMain(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleWindow(const std::string& key,
                    const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool Open(const std::string& key, const std::string& spec,
            const std::string& title, double width, double height);
  void CloseAll();
  void Place(HWND window);

  FlutterWindow* main_ = nullptr;
  std::unique_ptr<Channel> main_channel_;
  bool main_closing_ = false;
  std::map<std::string, Entry> entries_;
  std::vector<std::unique_ptr<FlutterWindow>> closed_;
};

#endif  // RUNNER_STEMIK_WINDOWS_H_
