#include "stemik_windows.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Arg(const EncodableValue* arguments, const char* name) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  auto it = map->find(EncodableValue(std::string(name)));
  return it == map->end() ? nullptr : &it->second;
}

std::string StringArg(const EncodableValue* arguments, const char* name) {
  const auto* value = std::get_if<std::string>(Arg(arguments, name));
  return value == nullptr ? std::string() : *value;
}

double DoubleArg(const EncodableValue* arguments, const char* name,
                 double fallback) {
  const EncodableValue* value = Arg(arguments, name);
  if (const auto* d = std::get_if<double>(value)) {
    return *d;
  }
  if (const auto* i = std::get_if<int32_t>(value)) {
    return static_cast<double>(*i);
  }
  return fallback;
}

EncodableValue MessageArg(const EncodableValue* arguments) {
  const EncodableValue* value = Arg(arguments, "message");
  return value == nullptr ? EncodableValue() : *value;
}

}  // namespace

StemikWindows& StemikWindows::Get() {
  static StemikWindows instance;
  return instance;
}

void StemikWindows::AttachMain(FlutterWindow* main,
                               flutter::BinaryMessenger* messenger) {
  main_ = main;
  main_channel_ = std::make_unique<Channel>(
      messenger, "studio.stemik/windows",
      &flutter::StandardMethodCodec::GetInstance());
  main_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMain(call, std::move(result));
      });
}

void StemikWindows::DetachMain() {
  if (main_channel_) {
    main_channel_->SetMethodCallHandler(nullptr);
    main_channel_ = nullptr;
  }
  main_ = nullptr;
}

void StemikWindows::MainClosing() {
  if (main_ == nullptr) {
    return;
  }
  main_closing_ = true;
  if (entries_.empty()) {
    main_->FinishClosing();
    return;
  }
  // Out of sight while the student windows finish.
  ::ShowWindow(main_->GetHandle(), SW_HIDE);
  CloseAll();
}

void StemikWindows::CloseAll() {
  std::vector<HWND> windows;
  for (const auto& pair : entries_) {
    if (pair.second.window && pair.second.window->GetHandle() != nullptr) {
      windows.push_back(pair.second.window->GetHandle());
    }
  }
  for (HWND window : windows) {
    ::PostMessage(window, WM_CLOSE, 0, 0);
  }
}

void StemikWindows::HandleMain(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const EncodableValue* arguments = call.arguments();
  const std::string& method = call.method_name();
  if (method == "open") {
    const std::string key = StringArg(arguments, "key");
    const std::string spec = StringArg(arguments, "spec");
    if (key.empty() || spec.empty()) {
      result->Error("args", "key and spec are required");
      return;
    }
    auto it = entries_.find(key);
    if (it != entries_.end() && it->second.window) {
      HWND window = it->second.window->GetHandle();
      if (::IsIconic(window)) {
        ::ShowWindow(window, SW_RESTORE);
      }
      ::SetForegroundWindow(window);
      result->Success(EncodableValue(false));
      return;
    }
    std::string title = StringArg(arguments, "title");
    if (title.empty()) {
      title = "Stemik";
    }
    if (!Open(key, spec, title, DoubleArg(arguments, "width", 760),
              DoubleArg(arguments, "height", 840))) {
      result->Error("open", "the window could not be created");
      return;
    }
    result->Success(EncodableValue(true));
  } else if (method == "send") {
    auto it = entries_.find(StringArg(arguments, "key"));
    if (it != entries_.end() && it->second.channel) {
      it->second.channel->InvokeMethod(
          "message", std::make_unique<EncodableValue>(MessageArg(arguments)));
    }
    result->Success();
  } else if (method == "broadcast") {
    for (auto& pair : entries_) {
      if (pair.second.channel) {
        pair.second.channel->InvokeMethod(
            "message",
            std::make_unique<EncodableValue>(MessageArg(arguments)));
      }
    }
    result->Success();
  } else if (method == "closeAll") {
    CloseAll();
    result->Success();
  } else if (method == "quit") {
    if (main_ != nullptr) {
      ::PostMessage(main_->GetHandle(), WM_CLOSE, 0, 0);
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

bool StemikWindows::Open(const std::string& key, const std::string& spec,
                         const std::string& title, double width,
                         double height) {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"window", spec});
  Entry& entry = entries_[key];
  entry.window = std::make_unique<FlutterWindow>(project, key);
  const Win32Window::Point origin(10, 10);
  const Win32Window::Size size(static_cast<unsigned int>(width),
                               static_cast<unsigned int>(height));
  if (!entry.window->Create(Utf16FromUtf8(title), origin, size)) {
    entries_.erase(key);
    return false;
  }
  Place(entry.window->GetHandle());
  // Shown by its first frame (FlutterWindow::OnCreate).
  return true;
}

// Over the right part of the main window, each further one a step down and
// to the right, and always on the main window's screen.
void StemikWindows::Place(HWND window) {
  if (main_ == nullptr || main_->GetHandle() == nullptr) {
    return;
  }
  HWND main_window = main_->GetHandle();
  const double scale = FlutterDesktopGetDpiForHWND(main_window) / 96.0;
  RECT main_rect;
  RECT rect;
  if (!::GetWindowRect(main_window, &main_rect) ||
      !::GetWindowRect(window, &rect)) {
    return;
  }
  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  const double index = static_cast<double>((entries_.size() - 1) % 6);
  const LONG step = static_cast<LONG>(index * 26 * scale);
  LONG x = main_rect.right - width - static_cast<LONG>(40 * scale) + step;
  LONG y = main_rect.top + static_cast<LONG>(70 * scale) + step;

  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (::GetMonitorInfo(::MonitorFromWindow(main_window, MONITOR_DEFAULTTONEAREST),
                       &monitor)) {
    const RECT& work = monitor.rcWork;
    x = std::max(work.left, std::min(x, work.right - width));
    y = std::max(work.top, std::min(y, work.bottom - height));
  }
  ::SetWindowPos(window, nullptr, x, y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void StemikWindows::AttachWindow(const std::string& key,
                                 flutter::BinaryMessenger* messenger) {
  auto it = entries_.find(key);
  if (it == entries_.end()) {
    return;
  }
  it->second.channel = std::make_unique<Channel>(
      messenger, "studio.stemik/window",
      &flutter::StandardMethodCodec::GetInstance());
  it->second.channel->SetMethodCallHandler(
      [this, key](const flutter::MethodCall<EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleWindow(key, call, std::move(result));
      });
}

void StemikWindows::HandleWindow(
    const std::string& key, const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = entries_.find(key);
  if (it == entries_.end() || !it->second.window) {
    result->Success();
    return;
  }
  HWND window = it->second.window->GetHandle();
  const std::string& method = call.method_name();
  if (method == "toMain") {
    if (main_channel_) {
      EncodableMap payload{
          {EncodableValue(std::string("key")), EncodableValue(key)},
          {EncodableValue(std::string("message")),
           call.arguments() == nullptr ? EncodableValue() : *call.arguments()},
      };
      main_channel_->InvokeMethod(
          "message", std::make_unique<EncodableValue>(std::move(payload)));
    }
    result->Success();
  } else if (method == "setTitle") {
    const auto* title = std::get_if<std::string>(call.arguments());
    if (title != nullptr && window != nullptr) {
      ::SetWindowText(window, Utf16FromUtf8(*title).c_str());
    }
    result->Success();
  } else if (method == "close") {
    if (window != nullptr) {
      ::PostMessage(window, WM_CLOSE, 0, 0);
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void StemikWindows::AskToFinish(const std::string& key) {
  auto it = entries_.find(key);
  if (it == entries_.end() || !it->second.channel) {
    if (it != entries_.end() && it->second.window) {
      it->second.window->FinishClosing();
    }
    return;
  }
  auto finish = [this, key]() {
    auto found = entries_.find(key);
    if (found != entries_.end() && found->second.window) {
      found->second.window->FinishClosing();
    }
  };
  it->second.channel->InvokeMethod(
      "willClose", nullptr,
      std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
          [finish](const EncodableValue*) { finish(); },
          [finish](const std::string&, const std::string&,
                   const EncodableValue*) { finish(); },
          [finish]() { finish(); }));
}

void StemikWindows::WindowDestroyed(const std::string& key) {
  auto it = entries_.find(key);
  if (it == entries_.end()) {
    return;
  }
  if (it->second.channel) {
    it->second.channel->SetMethodCallHandler(nullptr);
    it->second.channel = nullptr;
  }
  // Freed later: this runs inside the window's own message handling.
  if (it->second.window) {
    closed_.push_back(std::move(it->second.window));
  }
  entries_.erase(it);

  if (main_channel_) {
    main_channel_->InvokeMethod("closed",
                                std::make_unique<EncodableValue>(key));
  }
  if (main_ != nullptr && main_->GetHandle() != nullptr) {
    ::PostMessage(main_->GetHandle(), kCleanUpMessage, 0, 0);
    if (main_closing_ && entries_.empty()) {
      main_->FinishClosing();
    }
  }
}

void StemikWindows::CleanUp() {
  closed_.clear();
}
