# ATLAS Link Launcher

An Enhanced OGFN Launcher designed for ease-of-use

## Modules

- `Library`: import versions, select builds, launch/stop Fortnite client
- `Launching`: client launch/stop, host launch/stop
- `Backend`: backend config
- `Settings`: profile, apperance, and internal files

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

ATLAS Link installer uses **Inno Setup**

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
