<p align="center">
  <img width="1920" height="1080" alt="ATLAS Banner" src="https://github.com/user-attachments/assets/23883b15-d35d-427b-93ac-d50e3aa2ea72" />
</p>

# ATLAS Link

ATLAS Link is an enhanced OGFN launcher built around a clean desktop experience and quality-of-life features for running and organizing Fortnite builds.

## Credits

- [Auties00](https://github.com/Auties00) - ATLAS Link is a fork of [Reboot Launcher](https://github.com/Auties00/Reboot-Launcher).
- [Lawin0129](https://github.com/Lawin0129) - LawinServer that is packaged with ATLAS as an embedded backend.
- [HybridFNBR](https://github.com/HybridFNBR) - NeoNiteV2 that is also packaged with ATLAS as an embedded backend.

## Features

### Build Library

- Import existing Fortnite installations into a clean library.
- Import multiple builds from one parent folder.
- Edit build names and root folders after importing.
- Open imported build folders directly from the launcher.
- Favorite builds with a star button.
- Filter and sort the library by highest version, lowest version, or favorites only.
- Search imported builds by name.

### Build Archives

- Dedicated Build Archives menu from the Library download button.
- Quick links for FortForge, Carbon, and Helix which are well known Fortnite version archives.

### Launching

- Launch selected builds from the Library.
- Easy to host game servers with many launch options.
- Automatic restart support for hosted game server sessions.
- Optional cleanup for `GFSDK_Aftermath_Lib.dll`.
- Built-in multi-client launching.

### Injector

- Injector menu for running Fortnite processes.
- Add one or multiple DLLs to your injector library.
- Search saved DLLs by name.
- Select multiple DLLs before injecting.
- Bundled DLL support for included patcher tools.

### Mods

- Dedicated Mods tab for browsing an online mod catalog.
- Separate Pak and DLL mod categories.
- Mod cards with image and video previews, descriptions, and versions.
- One-click install and uninstall.
- Version compatibility tags support a single version, a list (`10.00, 10.40` for those exact versions), or a range (`10.00-10.40` for those and everything between).
- When a mod fits more than one of your imported builds, choose which builds to install it to, and which to remove it from when uninstalling.
- Filter by all or installed mods.
- Search mods by name.
- Installed mods are tracked and detected automatically.
- Update notifications when a newer release of an installed mod is published: a badge on the Mods nav item and a `!` marker on the affected mod, with a one-click Update that re-syncs its files (handling renamed, replaced, and newly added files) across every build it is installed to.
- Optional "Update Files on Launch" keeps installed Paks and library DLLs (and bundled default DLLs) up to date automatically; turn it off to update manually.

### Backend

- Embedded optional backend support for LawinServer and Neonite.
- Backend install and launch helpers.
- Backend status, quick tips, and connection controls.
- Saved backend lists.

### Stats

- Track total ATLAS playtime.
- Track playtime per imported build.
- Search tracked builds.
- Sort by highest or lowest tracked time.
- Favorites-only stats filter.
- Clear tracked time with a confirmation dialog.

### Settings And Quality Of Life

- Profile name and avatar customization.
- Startup animation toggle in the Startup settings tab.
- Discord Rich Presence support.
- Default DLL preset management.
- Update Files on Launch toggle to auto-refresh bundled default DLLs, installed Paks, and library DLLs when the launcher opens.
- Update notes and launcher update checks.
- Data management tools for logs, internal files, and launcher reset.

## Project Layout

```text
ATLAS-Link/
+-- atlas_link_flutter/          Flutter desktop app
|   +-- lib/main.dart             Main launcher UI and app logic
|   +-- assets/backend/           Embedded backend assets
|   +-- assets/dlls/              Bundled DLL assets
|   +-- tool/                     Build helper tools
|   +-- test/                     Flutter tests
+-- discord_rpc_proxy/           Discord RPC proxy build output/source
+-- installer/                   Inno Setup installer script
+-- build-installer.cmd          Full setup builder
+-- launch-atlas-link.cmd        Run/build/analyze helper
+-- update-notes.md              Release notes copied into builds
```

## Developer Setup

### Requirements

- Windows 10 or newer.
- [Flutter](https://flutter.dev/) with Windows desktop support enabled.
- Dart, included with Flutter.
- Visual Studio 2022 or Build Tools with the **Desktop development with C++** workload.
- PowerShell.
- Inno Setup 6 if you want to build the installer.

### Clone And Install

```powershell
git clone https://github.com/cipherfps/ATLAS-Link.git
cd ATLAS-Link
cd atlas_link_flutter
flutter pub get
```

### Run The App

From the repository root:

```powershell
.\launch-atlas-link.cmd
```

Or from the Flutter project folder:

```powershell
cd atlas_link_flutter
flutter run -d windows
```

### Analyze And Test

```powershell
.\launch-atlas-link.cmd analyze

cd atlas_link_flutter
flutter test
```

### Build A Windows Release

```powershell
.\launch-atlas-link.cmd build
```

This builds the Flutter Windows release, compiles embedded backend wrappers, and copies `update-notes.md` plus backend assets into the release output.

The build command also rebuilds the bundled Discord RPC proxy DLL and copies it
to `atlas_link_flutter/assets/dlls/discord-rpc.dll`.

### Build The Setup Installer

```powershell
.\build-installer.cmd
```

The installer script:

- Resolves the app version from `atlas_link_flutter/pubspec.yaml`.
- Rebuilds the bundled Discord RPC proxy DLL.
- Builds embedded backend executables.
- Runs `flutter clean`.
- Builds the Windows release.
- Stages release files and assets.
- Bundles the VC++ redistributable.
- Compiles `dist/ATLAS Link Setup-<version>.exe` with Inno Setup.

### Versioning

Update both of these when preparing a launcher release:

- `atlas_link_flutter/pubspec.yaml`
- `_launcherVersion` and `_launcherBuildLabel` in `atlas_link_flutter/lib/main.dart`

Then rebuild the setup installer.

## Notes

ATLAS Link is intended for OGFN launcher workflows and local build management. Keep any third-party build archives, backend projects, and DLL tools credited and distributed according to their own terms.

## License

ATLAS Link uses a custom attribution license. You can use, modify, and distribute the project, but public forks, releases, installers, and rebrands must keep visible credit to ATLAS Link and its contributors. See [LICENSE](LICENSE) for the full terms.

Third-party projects and inherited code remain under their own licenses and copyright holders.
