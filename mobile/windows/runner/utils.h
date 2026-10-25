#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <windows.h>

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// The main window's size, place and maximized state are kept between
// launches (in the registry, HKCU\Software\StemikStudio\StemikAdmin).
void SaveWindowPlacement(HWND window);

// Puts a window (still hidden) where it was; |show_command| then says how
// to show it. False when nothing usable was saved.
bool RestoreWindowPlacement(HWND window, int* show_command);

// Takes a UTF-8 std::string and returns it as UTF-16. Returns an empty
// std::wstring on failure.
std::wstring Utf16FromUtf8(const std::string& utf8_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
