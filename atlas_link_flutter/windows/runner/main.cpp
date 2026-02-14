#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>
#include <cmath>

#include "flutter_window.h"
#include "utils.h"

namespace {

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
  POINT cursor_position{};
  HMONITOR monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  if (GetCursorPos(&cursor_position)) {
    monitor = MonitorFromPoint(cursor_position, MONITOR_DEFAULTTONEAREST);
  }

  // Always use a consistent launch size. We intentionally do not persist
  // window bounds so updates don't inherit stale/corrupt cached sizes.
  Win32Window::Size size(1350, 800);
  size = FitSizeToWorkArea(monitor, size);
  Win32Window::Point origin = CenteredOrigin(monitor, size);

  if (!window.Create(L"ATLAS Link", origin, size, monitor)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
