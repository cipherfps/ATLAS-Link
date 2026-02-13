# ATLAS Link Launcher

ATLAS Link is now a Flutter-first desktop launcher.

## Modules

- `Play`: import versions, select builds, launch/stop Fortnite client
- `Host`: server metadata, host launch/stop, copy share link/public IP
- `Browser`: connect to Reboot server browser, search entries, join/copy target IP
- `Backend`: backend config, start/stop/test, runtime logs
- `Info`: quick links for Discord/issues/docs
- `Settings`: profile, visuals, and launcher behavior

## Requirements

- Flutter SDK on PATH (`flutter.bat`)
- Windows desktop support enabled (`flutter config --enable-windows-desktop`)

## Run

```bat
launch-atlas-link.cmd
launch-atlas-link.cmd run
```

Manual equivalent:

```bat
cd atlas_link_flutter
flutter run -d windows
```

## Build

```bat
launch-atlas-link.cmd build
```

Manual equivalent:

```bat
cd atlas_link_flutter
flutter build windows
```

## Build Installer (Windows EXE)

ATLAS Link installer uses **Inno Setup** (same style as Reboot's installer flow).

Requirements:
- Flutter SDK on PATH
- Inno Setup 6 (`ISCC.exe`) on PATH or installed in default location

Command:

```powershell
.\installer\build-installer.ps1
```

Useful flags:
- `-SkipFlutterBuild` to package the current release output without rebuilding
- `-SkipInnoCompile` to only prepare/stage release output

Output:
- `dist\ATLAS Link Setup-<version>.exe`

## Analyze

```bat
launch-atlas-link.cmd analyze
```

## Notes

- Flutter source lives in `atlas_link_flutter`.
- Settings and logs are stored under `%APPDATA%\ATLAS Link`.
