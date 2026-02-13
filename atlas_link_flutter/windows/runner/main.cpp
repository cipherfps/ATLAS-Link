#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kWindowBoundsRegKey[] =
    L"Software\\ATLAS-Link\\ATLAS-Link-Flutter";
constexpr wchar_t kWindowBoundsRegValue[] = L"WindowBounds";

struct SavedWindowBounds {
  LONG x;
  LONG y;
  LONG width;
  LONG height;
};

bool LoadWindowBounds(SavedWindowBounds* bounds) {
  if (bounds == nullptr) {
    return false;
  }

  SavedWindowBounds loaded{};
  DWORD loaded_size = sizeof(loaded);
  const LSTATUS status =
      RegGetValueW(HKEY_CURRENT_USER, kWindowBoundsRegKey, kWindowBoundsRegValue,
                   RRF_RT_REG_BINARY, nullptr, &loaded, &loaded_size);
  if (status != ERROR_SUCCESS || loaded_size != sizeof(loaded)) {
    return false;
  }
  if (loaded.width < 640 || loaded.height < 480) {
    return false;
  }

  *bounds = loaded;
  return true;
}

void SaveWindowBounds(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);

  RECT normal_rect{};
  if (GetWindowPlacement(hwnd, &placement)) {
    normal_rect = placement.rcNormalPosition;
  } else if (!GetWindowRect(hwnd, &normal_rect)) {
    return;
  }

  SavedWindowBounds bounds{
      normal_rect.left,
      normal_rect.top,
      normal_rect.right - normal_rect.left,
      normal_rect.bottom - normal_rect.top,
  };
  if (bounds.width < 100 || bounds.height < 100) {
    return;
  }

  HKEY key = nullptr;
  const LSTATUS open_status = RegCreateKeyExW(
      HKEY_CURRENT_USER, kWindowBoundsRegKey, 0, nullptr, 0, KEY_SET_VALUE,
      nullptr, &key, nullptr);
  if (open_status != ERROR_SUCCESS || key == nullptr) {
    return;
  }

  RegSetValueExW(key, kWindowBoundsRegValue, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&bounds), sizeof(bounds));
  RegCloseKey(key);
}

Win32Window::Point CenteredOrigin(const Win32Window::Size& size) {
  HMONITOR primary_monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(primary_monitor, &monitor_info)) {
    return Win32Window::Point(50, 50);
  }
  const RECT work_area = monitor_info.rcWork;

  const LONG available_width = work_area.right - work_area.left;
  const LONG available_height = work_area.bottom - work_area.top;

  LONG centered_x =
      work_area.left + (available_width - static_cast<LONG>(size.width)) / 2;
  LONG centered_y =
      work_area.top + (available_height - static_cast<LONG>(size.height)) / 2;
  return Win32Window::Point(centered_x, centered_y);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(1250, 1080);
  Win32Window::Point origin = CenteredOrigin(size);
  SavedWindowBounds restored_bounds{};
  if (LoadWindowBounds(&restored_bounds)) {
    origin = Win32Window::Point(restored_bounds.x, restored_bounds.y);
    size = Win32Window::Size(static_cast<unsigned int>(restored_bounds.width),
                             static_cast<unsigned int>(restored_bounds.height));
  }

  if (!window.Create(L"ATLAS Link", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  bool bounds_saved = false;
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    if (!bounds_saved && msg.message == WM_CLOSE &&
        msg.hwnd == window.GetHandle()) {
      SaveWindowBounds(window.GetHandle());
      bounds_saved = true;
    }
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (!bounds_saved) {
    SaveWindowBounds(window.GetHandle());
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
