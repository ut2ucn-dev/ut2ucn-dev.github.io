#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>
// After windows.h.
#include <shobjidl.h>

#include <algorithm>

#include "flutter_window.h"
#include "stemik_windows.h"
#include "utils.h"

namespace {

constexpr const wchar_t kTitle[] = L"Stemik Admin";

// The window's class (win32_window.cpp): how a second launch finds the app.
constexpr const wchar_t kWindowClassName[] = L"STEMIK_ADMIN_WINDOW";

// Room for the sidebar, a list and a card side by side.
constexpr unsigned int kWidth = 1360;
constexpr unsigned int kHeight = 860;

// One app at a time: a second launch brings the running one to the front.
bool ActivateRunningApp() {
  HWND running = ::FindWindow(kWindowClassName, kTitle);
  if (running == nullptr) {
    return false;
  }
  if (::IsIconic(running)) {
    ::ShowWindow(running, SW_RESTORE);
  }
  ::SetForegroundWindow(running);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance =
      ::CreateMutex(nullptr, FALSE, L"StemikStudio.StemikAdmin.SingleInstance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningApp();
    if (single_instance != nullptr) {
      ::CloseHandle(single_instance);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // The same app id as the Start menu shortcut (installer/stemik_admin.iss)
  // and the notifications (lib/services/reminders.dart): one taskbar
  // button, and notifications under the app's name.
  ::SetCurrentProcessExplicitAppUserModelID(L"StemikStudio.StemikAdmin");

  // No command-line arguments for Dart: ["window", <spec>] is how an extra
  // window's engine starts (stemik_windows.cpp), never the app itself.
  flutter::DartProject project(L"data");

  // Centred on the main screen the first time; afterwards where it was.
  RECT work{};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0);
  const POINT top_left = {work.left, work.top};
  const double scale =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromPoint(top_left, MONITOR_DEFAULTTOPRIMARY)) /
      96.0;
  const unsigned int available_width =
      static_cast<unsigned int>((work.right - work.left) / scale);
  const unsigned int available_height =
      static_cast<unsigned int>((work.bottom - work.top) / scale);
  const unsigned int width = std::min(kWidth, available_width);
  const unsigned int height = std::min(kHeight, available_height);
  const Win32Window::Point origin(
      static_cast<unsigned int>(std::max(0.0, work.left / scale)) +
          (available_width - width) / 2,
      static_cast<unsigned int>(std::max(0.0, work.top / scale)) +
          (available_height - height) / 2);

  FlutterWindow window(project);
  if (!window.Create(kTitle, origin, Win32Window::Size(width, height))) {
    return EXIT_FAILURE;
  }
  int restored_show_command = SW_SHOWNORMAL;
  if (RestoreWindowPlacement(window.GetHandle(), &restored_show_command)) {
    window.SetShowCommand(restored_show_command);
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  StemikWindows::Get().CleanUp();
  ::CoUninitialize();
  ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
