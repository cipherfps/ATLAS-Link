#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>
#include <cmath>

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

double GetScaleFactorForMonitor(HMONITOR monitor) {
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi == 0) {
    return 1.0;
  }
  return dpi / 96.0;
}

bool GetWorkAreaForMonitor(HMONITOR monitor, RECT* work_area) {
  if (work_area == nullptr) {
    return false;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return false;
  }

  *work_area = monitor_info.rcWork;
  return true;
}

int PhysicalToLogical(LONG physical, double scale_factor) {
  if (scale_factor <= 0.0) {
    return static_cast<int>(physical);
  }
  return static_cast<int>(std::lround(physical / scale_factor));
}

unsigned int PhysicalToLogicalUnsigned(LONG physical, double scale_factor) {
  if (scale_factor <= 0.0) {
    return static_cast<unsigned int>(std::max<LONG>(1, physical));
  }
  const auto logical =
      static_cast<long>(std::lround(static_cast<double>(physical) / scale_factor));
  return static_cast<unsigned int>(std::max<long>(1, logical));
}

void ClampPhysicalBoundsToWorkArea(const RECT& work_area,
                                  SavedWindowBounds* bounds) {
  if (bounds == nullptr) {
    return;
  }

  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) {
    return;
  }

  bounds->width = std::max<LONG>(1, bounds->width);
  bounds->height = std::max<LONG>(1, bounds->height);

  if (bounds->width > work_width) {
    bounds->width = work_width;
  }
  if (bounds->height > work_height) {
    bounds->height = work_height;
  }

  if (bounds->x < work_area.left) {
    bounds->x = work_area.left;
  }
  if (bounds->y < work_area.top) {
    bounds->y = work_area.top;
  }

  if (bounds->x + bounds->width > work_area.right) {
    bounds->x = work_area.right - bounds->width;
  }
  if (bounds->y + bounds->height > work_area.bottom) {
    bounds->y = work_area.bottom - bounds->height;
  }
}

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

Win32Window::Size FitSizeToWorkArea(HMONITOR monitor,
                                    const Win32Window::Size& requested) {
  RECT work_area{};
  if (!GetWorkAreaForMonitor(monitor, &work_area)) {
    return requested;
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const double available_width =
      (work_area.right - work_area.left) / scale_factor;
  const double available_height =
      (work_area.bottom - work_area.top) / scale_factor;

  // Keep a small margin so the window doesn't exactly hug the work area.
  constexpr double kPadding = 32.0;
  const double max_width = std::max(1.0, std::floor(available_width - kPadding));
  const double max_height = std::max(1.0, std::floor(available_height - kPadding));

  unsigned int width =
      static_cast<unsigned int>(std::min<double>(requested.width, max_width));
  unsigned int height =
      static_cast<unsigned int>(std::min<double>(requested.height, max_height));

  if (width < 640 && max_width >= 640) {
    width = 640;
  }
  if (height < 480 && max_height >= 480) {
    height = 480;
  }

  return Win32Window::Size(width, height);
}

Win32Window::Point CenteredOrigin(HMONITOR monitor,
                                  const Win32Window::Size& logical_size) {
  RECT work_area{};
  if (!GetWorkAreaForMonitor(monitor, &work_area)) {
    return Win32Window::Point(50, 50);
  }

  const double scale_factor = GetScaleFactorForMonitor(monitor);
  const double work_left = work_area.left / scale_factor;
  const double work_top = work_area.top / scale_factor;
  const double work_width =
      (work_area.right - work_area.left) / scale_factor;
  const double work_height =
      (work_area.bottom - work_area.top) / scale_factor;

  const double centered_x =
      work_left + (work_width - logical_size.width) / 2.0;
  const double centered_y =
      work_top + (work_height - logical_size.height) / 2.0;

  return Win32Window::Point(
      static_cast<int>(std::lround(centered_x)),
      static_cast<int>(std::lround(centered_y)));
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
  HMONITOR monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  Win32Window::Size size(1250, 1080);
  Win32Window::Point origin(50, 50);
  SavedWindowBounds restored_bounds{};
  if (LoadWindowBounds(&restored_bounds)) {
    POINT restore_point{restored_bounds.x, restored_bounds.y};
    monitor = MonitorFromPoint(restore_point, MONITOR_DEFAULTTONEAREST);

    RECT work_area{};
    if (GetWorkAreaForMonitor(monitor, &work_area)) {
      ClampPhysicalBoundsToWorkArea(work_area, &restored_bounds);
    }

    const double scale_factor = GetScaleFactorForMonitor(monitor);
    origin =
        Win32Window::Point(PhysicalToLogical(restored_bounds.x, scale_factor),
                           PhysicalToLogical(restored_bounds.y, scale_factor));
    size = Win32Window::Size(
        PhysicalToLogicalUnsigned(restored_bounds.width, scale_factor),
        PhysicalToLogicalUnsigned(restored_bounds.height, scale_factor));
  } else {
    size = FitSizeToWorkArea(monitor, size);
    origin = CenteredOrigin(monitor, size);
  }

  if (!window.Create(L"ATLAS Link", origin, size, monitor)) {
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
