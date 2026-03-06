import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:win32/win32.dart';

import 'launcher_discord_rpc.dart';

const _fallbackAcrylicColorDark = Color(0x260A0E14);
const _fallbackAcrylicColorLight = Color(0x36F2F6FF);

RandomAccessFile? _singleInstanceLockHandle;

Future<void> _releaseSingleInstanceLock() async {
  final handle = _singleInstanceLockHandle;
  if (handle == null) return;
  _singleInstanceLockHandle = null;
  try {
    await handle.unlock();
  } catch (_) {
    // Ignore if lock was already released.
  }
  try {
    await handle.close();
  } catch (_) {
    // Ignore close failures during shutdown.
  }
}

void _registerSingleInstanceReleaseHooks() {
  Future<void> onSignal(_) async {
    await _releaseSingleInstanceLock();
    exit(0);
  }

  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ]) {
    try {
      signal.watch().listen((event) {
        unawaited(onSignal(event));
      });
    } catch (_) {
      // Some environments/signals may not be supported.
    }
  }
}

Future<bool> _acquireSingleInstanceLock() async {
  try {
    final appData = Platform.environment['APPDATA']?.trim();
    final lockRoot = appData != null && appData.isNotEmpty
        ? Directory('$appData\\ATLAS Link')
        : Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}ATLAS Link',
          );

    if (!lockRoot.existsSync()) {
      await lockRoot.create(recursive: true);
    }

    final lockFile = File(
      '${lockRoot.path}${Platform.pathSeparator}atlas_link.lock',
    );
    if (!lockFile.existsSync()) {
      await lockFile.create(recursive: true);
    }

    final handle = await lockFile.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    _singleInstanceLockHandle = handle;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lockAcquired = await _acquireSingleInstanceLock();
  if (!lockAcquired) {
    exit(0);
  }
  _registerSingleInstanceReleaseHooks();
  if (Platform.isWindows) {
    try {
      await Window.initialize();
      await Window.setEffect(
        effect: WindowEffect.acrylic,
        color: _fallbackAcrylicColorDark,
      );
      await Window.makeTitlebarTransparent();
      await Window.enableFullSizeContentView();
    } catch (_) {
      // Ignore unsupported configurations and continue with native fallback.
    }
  }
  runApp(const AtlasLauncherApp());
}

class AtlasLauncherApp extends StatefulWidget {
  const AtlasLauncherApp({super.key});

  @override
  State<AtlasLauncherApp> createState() => _AtlasLauncherAppState();
}

class _AtlasLauncherAppState extends State<AtlasLauncherApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  Future<void> _applyWindowThemeEffect(ThemeMode mode) async {
    if (!Platform.isWindows) return;
    final color = mode == ThemeMode.dark
        ? _fallbackAcrylicColorDark
        : _fallbackAcrylicColorLight;
    try {
      await Window.setEffect(effect: WindowEffect.acrylic, color: color);
    } catch (_) {
      // Ignore unsupported configurations and continue with native fallback.
    }
  }

  void _setDarkMode(bool enabled) {
    final nextMode = enabled ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == nextMode) return;
    setState(() => _themeMode = nextMode);
    unawaited(_applyWindowThemeEffect(nextMode));
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2A9DF4);
    const accentBlue = Color(0xFF1E88E5);

    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xFF0A0E14),
      colorScheme: const ColorScheme.dark(
        primary: seed,
        secondary: accentBlue,
        surface: Color(0xFF101722),
        onSurface: Color(0xFFE9F1FF),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentBlue,
        inactiveTrackColor: accentBlue.withValues(alpha: 0.25),
        thumbColor: accentBlue,
        overlayColor: accentBlue.withValues(alpha: 0.25),
        valueIndicatorColor: accentBlue,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.white54;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentBlue.withValues(alpha: 0.55);
          }
          return Colors.white24;
        }),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentBlue),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: const Color(0xFFF2F4F7),
      colorScheme: const ColorScheme.light(
        primary: seed,
        secondary: accentBlue,
        surface: Color(0xFFF7F9FC),
        onSurface: Color(0xFF121724),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentBlue,
        inactiveTrackColor: accentBlue.withValues(alpha: 0.2),
        thumbColor: accentBlue,
        overlayColor: accentBlue.withValues(alpha: 0.2),
        valueIndicatorColor: accentBlue,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentBlue.withValues(alpha: 0.55);
          }
          return Colors.black.withValues(alpha: 0.2);
        }),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentBlue),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    return MaterialApp(
      title: 'ATLAS Link',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AtlasScrollBehavior(),
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: LauncherScreen(onDarkModeChanged: _setDarkMode),
    );
  }
}

class _AtlasScrollBehavior extends MaterialScrollBehavior {
  const _AtlasScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _SmoothScrollPhysics(
      parent: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class _SmoothScrollPhysics extends ScrollPhysics {
  const _SmoothScrollPhysics({super.parent, this.multiplier = 0.35});

  final double multiplier;

  @override
  _SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SmoothScrollPhysics(
      parent: buildParent(ancestor),
      multiplier: multiplier,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * multiplier);
  }
}

enum LauncherTab { home, library, backend, general }

enum SettingsSection { profile, appearance, dataManagement, support }

enum GameServerInjectType { custom }

enum _GameActionState { idle, launching, closing }

enum _GameServerPromptAction { ignore, start }

enum BackendConnectionType { local, remote }

extension _BackendConnectionTypeLabel on BackendConnectionType {
  String get label => this == BackendConnectionType.local ? 'Local' : 'Remote';
}

class _FortniteProcessState {
  _FortniteProcessState({
    required this.pid,
    required this.host,
    required this.versionId,
    required this.gameVersion,
    required this.clientName,
    this.launcherPid,
    this.eacPid,
    this.child,
  });

  final int pid;
  final bool host;
  final String versionId;
  final String gameVersion;
  final String clientName;
  final int? launcherPid;
  final int? eacPid;
  final _FortniteProcessState? child;

  bool launched = false;
  bool tokenError = false;
  bool corrupted = false;
  bool killed = false;
  bool exited = false;
  bool postLoginInjected = false;
  bool postLoginInferredFromFallback = false;
  bool largePakInjected = false;
  bool gameServerInjected = false;
  bool hostPostLoginPatchersInjected = false;
  bool gameServerInjectionScheduled = false;

  void killAuxiliary() {
    final launcher = launcherPid;
    final eac = eacPid;
    if (launcher != null) _killPidSafe(launcher);
    if (eac != null) _killPidSafe(eac);
  }

  void kill({bool includeChild = true}) {
    if (killed) return;
    killed = true;
    launched = true;
    exited = true;
    if (includeChild) {
      child?.killAll();
    }
    _killPidSafe(pid);
    killAuxiliary();
  }

  void killAll() {
    kill(includeChild: true);
  }

  static void _killPidSafe(int pid) {
    try {
      Process.killPid(pid, ProcessSignal.sigabrt);
    } catch (_) {
      // Ignore failures (process might already be dead / access denied).
    }
  }
}

enum _UiStatusSeverity { info, success, warning, error }

class _UiStatus {
  const _UiStatus(this.message, this.severity);

  final String message;
  final _UiStatusSeverity severity;
}

class _InjectionAttempt {
  const _InjectionAttempt({
    required this.name,
    required this.required,
    required this.attempted,
    required this.success,
    this.error,
    this.skippedReason,
  });

  final String name;
  final bool required;
  final bool attempted;
  final bool success;
  final String? error;
  final String? skippedReason;
}

class _InjectionReport {
  const _InjectionReport(this.attempts);

  final List<_InjectionAttempt> attempts;

  _InjectionAttempt? get firstRequiredFailure {
    for (final attempt in attempts) {
      if (!attempt.required) continue;
      if (attempt.error != null) return attempt;
      if (attempt.attempted && !attempt.success) return attempt;
    }
    return null;
  }

  _InjectionAttempt? get firstOptionalFailure {
    for (final attempt in attempts) {
      if (attempt.required) continue;
      if (attempt.error != null) return attempt;
      if (attempt.attempted && !attempt.success) return attempt;
    }
    return null;
  }

  _InjectionAttempt? get firstFailure =>
      firstRequiredFailure ?? firstOptionalFailure;

  bool get hasRequiredFailure => firstRequiredFailure != null;

  bool get hasFailure => firstFailure != null;
}

class _ProfileSetupResult {
  const _ProfileSetupResult({
    required this.username,
    required this.profileAvatarPath,
    required this.useEmailPasswordAuth,
    required this.authEmail,
    required this.authPassword,
  });

  final String username;
  final String profileAvatarPath;
  final bool useEmailPasswordAuth;
  final String authEmail;
  final String authPassword;
}

class _LaunchAuthCredentials {
  const _LaunchAuthCredentials({required this.login, required this.password});

  final String login;
  final String password;
}

class _LaunchSessionTokens {
  const _LaunchSessionTokens({this.fltoken, this.caldera});

  final String? fltoken;
  final String? caldera;

  bool get hasAny => fltoken != null || caldera != null;

  bool get hasBoth => fltoken != null && caldera != null;
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key, required this.onDarkModeChanged});

  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen>
    with TickerProviderStateMixin {
  static const String _launcherVersion = '1.1.3';
  static const String _launcherBuildLabel = 'Stable 1.1.3';
  static const String _shippingExeName = 'FortniteClient-Win64-Shipping.exe';
  static const String _launcherExeName = 'FortniteLauncher.exe';
  static const String _eacExeName = 'FortniteClient-Win64-Shipping_EAC.exe';
  static const String _defaultBackendHost = '127.0.0.1';
  static const int _defaultBackendPort = 3551;
  static const int _defaultGameServerPort = 7777;
  static const int _authInjectionInitialDelayMs = 0;
  static const int _authInjectionRetryDelayMs = 100;
  static const int _authInjectionMaxRetryDelayMs = 800;
  static const int _authInjectionMaxAttempts = 3;
  // Optimized for low-end PCs: increased from 20s to 40s timeout to account for
  // slow disk I/O, AV scanning, and heavy system contention. This significantly
  // reduces "Injection timed out" failures on low-end hardware.
  static const int _dllInjectionWaitMs = 40000;
  static const int _gameServerInjectionRetryDelayMs = 100;
  static const int _gameServerInjectionMaxRetryDelayMs = 800;
  static const int _gameServerInjectionMaxAttempts = 3;
  static const String _legacyLaunchFltoken = '3db3ba5dcbd2e16703f3978d';
  static const String _legacyLaunchCalderaToken =
      'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2NvdW50X2lkIjoiYmU5ZGE1YzJmYmVhNDQwN2IyZjQwZWJhYWQ4NTlhZDQiLCJnZW5lcmF0ZWQiOjE2Mzg3MTcyNzgsImNhbGRlcmFHdWlkIjoiMzgxMGI4NjMtMmE2NS00NDU3LTliNTgtNGRhYjNiNDgyYTg2IiwiYWNQcm92aWRlciI6IkVhc3lBbnRpQ2hlYXQiLCJub3RlcyI6IiIsImZhbGxiYWNrIjpmYWxzZX0.VAWQB67RTxhiWOxx7DBjnzDnXyyEnX7OljJm-j2d88G_WgwQ9wrE6lwMEHZHjBd1ISJdUO1UVUqkfLdU5nofBQ';
  static const Duration _maxLaunchTokenAge = Duration(days: 30);
  static const Duration _maxLaunchTokenClockSkew = Duration(minutes: 10);
  // Reduced post-login delay for faster injection start on low-end PCs
  static const int _postLoginInjectionDelayMs = 300;
  // Reduced UI status delay for snappier feedback
  static const int _uiStatusDelayMs = 20;
  static const String _aftermathDllName = 'GFSDK_Aftermath_Lib.dll';
  static const String _discordRpcDllName = 'discord-rpc.dll';
  static const String _discordRpcOriginalDllName = 'discord-rpc-original.dll';
  static const String _discordRpcBundledAssetPath =
      'assets/dlls/discord-rpc.dll';
  static const List<String> _discordRpcTargetRelativeDirectory = <String>[
    'FortniteGame',
    'Binaries',
    'ThirdParty',
    'Discord',
    'Win64',
  ];
  static const String _atlasLinkRepository =
      'https://github.com/cipherfps/ATLAS-Link';
  static const String _atlasLinkReleasesPage =
      'https://github.com/cipherfps/ATLAS-Link/releases';
  static const String _atlasLinkDiscordInvite = 'https://discord.gg/GqgakxU6bm';
  static const String _launcherDiscordApplicationId = '1465348345122914335';
  static const String _launcherDiscordLargeImageKey = 'atlas-icon';
  static const String _launcherDiscordLargeImageText =
      '@cipherfps (v$_launcherVersion)';
  static const String _launcherDiscordButtonLabel = 'Discord';
  static const String _launcherDownloadButtonLabel = 'Download';
  static const String _atlasLinkBundledDllContentsApi =
      'https://api.github.com/repos/cipherfps/ATLAS-Link/contents/atlas_link_flutter/assets/dlls?ref=main';
  static const String _atlasLinkBundledDllFallbackBaseUrl =
      'https://raw.githubusercontent.com/cipherfps/ATLAS-Link/main/atlas_link_flutter/';
  static const List<_BundledDllSpec> _bundledDllSpecs = <_BundledDllSpec>[
    _BundledDllSpec(
      assetPath: 'assets/dlls/Magnesium.dll',
      fileName: 'Magnesium.dll',
      label: 'game server',
    ),
    _BundledDllSpec(
      assetPath: 'assets/dlls/LargePakPatch.dll',
      fileName: 'LargePakPatch.dll',
      label: 'large pak patcher',
    ),
    _BundledDllSpec(
      assetPath: 'assets/dlls/memory.dll',
      fileName: 'memory.dll',
      label: 'memory patcher',
    ),
    _BundledDllSpec(
      assetPath: 'assets/dlls/Tellurium.dll',
      fileName: 'Tellurium.dll',
      label: 'authentication patcher',
    ),
    _BundledDllSpec(
      assetPath: 'assets/dlls/console.dll',
      fileName: 'console.dll',
      label: 'unreal engine patcher',
    ),
  ];
  static const String _atlasBackendLatestReleaseApi =
      'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases/latest';
  static const String _atlasBackendLatestReleasePage =
      'https://github.com/cipherfps/ATLAS-Backend/releases/latest';
  static const String _launcherDataDirName = 'ATLAS Link';
  static const String _legacyLauncherDataDirName = 'atlas-link-launcher';
  static const Duration _homeHeroRotateInterval = Duration(seconds: 7);
  static const List<_EventCardData> _homeFeaturedCards = <_EventCardData>[
    _EventCardData(
      image: 'assets/images/hero_banner.png',
      category: 'LAUNCHER',
      title: 'ATLAS Link',
      description:
          'ATLAS has released a new launcher focused on clean visuals, ease of use, and overall backend compatability!',
      buttonLabel: 'Open ATLAS Link GitHub',
      buttonUrl: _atlasLinkRepository,
    ),
    _EventCardData(
      image: 'assets/images/discord.webp',
      category: 'COMMUNITY',
      title: 'ATLAS Discord',
      description:
          'Join the ATLAS discord for more resources, news and updates!',
      buttonLabel: 'Join ATLAS Discord',
      buttonUrl: _atlasLinkDiscordInvite,
      imageFit: BoxFit.cover,
    ),
  ];
  static const String _loginContinueMarker =
      '[UOnlineAccountCommon::ContinueLoggingIn]';
  static const String _loginCompleteStepMarker = 'Login: Completing Sign-in';
  static const String _loginCompletedMarker = '(Completed)';
  static const String _loginUiStateTransitionMarker =
      'UI State changing from [UI.State.Startup.Login]';
  static const List<String> _corruptedBuildErrors = <String>[
    'Critical error',
    'when 0 bytes remain',
    'Pak chunk signature verification failed!',
    'LogWindows:Error: Fatal error!',
  ];
  static const List<String> _cannotConnectErrors = <String>[
    'port 3551 failed: Connection refused',
    'Unable to login to Fortnite servers',
    'HTTP 400 response from ',
    'Network failure when attempting to check platform restrictions',
    'UOnlineAccountCommon::ForceLogout',
  ];
  static const Set<String> _splashImageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
  };

  final _rng = Random(17);
  final ListQueue<String> _logs = ListQueue<String>();
  static const int _maxLogLines = 500;
  final StringBuffer _logWriteBuffer = StringBuffer();
  Timer? _logFlushTimer;
  Future<void> _logWriteChain = Future<void>.value();
  bool _logFileReady = false;

  OverlayEntry? _toastOverlayEntry;
  final GlobalKey<_ToastOverlayHostState> _toastHostKey =
      GlobalKey<_ToastOverlayHostState>();

  final _usernameController = TextEditingController();
  final _profileAuthEmailController = TextEditingController();
  final _profileAuthPasswordController = TextEditingController();
  final _backendDirController = TextEditingController();
  final _backendCommandController = TextEditingController();
  final _backendHostController = TextEditingController();
  final _backendPortController = TextEditingController();
  final _librarySearchController = TextEditingController();
  final _savedBackendSearchController = TextEditingController();
  final ScrollController _libraryScrollController = ScrollController();
  final _unrealEnginePatcherController = TextEditingController();
  final _authenticationPatcherController = TextEditingController();
  final _memoryPatcherController = TextEditingController();
  final _gameServerFileController = TextEditingController();
  final _largePakPatcherController = TextEditingController();

  LauncherTab _tab = LauncherTab.home;
  LauncherTab _settingsReturnTab = LauncherTab.home;
  SettingsSection _settingsSection = SettingsSection.profile;
  LauncherSettings _settings = LauncherSettings.defaults();
  int _homeHeroIndex = 0;

  List<VersionEntry>? _sortedVersionsSource;
  List<VersionEntry> _sortedVersionsCache = const <VersionEntry>[];

  String? _librarySplashPrefetchSignature;
  bool _librarySplashPrefetchQueued = false;
  bool _libraryWarmupQueued = false;
  bool _libraryWarmupCompleted = false;

  bool _showStartup = true;
  bool _startupConfigResolved = false;
  bool _backendOnline = false;
  DateTime? _lastBackendUndetectedToastAt;
  DateTime? _lastBackendCheckingToastAt;
  bool _checkingLauncherUpdate = false;
  bool _checkingBundledDllDefaultsUpdate = false;
  bool _bundledDllDefaultsUpdateAvailable = false;
  bool _updatingDefaultDlls = false;
  Set<String> _bundledDllUpdatedFileNames = <String>{};
  Map<String, _BundledDllRemoteAsset> _bundledDllRemoteAssetsByName =
      <String, _BundledDllRemoteAsset>{};
  bool _launcherUpdateDialogVisible = false;
  bool _launcherUpdateAutoCheckQueued = false;
  bool _launcherUpdateAutoChecked = false;
  bool _launcherUpdateInstallerCleanupWatcherActive = false;
  bool _atlasBackendActionBusy = false;
  _GameActionState _gameAction = _GameActionState.idle;
  bool _gameServerLaunching = false;
  // When the game server is started from the "start game server?" prompt during
  // launching, treat it as session-linked and stop it once all clients close.
  bool _stopHostingWhenNoClientsRemain = false;
  bool _stoppingSessionLinkedHosting = false;
  bool _profileSetupDialogVisible = false;
  bool _profileSetupDialogQueued = false;
  bool _showProfileAuthPassword = false;
  bool _profileAuthValidationAttempted = false;
  bool _profileAuthQuickTipManualVisible = false;
  bool _libraryImportTipFadingOut = false;
  bool _libraryQuickTipManualVisible = false;
  bool _backendQuickTipManualVisible = false;
  int _libraryQuickTipStep = 0;
  int _backendQuickTipStep = 0;
  BackendConnectionType? _backendQuickTipOriginalType;
  String? _backendQuickTipOriginalHost;
  String _versionSearchQuery = '';
  String _savedBackendSearchQuery = '';

  Process? _gameProcess;
  Process? _gameServerProcess;
  Process? _atlasBackendProcess;
  BuildContext? _atlasBackendInstallDialogContext;
  bool _atlasBackendInstallDialogVisible = false;
  bool _atlasBackendInstallCleanupWatcherActive = false;
  final ValueNotifier<_BackendInstallProgress> _atlasBackendInstallProgress =
      ValueNotifier<_BackendInstallProgress>(
        const _BackendInstallProgress(
          message: 'Preparing download...',
          progress: null,
        ),
      );
  _FortniteProcessState? _gameInstance;
  final List<_FortniteProcessState> _extraGameInstances =
      <_FortniteProcessState>[];
  _FortniteProcessState? _gameServerInstance;
  Timer? _homeHeroTimer;
  Timer? _pollTimer;
  Timer? _gameServerCrashStatusClearTimer;
  bool _runtimePollingStarted = false;
  DateTime? _runtimePollingStartedAt;
  Future<void>? _runtimeRefreshInFlight;

  _UiStatus? _gameUiStatus;
  _UiStatus? _gameServerUiStatus;

  bool _launchProgressPopupDismissed = false;
  String? _lastLaunchStatusToast;
  DateTime? _lastLaunchStatusToastAt;

  bool _gameServerPromptVisible = false;
  bool _gameServerPromptRequiredForLaunch = false;
  bool _gameServerPromptResolvedForLaunch = true;

  final Set<String> _afterMathCleanedRoots = <String>{};
  final Map<String, String> _discordRpcReplacedBuildRootsByNormalized =
      <String, String>{};
  bool _discordRpcRestoreInFlight = false;
  late final LauncherDiscordRpcClient _launcherDiscordRpc =
      LauncherDiscordRpcClient(applicationId: _launcherDiscordApplicationId);
  String? _launcherDiscordPresenceSignature;
  bool _launcherDiscordPresenceCleared = true;

  HttpServer? _backendProxyServer;
  HttpClient? _backendProxyClient;
  Uri? _backendProxyTarget;
  String? _backendProxySignature;
  Future<void>? _backendProxySyncInFlight;

  late final AnimationController _shellEntranceController;
  late final Animation<double> _shellEntranceFade;
  late final Animation<double> _shellEntranceScale;
  late final AnimationController _libraryActionsNudgeController;
  late final Animation<double> _libraryActionsNudgePulse;

  late Directory _dataDir;
  late File _settingsFile;
  late File _installStateFile;
  late File _logFile;

  LauncherInstallState _installState = LauncherInstallState.defaults();

  @override
  void initState() {
    super.initState();
    _shellEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _shellEntranceFade = CurvedAnimation(
      parent: _shellEntranceController,
      curve: const Interval(0.0, 0.92, curve: Curves.easeOutCubic),
    );
    _shellEntranceScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _shellEntranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    _libraryActionsNudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _libraryActionsNudgePulse = CurvedAnimation(
      parent: _libraryActionsNudgeController,
      curve: Curves.easeInOut,
    );

    unawaited(_bootstrap());
    _startHomeHeroAutoRotate();
  }

  @override
  void dispose() {
    _homeHeroTimer?.cancel();
    _pollTimer?.cancel();
    _gameServerCrashStatusClearTimer?.cancel();
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;
    _logFlushTimer?.cancel();
    _flushLogBuffer();
    _shellEntranceController.dispose();
    _libraryActionsNudgeController.dispose();
    _usernameController.dispose();
    _profileAuthEmailController.dispose();
    _profileAuthPasswordController.dispose();
    _backendDirController.dispose();
    _backendCommandController.dispose();
    _backendHostController.dispose();
    _backendPortController.dispose();
    _librarySearchController.dispose();
    _savedBackendSearchController.dispose();
    _libraryScrollController.dispose();
    _unrealEnginePatcherController.dispose();
    _authenticationPatcherController.dispose();
    _memoryPatcherController.dispose();
    _gameServerFileController.dispose();
    _largePakPatcherController.dispose();
    _atlasBackendInstallProgress.dispose();
    unawaited(_stopBackendProxy());
    _launcherDiscordRpc.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _initStorage();
      unawaited(_cleanupLauncherUpdateInstallerCacheOnLaunch());
      await _loadInstallState();
      await _loadSettings();
      await _reconcileInstallState();
      final priorLauncherVersion = _installState.lastSeenLauncherVersion.trim();
      final currentLauncherVersion = _launcherVersion.trim();
      var launcherUpdated =
          priorLauncherVersion.isNotEmpty &&
          currentLauncherVersion.isNotEmpty &&
          priorLauncherVersion != currentLauncherVersion;
      if (launcherUpdated) {
        await _performPostUpdateReinstallReset(
          priorVersion: priorLauncherVersion,
          currentVersion: currentLauncherVersion,
        );
        launcherUpdated = false;
      }
      if (mounted) {
        setState(() {
          _showStartup = _settings.startupAnimationEnabled;
          _startupConfigResolved = true;
        });
        if (!_showStartup) {
          _shellEntranceController.value = 1.0;
        }
      }
      _syncControllers();
      await _applyBundledDllDefaults(forceResetBundledPaths: launcherUpdated);
      await _restoreOriginalDiscordRpcDllAcrossBuildsIfIdle();
      unawaited(_checkForBundledDllDefaultUpdates(silent: true));
      if (currentLauncherVersion.isNotEmpty &&
          _installState.lastSeenLauncherVersion != currentLauncherVersion) {
        _installState = _installState.copyWith(
          lastSeenLauncherVersion: currentLauncherVersion,
        );
        try {
          await _saveInstallState();
        } catch (error) {
          _log('settings', 'Failed to save install state: $error');
        }
      }
      // Apply loaded settings (blur/background/particles) immediately so the
      // startup overlay doesn't appear to "add extra blur" before settings load.
      if (mounted) {
        widget.onDarkModeChanged(_settings.darkModeEnabled);
        setState(() {});
      }
      _log('launcher', 'ATLAS Link initialized.');

      unawaited(_cleanupAtlasBackendInstallerIfBackendDetected());
      if (!_showStartup) {
        _startRuntimeRefreshLoopIfNeeded();
      }

      _queueFirstRunProfileSetup();
      _queueLauncherAutoUpdateCheckOnLaunch();
    } catch (error) {
      debugPrint('ATLAS Link bootstrap failed: $error');
    } finally {
      if (mounted && !_startupConfigResolved) {
        setState(() {
          _showStartup = false;
          _startupConfigResolved = true;
        });
        _shellEntranceController.value = 1.0;
        _startRuntimeRefreshLoopIfNeeded();
      }
      _syncLauncherDiscordPresence();
    }
  }

  Future<void> _performPostUpdateReinstallReset({
    required String priorVersion,
    required String currentVersion,
  }) async {
    final fromVersion = priorVersion.trim();
    final toVersion = currentVersion.trim();
    if (fromVersion.isEmpty || toVersion.isEmpty) return;
    if (fromVersion == toVersion) return;

    _log(
      'settings',
      'Launcher updated ($fromVersion -> $toVersion). Performing full reinstall reset (preserving library + profile + appearance + saved backend settings).',
    );

    final preservedVersions = List<VersionEntry>.from(_settings.versions);
    var preservedSelectedVersionId = _settings.selectedVersionId;
    if (preservedSelectedVersionId.trim().isNotEmpty &&
        !preservedVersions.any(
          (entry) => entry.id == preservedSelectedVersionId,
        )) {
      preservedSelectedVersionId = preservedVersions.isNotEmpty
          ? preservedVersions.first.id
          : '';
    }
    if (preservedSelectedVersionId.trim().isEmpty &&
        preservedVersions.isNotEmpty) {
      preservedSelectedVersionId = preservedVersions.first.id;
    }

    var preservedUsername = _settings.username.trim();
    if (preservedUsername.isEmpty) preservedUsername = 'Player';
    final preservedProfileUseEmailPasswordAuth =
        _settings.profileUseEmailPasswordAuth;
    final preservedProfileAuthEmail = _settings.profileAuthEmail.trim();
    final preservedProfileAuthPassword = _settings.profileAuthPassword;
    final preservedProfileAuthQuickTipComplete =
        _settings.profileAuthQuickTipComplete;

    var preservedAvatarPath = _settings.profileAvatarPath.trim();
    if (preservedAvatarPath.isNotEmpty) {
      try {
        if (!File(preservedAvatarPath).existsSync()) {
          preservedAvatarPath = '';
        }
      } catch (_) {
        preservedAvatarPath = '';
      }
    }

    final preservedSavedBackendsByProfile = <String, List<SavedBackend>>{};
    for (final entry in _settings.savedBackendsByProfile.entries) {
      final normalizedKey = LauncherSettings.profileBackendsKey(entry.key);
      preservedSavedBackendsByProfile[normalizedKey] = List<SavedBackend>.from(
        entry.value,
      );
    }
    final preservedProfileSavedBackendsKey =
        LauncherSettings.profileBackendsKey(preservedUsername);
    final preservedSavedBackends = List<SavedBackend>.from(
      preservedSavedBackendsByProfile[preservedProfileSavedBackendsKey] ??
          _settings.savedBackends,
    );
    preservedSavedBackendsByProfile[preservedProfileSavedBackendsKey] =
        List<SavedBackend>.from(preservedSavedBackends);

    final preservedDarkModeEnabled = _settings.darkModeEnabled;
    final preservedPopupBackgroundBlurEnabled =
        _settings.popupBackgroundBlurEnabled;
    final preservedBackgroundImagePath = _settings.backgroundImagePath.trim();
    final preservedBackgroundBlur = _settings.backgroundBlur;
    final preservedBackgroundParticlesOpacity =
        _settings.backgroundParticlesOpacity;
    final preservedStartupAnimationEnabled = _settings.startupAnimationEnabled;
    final preservedLibraryActionsNudgeComplete =
        _settings.libraryActionsNudgeComplete ||
        _installState.libraryActionsNudgeComplete;
    final preservedBackendConnectionTipComplete =
        _settings.backendConnectionTipComplete ||
        _installState.backendConnectionTipComplete;

    final preservedProfileSetupComplete =
        _settings.profileSetupComplete || _installState.profileSetupComplete;

    Future<void> deleteDir(Directory dir) async {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup failures (locks, permissions, etc.).
      }
    }

    // Stop background log flushes before truncating/clearing the log file.
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    _flushLogBuffer();
    try {
      await _logWriteChain;
    } catch (_) {
      // Ignore pending log write failures.
    }

    await deleteDir(Directory(_joinPath([_dataDir.path, 'backend-installer'])));
    await deleteDir(
      Directory(_joinPath([_dataDir.path, 'launcher-installer'])),
    );
    await deleteDir(Directory(_joinPath([_dataDir.path, 'dlls'])));

    // Clear logs on update-reinstall. Keep the file itself so logging stays ready.
    try {
      if (await _logFile.exists()) {
        await _logFile.writeAsString('', flush: true);
      }
    } catch (_) {
      // Ignore log truncation failures.
    }
    _logs.clear();
    _logWriteBuffer.clear();

    final defaults = LauncherSettings.defaults();
    final nextSettings = defaults.copyWith(
      username: preservedUsername,
      profileUseEmailPasswordAuth: preservedProfileUseEmailPasswordAuth,
      profileAuthEmail: preservedProfileAuthEmail,
      profileAuthPassword: preservedProfileAuthPassword,
      profileAuthQuickTipComplete: preservedProfileAuthQuickTipComplete,
      profileAvatarPath: preservedAvatarPath,
      profileSetupComplete: preservedProfileSetupComplete,
      libraryActionsNudgeComplete: preservedLibraryActionsNudgeComplete,
      darkModeEnabled: preservedDarkModeEnabled,
      popupBackgroundBlurEnabled: preservedPopupBackgroundBlurEnabled,
      backgroundImagePath: preservedBackgroundImagePath,
      backgroundBlur: preservedBackgroundBlur,
      backgroundParticlesOpacity: preservedBackgroundParticlesOpacity,
      startupAnimationEnabled: preservedStartupAnimationEnabled,
      backendConnectionTipComplete: preservedBackendConnectionTipComplete,
      savedBackends: preservedSavedBackends,
      savedBackendsByProfile: preservedSavedBackendsByProfile,
      versions: preservedVersions,
      selectedVersionId: preservedSelectedVersionId,
    );
    final nextInstallState = LauncherInstallState.defaults().copyWith(
      profileSetupComplete: preservedProfileSetupComplete,
      libraryActionsNudgeComplete: preservedLibraryActionsNudgeComplete,
      backendConnectionTipComplete: preservedBackendConnectionTipComplete,
      lastSeenLauncherVersion: toVersion,
    );

    _settings = nextSettings;
    _installState = nextInstallState;
    _syncControllers();

    try {
      await _saveSettings(toast: false, applyControllers: false);
    } catch (error) {
      _log('settings', 'Failed to save post-update settings: $error');
    }

    try {
      await _saveInstallState();
    } catch (error) {
      _log('settings', 'Failed to save post-update install state: $error');
    }

    _log(
      'settings',
      'Post-update reinstall reset completed (library + profile + appearance + saved backend settings preserved).',
    );
  }

  void _finishStartupAnimation() {
    if (!mounted || !_showStartup) return;
    setState(() {
      _showStartup = false;
    });
    _shellEntranceController.forward(from: 0);
    _startRuntimeRefreshLoopIfNeeded();
    _queueFirstRunProfileSetup();
    _queueLauncherAutoUpdateCheckOnLaunch();
    _queueLibraryWarmup();
  }

  void _queueLibraryWarmup() {
    if (_libraryWarmupQueued || _libraryWarmupCompleted) return;
    _libraryWarmupQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryWarmupQueued = false;

      // Give the shell a moment to settle before doing any heavy work.
      Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        if (_showStartup) return;
        if (_libraryWarmupCompleted) return;

        unawaited(_runLibraryWarmupNow());
      });
    });
  }

  Future<void> _runLibraryWarmupNow() async {
    if (!mounted) return;
    if (_showStartup) return;
    if (_libraryWarmupCompleted) return;

    // Pre-sort versions so the first Library open doesn't pay the cost.
    final installed = _sortedInstalledVersions();

    final dpr = MediaQuery.of(context).devicePixelRatio;

    // Pre-cache the selected cover at its typical display size.
    try {
      final coverProvider = ResizeImage(
        _libraryCoverImage(_settings.selectedVersion),
        width: (250 * dpr).round().clamp(1, 4096),
      );
      await precacheImage(coverProvider, context);
    } catch (_) {
      // Ignore bad images.
    }

    // Pre-cache a small batch of grid covers to reduce first-scroll pop-in.
    final cacheWidth = (520 * dpr).round().clamp(1, 4096);
    final count = min(4, installed.length);
    for (var i = 0; i < count; i++) {
      if (!mounted) return;
      try {
        await precacheImage(
          ResizeImage(_libraryCoverImage(installed[i]), width: cacheWidth),
          context,
        );
      } catch (_) {
        // Ignore bad images.
      }
    }

    _libraryWarmupCompleted = true;
  }

  void _startRuntimeRefreshLoopIfNeeded() {
    if (_runtimePollingStarted) return;
    _runtimePollingStarted = true;
    _runtimePollingStartedAt = DateTime.now();

    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 320));
        if (!mounted) return;
        await _refreshRuntime();
      }),
    );

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_refreshRuntime());
    });
  }

  bool _deferNonCriticalRuntimeRefresh() {
    if (!_profileSetupDialogVisible) return false;
    final startedAt = _runtimePollingStartedAt;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) < const Duration(seconds: 14);
  }

  bool get _showOnboardingDiscordPresence {
    return _startupConfigResolved &&
        !_showStartup &&
        !_settings.profileSetupComplete;
  }

  void _queueFirstRunProfileSetup() {
    if (_settings.profileSetupComplete) return;
    if (_profileSetupDialogQueued) return;
    _profileSetupDialogQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _profileSetupDialogQueued = false;
      unawaited(
        Future<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (!mounted) return;
          await _maybeShowFirstRunProfileSetup();
        }),
      );
    });
  }

  void _queueLauncherAutoUpdateCheckOnLaunch() {
    if (_launcherUpdateAutoChecked) return;
    if (_launcherUpdateAutoCheckQueued) return;
    _launcherUpdateAutoCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launcherUpdateAutoCheckQueued = false;
      unawaited(
        Future<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (!mounted) return;
          await _maybeAutoCheckForLauncherUpdatesOnLaunch();
        }),
      );
    });
  }

  Future<void> _maybeAutoCheckForLauncherUpdatesOnLaunch() async {
    if (!mounted) return;
    if (_launcherUpdateAutoChecked) return;
    if (!_startupConfigResolved) return;
    if (_showStartup) return;
    if (_launcherUpdateDialogVisible) return;
    if (!_settings.profileSetupComplete) return;
    if (_profileSetupDialogVisible) {
      _queueLauncherAutoUpdateCheckOnLaunch();
      return;
    }

    _launcherUpdateAutoChecked = true;
    await _checkForLauncherUpdates(silent: true);
  }

  Future<void> _maybeShowFirstRunProfileSetup() async {
    if (!mounted) return;
    if (_profileSetupDialogVisible) return;
    if (_settings.profileSetupComplete) return;
    if (!_startupConfigResolved) return;
    if (_showStartup) return;

    _profileSetupDialogVisible = true;
    _syncLauncherDiscordPresence();
    try {
      final result = await _promptFirstRunProfileSetup();
      if (result == null) return;
      if (!mounted) return;

      final resolvedUsername = result.username.trim().isEmpty
          ? 'Player'
          : result.username.trim();
      setState(() {
        _setActiveSettingsUsername(resolvedUsername);
        _settings = _settings.copyWith(
          profileAvatarPath: result.profileAvatarPath.trim(),
          profileUseEmailPasswordAuth: result.useEmailPasswordAuth,
          profileAuthEmail: result.authEmail.trim(),
          profileAuthPassword: result.authPassword,
          profileSetupComplete: true,
        );
        _installState = _installState.copyWith(profileSetupComplete: true);
        _usernameController.text = resolvedUsername;
        _profileAuthEmailController.text = result.authEmail.trim();
        _profileAuthPasswordController.text = result.authPassword;
      });
      final forcedRemote = _forceRemoteBackendForEmailPasswordAuth();
      await _saveSettings(toast: false);
      if (forcedRemote && mounted) {
        _toast(
          'Email/password auth enabled. Backend Type was switched to Remote.',
        );
      }
      try {
        await _saveInstallState();
      } catch (error) {
        _log('settings', 'Failed to persist install state: $error');
      }
      _syncLauncherDiscordPresence();
      _queueLauncherAutoUpdateCheckOnLaunch();
    } catch (error) {
      _log('settings', 'First-run profile setup failed: $error');
    } finally {
      _profileSetupDialogVisible = false;
      if (mounted) _syncLauncherDiscordPresence();
    }
  }

  Future<_ProfileSetupResult?> _promptFirstRunProfileSetup() async {
    if (!mounted) return null;

    // Start blank so profile setup always feels like a fresh choice (especially
    // after a Reset Launcher) and never pre-fills from environment/usernames.
    final usernameController = TextEditingController();
    final emailController = TextEditingController(
      text: _settings.profileAuthEmail,
    );
    final passwordController = TextEditingController(
      text: _settings.profileAuthPassword,
    );
    final usernameFocusNode = FocusNode();
    final emailFocusNode = FocusNode();
    final passwordFocusNode = FocusNode();
    try {
      return await showGeneralDialog<_ProfileSetupResult>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var selectedAvatarPath = _settings.profileAvatarPath.trim();
          var validation = '';
          var submitted = false;
          var focusRequested = false;
          var useEmailPasswordAuth = _settings.profileUseEmailPasswordAuth;
          var showPassword = false;
          var authValidationAttempted = false;

          ImageProvider<Object> avatarProvider() {
            final selected = selectedAvatarPath.trim();
            if (selected.isNotEmpty && File(selected).existsSync()) {
              return FileImage(File(selected));
            }
            return const AssetImage('assets/images/default_pfp.png');
          }

          Future<void> pickAvatar() async {
            if (!Platform.isWindows) return;
            final picked = await FilePicker.platform.pickFiles(
              type: FileType.image,
              dialogTitle: 'Select profile picture',
            );
            final path = picked?.files.single.path?.trim() ?? '';
            if (path.isEmpty) return;
            selectedAvatarPath = path;
          }

          void setDefaultAvatar() {
            selectedAvatarPath = '';
          }

          TextEditingController activePrimaryController() {
            return useEmailPasswordAuth ? emailController : usernameController;
          }

          FocusNode activePrimaryFocusNode() {
            return useEmailPasswordAuth ? emailFocusNode : usernameFocusNode;
          }

          void focusActivePrimaryField() {
            final activeController = activePrimaryController();
            final activeFocusNode = activePrimaryFocusNode();
            activeFocusNode.requestFocus();
            activeController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: activeController.text.length,
            );
          }

          void submitDialog(StateSetter setDialogState) {
            if (submitted) return;
            final displayName = usernameController.text.trim();
            if (!useEmailPasswordAuth && displayName.isEmpty) {
              setDialogState(() {
                validation = 'Enter a display name.';
              });
              return;
            }
            final authError = _profileAuthValidationError(
              useEmailPassword: useEmailPasswordAuth,
              email: emailController.text.trim(),
              password: passwordController.text,
            );
            if (authError != null) {
              setDialogState(() {
                validation = '';
                authValidationAttempted = true;
              });
              return;
            }
            setDialogState(() {
              validation = '';
              authValidationAttempted = false;
              submitted = true;
            });

            final emailDerivedDisplayName = _usernameFromEmail(
              emailController.text,
            );
            final resolvedDisplayName = useEmailPasswordAuth
                ? (emailDerivedDisplayName.isEmpty
                      ? 'Player'
                      : emailDerivedDisplayName)
                : (displayName.isEmpty ? 'Player' : displayName);
            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(
                _ProfileSetupResult(
                  username: resolvedDisplayName,
                  profileAvatarPath: selectedAvatarPath,
                  useEmailPasswordAuth: useEmailPasswordAuth,
                  authEmail: useEmailPasswordAuth
                      ? emailController.text.trim()
                      : '',
                  authPassword: useEmailPasswordAuth
                      ? passwordController.text
                      : '',
                ),
              );
            });
          }

          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              if (!focusRequested) {
                focusRequested = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!dialogContext.mounted) return;
                  focusActivePrimaryField();
                });
              }

              final onSurface = _onSurface(dialogContext, 0.92);
              final onSurfaceMuted = _onSurface(dialogContext, 0.70);
              final compact = MediaQuery.of(dialogContext).size.width < 720;
              final avatarSize = compact ? 104.0 : 124.0;

              final avatar = SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Material(
                      color: Colors.transparent,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: _onSurface(dialogContext, 0.16),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Ink.image(
                        image: avatarProvider(),
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                        child: InkWell(
                          onTap: () async {
                            await pickAvatar();
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () async {
                            await pickAvatar();
                            setDialogState(() {});
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _adaptiveScrimColor(
                                dialogContext,
                                darkAlpha: 0.22,
                                lightAlpha: 0.26,
                              ),
                              border: Border.all(
                                color: _onSurface(dialogContext, 0.16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _dialogShadowColor(
                                    dialogContext,
                                  ).withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: _onSurface(dialogContext, 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              Widget buildAuthSwitchButton() {
                return Tooltip(
                  message: 'Switch Login Authentication',
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      onPressed: submitted
                          ? null
                          : () {
                              setDialogState(() {
                                useEmailPasswordAuth = !useEmailPasswordAuth;
                                showPassword = false;
                                validation = '';
                                authValidationAttempted = false;
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!dialogContext.mounted) return;
                                focusActivePrimaryField();
                              });
                            },
                      icon: Icon(
                        useEmailPasswordAuth
                            ? Icons.alternate_email_rounded
                            : Icons.person_rounded,
                        size: 18,
                      ),
                    ),
                  ),
                );
              }

              final authValidationError = authValidationAttempted
                  ? _profileAuthValidationError(
                      useEmailPassword: useEmailPasswordAuth,
                      email: emailController.text.trim(),
                      password: passwordController.text,
                    )
                  : null;
              final showPrimaryAuthError =
                  useEmailPasswordAuth &&
                  authValidationError != null &&
                  authValidationError.toLowerCase().contains('email');

              final primaryField = TextField(
                controller: activePrimaryController(),
                focusNode: activePrimaryFocusNode(),
                onChanged: (_) {
                  if (useEmailPasswordAuth) {
                    if (!authValidationAttempted) return;
                    setDialogState(() => authValidationAttempted = false);
                    return;
                  }
                  if (validation.isEmpty) return;
                  setDialogState(() => validation = '');
                },
                onSubmitted: (_) {
                  if (useEmailPasswordAuth) {
                    passwordFocusNode.requestFocus();
                    return;
                  }
                  submitDialog(setDialogState);
                },
                textInputAction: useEmailPasswordAuth
                    ? TextInputAction.next
                    : TextInputAction.done,
                keyboardType: useEmailPasswordAuth
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: useEmailPasswordAuth ? 'Email' : 'Display name',
                  hintText: useEmailPasswordAuth
                      ? 'name@example.com'
                      : 'Player',
                  isDense: true,
                  filled: true,
                  fillColor: _onSurface(dialogContext, 0.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  suffixIcon: buildAuthSwitchButton(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _onSurface(dialogContext, 0.18),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _onSurface(dialogContext, 0.18),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(dialogContext).colorScheme.secondary,
                      width: 1.2,
                    ),
                  ),
                  errorText: useEmailPasswordAuth
                      ? (showPrimaryAuthError ? authValidationError : null)
                      : (validation.isEmpty ? null : validation),
                ),
                style: TextStyle(color: onSurface),
              );

              final passwordField = TextField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                onChanged: (_) {
                  if (!authValidationAttempted) return;
                  setDialogState(() => authValidationAttempted = false);
                },
                onSubmitted: (_) => submitDialog(setDialogState),
                textInputAction: TextInputAction.done,
                obscureText: !showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Set password',
                  isDense: true,
                  filled: true,
                  fillColor: _onSurface(dialogContext, 0.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  suffixIcon: SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      tooltip: showPassword ? 'Hide password' : 'Show password',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      onPressed: passwordController.text.isEmpty
                          ? null
                          : () {
                              setDialogState(
                                () => showPassword = !showPassword,
                              );
                            },
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _onSurface(dialogContext, 0.18),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _onSurface(dialogContext, 0.18),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(dialogContext).colorScheme.secondary,
                      width: 1.2,
                    ),
                  ),
                  errorText:
                      useEmailPasswordAuth &&
                          authValidationError != null &&
                          !showPrimaryAuthError
                      ? authValidationError
                      : null,
                ),
                style: TextStyle(color: onSurface),
              );

              final profileFields = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primaryField,
                  if (useEmailPasswordAuth) ...[
                    const SizedBox(height: 8),
                    passwordField,
                  ],
                ],
              );

              final mainRow = compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: avatar),
                        const SizedBox(height: 14),
                        profileFields,
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: submitted
                                  ? null
                                  : () async {
                                      await pickAvatar();
                                      setDialogState(() {});
                                    },
                              icon: const Icon(Icons.image_rounded, size: 18),
                              label: Text(
                                selectedAvatarPath.trim().isEmpty
                                    ? 'Choose PFP'
                                    : 'Change PFP',
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed:
                                  submitted || selectedAvatarPath.trim().isEmpty
                                  ? null
                                  : () => setDialogState(setDefaultAvatar),
                              icon: const Icon(Icons.restore_rounded, size: 18),
                              label: const Text('Default'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              profileFields,
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: submitted
                                        ? null
                                        : () async {
                                            await pickAvatar();
                                            setDialogState(() {});
                                          },
                                    icon: const Icon(
                                      Icons.image_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      selectedAvatarPath.trim().isEmpty
                                          ? 'Choose PFP'
                                          : 'Change PFP',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed:
                                        submitted ||
                                            selectedAvatarPath.trim().isEmpty
                                        ? null
                                        : () =>
                                              setDialogState(setDefaultAvatar),
                                    icon: const Icon(
                                      Icons.restore_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Default'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

              return Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (intent) {
                        submitDialog(setDialogState);
                        return null;
                      },
                    ),
                  },
                  child: SafeArea(
                    child: Center(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 680),
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                          decoration: BoxDecoration(
                            color: _dialogSurfaceColor(dialogContext),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: _onSurface(dialogContext, 0.10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _dialogShadowColor(dialogContext),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(dialogContext)
                                          .colorScheme
                                          .secondary
                                          .withValues(alpha: 0.18),
                                      border: Border.all(
                                        color: _onSurface(dialogContext, 0.18),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.person_rounded,
                                      size: 18,
                                      color: _onSurface(dialogContext, 0.9),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'PROFILE SETUP',
                                    style: TextStyle(
                                      fontSize: 12,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w800,
                                      color: _onSurface(dialogContext, 0.66),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Create your profile',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: _onSurface(dialogContext, 0.96),
                                  height: 1.04,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Set your name and profile picture! You can change this later in your profile settings.',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.38,
                                  color: onSurfaceMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              mainRow,
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      submitted ? 'Saving...' : '',
                                      style: TextStyle(
                                        color: onSurfaceMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: submitted
                                        ? null
                                        : () => submitDialog(setDialogState),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Continue'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3.2 * curved.value,
                          sigmaY: 3.2 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    } finally {
      passwordFocusNode.dispose();
      emailFocusNode.dispose();
      usernameFocusNode.dispose();
      passwordController.dispose();
      emailController.dispose();
      usernameController.dispose();
    }
  }

  void _startHomeHeroAutoRotate() {
    _homeHeroTimer?.cancel();
    _homeHeroTimer = Timer.periodic(_homeHeroRotateInterval, (_) {
      if (!mounted || _tab != LauncherTab.home) return;
      final count = _homeFeaturedCards.length;
      if (count <= 1) return;
      setState(() {
        _homeHeroIndex = (_homeHeroIndex + 1) % count;
      });
    });
  }

  void _setHomeHeroIndex(int index) {
    final count = _homeFeaturedCards.length;
    if (count == 0) return;
    if (!mounted) {
      _homeHeroIndex = index % count;
      return;
    }
    setState(() => _homeHeroIndex = index % count);
    _startHomeHeroAutoRotate();
  }

  Future<void> _initStorage() async {
    final appData =
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final preferredDataDir = Directory(
      _joinPath([appData, _launcherDataDirName]),
    );
    final legacyDataDir = Directory(
      _joinPath([appData, _legacyLauncherDataDirName]),
    );
    await _migrateLegacyDataDirIfNeeded(
      legacyDataDir: legacyDataDir,
      preferredDataDir: preferredDataDir,
    );
    _dataDir = preferredDataDir;
    await _dataDir.create(recursive: true);
    _settingsFile = File(_joinPath([_dataDir.path, 'settings.json']));
    _installStateFile = File(_joinPath([_dataDir.path, 'install_state.json']));
    _logFile = File(_joinPath([_dataDir.path, 'launcher.log']));
    // Reset launcher logs on every app start so each run has a clean log.
    // If truncation fails (locked, permissions), keep going.
    try {
      await _logFile.writeAsString('', flush: true);
    } catch (_) {
      try {
        if (!await _logFile.exists()) {
          await _logFile.create(recursive: true);
        }
      } catch (_) {
        // Ignore log initialization failures.
      }
    }
    _logFileReady = true;
  }

  Future<void> _migrateLegacyDataDirIfNeeded({
    required Directory legacyDataDir,
    required Directory preferredDataDir,
  }) async {
    if (await preferredDataDir.exists()) return;
    if (!await legacyDataDir.exists()) return;

    try {
      await legacyDataDir.rename(preferredDataDir.path);
      return;
    } catch (_) {
      // Fall back to copying if rename is blocked (for example by a file lock).
    }

    try {
      await preferredDataDir.create(recursive: true);
      await for (final entity in legacyDataDir.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path
            .substring(legacyDataDir.path.length)
            .replaceFirst(RegExp(r'^[\\/]+'), '');
        if (relative.isEmpty) continue;
        final destinationPath = _joinPath([preferredDataDir.path, relative]);
        if (entity is Directory) {
          await Directory(destinationPath).create(recursive: true);
          continue;
        }
        if (entity is File) {
          final destinationFile = File(destinationPath);
          await destinationFile.parent.create(recursive: true);
          if (!await destinationFile.exists()) {
            await entity.copy(destinationPath);
          }
        }
      }
    } catch (_) {
      // If migration fails, continue with the preferred directory path.
    }
  }

  String? _resolveBundledAssetFilePath(String bundledAssetPath) {
    final normalized = bundledAssetPath
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty) return null;

    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    // On Flutter Windows, packaged assets live next to the executable:
    //   <exeDir>\data\flutter_assets\<assetPath>
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate = _joinPath([exeDir, 'data', 'flutter_assets', ...parts]);
    if (File(candidate).existsSync()) return candidate;

    return null;
  }

  bool _isManagedBundledDllPath(String configuredPath, String fileName) {
    final raw = configuredPath.trim();
    if (raw.isEmpty) return false;
    if (_basename(raw).toLowerCase() != fileName.toLowerCase()) return false;

    final normalizedRaw = _normalizePath(raw);
    final candidates = <String>[
      _joinPath([_dataDir.path, 'dlls', fileName]),
    ];

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      candidates.add(
        _joinPath([appData, _legacyLauncherDataDirName, 'dlls', fileName]),
      );
    }

    for (final candidate in candidates) {
      if (_normalizePath(candidate) == normalizedRaw) return true;
    }
    return false;
  }

  bool _looksLikeBundledAssetDllPath(String configuredPath, String fileName) {
    final raw = configuredPath.trim();
    if (raw.isEmpty) return false;
    if (_basename(raw).toLowerCase() != fileName.toLowerCase()) return false;

    final normalizedRaw = _normalizePath(raw);
    final needle = _normalizePath(
      _joinPath(['data', 'flutter_assets', 'assets', 'dlls', fileName]),
    );
    return normalizedRaw.contains(needle);
  }

  bool _isBundledAssetDllFromCurrentInstall(
    String configuredPath,
    String fileName,
  ) {
    if (!_looksLikeBundledAssetDllPath(configuredPath, fileName)) return false;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final normalizedExeDir = _normalizePath(exeDir);
    final normalizedPath = _normalizePath(configuredPath);
    final prefix = normalizedExeDir.endsWith('/')
        ? normalizedExeDir
        : '$normalizedExeDir/';
    return normalizedPath.startsWith(prefix);
  }

  _BundledDllSpec _bundledDllSpecByFileName(String fileName) {
    final lower = fileName.trim().toLowerCase();
    for (final spec in _bundledDllSpecs) {
      if (spec.fileNameLower == lower) return spec;
    }
    throw StateError('Unknown bundled DLL file name: $fileName');
  }

  String? _resolveCurrentBundledDefaultDllPath(_BundledDllSpec spec) {
    final configuredPath = _configuredDllPathForSpec(spec).trim();
    final configuredLooksLikeDll =
        configuredPath.isNotEmpty &&
        configuredPath.toLowerCase().endsWith('.dll');
    final configuredIsBundledDefaultLocation =
        _isManagedBundledDllPath(configuredPath, spec.fileName) ||
        _looksLikeBundledAssetDllPath(configuredPath, spec.fileName);
    if (configuredLooksLikeDll &&
        configuredIsBundledDefaultLocation &&
        File(configuredPath).existsSync()) {
      return configuredPath;
    }

    final installedPath = _resolveBundledAssetFilePath(spec.assetPath);
    if (installedPath != null && installedPath.trim().isNotEmpty) {
      return installedPath;
    }
    final managedPath = _joinPath([_dataDir.path, 'dlls', spec.fileName]);
    if (File(managedPath).existsSync()) return managedPath;
    return null;
  }

  String _configuredDllPathForSpec(_BundledDllSpec spec) {
    switch (spec.fileNameLower) {
      case 'console.dll':
        return _settings.unrealEnginePatcherPath;
      case 'tellurium.dll':
        return _settings.authenticationPatcherPath;
      case 'memory.dll':
        return _settings.memoryPatcherPath;
      case 'magnesium.dll':
        return _settings.gameServerFilePath;
      case 'largepakpatch.dll':
        return _settings.largePakPatcherFilePath;
      default:
        return '';
    }
  }

  Future<String?> _computeGitBlobShaForFile(File file) async {
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final header = ascii.encode('blob ${bytes.length}\u0000');
      final payload = Uint8List(header.length + bytes.length);
      payload.setRange(0, header.length, header);
      payload.setRange(header.length, payload.length, bytes);
      return crypto.sha1.convert(payload).toString().toLowerCase();
    } catch (error) {
      _log('settings', 'Failed to hash DLL file (${file.path}): $error');
      return null;
    }
  }

  Future<Map<String, _BundledDllRemoteAsset>> _fetchBundledDllRemoteAssets({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _bundledDllRemoteAssetsByName.isNotEmpty) {
      return _bundledDllRemoteAssetsByName;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'ATLAS-Link';
    try {
      final request = await client.getUrl(
        Uri.parse(_atlasLinkBundledDllContentsApi),
      );
      request.followRedirects = true;
      request.maxRedirects = 6;
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        final remaining = response.headers.value('x-ratelimit-remaining');
        final hint = remaining == null || remaining.trim().isEmpty
            ? ''
            : ' (rate remaining $remaining)';
        _log(
          'settings',
          'GitHub bundled DLL manifest request failed (HTTP ${response.statusCode})$hint.',
        );
        return const <String, _BundledDllRemoteAsset>{};
      }

      final body = await response.transform(utf8.decoder).join();
      if (body.trim().isEmpty) {
        return const <String, _BundledDllRemoteAsset>{};
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        return const <String, _BundledDllRemoteAsset>{};
      }

      final next = <String, _BundledDllRemoteAsset>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final map = entry.cast<dynamic, dynamic>();
        final type = (map['type'] ?? '').toString().trim().toLowerCase();
        if (type != 'file') continue;

        final name = (map['name'] ?? '').toString().trim();
        final sha = (map['sha'] ?? '').toString().trim().toLowerCase();
        final downloadUrl = (map['download_url'] ?? '').toString().trim();
        if (name.isEmpty || sha.isEmpty) continue;

        next[name.toLowerCase()] = _BundledDllRemoteAsset(
          sha: sha,
          downloadUrl: downloadUrl,
        );
      }

      if (next.isNotEmpty) {
        _bundledDllRemoteAssetsByName = next;
      }
      return next;
    } catch (error) {
      _log('settings', 'Failed to fetch bundled DLL manifest: $error');
      return const <String, _BundledDllRemoteAsset>{};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _checkForBundledDllDefaultUpdates({
    required bool silent,
    bool forceRefresh = true,
  }) async {
    if (_checkingBundledDllDefaultsUpdate) return;
    _checkingBundledDllDefaultsUpdate = true;
    try {
      final remoteAssets = await _fetchBundledDllRemoteAssets(
        forceRefresh: forceRefresh,
      );
      if (remoteAssets.isEmpty) {
        if (!silent && mounted) {
          _toast('Unable to check default DLL updates right now');
        }
        return;
      }

      final updatedFiles = <String>{};
      for (final spec in _bundledDllSpecs) {
        final remote = remoteAssets[spec.fileNameLower];
        if (remote == null) continue;

        final localPath = _resolveCurrentBundledDefaultDllPath(spec);
        if (localPath == null || localPath.trim().isEmpty) {
          updatedFiles.add(spec.fileNameLower);
          continue;
        }
        final localSha = await _computeGitBlobShaForFile(File(localPath));
        if (localSha == null || localSha != remote.sha) {
          updatedFiles.add(spec.fileNameLower);
        }
      }

      if (mounted) {
        setState(() {
          _bundledDllUpdatedFileNames = updatedFiles;
          _bundledDllDefaultsUpdateAvailable = updatedFiles.isNotEmpty;
        });
      } else {
        _bundledDllUpdatedFileNames = updatedFiles;
        _bundledDllDefaultsUpdateAvailable = updatedFiles.isNotEmpty;
      }

      if (!silent && mounted) {
        if (updatedFiles.isEmpty) {
          _toast('Default DLLs are up to date');
        } else {
          _toast('New Default DLL updates are available');
        }
      }
    } catch (error) {
      _log('settings', 'Failed to check for bundled DLL updates: $error');
      if (!silent && mounted) {
        _toast('Unable to check default DLL updates right now');
      }
    } finally {
      _checkingBundledDllDefaultsUpdate = false;
    }
  }

  Future<String?> _downloadLatestBundledDllFromGitHub({
    required _BundledDllSpec spec,
    Map<String, _BundledDllRemoteAsset>? remoteAssets,
  }) async {
    final resolvedRemoteAssets =
        remoteAssets ?? await _fetchBundledDllRemoteAssets(forceRefresh: true);
    final remote = resolvedRemoteAssets[spec.fileNameLower];
    final fallbackUrl =
        '$_atlasLinkBundledDllFallbackBaseUrl${spec.normalizedAssetPath}';
    final downloadUrl = remote?.downloadUrl.trim().isNotEmpty == true
        ? remote!.downloadUrl.trim()
        : fallbackUrl;

    final dllDir = Directory(_joinPath([_dataDir.path, 'dlls']));
    final outputPath = _joinPath([dllDir.path, spec.fileName]);
    final outputFile = File(outputPath);
    final tmp = File('$outputPath.tmp');
    try {
      await dllDir.create(recursive: true);
      if (await tmp.exists()) {
        await tmp.delete();
      }

      final progressMessage = 'Updating ${spec.fileName}...';
      if (mounted) {
        _toastProgress(progressMessage, progress: null, indeterminate: true);
      }

      await _downloadToFile(
        downloadUrl,
        tmp,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted) return;
          if (totalBytes == null || totalBytes <= 0) {
            _toastProgress(
              progressMessage,
              progress: null,
              indeterminate: true,
            );
            return;
          }
          final ratio = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          _toastProgress(
            progressMessage,
            progress: ratio,
            indeterminate: false,
          );
        },
      );
      final length = await tmp.length();
      if (length <= 0) {
        throw 'Downloaded file was empty.';
      }

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await tmp.rename(outputFile.path);

      if (remote != null) {
        final localSha = await _computeGitBlobShaForFile(outputFile);
        if (localSha == null || localSha != remote.sha) {
          throw 'Downloaded file hash did not match GitHub metadata.';
        }
      }

      if (mounted) {
        _toastProgressDismiss();
      }
      return outputPath;
    } catch (error) {
      _log(
        'settings',
        'Failed to download latest ${spec.label} DLL from GitHub ($downloadUrl): $error',
      );
      if (mounted) {
        _toastProgressDismiss();
      }
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {
        // Ignore cleanup failures.
      }
      return null;
    }
  }

  Future<void> _resetBundledDllPathToLatest({
    required _BundledDllSpec spec,
    required LauncherSettings Function(LauncherSettings, String) applySetting,
    required TextEditingController controller,
    bool checkForUpdatesAfter = true,
    Map<String, _BundledDllRemoteAsset>? remoteAssets,
  }) async {
    var nextPath = await _downloadLatestBundledDllFromGitHub(
      spec: spec,
      remoteAssets: remoteAssets,
    );
    if (nextPath == null || nextPath.trim().isEmpty) {
      _log(
        'settings',
        'Falling back to packaged ${spec.label} DLL after GitHub refresh failed.',
      );
      if (mounted) {
        _toast('Updating ${spec.fileName}...');
      }
      nextPath = await _ensureBundledDll(
        bundledAssetPath: spec.assetPath,
        bundledFileName: spec.fileName,
        label: spec.label,
        overwriteFallbackCopy: true,
      );
    }

    final normalized = nextPath?.trim() ?? '';
    if (mounted) {
      setState(() {
        _settings = applySetting(_settings, normalized);
        controller.text = normalized;
      });
    } else {
      _settings = applySetting(_settings, normalized);
      controller.text = normalized;
    }
    await _saveSettings(toast: false);
    if (checkForUpdatesAfter) {
      unawaited(_checkForBundledDllDefaultUpdates(silent: true));
    }
  }

  Future<bool> _tryDownloadBundledDllFromGitHub({
    required String bundledAssetPath,
    required File outputFile,
    required String label,
  }) async {
    final normalized = bundledAssetPath
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty) return false;

    // Only allow downloading assets that are expected to ship with the launcher.
    if (!normalized.toLowerCase().startsWith('assets/dlls/')) return false;

    final url = '$_atlasLinkBundledDllFallbackBaseUrl$normalized';
    final tmp = File('${outputFile.path}.tmp');
    try {
      if (await tmp.exists()) {
        await tmp.delete();
      }

      _log(
        'settings',
        'Bundled $label DLL missing. Downloading from GitHub...',
      );
      final progressMessage = 'Updating ${_basename(outputFile.path)}...';
      if (mounted) {
        _toastProgress(progressMessage, progress: null, indeterminate: true);
      }
      await _downloadToFile(
        url,
        tmp,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted) return;
          if (totalBytes == null || totalBytes <= 0) {
            _toastProgress(
              progressMessage,
              progress: null,
              indeterminate: true,
            );
            return;
          }
          final ratio = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          _toastProgress(
            progressMessage,
            progress: ratio,
            indeterminate: false,
          );
        },
      );
      final length = await tmp.length();
      if (length <= 0) {
        throw 'Downloaded file was empty.';
      }

      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await tmp.rename(outputFile.path);
      if (mounted) {
        _toastProgressDismiss();
      }
      return true;
    } catch (error) {
      _log(
        'settings',
        'Failed to download default $label DLL from GitHub ($url): $error',
      );
      if (mounted) {
        _toastProgressDismiss();
      }
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {
        // Ignore cleanup failures.
      }
      return false;
    }
  }

  Future<String?> _ensureBundledDll({
    required String bundledAssetPath,
    required String bundledFileName,
    required String label,
    bool overwriteFallbackCopy = false,
  }) async {
    final installedPath = _resolveBundledAssetFilePath(bundledAssetPath);
    if (installedPath != null) return installedPath;

    final dllDir = Directory(_joinPath([_dataDir.path, 'dlls']));
    try {
      await dllDir.create(recursive: true);
      final outputPath = _joinPath([dllDir.path, bundledFileName]);
      final outputFile = File(outputPath);
      if (overwriteFallbackCopy || !outputFile.existsSync()) {
        if (mounted && overwriteFallbackCopy) {
          _toast('Updating $bundledFileName...');
        }
        try {
          final bytes = await rootBundle.load(bundledAssetPath);
          await outputFile.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            flush: true,
          );
        } catch (error) {
          // If the packaged asset is missing/corrupted, fall back to fetching
          // the default from GitHub so the Reset button can still restore it.
          _log(
            'settings',
            'Failed to extract bundled $label DLL ($bundledAssetPath): $error',
          );
          final downloaded = await _tryDownloadBundledDllFromGitHub(
            bundledAssetPath: bundledAssetPath,
            outputFile: outputFile,
            label: label,
          );
          if (!downloaded) rethrow;
        }
      }
      return outputPath;
    } catch (error) {
      _log(
        'settings',
        'Failed to prepare bundled $label DLL ($bundledAssetPath): $error',
      );
      return null;
    }
  }

  Future<void> _applyBundledDllDefaults({
    bool forceResetBundledPaths = false,
  }) async {
    var nextSettings = _settings;
    var changed = false;

    final bundledGameServerPath = await _ensureBundledDll(
      bundledAssetPath: 'assets/dlls/Magnesium.dll',
      bundledFileName: 'Magnesium.dll',
      label: 'game server',
      overwriteFallbackCopy: forceResetBundledPaths,
    );
    if (bundledGameServerPath != null &&
        bundledGameServerPath.trim().isNotEmpty) {
      final configuredGameServer = _settings.gameServerFilePath.trim();
      final gameServerExists =
          configuredGameServer.isNotEmpty &&
          File(configuredGameServer).existsSync();
      final looksBundledGameServer = _looksLikeBundledAssetDllPath(
        configuredGameServer,
        'Magnesium.dll',
      );
      final bundledFromCurrentInstall = _isBundledAssetDllFromCurrentInstall(
        configuredGameServer,
        'Magnesium.dll',
      );
      final shouldAdoptBundledGameServer =
          configuredGameServer.isEmpty ||
          (configuredGameServer.isNotEmpty && !gameServerExists) ||
          (looksBundledGameServer &&
              (!bundledFromCurrentInstall || forceResetBundledPaths));
      if (shouldAdoptBundledGameServer) {
        nextSettings = nextSettings.copyWith(
          gameServerFilePath: bundledGameServerPath,
        );
        _gameServerFileController.text = bundledGameServerPath;
        changed = true;
        if (configuredGameServer.isNotEmpty && !gameServerExists) {
          _log(
            'settings',
            'Game server DLL missing at $configuredGameServer. Restored bundled default.',
          );
        }
      }
    }

    final bundledLargePakPath = await _ensureBundledDll(
      bundledAssetPath: 'assets/dlls/LargePakPatch.dll',
      bundledFileName: 'LargePakPatch.dll',
      label: 'large pak patcher',
      overwriteFallbackCopy: forceResetBundledPaths,
    );
    if (bundledLargePakPath != null && bundledLargePakPath.trim().isNotEmpty) {
      final configuredLargePak = _settings.largePakPatcherFilePath.trim();
      final largePakExists =
          configuredLargePak.isNotEmpty &&
          File(configuredLargePak).existsSync();
      final looksBundledLargePak =
          _looksLikeBundledAssetDllPath(
            configuredLargePak,
            'LargePakPatch.dll',
          ) ||
          _looksLikeBundledAssetDllPath(
            configuredLargePak,
            'LargePakPatcher.dll',
          );
      final bundledLargePakFromCurrentInstall =
          _isBundledAssetDllFromCurrentInstall(
            configuredLargePak,
            'LargePakPatch.dll',
          ) ||
          _isBundledAssetDllFromCurrentInstall(
            configuredLargePak,
            'LargePakPatcher.dll',
          );
      final shouldAdoptBundledLargePak =
          configuredLargePak.isEmpty ||
          (configuredLargePak.isNotEmpty && !largePakExists) ||
          (looksBundledLargePak &&
              (!bundledLargePakFromCurrentInstall || forceResetBundledPaths));
      if (shouldAdoptBundledLargePak) {
        nextSettings = nextSettings.copyWith(
          largePakPatcherFilePath: bundledLargePakPath,
        );
        _largePakPatcherController.text = bundledLargePakPath;
        changed = true;
        if (configuredLargePak.isNotEmpty && !largePakExists) {
          _log(
            'settings',
            'Large pak patcher DLL missing at $configuredLargePak. Restored bundled default.',
          );
        }
      }
    }

    final bundledMemoryPath = await _ensureBundledDll(
      bundledAssetPath: 'assets/dlls/memory.dll',
      bundledFileName: 'memory.dll',
      label: 'memory patcher',
      overwriteFallbackCopy: forceResetBundledPaths,
    );
    if (bundledMemoryPath != null && bundledMemoryPath.trim().isNotEmpty) {
      final configuredMemory = _settings.memoryPatcherPath.trim();
      final memoryExists =
          configuredMemory.isNotEmpty && File(configuredMemory).existsSync();
      final looksBundledMemory = _looksLikeBundledAssetDllPath(
        configuredMemory,
        'memory.dll',
      );
      final bundledMemoryFromCurrentInstall =
          _isBundledAssetDllFromCurrentInstall(configuredMemory, 'memory.dll');
      final shouldAdoptBundledMemory =
          configuredMemory.isEmpty ||
          (configuredMemory.isNotEmpty && !memoryExists) ||
          (looksBundledMemory &&
              (!bundledMemoryFromCurrentInstall || forceResetBundledPaths));
      if (shouldAdoptBundledMemory) {
        nextSettings = nextSettings.copyWith(
          memoryPatcherPath: bundledMemoryPath,
        );
        _memoryPatcherController.text = bundledMemoryPath;
        changed = true;
        if (configuredMemory.isNotEmpty && !memoryExists) {
          _log(
            'settings',
            'Memory patcher DLL missing at $configuredMemory. Restored bundled default.',
          );
        }
      }
    }

    final bundledAuthPath = await _ensureBundledDll(
      bundledAssetPath: 'assets/dlls/Tellurium.dll',
      bundledFileName: 'Tellurium.dll',
      label: 'authentication patcher',
      overwriteFallbackCopy: forceResetBundledPaths,
    );
    if (bundledAuthPath != null && bundledAuthPath.trim().isNotEmpty) {
      final configuredAuth = _settings.authenticationPatcherPath.trim();
      final authExists =
          configuredAuth.isNotEmpty && File(configuredAuth).existsSync();
      final looksBundledAuth = _looksLikeBundledAssetDllPath(
        configuredAuth,
        'Tellurium.dll',
      );
      final bundledAuthFromCurrentInstall =
          _isBundledAssetDllFromCurrentInstall(configuredAuth, 'Tellurium.dll');
      final shouldAdoptBundledAuth =
          configuredAuth.isEmpty ||
          (configuredAuth.isNotEmpty && !authExists) ||
          (looksBundledAuth &&
              (!bundledAuthFromCurrentInstall || forceResetBundledPaths));
      if (shouldAdoptBundledAuth) {
        nextSettings = nextSettings.copyWith(
          authenticationPatcherPath: bundledAuthPath,
        );
        _authenticationPatcherController.text = bundledAuthPath;
        changed = true;
        if (configuredAuth.isNotEmpty && !authExists) {
          _log(
            'settings',
            'Authentication patcher DLL missing at $configuredAuth. Restored bundled default.',
          );
        }
      }
    }

    final bundledUnrealPath = await _ensureBundledDll(
      bundledAssetPath: 'assets/dlls/console.dll',
      bundledFileName: 'console.dll',
      label: 'unreal engine patcher',
      overwriteFallbackCopy: forceResetBundledPaths,
    );
    if (bundledUnrealPath != null && bundledUnrealPath.trim().isNotEmpty) {
      final configuredUnreal = _settings.unrealEnginePatcherPath.trim();
      final unrealExists =
          configuredUnreal.isNotEmpty && File(configuredUnreal).existsSync();
      final looksBundledUnreal = _looksLikeBundledAssetDllPath(
        configuredUnreal,
        'console.dll',
      );
      final bundledUnrealFromCurrentInstall =
          _isBundledAssetDllFromCurrentInstall(configuredUnreal, 'console.dll');
      final shouldAdoptBundledUnreal =
          configuredUnreal.isEmpty ||
          (configuredUnreal.isNotEmpty && !unrealExists) ||
          (looksBundledUnreal &&
              (!bundledUnrealFromCurrentInstall || forceResetBundledPaths));
      if (shouldAdoptBundledUnreal) {
        nextSettings = nextSettings.copyWith(
          unrealEnginePatcherPath: bundledUnrealPath,
        );
        _unrealEnginePatcherController.text = bundledUnrealPath;
        changed = true;
        if (configuredUnreal.isNotEmpty && !unrealExists) {
          _log(
            'settings',
            'Unreal engine patcher DLL missing at $configuredUnreal. Restored bundled default.',
          );
        }
      }
    }

    if (!changed) return;
    _settings = nextSettings;
    await _saveSettings(toast: false);
  }

  Future<void> _loadInstallState() async {
    if (!await _installStateFile.exists()) {
      _installState = LauncherInstallState.defaults();
      return;
    }
    try {
      final raw = await _installStateFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _installState = LauncherInstallState.fromJson(decoded);
      } else if (decoded is Map) {
        _installState = LauncherInstallState.fromJson(
          decoded.cast<String, dynamic>(),
        );
      } else {
        _installState = LauncherInstallState.defaults();
      }
    } catch (error) {
      _installState = LauncherInstallState.defaults();
      _log('settings', 'Invalid install state file. Loaded defaults. $error');
    }
  }

  Future<void> _saveInstallState() async {
    final pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_installState.toJson());
    await _installStateFile.writeAsString(pretty, flush: true);
  }

  Future<void> _reconcileInstallState() async {
    final resolvedProfileSetup =
        _settings.profileSetupComplete || _installState.profileSetupComplete;
    final resolvedLibraryNudge =
        _settings.libraryActionsNudgeComplete ||
        _installState.libraryActionsNudgeComplete;
    final resolvedBackendConnectionTip =
        _settings.backendConnectionTipComplete ||
        _installState.backendConnectionTipComplete;

    var installStateChanged = false;
    var settingsChanged = false;

    if (_installState.profileSetupComplete != resolvedProfileSetup ||
        _installState.libraryActionsNudgeComplete != resolvedLibraryNudge ||
        _installState.backendConnectionTipComplete !=
            resolvedBackendConnectionTip) {
      _installState = _installState.copyWith(
        profileSetupComplete: resolvedProfileSetup,
        libraryActionsNudgeComplete: resolvedLibraryNudge,
        backendConnectionTipComplete: resolvedBackendConnectionTip,
      );
      installStateChanged = true;
    }

    if (_settings.profileSetupComplete != resolvedProfileSetup ||
        _settings.libraryActionsNudgeComplete != resolvedLibraryNudge ||
        _settings.backendConnectionTipComplete !=
            resolvedBackendConnectionTip) {
      _settings = _settings.copyWith(
        profileSetupComplete: resolvedProfileSetup,
        libraryActionsNudgeComplete: resolvedLibraryNudge,
        backendConnectionTipComplete: resolvedBackendConnectionTip,
      );
      settingsChanged = true;
    }

    if (installStateChanged) {
      try {
        await _saveInstallState();
      } catch (error) {
        _log('settings', 'Failed to save install state: $error');
      }
    }

    if (settingsChanged) {
      try {
        await _saveSettings(toast: false, applyControllers: false);
      } catch (error) {
        _log('settings', 'Failed to persist reconciled settings: $error');
      }
    }
  }

  Future<void> _loadSettings() async {
    if (!await _settingsFile.exists()) {
      _settings = LauncherSettings.defaults();
      await _migrateAppearanceSettingsFileIfNeeded();
      return;
    }
    try {
      final raw = await _settingsFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _settings = LauncherSettings.fromJson(decoded);
      } else if (decoded is Map) {
        _settings = LauncherSettings.fromJson(decoded.cast<String, dynamic>());
      } else {
        _settings = LauncherSettings.defaults();
      }
      final forcedRemote = _forceRemoteBackendForEmailPasswordAuth();
      if (forcedRemote) {
        _log(
          'settings',
          'Email/password auth was enabled with local backend. Switched backend type to remote.',
        );
      }
      await _migrateAppearanceSettingsFileIfNeeded();
    } catch (error) {
      _settings = LauncherSettings.defaults();
      _log('settings', 'Invalid settings file. Loaded defaults. $error');
      await _migrateAppearanceSettingsFileIfNeeded();
    }
  }

  Future<void> _migrateAppearanceSettingsFileIfNeeded() async {
    final legacyAppearanceSettingsFile = File(
      _joinPath([_dataDir.path, 'appearance_settings.json']),
    );
    if (!await legacyAppearanceSettingsFile.exists()) {
      return;
    }
    try {
      final raw = await legacyAppearanceSettingsFile.readAsString();
      final decoded = jsonDecode(raw);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? decoded.cast<String, dynamic>()
          : const <String, dynamic>{};

      double asDouble(dynamic value, double fallback) {
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? fallback;
        return fallback;
      }

      bool asBool(dynamic value, bool fallback) {
        if (value is bool) return value;
        if (value is num) return value != 0;
        if (value is String) {
          final lowered = value.toLowerCase();
          if (lowered == 'true' || lowered == '1') return true;
          if (lowered == 'false' || lowered == '0') return false;
        }
        return fallback;
      }

      final merged = _settings.copyWith(
        darkModeEnabled: asBool(
          data['darkModeEnabled'] ?? data['darkMode'] ?? data['DarkMode'],
          _settings.darkModeEnabled,
        ),
        popupBackgroundBlurEnabled: asBool(
          data['popupBackgroundBlurEnabled'] ??
              data['popupBackgroundBlur'] ??
              data['PopupBackgroundBlur'],
          _settings.popupBackgroundBlurEnabled,
        ),
        backgroundImagePath:
            (data['backgroundImagePath'] ?? data['BackgroundImagePath'] ?? '')
                .toString(),
        backgroundBlur: asDouble(
          data['backgroundBlur'] ?? data['BackgroundBlur'],
          _settings.backgroundBlur,
        ).clamp(0, 30),
        backgroundParticlesOpacity: asDouble(
          data['backgroundParticlesOpacity'] ??
              data['BackgroundParticlesOpacity'],
          _settings.backgroundParticlesOpacity,
        ).clamp(0, 2),
        startupAnimationEnabled: asBool(
          data['startupAnimationEnabled'] ?? data['StartupAnimationEnabled'],
          _settings.startupAnimationEnabled,
        ),
      );

      _settings = merged;

      final pretty = const JsonEncoder.withIndent(
        '  ',
      ).convert(_settings.toJson());
      await _settingsFile.writeAsString(pretty, flush: true);

      try {
        await legacyAppearanceSettingsFile.delete();
      } catch (_) {
        // Ignore legacy cleanup failures.
      }

      _log(
        'settings',
        'Migrated legacy appearance_settings.json into settings.json.',
      );
    } catch (error) {
      _log(
        'settings',
        'Invalid legacy appearance settings file. Keeping current settings values. $error',
      );
    }
  }

  Future<void> _saveProfileSettings() async {
    final useEmailPasswordAuth = _settings.profileUseEmailPasswordAuth;
    final trimmedEmail = _profileAuthEmailController.text.trim();
    final rawPassword = _profileAuthPasswordController.text;
    final validationError = _profileAuthValidationError(
      useEmailPassword: useEmailPasswordAuth,
      email: trimmedEmail,
      password: rawPassword,
    );
    if (validationError != null) {
      if (mounted) {
        setState(() => _profileAuthValidationAttempted = true);
      } else {
        _profileAuthValidationAttempted = true;
      }
      _toast(validationError);
      return;
    }

    final resolvedUsername = useEmailPasswordAuth
        ? _usernameFromEmail(trimmedEmail)
        : _usernameController.text.trim();
    final nextUsername = resolvedUsername.isEmpty ? 'Player' : resolvedUsername;

    if (mounted) {
      setState(() {
        _setActiveSettingsUsername(nextUsername);
        _usernameController.text = _settings.username;
        _settings = _settings.copyWith(
          profileAuthEmail: useEmailPasswordAuth ? trimmedEmail : '',
          profileAuthPassword: useEmailPasswordAuth ? rawPassword : '',
        );
        _profileAuthValidationAttempted = false;
      });
    } else {
      _setActiveSettingsUsername(nextUsername);
      _usernameController.text = _settings.username;
      _settings = _settings.copyWith(
        profileAuthEmail: useEmailPasswordAuth ? trimmedEmail : '',
        profileAuthPassword: useEmailPasswordAuth ? rawPassword : '',
      );
      _profileAuthValidationAttempted = false;
    }

    final forcedRemote = _forceRemoteBackendForEmailPasswordAuth();
    await _saveSettings(applyControllers: false);
    if (forcedRemote && mounted) {
      _toast(
        'Email/password auth requires Remote backend. Switched to Remote.',
      );
    }
  }

  Future<void> _saveSettings({
    bool toast = true,
    bool applyControllers = true,
  }) async {
    if (applyControllers) _applyControllers();
    _forceRemoteBackendForEmailPasswordAuth();
    _syncSavedBackendsForActiveProfile();
    final pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_settings.toJson());
    await _settingsFile.writeAsString(pretty, flush: true);
    _log('settings', 'Settings saved.');
    if (!mounted) return;
    setState(() {});
    if (toast) _toast('Settings saved');
  }

  Map<String, List<SavedBackend>> _cloneSavedBackendsByProfile({
    Map<String, List<SavedBackend>>? source,
  }) {
    final original = source ?? _settings.savedBackendsByProfile;
    final cloned = <String, List<SavedBackend>>{};
    for (final entry in original.entries) {
      final normalizedKey = LauncherSettings.profileBackendsKey(entry.key);
      cloned[normalizedKey] = List<SavedBackend>.from(entry.value);
    }
    return cloned;
  }

  LauncherSettings _settingsWithSavedBackendsForActiveProfile(
    List<SavedBackend> backends,
  ) {
    final normalizedBackends = List<SavedBackend>.from(backends);
    final scopedBackends = _cloneSavedBackendsByProfile();
    final profileKey = LauncherSettings.profileBackendsKey(_settings.username);
    scopedBackends[profileKey] = normalizedBackends;
    return _settings.copyWith(
      savedBackends: normalizedBackends,
      savedBackendsByProfile: scopedBackends,
    );
  }

  void _syncSavedBackendsForActiveProfile() {
    _settings = _settingsWithSavedBackendsForActiveProfile(
      _settings.savedBackends,
    );
  }

  void _setActiveSettingsUsername(String username) {
    final resolvedUsername = username.trim().isEmpty
        ? 'Player'
        : username.trim();
    final currentProfileKey = LauncherSettings.profileBackendsKey(
      _settings.username,
    );
    final nextProfileKey = LauncherSettings.profileBackendsKey(
      resolvedUsername,
    );
    final scopedBackends = _cloneSavedBackendsByProfile();
    final currentBackends = List<SavedBackend>.from(_settings.savedBackends);
    scopedBackends[currentProfileKey] = currentBackends;

    final nextBackends = currentProfileKey == nextProfileKey
        ? currentBackends
        : List<SavedBackend>.from(
            scopedBackends[nextProfileKey] ?? const <SavedBackend>[],
          );

    _settings = _settings.copyWith(
      username: resolvedUsername,
      savedBackends: nextBackends,
      savedBackendsByProfile: scopedBackends,
    );
  }

  void _syncControllers() {
    _usernameController.text = _settings.username;
    _profileAuthEmailController.text = _settings.profileAuthEmail;
    _profileAuthPasswordController.text = _settings.profileAuthPassword;
    _backendDirController.text = _settings.backendWorkingDirectory;
    _backendCommandController.text = _settings.backendStartCommand;
    _backendHostController.text = _effectiveBackendHost();
    _backendPortController.text = _effectiveBackendPort().toString();
    _unrealEnginePatcherController.text = _settings.unrealEnginePatcherPath;
    _authenticationPatcherController.text = _settings.authenticationPatcherPath;
    _memoryPatcherController.text = _settings.memoryPatcherPath;
    _gameServerFileController.text = _settings.gameServerFilePath;
    _largePakPatcherController.text = _settings.largePakPatcherFilePath;
  }

  void _applyControllers() {
    final hostInput = _backendHostController.text.trim();
    final normalizedRemoteHost = hostInput.isEmpty || _isLocalHost(hostInput)
        ? ''
        : hostInput;
    _settings = _settings.copyWith(
      backendWorkingDirectory: _backendDirController.text.trim(),
      backendStartCommand: _backendCommandController.text.trim(),
      backendHost:
          _settings.backendConnectionType == BackendConnectionType.local
          ? '127.0.0.1'
          : normalizedRemoteHost,
      backendPort:
          int.tryParse(_backendPortController.text.trim()) ??
          _settings.backendPort,
    );
  }

  String _effectiveBackendHost() {
    if (_settings.backendConnectionType == BackendConnectionType.local) {
      return '127.0.0.1';
    }
    final host = _settings.backendHost.trim();
    if (host.isEmpty || _isLocalHost(host)) {
      return '';
    }
    return host;
  }

  int _effectiveBackendPort() {
    final port = _settings.backendPort;
    return port > 0 ? port : 3551;
  }

  String _effectiveBackendHostForLaunchArgs() {
    final host = _effectiveBackendHost().trim();
    if (host.isEmpty) return _defaultBackendHost;

    final normalized = host
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^https://', caseSensitive: false), '')
        .split('/')
        .first
        .trim();
    if (normalized.isEmpty) return _defaultBackendHost;

    // Strip an inline port if one was provided.
    if (normalized.startsWith('[')) {
      final endBracket = normalized.indexOf(']');
      if (endBracket > 0) {
        return normalized.substring(1, endBracket).trim();
      }
      return normalized.replaceAll('[', '').replaceAll(']', '').trim();
    }

    final parts = normalized.split(':');
    return parts.isEmpty ? _defaultBackendHost : parts.first.trim();
  }

  int _effectiveGameServerPort() {
    final port = _settings.hostPort;
    if (port <= 0 || port > 65535) return _defaultGameServerPort;
    return port;
  }

  VersionEntry? _findVersionById(String versionId) {
    for (final version in _settings.versions) {
      if (version.id == versionId) return version;
    }
    return null;
  }

  Iterable<_FortniteProcessState> _runningGameClients() sync* {
    final primary = _gameInstance;
    if (primary != null && !primary.host && !primary.killed) {
      yield primary;
    }
    for (final client in _extraGameInstances) {
      if (!client.host && !client.killed) {
        yield client;
      }
    }
  }

  bool get _hasRunningGameClient => _runningGameClients().isNotEmpty;

  Set<String> _activeGameClientNames() {
    final names = <String>{};
    for (final client in _runningGameClients()) {
      names.add(client.clientName.toLowerCase());
    }
    return names;
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _setBackendConnectionType(BackendConnectionType type) async {
    if (_settings.backendConnectionType == type) return;
    if (type == BackendConnectionType.local &&
        _settings.profileUseEmailPasswordAuth) {
      if (mounted) _toast(_emailAuthRemoteBackendRequiredMessage);
      return;
    }
    setState(() {
      _settings = _settings.copyWith(
        backendConnectionType: type,
        backendHost: type == BackendConnectionType.local ? '127.0.0.1' : '',
      );
      _backendHostController.text = _effectiveBackendHost();
    });
    await _saveSettings(toast: false);
    await _refreshRuntime();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  void _log(String source, String message) {
    final now = DateTime.now();
    final line =
        '[${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}] [${source.toUpperCase()}] $message';
    // Never call setState here. During launch Fortnite can spew a lot of log
    // lines; rebuilding the entire UI for each line causes jank.
    _logs.addFirst(line);
    while (_logs.length > _maxLogLines) {
      _logs.removeLast();
    }

    if (_logFileReady) {
      _logWriteBuffer.writeln(line);
      _scheduleLogFlush();
    }
  }

  void _scheduleLogFlush() {
    if (_logFlushTimer != null) return;
    _logFlushTimer = Timer(const Duration(milliseconds: 250), () {
      _logFlushTimer = null;
      _flushLogBuffer();
    });
  }

  void _flushLogBuffer() {
    if (!_logFileReady) return;
    if (_logWriteBuffer.length == 0) return;

    final chunk = _logWriteBuffer.toString();
    _logWriteBuffer.clear();

    _logWriteChain = _logWriteChain.then((_) async {
      try {
        await _logFile.writeAsString(chunk, mode: FileMode.append);
      } catch (_) {
        // Ignore log write failures.
      }
    });
  }

  Future<void> _refreshRuntime({bool force = false}) async {
    if (!force && _deferNonCriticalRuntimeRefresh()) return;

    final inFlight = _runtimeRefreshInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final completer = Completer<void>();
    _runtimeRefreshInFlight = completer.future;
    try {
      final proxyOk = await _syncBackendProxy();
      if (!proxyOk) {
        if (mounted) {
          final wasOnline = _backendOnline;
          if (wasOnline) {
            setState(() => _backendOnline = false);
            _toastBackendUndetected();
          }
        }
        return;
      }

      final uri = Uri(
        scheme: 'http',
        host: _defaultBackendHost,
        port: _defaultBackendPort,
        path: 'unknown',
      );

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..autoUncompress = false;
      try {
        final req = await client.getUrl(uri);
        final res = await req.close();
        if (mounted) {
          final online = res.statusCode < 500;
          if (_backendOnline != online) {
            final wasOnline = _backendOnline;
            setState(() {
              // If we get a response and it's not a proxy error, treat it as online.
              _backendOnline = online;
            });
            if (wasOnline && !online) {
              _toastBackendUndetected();
            }
          }
        }
      } catch (_) {
        if (mounted) {
          final wasOnline = _backendOnline;
          if (wasOnline) {
            setState(() => _backendOnline = false);
            _toastBackendUndetected();
          }
        }
      } finally {
        client.close(force: true);
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _runtimeRefreshInFlight = null;
    }
  }

  void _toastBackendUndetected() {
    if (!mounted) return;

    final now = DateTime.now();
    final lastAt = _lastBackendUndetectedToastAt;
    if (lastAt != null && now.difference(lastAt).inSeconds < 10) {
      return;
    }
    _lastBackendUndetectedToastAt = now;

    final configured = '${_effectiveBackendHost()}:${_effectiveBackendPort()}';
    _toast('Backend undetected (configured: $configured)');
  }

  bool _backendProxyRequired() {
    if (_settings.backendConnectionType == BackendConnectionType.remote) {
      return true;
    }
    // Local backend not on the default port: proxy local 3551 -> local custom port.
    return _effectiveBackendPort() != _defaultBackendPort;
  }

  Future<bool> _syncBackendProxy() async {
    final inFlight = _backendProxySyncInFlight;
    if (inFlight != null) {
      await inFlight;
      return _backendProxyRequired()
          ? _backendProxyServer != null && _backendProxyTarget != null
          : true;
    }

    final completer = Completer<void>();
    _backendProxySyncInFlight = completer.future;
    try {
      if (!_backendProxyRequired()) {
        await _stopBackendProxy();
        return true;
      }

      final signature =
          '${_settings.backendConnectionType.name}|${_effectiveBackendHost()}|${_effectiveBackendPort()}';
      if (_backendProxyServer != null &&
          _backendProxyTarget != null &&
          _backendProxySignature == signature) {
        return true;
      }

      await _stopBackendProxy();

      final target = await _resolveBackendProxyTarget();
      if (target == null) {
        _log(
          'backend',
          'Backend unreachable: ${_effectiveBackendHost()}:${_effectiveBackendPort()}',
        );
        return false;
      }

      final server = await _bindBackendProxyServer();
      if (server == null) return false;

      _backendProxyClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..autoUncompress = false;
      _backendProxyServer = server;
      _backendProxyTarget = target;
      _backendProxySignature = signature;

      server.listen(
        (request) => unawaited(_handleBackendProxyRequest(request)),
        onError: (error, stackTrace) {
          _log('backend', 'Proxy server error: $error');
        },
      );

      _log(
        'backend',
        'Proxy started http://$_defaultBackendHost:$_defaultBackendPort -> $target',
      );
      return true;
    } finally {
      _backendProxySyncInFlight = null;
      completer.complete();
    }
  }

  Future<HttpServer?> _bindBackendProxyServer() async {
    Future<HttpServer?> tryBind() async {
      try {
        return await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          _defaultBackendPort,
        );
      } on SocketException {
        return null;
      }
    }

    var server = await tryBind();
    if (server != null) return server;

    // Reboot-style: free the default backend port and try again.
    await _killExistingProcessByPort(_defaultBackendPort);
    await Future.delayed(const Duration(milliseconds: 200));
    server = await tryBind();
    if (server == null) {
      _log(
        'backend',
        'Unable to bind backend proxy on port $_defaultBackendPort',
      );
      if (mounted) _toast('Port $_defaultBackendPort is already in use');
    }
    return server;
  }

  Future<Uri?> _resolveBackendProxyTarget() async {
    final host = _effectiveBackendHost().trim();
    final port = _effectiveBackendPort();

    if (_settings.backendConnectionType == BackendConnectionType.local) {
      return Uri(scheme: 'http', host: _defaultBackendHost, port: port);
    }

    if (host.isEmpty) return null;
    if (_isLocalHost(host)) return null;
    final ping = await _pingBackend(host, port);
    if (ping == null) return null;
    return Uri(scheme: ping.scheme, host: ping.host, port: ping.port);
  }

  bool _isLocalHost(String host) {
    final normalized = host
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^https://', caseSensitive: false), '')
        .split('/')
        .first;
    final bare = normalized.startsWith('[')
        ? normalized.split(']').first.replaceFirst('[', '')
        : normalized.split(':').first;
    return bare == 'localhost' ||
        bare == '0.0.0.0' ||
        bare == '::1' ||
        bare == '127.0.0.1' ||
        bare.startsWith('127.');
  }

  Future<Uri?> _pingBackend(String host, int port, [bool https = false]) async {
    final trimmed = host.trim();
    final hostName = trimmed
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^https://', caseSensitive: false), '');
    final declaredScheme = trimmed.toLowerCase().startsWith('http://')
        ? 'http'
        : trimmed.toLowerCase().startsWith('https://')
        ? 'https'
        : null;
    final uri = Uri(
      scheme: declaredScheme ?? (https ? 'https' : 'http'),
      host: hostName,
      port: port,
      path: 'unknown',
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..autoUncompress = false;
    try {
      final request = await client.getUrl(uri);
      await request.close().timeout(const Duration(seconds: 6));
      return uri;
    } catch (_) {
      if (https || declaredScheme != null || _isLocalHost(hostName)) {
        return null;
      }
      return _pingBackend(host, port, true);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _handleBackendProxyRequest(HttpRequest request) async {
    final targetBase = _backendProxyTarget;
    final client = _backendProxyClient;
    if (targetBase == null || client == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final targetUri = targetBase.replace(
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );

    try {
      final outbound = await client.openUrl(request.method, targetUri);
      outbound.followRedirects = false;

      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host' ||
            lower == 'content-length' ||
            lower == 'connection') {
          return;
        }
        for (final value in values) {
          outbound.headers.add(name, value);
        }
      });

      await outbound.addStream(request);
      final response = await outbound.close();

      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'transfer-encoding' || lower == 'connection') return;
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });

      await response.pipe(request.response);
    } catch (error) {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.write('Backend proxy error.');
      await request.response.close();
    }
  }

  Future<void> _stopBackendProxy() async {
    final server = _backendProxyServer;
    _backendProxyServer = null;
    _backendProxyTarget = null;
    _backendProxySignature = null;
    final client = _backendProxyClient;
    _backendProxyClient = null;
    client?.close(force: true);
    if (server != null) {
      try {
        await server.close(force: true);
        _log('backend', 'Proxy stopped.');
      } catch (_) {
        // Ignore.
      }
    }
  }

  Future<void> _handleRefreshPressed() async {
    await _refreshRuntime();
    await _checkForLauncherUpdates(silent: false);
    await _checkForBundledDllDefaultUpdates(silent: false);
  }

  Future<void> _checkForLauncherUpdates({required bool silent}) async {
    if (_checkingLauncherUpdate) return;
    if (_launcherUpdateDialogVisible) return;
    _checkingLauncherUpdate = true;
    try {
      final info = await LauncherUpdateService.checkForUpdate(
        currentVersion: _launcherVersion,
      );
      if (!mounted) return;
      if (info == null) {
        if (!silent) _toast('No updates available');
        return;
      }
      await _showLauncherUpdateDialog(info);
    } catch (_) {
      if (!mounted || silent) return;
      _toast('Unable to check for updates right now');
    } finally {
      _checkingLauncherUpdate = false;
    }
  }

  Widget _buildVersionTag(
    BuildContext context, {
    required String label,
    required Color accent,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.2),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onSurface.withValues(alpha: 0.96),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _versionLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'v0.0.0';
    return trimmed.toLowerCase().startsWith('v') ? trimmed : 'v$trimmed';
  }

  Future<void> _showLauncherNotesDialog({
    required String version,
    required String notes,
    String title = "What's New",
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogSurfaceColor(dialogContext),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _onSurface(dialogContext, 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: _dialogShadowColor(dialogContext),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded),
                            const SizedBox(width: 10),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                                color: _onSurface(dialogContext, 0.95),
                              ),
                            ),
                            const Spacer(),
                            _buildVersionTag(
                              dialogContext,
                              label: _versionLabel(version),
                              accent: const Color(0xFF16C47F),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: SingleChildScrollView(
                            child: MarkdownBody(
                              data: notes,
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(dialogContext),
                                  ).copyWith(
                                    p: TextStyle(
                                      color: _onSurface(dialogContext, 0.9),
                                      height: 1.35,
                                    ),
                                    horizontalRuleDecoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          width: 2.0,
                                          color: _onSurface(
                                            dialogContext,
                                            0.12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              onTapLink: (text, href, title) async {
                                if (href == null || href.trim().isEmpty) return;
                                await _openUrl(href);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAboutDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final secondary = Theme.of(dialogContext).colorScheme.secondary;
        Widget linkRow({required String label, required String url}) {
          final pretty = url
              .replaceFirst('https://', '')
              .replaceFirst('http://', '');
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                '$label:',
                style: TextStyle(
                  color: _onSurface(dialogContext, 0.86),
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: () => unawaited(_openUrl(url)),
                borderRadius: BorderRadius.circular(6),
                child: Text(
                  pretty,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: secondary,
                  ),
                ),
              ),
            ],
          );
        }

        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogSurfaceColor(dialogContext),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _onSurface(dialogContext, 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: _dialogShadowColor(dialogContext),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _adaptiveScrimColor(
                                  dialogContext,
                                  darkAlpha: 0.24,
                                  lightAlpha: 0.14,
                                ),
                                border: Border.all(
                                  color: _onSurface(dialogContext, 0.12),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Image.asset(
                                  'assets/images/atlas_logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'About',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: _onSurface(dialogContext, 0.96),
                              ),
                            ),
                            const Spacer(),
                            _buildVersionTag(
                              dialogContext,
                              label: _versionLabel(_launcherVersion),
                              accent: secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Made by cipher',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _onSurface(dialogContext, 0.96),
                          ),
                        ),
                        const SizedBox(height: 8),
                        linkRow(label: 'GitHub', url: _atlasLinkRepository),
                        const SizedBox(height: 6),
                        linkRow(label: 'Support', url: _atlasLinkDiscordInvite),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLatestLauncherUpdateNotes() async {
    final payload = await LauncherUpdateNotesService.loadNotes();
    if (!mounted) return;
    if (payload != null) {
      await _showLauncherNotesDialog(
        version: payload.version.isEmpty ? _launcherVersion : payload.version,
        notes: payload.notes,
      );
      return;
    }
    final release = await LauncherUpdateService.fetchLatestReleaseWithNotes();
    if (!mounted) return;
    if (release == null || (release.notes ?? '').trim().isEmpty) {
      _toast('No update notes found');
      return;
    }
    await _showLauncherNotesDialog(
      version: release.version,
      notes: release.notes!,
    );
  }

  Future<void> _showLauncherUpdateDialog(LauncherUpdateInfo info) async {
    if (_launcherUpdateDialogVisible) return;
    _launcherUpdateDialogVisible = true;
    try {
      final notes = info.notes?.trim() ?? '';
      var updating = false;
      var statusMessage = 'Preparing download...';
      double? progress;
      String? error;

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return SafeArea(
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    Future<void> startUpdate() async {
                      if (updating) return;
                      setDialogState(() {
                        updating = true;
                        error = null;
                        progress = null;
                        statusMessage = 'Preparing download...';
                      });

                      try {
                        await _downloadAndLaunchLauncherUpdate(
                          info,
                          onStatus: (message, nextProgress) {
                            if (!mounted) return;
                            setDialogState(() {
                              statusMessage = message;
                              progress = nextProgress;
                            });
                          },
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                      } catch (err) {
                        setDialogState(() {
                          error = 'Update failed: $err';
                          updating = false;
                          progress = null;
                        });
                      }
                    }

                    final showProgress = updating;
                    final progressValue = progress;
                    final isIndeterminate =
                        progressValue == null ||
                        progressValue <= 0 ||
                        progressValue >= 1;

                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _dialogSurfaceColor(dialogContext),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _onSurface(dialogContext, 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _dialogShadowColor(dialogContext),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update available',
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface(dialogContext, 0.95),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _buildVersionTag(
                                    dialogContext,
                                    label: _versionLabel(info.currentVersion),
                                    accent: const Color(0xFFDC3545),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'to',
                                    style: TextStyle(
                                      color: _onSurface(dialogContext, 0.7),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildVersionTag(
                                    dialogContext,
                                    label: _versionLabel(info.latestVersion),
                                    accent: const Color(0xFF16C47F),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: _adaptiveScrimColor(
                                    dialogContext,
                                    darkAlpha: 0.08,
                                    lightAlpha: 0.18,
                                  ),
                                  border: Border.all(
                                    color: _onSurface(dialogContext, 0.1),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: _onSurface(dialogContext, 0.82),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'ATLAS Link will download the latest setup and launch it. The launcher will close so the update can install.',
                                        style: TextStyle(
                                          color: _onSurface(
                                            dialogContext,
                                            0.78,
                                          ),
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 260,
                                  ),
                                  child: SingleChildScrollView(
                                    child: MarkdownBody(
                                      data: notes,
                                      styleSheet:
                                          MarkdownStyleSheet.fromTheme(
                                            Theme.of(dialogContext),
                                          ).copyWith(
                                            p: TextStyle(
                                              color: _onSurface(
                                                dialogContext,
                                                0.9,
                                              ),
                                              height: 1.35,
                                            ),
                                            horizontalRuleDecoration:
                                                BoxDecoration(
                                                  border: Border(
                                                    top: BorderSide(
                                                      width: 2.0,
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                          ),
                                      onTapLink: (text, href, title) async {
                                        if (href == null ||
                                            href.trim().isEmpty) {
                                          return;
                                        }
                                        await _openUrl(href);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                              if (showProgress) ...[
                                const SizedBox(height: 14),
                                LinearProgressIndicator(
                                  value: isIndeterminate ? null : progressValue,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  statusMessage,
                                  style: TextStyle(
                                    color: _onSurface(dialogContext, 0.82),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  error!,
                                  style: const TextStyle(
                                    color: Color(0xFFDC3545),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: updating
                                        ? null
                                        : () =>
                                              Navigator.of(dialogContext).pop(),
                                    child: const Text('Later'),
                                  ),
                                  const SizedBox(width: 8),
                                  if (notes.isNotEmpty)
                                    TextButton(
                                      onPressed: updating
                                          ? null
                                          : () async {
                                              Navigator.of(dialogContext).pop();
                                              if (!mounted) return;
                                              await _showLauncherNotesDialog(
                                                version: info.latestVersion,
                                                notes: notes,
                                              );
                                            },
                                      child: const Text('Update notes'),
                                    ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: updating ? null : startUpdate,
                                    child: Text(
                                      updating ? 'Updating...' : 'Update now',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3.2 * curved.value,
                          sigmaY: 3.2 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _launcherUpdateDialogVisible = false;
    }
  }

  Future<void> _downloadAndLaunchLauncherUpdate(
    LauncherUpdateInfo info, {
    required void Function(String message, double? progress) onStatus,
  }) async {
    final downloadUrl = info.downloadUrl.trim();
    if (downloadUrl.isEmpty) throw 'Update download URL unavailable.';

    if (!Platform.isWindows) {
      onStatus('Opening download page...', null);
      await _openUrl(downloadUrl);
      return;
    }

    final tempDir = _launcherUpdateInstallerDirectory();
    var keepInstallerFolder = false;
    var downloadedInstaller = false;
    onStatus('Preparing download...', null);
    try {
      // Avoid racing a previous cleanup attempt (for example right after an update
      // where the installer is still holding locks).
      if (_launcherUpdateInstallerCleanupWatcherActive) {
        onStatus('Cleaning previous installer cache...', null);
        for (
          var attempt = 0;
          attempt < 240 && _launcherUpdateInstallerCleanupWatcherActive;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      await tempDir.parent.create(recursive: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      final installerUrl = downloadUrl;
      final initialUri = Uri.tryParse(installerUrl);
      final initialLowerPath = (initialUri?.path ?? installerUrl).toLowerCase();
      var extension = initialLowerPath.endsWith('.msi')
          ? '.msi'
          : initialLowerPath.endsWith('.exe')
          ? '.exe'
          : '.exe';
      var installerFile = File(
        _joinPath([tempDir.path, 'atlas-link-setup$extension']),
      );

      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (attempt > 1) {
          onStatus(
            'Retrying download... (attempt $attempt/$maxAttempts)',
            null,
          );
        }
        try {
          await _downloadToFile(
            installerUrl,
            installerFile,
            onProgress: (receivedBytes, totalBytes) {
              if (totalBytes == null || totalBytes <= 0) {
                onStatus(
                  'Downloading installer... ${_formatByteSize(receivedBytes)}',
                  null,
                );
                return;
              }
              final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
              onStatus(
                'Downloading installer... ${_formatByteSize(receivedBytes)} / ${_formatByteSize(totalBytes)}',
                progress.toDouble(),
              );
            },
          );
          break;
        } catch (error) {
          _log('launcher', 'Update download attempt $attempt failed: $error');
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }

      final detectedExtension = await _detectWindowsInstallerExtension(
        installerFile,
      );
      if (detectedExtension == null) {
        throw 'Downloaded update is not a Windows installer.';
      }
      if (detectedExtension != extension) {
        _log(
          'launcher',
          'Installer type mismatch: expected $extension but detected $detectedExtension. Renaming.',
        );
        final corrected = File(
          _joinPath([tempDir.path, 'atlas-link-setup$detectedExtension']),
        );
        try {
          if (await corrected.exists()) await corrected.delete();
        } catch (_) {
          // Ignore pre-clean failures.
        }
        try {
          installerFile = await installerFile.rename(corrected.path);
          extension = detectedExtension;
        } catch (_) {
          try {
            await installerFile.copy(corrected.path);
            installerFile = corrected;
            extension = detectedExtension;
          } catch (_) {
            // Keep original file name; still use the detected type for launch.
            extension = detectedExtension;
          }
        }
      }

      downloadedInstaller = true;

      onStatus('Launching setup...', 1);
      _log('launcher', 'Launching update installer: ${installerFile.path}');

      if (extension == '.msi') {
        await Process.start(
          'msiexec',
          ['/i', installerFile.path],
          runInShell: true,
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(
          installerFile.path,
          const <String>[],
          runInShell: true,
          mode: ProcessStartMode.detached,
        );
      }

      keepInstallerFolder = true;

      // Best-effort cleanup helper; the cache is also cleared on next launch.
      await _spawnLauncherUpdateCleanupHelper(
        installerFilePath: installerFile.path,
        installerDirPath: tempDir.path,
      );

      exit(0);
    } catch (error) {
      if (!downloadedInstaller) {
        try {
          onStatus(
            'Unable to download installer. Opening download page...',
            null,
          );
          await _openUrl(downloadUrl);
          return;
        } catch (_) {
          // Ignore browser launch failures.
        }
      }
      rethrow;
    } finally {
      try {
        if (!keepInstallerFolder && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // Ignore cleanup failures.
      }
    }
  }

  Future<void> _spawnLauncherUpdateCleanupHelper({
    required String installerFilePath,
    required String installerDirPath,
  }) async {
    if (!Platform.isWindows) return;
    final installerPath = installerFilePath.trim();
    final dirPath = installerDirPath.trim();
    if (installerPath.isEmpty || dirPath.isEmpty) return;

    String psEscape(String value) => value.replaceAll("'", "''");

    final command =
        '''
\$ErrorActionPreference = 'SilentlyContinue'
\$installer = '${psEscape(installerPath)}'
\$dir = '${psEscape(dirPath)}'
for (\$i = 0; \$i -lt 180; \$i++) {
  try {
    if (Test-Path -LiteralPath \$installer) {
      Remove-Item -LiteralPath \$installer -Force -ErrorAction Stop
    }
  } catch {}
  try {
    if (Test-Path -LiteralPath \$dir) {
      Remove-Item -LiteralPath \$dir -Recurse -Force -ErrorAction Stop
    }
  } catch {}
  if (-not (Test-Path -LiteralPath \$installer) -and -not (Test-Path -LiteralPath \$dir)) { break }
  Start-Sleep -Seconds 5
}
''';

    final systemRoot = Platform.environment['SystemRoot'];
    final powershellExe = systemRoot == null || systemRoot.trim().isEmpty
        ? 'powershell'
        : _joinPath([
            systemRoot,
            'System32',
            'WindowsPowerShell',
            'v1.0',
            'powershell.exe',
          ]);

    try {
      await Process.start(
        powershellExe,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      _log('launcher', 'Failed to spawn update cleanup helper: $error');
    }
  }

  void _attachProcessLogs(
    Process process, {
    required String source,
    void Function(String line, bool isError)? onLine,
  }) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log(source, line);
          onLine?.call(line, false);
        });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log(source, line);
          onLine?.call(line, true);
        });
  }

  void _setUiStatus({
    required bool host,
    required String message,
    required _UiStatusSeverity severity,
  }) {
    final next = _UiStatus(message, severity);
    if (!mounted) {
      if (host) {
        _gameServerUiStatus = next;
      } else {
        _gameUiStatus = next;
      }
      return;
    }

    setState(() {
      if (host) {
        _gameServerUiStatus = next;
      } else {
        _gameUiStatus = next;
      }
    });

    _maybeToastLaunchStatus(host: host, status: next);
    _resetLaunchProgressPopupDismissalIfNeeded();

    if (host &&
        severity == _UiStatusSeverity.error &&
        message.trim() == 'Game server crashed.') {
      _gameServerCrashStatusClearTimer?.cancel();
      _gameServerCrashStatusClearTimer = Timer(const Duration(seconds: 8), () {
        if (!identical(_gameServerUiStatus, next)) return;
        _clearUiStatus(host: true);
      });
    }
  }

  void _clearUiStatus({required bool host}) {
    if (host ? _gameServerUiStatus == null : _gameUiStatus == null) return;
    if (!mounted) {
      if (host) {
        _gameServerUiStatus = null;
      } else {
        _gameUiStatus = null;
      }
      return;
    }

    setState(() {
      if (host) {
        _gameServerUiStatus = null;
      } else {
        _gameUiStatus = null;
      }
    });

    _resetLaunchProgressPopupDismissalIfNeeded();
  }

  void _clearStaleHostStoppedWarningOnNewSession() {
    if (_gameServerProcess != null) return;
    if (_gameServerLaunching) return;
    final status = _gameServerUiStatus;
    if (status == null) return;
    if (status.severity != _UiStatusSeverity.warning) return;

    final lower = status.message.toLowerCase();
    final isStoppedPrompt =
        lower.contains('stopped') && lower.contains('click host');
    if (!isStoppedPrompt) return;

    _clearUiStatus(host: true);
  }

  void _maybeToastLaunchStatus({
    required bool host,
    required _UiStatus status,
  }) {
    if (!mounted) return;
    if (!_launchProgressPopupDismissed) return;
    if (status.severity != _UiStatusSeverity.info) return;
    if (!_isLaunchInProgress()) return;

    final lower = status.message.toLowerCase();
    final isLaunchMessage =
        lower.contains('starting') ||
        lower.contains('launching') ||
        lower.contains('checking') ||
        lower.contains('waiting') ||
        lower.contains('inject') ||
        lower.contains('finalizing') ||
        lower.contains('preparing');
    if (!isLaunchMessage) return;

    final prefix = host ? 'Host' : 'Fortnite';
    final rawMessage = status.message.trim();
    final toastDetail = rawMessage.endsWith('.') && !rawMessage.endsWith('...')
        ? rawMessage.substring(0, rawMessage.length - 1)
        : rawMessage;
    final toastMessage = '$prefix: $toastDetail';
    if (toastMessage.trim().isEmpty) return;

    final now = DateTime.now();
    final last = _lastLaunchStatusToast;
    final lastAt = _lastLaunchStatusToastAt;
    if (last == toastMessage) return;
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 650) return;

    _lastLaunchStatusToast = toastMessage;
    _lastLaunchStatusToastAt = now;
    _toast(toastMessage);
  }

  void _resetLaunchProgressPopupDismissalIfNeeded() {
    if (!_launchProgressPopupDismissed) return;
    if (_isLaunchInProgress()) return;
    if (!mounted) {
      _launchProgressPopupDismissed = false;
    } else {
      setState(() => _launchProgressPopupDismissed = false);
    }
    _lastLaunchStatusToast = null;
    _lastLaunchStatusToastAt = null;
  }

  Color _statusAccentColor(BuildContext context, _UiStatusSeverity severity) {
    return switch (severity) {
      _UiStatusSeverity.success => const Color(0xFF16C47F),
      _UiStatusSeverity.warning => const Color(0xFFFFC107),
      _UiStatusSeverity.error => const Color(0xFFDC3545),
      _UiStatusSeverity.info => Theme.of(context).colorScheme.secondary,
    };
  }

  IconData _statusIcon(_UiStatusSeverity severity) {
    return switch (severity) {
      _UiStatusSeverity.success => Icons.check_circle_rounded,
      _UiStatusSeverity.warning => Icons.warning_amber_rounded,
      _UiStatusSeverity.error => Icons.error_outline_rounded,
      _UiStatusSeverity.info => Icons.info_outline_rounded,
    };
  }

  _UiStatus? _currentLibraryGameStatus() {
    final selected = _settings.selectedVersion;
    if (selected == null) return null;

    final running = _hasRunningGameClient;
    if (_gameAction == _GameActionState.launching) {
      return _gameUiStatus ??
          const _UiStatus('Launching...', _UiStatusSeverity.info);
    }
    if (_gameAction == _GameActionState.closing) {
      return _gameUiStatus ??
          const _UiStatus('Closing...', _UiStatusSeverity.info);
    }
    if (running) {
      if (_gameUiStatus != null) return _gameUiStatus;
      if (_runningGameClients().any((client) => client.launched)) {
        return const _UiStatus('Fortnite running', _UiStatusSeverity.success);
      }
      return const _UiStatus('Fortnite starting...', _UiStatusSeverity.info);
    }
    return _gameUiStatus;
  }

  _UiStatus? _currentLibraryGameServerStatus() {
    final running = _gameServerProcess != null;
    if (!running && _gameServerUiStatus == null) return null;

    if (running) {
      if (_gameServerUiStatus != null) return _gameServerUiStatus;
      if (_gameServerInstance?.launched == true) {
        return const _UiStatus('Running', _UiStatusSeverity.success);
      }
      return const _UiStatus('Starting...', _UiStatusSeverity.info);
    }

    return _gameServerUiStatus;
  }

  Widget _buildLibraryGameStatusLine() {
    if (_isLaunchInProgress()) {
      return const SizedBox.shrink();
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Show the most relevant status while launching. When both Fortnite and the
    // game server are active, show both during action phases so injections
    // (like Large Pak Patcher) are visible.
    final gameStatus = _currentLibraryGameStatus();
    final serverStatus = _currentLibraryGameServerStatus();

    String cleanLabeledMessage({
      required String label,
      required String message,
    }) {
      var text = message.trim();
      if (text.isEmpty) return text;

      final labelLower = label.toLowerCase();
      var lower = text.toLowerCase();

      // When the label is already shown, avoid repeating it in the message.
      if (lower.startsWith(labelLower)) {
        text = text.substring(label.length).trimLeft();
        text = text.replaceFirst(RegExp(r'^[:\-\s]+'), '');
        lower = text.toLowerCase();
      }

      if (labelLower == 'fortnite' &&
          (lower.startsWith('starting fortnite') ||
              lower.startsWith('fortnite starting'))) {
        return 'Starting...';
      }
      if (labelLower == 'host' &&
          (lower.startsWith('starting host') ||
              lower.startsWith('host starting') ||
              lower.startsWith('starting game server') ||
              lower.startsWith('game server starting'))) {
        return 'Starting...';
      }

      // Sentence-case when we stripped a leading label.
      if (text.isNotEmpty && RegExp(r'^[a-z]').hasMatch(text)) {
        text = '${text[0].toUpperCase()}${text.substring(1)}';
      }

      if (text.endsWith('.') && !text.endsWith('...')) {
        text = text.substring(0, text.length - 1).trimRight();
      }

      final actionLower = text.toLowerCase();
      final isAction =
          actionLower.contains('inject') ||
          actionLower.contains('starting') ||
          actionLower.contains('launching') ||
          actionLower.contains('preparing') ||
          actionLower.contains('waiting');
      if (isAction && !text.endsWith('...')) {
        text = '$text...';
      }
      return text;
    }

    bool showGame(_UiStatus status) {
      return switch (status.severity) {
        _UiStatusSeverity.error || _UiStatusSeverity.warning => true,
        _UiStatusSeverity.info =>
          _gameAction != _GameActionState.idle || _hasRunningGameClient,
        _UiStatusSeverity.success => _hasRunningGameClient,
      };
    }

    bool showServer(_UiStatus status) {
      return switch (status.severity) {
        _UiStatusSeverity.error || _UiStatusSeverity.warning => true,
        _UiStatusSeverity.info =>
          _gameServerLaunching || _gameServerProcess != null,
        _UiStatusSeverity.success => _gameServerProcess != null,
      };
    }

    int severityRank(_UiStatusSeverity severity) {
      return switch (severity) {
        _UiStatusSeverity.error => 3,
        _UiStatusSeverity.warning => 2,
        _UiStatusSeverity.info => 1,
        _UiStatusSeverity.success => 0,
      };
    }

    final showGameLine =
        gameStatus != null &&
        gameStatus.message.trim().isNotEmpty &&
        showGame(gameStatus);
    final showServerLine =
        serverStatus != null &&
        serverStatus.message.trim().isNotEmpty &&
        showServer(serverStatus);
    if (!showGameLine && !showServerLine) return const SizedBox.shrink();

    String formatStatusLine() {
      if (showGameLine && showServerLine) {
        final gameText = cleanLabeledMessage(
          label: 'Fortnite',
          message: gameStatus.message,
        );
        final serverText = cleanLabeledMessage(
          label: 'Host',
          message: serverStatus.message,
        );
        return 'Fortnite: $gameText\nHost: $serverText';
      }
      if (showServerLine) {
        final serverText = cleanLabeledMessage(
          label: 'Host',
          message: serverStatus.message,
        );
        return 'Host: $serverText';
      }
      final gameText = cleanLabeledMessage(
        label: 'Fortnite',
        message: gameStatus!.message,
      );
      return 'Fortnite: $gameText';
    }

    _UiStatusSeverity worstSeverity() {
      final severities = <_UiStatusSeverity>[
        if (showGameLine) gameStatus.severity,
        if (showServerLine) serverStatus.severity,
      ];
      return severities.reduce((a, b) {
        return severityRank(a) >= severityRank(b) ? a : b;
      });
    }

    final worst = worstSeverity();
    final accent = _statusAccentColor(context, worst);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: onSurface.withValues(alpha: 0.06),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_statusIcon(worst), size: 18, color: accent),
              const SizedBox(width: 10),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  formatStatusLine(),
                  maxLines: showGameLine && showServerLine ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isLaunchInProgress() {
    if (!_startupConfigResolved || _showStartup) return false;

    bool isLaunchMessage(_UiStatus status) {
      if (status.severity != _UiStatusSeverity.info) return false;
      final lower = status.message.toLowerCase();
      if (lower.isEmpty) return false;
      if (lower.contains('closing') || lower.contains('stopping')) return false;
      return lower.contains('starting') ||
          lower.contains('launching') ||
          lower.contains('checking') ||
          lower.contains('waiting') ||
          lower.contains('inject') ||
          lower.contains('finalizing') ||
          lower.contains('preparing');
    }

    final gameStatus = _currentLibraryGameStatus();
    final hostStatus = _currentLibraryGameServerStatus();
    final showGame = gameStatus != null && isLaunchMessage(gameStatus);
    final showHost = hostStatus != null && isLaunchMessage(hostStatus);
    return showGame || showHost;
  }

  bool _shouldShowLaunchProgressPopup() {
    if (_launchProgressPopupDismissed) return false;
    if (_gameServerPromptVisible) return false;
    if (_gameServerPromptRequiredForLaunch &&
        !_gameServerPromptResolvedForLaunch) {
      return false;
    }
    return _isLaunchInProgress();
  }

  String _launchPopupLine({required String label, required String message}) {
    var text = message.trim();
    if (text.isEmpty) return '';
    if (text.endsWith('.') && !text.endsWith('...')) {
      text = text.substring(0, text.length - 1).trimRight();
    }
    return '$label: $text';
  }

  Widget _buildLaunchProgressPopup() {
    final selected = _settings.selectedVersion;
    final cover = _libraryCoverImage(selected);
    final title = selected?.name.trim().isNotEmpty == true
        ? selected!.name.trim()
        : 'Launching';
    final subtitle = selected?.gameVersion.trim().isNotEmpty == true
        ? selected!.gameVersion.trim()
        : '';

    final gameStatus = _currentLibraryGameStatus();
    final hostStatus = _currentLibraryGameServerStatus();
    final lines = <String>[
      if (hostStatus != null)
        _launchPopupLine(label: 'Host', message: hostStatus.message),
      if (gameStatus != null)
        _launchPopupLine(label: 'Fortnite', message: gameStatus.message),
    ].where((line) => line.trim().isNotEmpty).toList();

    final statusText = lines.isEmpty ? 'Working...' : lines.join('\n');

    return Stack(
      children: [
        Positioned.fill(
          child: AbsorbPointer(
            child: _settings.popupBackgroundBlurEnabled
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                    child: Container(color: _dialogBarrierColor(context, 1.0)),
                  )
                : Container(color: _dialogBarrierColor(context, 1.0)),
          ),
        ),
        Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: _dialogSurfaceColor(context),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _onSurface(context, 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: _dialogShadowColor(context),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image(
                          image: cover,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _onSurface(context, 0.94),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _onSurface(context, 0.70),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          setState(() => _launchProgressPopupDismissed = true);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: _onSurface(context, 0.70),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: _onSurface(context, 0.05),
                      border: Border.all(color: _onSurface(context, 0.10)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: _onSurface(context, 0.88),
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: null,
                      minHeight: 6,
                      backgroundColor: _onSurface(context, 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isLoginCompleteSignal(String line) {
    final lower = line.toLowerCase();

    // Most reliable marker across builds.
    if (lower.contains(_loginContinueMarker.toLowerCase()) &&
        lower.contains(_loginCompleteStepMarker.toLowerCase()) &&
        lower.contains(_loginCompletedMarker.toLowerCase())) {
      return true;
    }

    // Fallback marker some builds emit immediately after finishing login.
    if (lower.contains(_loginUiStateTransitionMarker.toLowerCase())) {
      return true;
    }

    return false;
  }

  /// Markers that indicate the client loading screen has completed.
  /// Multiple markers increase chances of catching game fully loaded in various versions.
  static const List<String> _clientLoadingCompleteMarkers = [
    'UI.State.Startup.SubgameSelect',
    'LobbyUI',
    'Lobby',
    'UI.State.Lobby',
    'Started Application',
    'Foreground',
    'UGameEngine::Tick',
    'World changed',
    'Engine',
  ];

  void _handleFortniteOutput(_FortniteProcessState state, String line) {
    if (state.killed || state.exited) return;

    if (!state.launched) {
      if (_cannotConnectErrors.any(line.contains)) {
        state.tokenError = true;
      }
      if (_corruptedBuildErrors.any(line.contains)) {
        state.corrupted = true;
      }
    }

    if (!state.postLoginInjected && _isLoginCompleteSignal(line)) {
      state.launched = true;
      state.postLoginInjected = true;
      state.postLoginInferredFromFallback = false;
      _log(
        state.host ? 'gameserver' : 'game',
        'Login complete detected. Scheduling post-login injections...',
      );
      _setUiStatus(
        host: state.host,
        message: state.host
            ? 'Logged in. Waiting for host to finish loading...'
            : 'Logged in. Finalizing launch...',
        severity: _UiStatusSeverity.info,
      );
      unawaited(_performPostLoginInjections(state));
    }

    // Inject the large pak patcher for the client after the loading screen.
    if (!state.host &&
        !state.largePakInjected &&
        state.postLoginInjected &&
        _clientLoadingCompleteMarkers.any(line.contains)) {
      state.largePakInjected = true;
      _log('game', 'Client fully loaded. Scheduling large pak injection...');
      unawaited(_performDeferredLargePakInjection(state));
    }

    // For hosting, delay the game server DLL injection until the lobby marker.
    if (state.host &&
        state.postLoginInjected &&
        state.hostPostLoginPatchersInjected &&
        !state.gameServerInjected &&
        !state.gameServerInjectionScheduled &&
        _clientLoadingCompleteMarkers.any(line.contains)) {
      state.gameServerInjectionScheduled = true;
      _log(
        'gameserver',
        'Host fully loaded. Scheduling game server DLL injection...',
      );
      unawaited(_performDeferredGameServerInjection(state));
    }
  }

  int _calculateExponentialBackoffMs(
    int attempt,
    int baseDelayMs,
    int maxDelayMs,
  ) {
    // Calculate delay: baseDelay * (2 ^ (attempt - 2)) with jitter, capped at maxDelay
    // attempt 2: baseDelay, attempt 3: baseDelay * 2, attempt 4: baseDelay * 4, etc.
    final exponentialDelay = baseDelayMs * (1 << (attempt - 2));
    final cappedDelay = exponentialDelay > maxDelayMs
        ? maxDelayMs
        : exponentialDelay;
    // Add ±10% random jitter to prevent thundering herd
    final jitter = (cappedDelay * 0.1 * (_rng.nextDouble() * 2 - 1)).toInt();
    return (cappedDelay + jitter).clamp(0, maxDelayMs);
  }

  Future<void> _performPostLoginInjections(_FortniteProcessState state) async {
    // Optimized for low-end PCs: reduced from 900ms to 300ms to start injections faster
    // while still giving the client time to initialize.
    await Future.delayed(
      const Duration(milliseconds: _postLoginInjectionDelayMs),
    );
    if (state.killed || state.exited) return;

    if (state.host) {
      final inferredFallbackLogin = state.postLoginInferredFromFallback;

      // For the host, inject post-login patchers and then schedule the game
      // server DLL injection. If login was only inferred via fallback (no real
      // login marker), skip memory.dll to avoid early-load access violations.
      if (inferredFallbackLogin) {
        _log(
          'gameserver',
          'Using safe fallback host flow: skipping memory patcher until stable login markers.',
        );
      }
      _setUiStatus(
        host: true,
        message: 'Injecting post-login patchers...',
        severity: _UiStatusSeverity.info,
      );
      await Future<void>.delayed(
        const Duration(milliseconds: _uiStatusDelayMs),
      );

      final report = await _injectConfiguredPatchers(
        state.pid,
        state.gameVersion,
        includeAuth: false,
        includeMemory: !inferredFallbackLogin,
        includeLargePak: false,
        includeUnreal: false,
        includeGameServer: false,
      );

      final failure = report.firstRequiredFailure;
      if (failure != null) {
        _setUiStatus(
          host: true,
          message: 'Failed to inject ${failure.name}.',
          severity: _UiStatusSeverity.error,
        );
        return;
      }
      await _killExistingProcessByPort(
        _effectiveGameServerPort(),
        exceptPid: state.pid,
      );

      state.hostPostLoginPatchersInjected = true;
      _setUiStatus(
        host: true,
        message: 'Logged in. Waiting for host to finish loading...',
        severity: _UiStatusSeverity.info,
      );
      unawaited(_scheduleHostFallbackGameServerInjection(state));
    } else {
      _setUiStatus(
        host: false,
        message: 'Injecting launch patchers...',
        severity: _UiStatusSeverity.info,
      );
      await Future<void>.delayed(
        const Duration(milliseconds: _uiStatusDelayMs),
      );

      final report = await _injectConfiguredPatchers(
        state.pid,
        state.gameVersion,
        includeAuth: false,
        includeMemory: true,
        includeUnreal: true,
        includeGameServer: false,
      );

      final requiredFailure = report.firstRequiredFailure;
      if (requiredFailure != null) {
        _setUiStatus(
          host: false,
          message: 'Failed to inject ${requiredFailure.name}.',
          severity: _UiStatusSeverity.error,
        );
        return;
      }
      // Large Pak normally injects on a specific loading-complete marker.
      // In some game-server launch flows that marker may be delayed/missing,
      // so schedule a fallback attempt after post-login setup.
      unawaited(_scheduleLargePakFallbackInjection(state));

      final optionalFailure = report.firstOptionalFailure;
      if (optionalFailure != null) {
        _setUiStatus(
          host: false,
          message:
              'Fortnite running (optional patcher issue: ${optionalFailure.name}).',
          severity: _UiStatusSeverity.warning,
        );
        return;
      }

      _setUiStatus(
        host: false,
        message: 'Fortnite running.',
        severity: _UiStatusSeverity.success,
      );
    }
  }

  Future<void> _performDeferredLargePakInjection(
    _FortniteProcessState state,
  ) async {
    if (state.killed || state.exited || !_settings.largePakPatcherEnabled) {
      return;
    }

    // Give the frontend a moment to settle after the loading screen.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (state.killed || state.exited) return;

    _setUiStatus(
      host: false,
      message: 'Injecting large pak patcher...',
      severity: _UiStatusSeverity.info,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final report = await _injectConfiguredPatchers(
      state.pid,
      state.gameVersion,
      includeAuth: false,
      includeMemory: false,
      includeLargePak: true,
      includeUnreal: false,
      includeGameServer: false,
    );

    final optionalFailure = report.firstOptionalFailure;
    if (optionalFailure != null) {
      _setUiStatus(
        host: false,
        message:
            'Fortnite running (optional patcher issue: ${optionalFailure.name}).',
        severity: _UiStatusSeverity.warning,
      );
      return;
    }

    _setUiStatus(
      host: false,
      message: 'Fortnite running.',
      severity: _UiStatusSeverity.success,
    );
  }

  Future<void> _scheduleLargePakFallbackInjection(
    _FortniteProcessState state,
  ) async {
    if (state.host || !_settings.largePakPatcherEnabled) return;

    await Future<void>.delayed(const Duration(seconds: 8));
    if (state.killed || state.exited || state.largePakInjected) return;
    if (!state.postLoginInjected) return;

    state.largePakInjected = true;
    _log(
      'game',
      'Client loading marker not seen in time. Running fallback large pak injection...',
    );
    await _performDeferredLargePakInjection(state);
  }

  Future<void> _performDeferredGameServerInjection(
    _FortniteProcessState state,
  ) async {
    if (!state.host) return;
    if (state.killed || state.exited) return;
    if (state.gameServerInjected) return;

    // Give the lobby/subgame UI a moment to settle.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (state.killed || state.exited) return;
    if (state.gameServerInjected) return;

    _setUiStatus(
      host: true,
      message: 'Injecting game server DLL...',
      severity: _UiStatusSeverity.info,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final serverReport = await _injectConfiguredPatchers(
      state.pid,
      state.gameVersion,
      includeAuth: false,
      includeMemory: false,
      includeLargePak: false,
      includeUnreal: false,
      includeGameServer: true,
    );

    final serverFailure = serverReport.firstRequiredFailure;
    if (serverFailure != null) {
      state.gameServerInjectionScheduled = false;
      _setUiStatus(
        host: true,
        message: 'Failed to inject ${serverFailure.name}.',
        severity: _UiStatusSeverity.error,
      );
      return;
    }

    state.gameServerInjected = true;
    _setUiStatus(
      host: true,
      message: 'Running.',
      severity: _UiStatusSeverity.success,
    );
  }

  Future<void> _scheduleHostFallbackGameServerInjection(
    _FortniteProcessState state,
  ) async {
    if (!state.host) return;
    if (state.killed || state.exited) return;
    if (state.gameServerInjected || state.gameServerInjectionScheduled) return;

    // Some builds never emit the lobby UI marker. As a fallback, attempt the
    // server DLL injection after a short delay once post-login patchers ran.
    await Future<void>.delayed(const Duration(seconds: 16));
    if (state.killed || state.exited) return;
    if (!state.hostPostLoginPatchersInjected) return;
    if (state.gameServerInjected || state.gameServerInjectionScheduled) return;

    state.gameServerInjectionScheduled = true;
    _log(
      'gameserver',
      'Host loading marker not seen. Running fallback game server DLL injection...',
    );
    unawaited(_performDeferredGameServerInjection(state));
  }

  Future<void> _killExistingProcessByPort(int port, {int? exceptPid}) async {
    if (!Platform.isWindows) return;
    final pids = <int>{};
    try {
      final result = await Process.run('netstat', ['-ano'], runInShell: true);
      final output = '${result.stdout}\n${result.stderr}';
      final lines = output.split(RegExp(r'\r?\n'));
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (!line.startsWith('TCP')) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 5) continue;
        final localAddress = parts[1];
        final state = parts[3];
        final pidRaw = parts[4];
        if (state.toUpperCase() != 'LISTENING') continue;
        if (!localAddress.endsWith(':$port')) continue;
        final pid = int.tryParse(pidRaw);
        if (pid == null) continue;
        if (exceptPid != null && pid == exceptPid) continue;
        pids.add(pid);
      }
    } catch (_) {
      return;
    }

    for (final pid in pids) {
      try {
        await Process.run('taskkill', [
          '/F',
          '/PID',
          pid.toString(),
        ], runInShell: true);
        _log(
          'gameserver',
          'Killed process listening on port $port (pid $pid).',
        );
      } catch (_) {
        // Ignore processes we can't terminate.
      }
    }
  }

  void _handleFortniteExit(_FortniteProcessState state, int exitCode) {
    state.exited = true;
    state.killAuxiliary();
    if (!state.host && state.child != null) {
      // Back-compat: older sessions used the child link to decide when to stop
      // automatic hosting. Preserve that behavior by marking hosting as
      // session-linked.
      _stopHostingWhenNoClientsRemain = true;
    }

    if (state.host) {
      if (_gameServerProcess?.pid == state.pid) _gameServerProcess = null;
      if (identical(_gameServerInstance, state)) _gameServerInstance = null;
    } else {
      _extraGameInstances.removeWhere(
        (entry) => identical(entry, state) || entry.pid == state.pid,
      );
      if (_gameProcess?.pid == state.pid) _gameProcess = null;
      if (identical(_gameInstance, state)) {
        _gameInstance = _extraGameInstances.isNotEmpty
            ? _extraGameInstances.removeAt(0)
            : null;
      }
    }

    final tag = state.host ? 'gameserver' : 'game';
    _log(
      tag,
      'Fortnite exited with code $exitCode '
      '(killed=${state.killed}, launched=${state.launched}, '
      'postLoginInjected=${state.postLoginInjected}, '
      'hostPostLoginPatchersInjected=${state.hostPostLoginPatchersInjected}, '
      'gameServerInjected=${state.gameServerInjected}).',
    );

    if (!state.host) {
      // If hosting was started for this session, stop it only once every client
      // has exited (multi-launch can have more than one client alive).
      unawaited(_stopSessionLinkedHostingIfNeeded());
    }

    if (state.host && !state.killed && _settings.hostAutoRestartEnabled) {
      _setUiStatus(
        host: true,
        message: 'Stopped. Restarting...',
        severity: _UiStatusSeverity.info,
      );
      _syncLauncherDiscordPresence();
      unawaited(_autoRestartHosting(state.versionId));
      return;
    }

    if (state.host && !state.killed && exitCode == 0 && state.launched) {
      if (mounted) _toast('Host stopped');
      _setUiStatus(
        host: true,
        message: 'Stopped. Click Host to start again.',
        severity: _UiStatusSeverity.warning,
      );
      _syncLauncherDiscordPresence();
      unawaited(_restoreOriginalDiscordRpcDllAcrossBuildsIfIdle());
      return;
    }

    final crashed = !state.killed && (exitCode != 0 || !state.launched);
    if (crashed) {
      final message = state.tokenError
          ? 'Unable to connect to the backend'
          : state.corrupted
          ? 'This build looks corrupted (see launcher.log)'
          : state.host
          ? 'Game server crashed'
          : 'Fortnite crashed';
      if (mounted) _toast(message);
      _setUiStatus(
        host: state.host,
        message: message,
        severity: _UiStatusSeverity.error,
      );
    } else {
      _clearUiStatus(host: state.host);
    }

    _syncLauncherDiscordPresence();
    unawaited(_restoreOriginalDiscordRpcDllAcrossBuildsIfIdle());
  }

  Future<void> _stopSessionLinkedHostingIfNeeded() async {
    if (!_stopHostingWhenNoClientsRemain) return;
    if (_hasRunningGameClient) return;
    if (_stoppingSessionLinkedHosting) return;

    final instance = _gameServerInstance;
    final process = _gameServerProcess;
    if (instance == null && process == null) {
      _stopHostingWhenNoClientsRemain = false;
      return;
    }

    _stoppingSessionLinkedHosting = true;
    try {
      _setUiStatus(
        host: true,
        message: 'Stopping game server...',
        severity: _UiStatusSeverity.info,
      );

      final pids = <int>{
        if (instance != null) instance.pid,
        if (instance?.launcherPid != null) instance!.launcherPid!,
        if (instance?.eacPid != null) instance!.eacPid!,
        if (process != null) process.pid,
      };

      if (instance != null) {
        instance.killAll();
      } else if (process != null) {
        _FortniteProcessState._killPidSafe(process.pid);
      }

      for (final pid in pids) {
        try {
          await Process.run('taskkill', [
            '/F',
            '/PID',
            '$pid',
          ], runInShell: true);
        } catch (_) {
          // Ignore already-closed processes.
        }
      }

      _gameServerInstance = null;
      _gameServerProcess = null;
      _stopHostingWhenNoClientsRemain = false;
      _clearUiStatus(host: true);
      _log('gameserver', 'Session-linked hosting stopped (no clients remain).');
      _syncLauncherDiscordPresence();
      unawaited(_restoreOriginalDiscordRpcDllAcrossBuildsIfIdle());
    } finally {
      _stoppingSessionLinkedHosting = false;
    }
  }

  Future<void> _autoRestartHosting(String versionId) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (_gameServerProcess != null || _gameServerLaunching) return;
    if (!_settings.hostAutoRestartEnabled) return;
    final version = _findVersionById(versionId);
    if (version == null) {
      _setUiStatus(
        host: true,
        message: 'Auto restart skipped: build no longer exists.',
        severity: _UiStatusSeverity.warning,
      );
      return;
    }
    await _startHosting(overrideVersion: version, triggeredByAutoRestart: true);
  }

  Future<bool> _ensureBackendReadyForSession({
    required bool host,
    bool toastOnFailure = true,
  }) async {
    final backendValidationError = _emailPasswordBackendValidationError();
    if (backendValidationError != null) {
      if (toastOnFailure && mounted) _toast(backendValidationError);
      _setUiStatus(
        host: host,
        message: backendValidationError,
        severity: _UiStatusSeverity.error,
      );
      return false;
    }

    if (_backendOnline) return true;

    _toastBackendCheckingDuringLaunch(host: host);

    _setUiStatus(
      host: host,
      message: 'Checking backend connection...',
      severity: _UiStatusSeverity.info,
    );
    await _refreshRuntime();
    if (_backendOnline) return true;

    final shouldLaunchManagedBackend =
        _settings.launchBackendOnSessionStart &&
        _settings.backendConnectionType == BackendConnectionType.local &&
        Platform.isWindows;
    if (shouldLaunchManagedBackend) {
      _setUiStatus(
        host: host,
        message: 'Launching ATLAS Backend...',
        severity: _UiStatusSeverity.info,
      );
      await _launchManagedAtlasBackend();
      if (!mounted) return false;

      // Give the backend time to bind/listen before proceeding to game processes.
      const attempts = 18;
      for (var attempt = 0; attempt < attempts; attempt++) {
        await _refreshRuntime();
        if (_backendOnline) return true;
        if (!mounted) return false;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    final msg =
        'No backend found on ${_effectiveBackendHost()}:${_effectiveBackendPort()}';
    if (toastOnFailure && mounted) _toast(msg);
    _setUiStatus(host: host, message: msg, severity: _UiStatusSeverity.error);
    return false;
  }

  void _toastBackendCheckingDuringLaunch({required bool host}) {
    if (!mounted) return;

    // Only toast this during a launch/host-start flow.
    final launching =
        _gameAction == _GameActionState.launching || _gameServerLaunching;
    if (!launching) return;

    // The game server prompt happens before the actual launch steps. Toasting
    // here helps the user understand why Launch may be waiting.
    final now = DateTime.now();
    final lastAt = _lastBackendCheckingToastAt;
    if (lastAt != null && now.difference(lastAt).inSeconds < 6) {
      return;
    }
    _lastBackendCheckingToastAt = now;

    final prefix = host ? 'Host' : 'Fortnite';
    _toast('$prefix: Checking backend connection...');
  }

  Future<void> _startFortnite({
    String? usernameOverride,
    bool launchingAdditionalClient = false,
  }) async {
    if (_gameAction != _GameActionState.idle) return;
    final version = _settings.selectedVersion;
    if (version == null) {
      _toast('Import and select a version first');
      return;
    }
    if (!Platform.isWindows) {
      _toast('Fortnite launch is only available on Windows');
      return;
    }

    _FortniteProcessState? linkedHosting;
    _clearStaleHostStoppedWarningOnNewSession();
    setState(() => _gameAction = _GameActionState.launching);
    _syncLauncherDiscordPresence();
    try {
      final shouldOfferPrompt =
          !launchingAdditionalClient && _shouldOfferGameServerPrompt();
      if (mounted) {
        setState(() {
          _gameServerPromptRequiredForLaunch = shouldOfferPrompt;
          _gameServerPromptResolvedForLaunch = !shouldOfferPrompt;
          _gameServerPromptVisible = false;
        });
      } else {
        _gameServerPromptRequiredForLaunch = shouldOfferPrompt;
        _gameServerPromptResolvedForLaunch = !shouldOfferPrompt;
        _gameServerPromptVisible = false;
      }

      _setUiStatus(
        host: false,
        message: 'Preparing launch...',
        severity: _UiStatusSeverity.info,
      );
      final exe = await _resolveExecutable(version);
      if (exe == null) {
        _toast('Fortnite executable not found for selected version');
        return;
      }
      final exeDir = File(exe).parent.path;

      final backendReady = await _ensureBackendReadyForSession(host: false);
      if (!backendReady) return;
      _setUiStatus(
        host: false,
        message: 'Syncing Discord RPC override...',
        severity: _UiStatusSeverity.info,
      );
      await _syncCustomDiscordRpcDllForBuild(version);
      _GameServerPromptAction? gameServerPrompt;
      if (shouldOfferPrompt) {
        if (mounted) {
          setState(() => _gameServerPromptVisible = true);
        } else {
          _gameServerPromptVisible = true;
        }
        try {
          gameServerPrompt = await _promptAutomaticGameServerStart();
        } finally {
          if (mounted) {
            setState(() {
              _gameServerPromptVisible = false;
              _gameServerPromptResolvedForLaunch = true;
            });
          } else {
            _gameServerPromptVisible = false;
            _gameServerPromptResolvedForLaunch = true;
          }
        }
      } else {
        gameServerPrompt = _GameServerPromptAction.ignore;
      }
      if (!mounted) return;
      if (gameServerPrompt == null) {
        _log('game', 'Launch cancelled at game server prompt.');
        if (mounted) _toast('Launch cancelled');
        _clearUiStatus(host: false);
        return;
      }
      if (gameServerPrompt == _GameServerPromptAction.start) {
        if (mounted) {
          setState(() => _gameServerLaunching = true);
        } else {
          _gameServerLaunching = true;
        }
        _setUiStatus(
          host: true,
          message: 'Starting game server...',
          severity: _UiStatusSeverity.info,
        );
        linkedHosting = await _startImplicitGameServer(
          version,
          syncDiscordRpc: false,
        );
        if (!mounted) return;
        setState(() => _gameServerLaunching = false);
        if (linkedHosting != null) {
          _stopHostingWhenNoClientsRemain = true;
          _log(
            'gameserver',
            'Session-linked hosting enabled (will stop when all clients close).',
          );
        } else {
          _stopHostingWhenNoClientsRemain = false;
        }
        if (linkedHosting == null) {
          _setUiStatus(
            host: true,
            message: 'Failed to start game server.',
            severity: _UiStatusSeverity.warning,
          );
        }
      }

      _setUiStatus(
        host: false,
        message: 'Preparing build...',
        severity: _UiStatusSeverity.info,
      );
      final requestedClientName = usernameOverride ?? _settings.username;
      final launchAuth = _resolveLaunchAuthCredentials(
        username: requestedClientName,
        host: false,
      );
      if (launchAuth == null) return;
      final playCustomArgs = _settings.playCustomLaunchArgs;
      final playLaunchTokens = _resolveLaunchSessionTokens(
        customArgs: playCustomArgs,
      );
      final playTokenValidationError = _validateLaunchSessionTokens(
        playLaunchTokens,
      );
      if (playTokenValidationError != null) {
        _log(
          'game',
          'Launch token validation failed: $playTokenValidationError',
        );
        _setUiStatus(
          host: false,
          message: playTokenValidationError,
          severity: _UiStatusSeverity.error,
        );
        if (mounted) _toast(playTokenValidationError);
        return;
      }
      final launchClientName = _normalizeClientUsername(requestedClientName);

      await _deleteAftermathCrashDlls(version.location);
      final launcherPid = await _startPausedAuxiliaryProcess(
        version.location,
        _launcherExeName,
        hintDir: exeDir,
      );
      final eacPid = await _startPausedAuxiliaryProcess(
        version.location,
        _eacExeName,
        hintDir: exeDir,
      );

      final backendHost = _effectiveBackendHostForLaunchArgs();
      final backendPort = _effectiveBackendPort();
      final args =
          _createRebootLaunchArgs(
              username: launchAuth.login,
              password: launchAuth.password,
              launchTokens: playLaunchTokens,
              customArgs: playCustomArgs,
            )
            ..add('-BackendHost=$backendHost')
            ..add('-BackendPort=$backendPort');

      _log(
        'game',
        'Starting with args: ${_redactSensitiveLaunchArgs(args).join(' ')}',
      );

      Process child;
      try {
        _setUiStatus(
          host: false,
          message: 'Starting Fortnite...',
          severity: _UiStatusSeverity.info,
        );
        child = await Process.start(
          exe,
          args,
          workingDirectory: File(exe).parent.path,
          environment: {
            ...Platform.environment,
            'OPENSSL_ia32cap': '~0x20000000',
          },
        );
      } catch (error) {
        if (launcherPid != null) {
          _FortniteProcessState._killPidSafe(launcherPid);
        }
        if (eacPid != null) {
          _FortniteProcessState._killPidSafe(eacPid);
        }
        rethrow;
      }

      final instance = _FortniteProcessState(
        pid: child.pid,
        host: false,
        versionId: version.id,
        gameVersion: version.gameVersion,
        clientName: launchClientName,
        launcherPid: launcherPid,
        eacPid: eacPid,
        child: linkedHosting,
      );
      if (_gameInstance == null) {
        _gameInstance = instance;
        _gameProcess = child;
      } else {
        _extraGameInstances.add(instance);
      }
      _attachProcessLogs(
        child,
        source: 'game',
        onLine: (line, _) => _handleFortniteOutput(instance, line),
      );
      _setUiStatus(
        host: false,
        message: 'Injecting authentication patcher...',
        severity: _UiStatusSeverity.info,
      );
      final report = await _injectConfiguredPatchers(
        child.pid,
        version.gameVersion,
        includeAuth: true,
        includeMemory: false,
        includeUnreal: false,
      );
      final failure = report.firstRequiredFailure;
      if (failure != null) {
        _setUiStatus(
          host: false,
          message: 'Failed to inject ${failure.name}.',
          severity: _UiStatusSeverity.error,
        );
      } else {
        _setUiStatus(
          host: false,
          message: 'Waiting for login...',
          severity: _UiStatusSeverity.info,
        );
      }
      _log('game', 'Fortnite launched (${version.gameVersion}).');
      child.exitCode.then((code) => _handleFortniteExit(instance, code));
      if (mounted) {
        _toast(
          launchingAdditionalClient
              ? 'Additional Fortnite client launched'
              : 'Fortnite launched',
        );
      }
    } catch (error) {
      linkedHosting?.killAll();
      _log('game', 'Failed to launch Fortnite: $error');
      if (mounted) _toast('Failed to launch Fortnite');
      _setUiStatus(
        host: false,
        message: 'Launch failed. See launcher.log.',
        severity: _UiStatusSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _gameServerPromptVisible = false;
          _gameServerPromptRequiredForLaunch = false;
          _gameServerPromptResolvedForLaunch = true;
        });
      } else {
        _gameServerPromptVisible = false;
        _gameServerPromptRequiredForLaunch = false;
        _gameServerPromptResolvedForLaunch = true;
      }
      if (mounted) setState(() => _gameAction = _GameActionState.idle);
      _syncLauncherDiscordPresence();
    }
  }

  Future<void> _onLaunchButtonPressed() async {
    if (_gameAction != _GameActionState.idle) return;

    if (_hasRunningGameClient && !_settings.allowMultipleGameClients) {
      await _closeFortnite();
      return;
    }

    if (_hasRunningGameClient && _settings.allowMultipleGameClients) {
      final additionalUsername = await _promptAdditionalClientUsername();
      if (additionalUsername == null || additionalUsername.trim().isEmpty) {
        return;
      }
      await _startFortnite(
        usernameOverride: additionalUsername,
        launchingAdditionalClient: true,
      );
      return;
    }

    await _startFortnite();
  }

  Future<String?> _promptAdditionalClientUsername() async {
    if (!mounted) return null;
    final usedNames = _activeGameClientNames();
    final hostName = _gameServerInstance?.clientName.trim() ?? '';
    if (hostName.isNotEmpty) {
      usedNames.add(hostName.toLowerCase());
    }
    var suffix = _runningGameClients().length + 1;
    var suggested = 'client$suffix';
    while (usedNames.contains(
      _normalizeClientUsername(suggested).toLowerCase(),
    )) {
      suffix += 1;
      suggested = 'client$suffix';
    }

    final usernameController = TextEditingController(text: suggested);
    final usernameFocusNode = FocusNode();
    try {
      return await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var validation = '';
          var dismissQueued = false;

          void dismissDialogSafely([String? result]) {
            if (dismissQueued) return;
            dismissQueued = true;
            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dismissQueued = false;
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(result);
            });
          }

          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              void submit() {
                final normalized = _normalizeClientUsername(
                  usernameController.text,
                );
                if (usedNames.contains(normalized.toLowerCase())) {
                  setDialogState(
                    () => validation =
                        'Client name already in use. Pick a different one.',
                  );
                  return;
                }
                dismissDialogSafely(normalized);
              }

              return Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (intent) {
                        if (usernameFocusNode.hasFocus) {
                          usernameFocusNode.unfocus();
                          return null;
                        }
                        dismissDialogSafely();
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    autofocus: true,
                    child: SafeArea(
                      child: Center(
                        child: Material(
                          type: MaterialType.transparency,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                            decoration: BoxDecoration(
                              color: _dialogSurfaceColor(dialogContext),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: _onSurface(dialogContext, 0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _dialogShadowColor(dialogContext),
                                  blurRadius: 34,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Additional Client',
                                  style: TextStyle(
                                    color: _onSurface(dialogContext, 0.96),
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    height: 1.02,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Set a unique client name for this launch.',
                                  style: TextStyle(
                                    color: _onSurface(dialogContext, 0.78),
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: usernameController,
                                  focusNode: usernameFocusNode,
                                  keyboardType: TextInputType.text,
                                  onSubmitted: (_) => submit(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText:
                                        'client${_runningGameClients().length + 1}',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                if (validation.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    validation,
                                    style: TextStyle(
                                      color: const Color(0xFFFF8A8A),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => dismissDialogSafely(),
                                      style: OutlinedButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                    const Spacer(),
                                    FilledButton(
                                      onPressed: submit,
                                      style: FilledButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('Launch client'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3 * curved.value,
                          sigmaY: 3 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      usernameFocusNode.dispose();
      usernameController.dispose();
    }
  }

  Future<void> _startHosting({
    VersionEntry? overrideVersion,
    bool triggeredByAutoRestart = false,
  }) async {
    if (_gameAction != _GameActionState.idle) return;
    if (_gameServerLaunching) return;

    final version = overrideVersion ?? _settings.selectedVersion;
    if (version == null) {
      if (!triggeredByAutoRestart) {
        _toast('Import and select a version first');
      }
      return;
    }
    if (!Platform.isWindows) {
      if (!triggeredByAutoRestart) {
        _toast('Hosting is only available on Windows');
      }
      return;
    }
    if (_gameServerProcess != null) {
      if (!triggeredByAutoRestart) {
        _toast('Hosting is already running');
      }
      return;
    }
    if (_settings.gameServerFilePath.trim().isEmpty) {
      if (!triggeredByAutoRestart) {
        _toast('Set your Game server DLL in Data Management first');
      }
      return;
    }

    // Manual hosting (Host button) should not auto-stop when clients close.
    if (!triggeredByAutoRestart) {
      _stopHostingWhenNoClientsRemain = false;
    }

    if (mounted) {
      setState(() => _gameServerLaunching = true);
    } else {
      _gameServerLaunching = true;
    }
    _syncLauncherDiscordPresence();

    _clearStaleHostStoppedWarningOnNewSession();

    try {
      _setUiStatus(
        host: true,
        message: 'Starting game server...',
        severity: _UiStatusSeverity.info,
      );

      final backendReady = await _ensureBackendReadyForSession(
        host: true,
        toastOnFailure: !triggeredByAutoRestart,
      );
      if (!backendReady) return;

      final instance = await _startImplicitGameServer(version);
      if (instance == null) {
        // _startImplicitGameServer typically shows a toast. Keep an error status
        // so the user knows why "Hosting" didn't start.
        _setUiStatus(
          host: true,
          message: 'Failed to start hosting. See launcher.log.',
          severity: _UiStatusSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _gameServerLaunching = false);
      } else {
        _gameServerLaunching = false;
      }
      _syncLauncherDiscordPresence();
    }
  }

  Future<void> _openHostOptionsDialog() async {
    if (!mounted) return;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;
    final hostUsernameFocusNode = FocusNode();
    final playLaunchArgsFocusNode = FocusNode();
    final hostLaunchArgsFocusNode = FocusNode();
    final portFocusNode = FocusNode();
    final dialogScrollController = ScrollController();
    final hostUsernameController = TextEditingController(
      text: _settings.hostUsername.trim().isEmpty
          ? 'host'
          : _settings.hostUsername,
    );
    final playLaunchArgsController = TextEditingController(
      text: _settings.playCustomLaunchArgs,
    );
    final launchArgsController = TextEditingController(
      text: _settings.hostCustomLaunchArgs,
    );
    final portController = TextEditingController(
      text: _effectiveGameServerPort().toString(),
    );
    var headless = _settings.hostHeadlessEnabled;
    var autoRestart = _settings.hostAutoRestartEnabled;
    var deleteAftermathOnLaunch = _settings.deleteAftermathOnLaunch;
    var allowMultipleClients = _settings.allowMultipleGameClients;
    var launchBackend = _settings.launchBackendOnSessionStart;
    var largePakPatcherEnabled = _settings.largePakPatcherEnabled;
    try {
      final shouldSave = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var dismissQueued = false;
          final maxDialogHeight = min(
            MediaQuery.of(dialogContext).size.height * 0.92,
            720.0,
          );

          Widget settingTile({
            required IconData icon,
            required String title,
            required String subtitle,
            required Widget trailing,
          }) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: onSurface.withValues(alpha: 0.05),
                border: Border.all(color: onSurface.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: onSurface.withValues(alpha: 0.8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.96),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.78),
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing,
                ],
              ),
            );
          }

          void dismissDialogSafely([bool? result]) {
            if (dismissQueued) return;
            dismissQueued = true;
            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dismissQueued = false;
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(result);
            });
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if ((event is KeyDownEvent) &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                if (hostUsernameFocusNode.hasFocus ||
                    playLaunchArgsFocusNode.hasFocus ||
                    hostLaunchArgsFocusNode.hasFocus ||
                    portFocusNode.hasFocus) {
                  hostUsernameFocusNode.unfocus();
                  playLaunchArgsFocusNode.unfocus();
                  hostLaunchArgsFocusNode.unfocus();
                  portFocusNode.unfocus();
                  return KeyEventResult.handled;
                }
                dismissDialogSafely(false);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: StatefulBuilder(
              builder: (dialogContext, setDialogState) {
                return SafeArea(
                  child: Center(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: 760,
                          maxHeight: maxDialogHeight,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                        decoration: BoxDecoration(
                          color: _dialogSurfaceColor(dialogContext),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _onSurface(dialogContext, 0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _dialogShadowColor(dialogContext),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Launch Options',
                              style: TextStyle(
                                color: _onSurface(dialogContext, 0.96),
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Customize launch arguments for Play and Host, plus host behavior settings.',
                              style: TextStyle(
                                color: _onSurface(dialogContext, 0.78),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Scrollbar(
                                controller: dialogScrollController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: dialogScrollController,
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      settingTile(
                                        icon: Icons.play_circle_outline_rounded,
                                        title: 'Play Launch Arguments',
                                        subtitle:
                                            'Additional arguments to use with the Launch button',
                                        trailing: SizedBox(
                                          width: 220,
                                          child: TextField(
                                            controller:
                                                playLaunchArgsController,
                                            focusNode: playLaunchArgsFocusNode,
                                            keyboardType: TextInputType.text,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: 'Arguments...',
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.tune_rounded,
                                        title: 'Host Launch Arguments',
                                        subtitle:
                                            'Additional arguments to use with the Host button',
                                        trailing: SizedBox(
                                          width: 220,
                                          child: TextField(
                                            controller: launchArgsController,
                                            focusNode: hostLaunchArgsFocusNode,
                                            keyboardType: TextInputType.text,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: 'Arguments...',
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.badge_rounded,
                                        title: 'Host Client Name',
                                        subtitle:
                                            'Username used for the hosted client',
                                        trailing: SizedBox(
                                          width: 220,
                                          child: TextField(
                                            controller: hostUsernameController,
                                            focusNode: hostUsernameFocusNode,
                                            keyboardType: TextInputType.text,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: 'host',
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.numbers_rounded,
                                        title: 'Port',
                                        subtitle:
                                            'The port the launcher expects the game server on',
                                        trailing: SizedBox(
                                          width: 220,
                                          child: TextField(
                                            controller: portController,
                                            focusNode: portFocusNode,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: _defaultGameServerPort
                                                  .toString(),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.web_asset_off_rounded,
                                        title: 'Headless',
                                        subtitle:
                                            'Disables game rendering to save resources',
                                        trailing: Switch(
                                          value: headless,
                                          onChanged: (value) {
                                            setDialogState(
                                              () => headless = value,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.groups_rounded,
                                        title: 'Multi-Client Launching',
                                        subtitle:
                                            'Allows Launch to open additional game clients while one is already running',
                                        trailing: Switch(
                                          value: allowMultipleClients,
                                          onChanged: (value) {
                                            setDialogState(
                                              () =>
                                                  allowMultipleClients = value,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.cloud_rounded,
                                        title: 'Launch Backend with Game',
                                        subtitle:
                                            'Start ATLAS Backend when launching a session',
                                        trailing: Switch(
                                          value: launchBackend,
                                          onChanged: (value) {
                                            setDialogState(
                                              () => launchBackend = value,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.restart_alt_rounded,
                                        title: 'Automatic Restart',
                                        subtitle:
                                            'Automatically restarts the game server when it exits',
                                        trailing: Switch(
                                          value: autoRestart,
                                          onChanged: (value) {
                                            setDialogState(
                                              () => autoRestart = value,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.folder_zip_rounded,
                                        title: 'Large Pak Patcher',
                                        subtitle:
                                            'Help large or custom pak files load correctly',
                                        trailing: Switch(
                                          value: largePakPatcherEnabled,
                                          onChanged: (value) {
                                            setDialogState(
                                              () => largePakPatcherEnabled =
                                                  value,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      settingTile(
                                        icon: Icons.warning_amber_rounded,
                                        title: 'Delete GFSDK_Aftermath_Lib.dll',
                                        subtitle:
                                            'Removes the Aftermath DLL from the game directory when launching the game',
                                        trailing: Switch(
                                          value: deleteAftermathOnLaunch,
                                          onChanged: (value) {
                                            setDialogState(
                                              () => deleteAftermathOnLaunch =
                                                  value,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => dismissDialogSafely(false),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: () => dismissDialogSafely(true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: secondary.withValues(
                                      alpha: 0.92,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3 * curved.value,
                          sigmaY: 3 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
      if (shouldSave != true || !mounted) return;

      final parsedPort = int.tryParse(portController.text.trim());
      final resolvedPort =
          parsedPort != null && parsedPort > 0 && parsedPort <= 65535
          ? parsedPort
          : _defaultGameServerPort;

      setState(() {
        _settings = _settings.copyWith(
          hostUsername: hostUsernameController.text.trim().isEmpty
              ? 'host'
              : hostUsernameController.text.trim(),
          playCustomLaunchArgs: playLaunchArgsController.text.trim(),
          hostCustomLaunchArgs: launchArgsController.text.trim(),
          allowMultipleGameClients: allowMultipleClients,
          hostHeadlessEnabled: headless,
          hostAutoRestartEnabled: autoRestart,
          deleteAftermathOnLaunch: deleteAftermathOnLaunch,
          hostPort: resolvedPort,
          launchBackendOnSessionStart: launchBackend,
          largePakPatcherEnabled: largePakPatcherEnabled,
        );
      });
      await _saveSettings(toast: false);
      if (mounted) _toast('Host settings saved');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      hostUsernameFocusNode.dispose();
      playLaunchArgsFocusNode.dispose();
      hostLaunchArgsFocusNode.dispose();
      portFocusNode.dispose();
      dialogScrollController.dispose();
      hostUsernameController.dispose();
      playLaunchArgsController.dispose();
      launchArgsController.dispose();
      portController.dispose();
    }
  }

  bool _shouldOfferGameServerPrompt() {
    if (_settings.backendConnectionType != BackendConnectionType.local) {
      return false;
    }
    if (_gameServerProcess != null) return false;
    return _settings.gameServerFilePath.trim().isNotEmpty;
  }

  Future<_GameServerPromptAction?> _promptAutomaticGameServerStart() async {
    if (!mounted) return null;
    var selectedGameServerPath = _settings.gameServerFilePath.trim();
    var selectedGameServerDll = selectedGameServerPath.isEmpty
        ? 'No game server DLL configured'
        : _basename(selectedGameServerPath);
    final result = await showGeneralDialog<_GameServerPromptAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickGameServerDll() async {
              if (!Platform.isWindows) return;
              final picked = await _pickSingleFile(
                dialogTitle: 'Select game server DLL',
                allowedExtensions: const ['dll'],
              );
              final trimmed = picked?.trim() ?? '';
              if (trimmed.isEmpty) return;
              setDialogState(() {
                selectedGameServerPath = trimmed;
                selectedGameServerDll = _basename(trimmed);
              });
            }

            void applySelectedDllIfChanged() {
              final trimmed = selectedGameServerPath.trim();
              if (trimmed.isEmpty) return;
              if (trimmed == _settings.gameServerFilePath.trim()) return;
              if (mounted) {
                setState(() {
                  _settings = _settings.copyWith(gameServerFilePath: trimmed);
                  _gameServerFileController.text = trimmed;
                });
              } else {
                _settings = _settings.copyWith(gameServerFilePath: trimmed);
                _gameServerFileController.text = trimmed;
              }
              unawaited(_saveSettings(toast: false));
            }

            return SafeArea(
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                    decoration: BoxDecoration(
                      color: _dialogSurfaceColor(dialogContext),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: _onSurface(dialogContext, 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: _dialogShadowColor(dialogContext),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(
                                  dialogContext,
                                ).colorScheme.secondary.withValues(alpha: 0.2),
                                border: Border.all(
                                  color: _onSurface(dialogContext, 0.2),
                                ),
                              ),
                              child: Icon(
                                Icons.cloud_upload_rounded,
                                size: 18,
                                color: _onSurface(dialogContext, 0.9),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'GAME SERVER',
                                style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface(dialogContext, 0.66),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Close',
                              child: SizedBox(
                                width: 34,
                                height: 34,
                                child: Material(
                                  color: _adaptiveScrimColor(
                                    dialogContext,
                                    darkAlpha: 0.08,
                                    lightAlpha: 0.14,
                                  ),
                                  shape: CircleBorder(
                                    side: BorderSide(
                                      color: _onSurface(dialogContext, 0.12),
                                    ),
                                  ),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () =>
                                        Navigator.of(dialogContext).pop(),
                                    child: Center(
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: _onSurface(dialogContext, 0.84),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Start game server?',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: _onSurface(dialogContext, 0.96),
                            height: 1.04,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ATLAS Link can launch an automatic local game server using your configured Game server DLL.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.36,
                            color: _onSurface(dialogContext, 0.84),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: _adaptiveScrimColor(
                            dialogContext,
                            darkAlpha: 0.10,
                            lightAlpha: 0.18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: _onSurface(dialogContext, 0.12),
                            ),
                          ),
                          child: InkWell(
                            onTap: pickGameServerDll,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.description_rounded,
                                    size: 17,
                                    color: _onSurface(dialogContext, 0.72),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedGameServerDll,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _onSurface(dialogContext, 0.82),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.folder_open_rounded,
                                    size: 18,
                                    color: _onSurface(dialogContext, 0.72),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.of(
                                dialogContext,
                              ).pop(_GameServerPromptAction.ignore),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                                side: BorderSide(
                                  color: _onSurface(dialogContext, 0.26),
                                ),
                                foregroundColor: _onSurface(
                                  dialogContext,
                                  0.92,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Ignore'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  applySelectedDllIfChanged();
                                  Navigator.of(
                                    dialogContext,
                                  ).pop(_GameServerPromptAction.start);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(dialogContext)
                                      .colorScheme
                                      .secondary
                                      .withValues(alpha: 0.92),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Start game server'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<_FortniteProcessState?> _startImplicitGameServer(
    VersionEntry version, {
    bool syncDiscordRpc = true,
  }) async {
    final gameServerPath = _settings.gameServerFilePath.trim();
    if (gameServerPath.isEmpty) return null;
    if (_gameServerProcess != null) return _gameServerInstance;

    final gameServerFile = File(gameServerPath);
    if (!gameServerFile.existsSync()) {
      _log('gameserver', 'Game server DLL not found at $gameServerPath.');
      if (mounted) _toast('Game server DLL file not found');
      return null;
    }
    if (!gameServerPath.toLowerCase().endsWith('.dll')) {
      _log('gameserver', 'Game server path is not a DLL: $gameServerPath.');
      if (mounted) _toast('Game server file must be a DLL');
      return null;
    }

    try {
      final exe = await _resolveExecutable(version);
      if (exe == null) {
        _log('gameserver', 'Cannot start server: shipping executable missing.');
        if (mounted) _toast('Cannot start game server for this build');
        return null;
      }
      final exeDir = File(exe).parent.path;
      if (syncDiscordRpc) {
        await _syncCustomDiscordRpcDllForBuild(version);
      }

      // Patch exe for headless mode if enabled
      if (_settings.hostHeadlessEnabled) {
        final patched = await _patchExecutableForHeadless(exe);
        if (patched) {
          _log('gameserver', 'Patched executable for headless mode.');
        } else {
          _log(
            'gameserver',
            'Exe headless patch not needed or already applied.',
          );
        }
      }

      final hostUsername = _settings.hostUsername.trim().isEmpty
          ? 'host'
          : _settings.hostUsername;
      final launchAuth = _resolveLaunchAuthCredentials(
        username: hostUsername,
        host: true,
      );
      if (launchAuth == null) return null;
      final hostCustomArgs = _settings.hostCustomLaunchArgs;
      final hostLaunchTokens = _resolveLaunchSessionTokens(
        customArgs: hostCustomArgs,
      );
      final hostTokenValidationError = _validateLaunchSessionTokens(
        hostLaunchTokens,
      );
      if (hostTokenValidationError != null) {
        _log(
          'gameserver',
          'Launch token validation failed: $hostTokenValidationError',
        );
        _setUiStatus(
          host: true,
          message: hostTokenValidationError,
          severity: _UiStatusSeverity.error,
        );
        if (mounted) _toast(hostTokenValidationError);
        return null;
      }

      await _deleteAftermathCrashDlls(version.location);
      final launcherPid = await _startPausedAuxiliaryProcess(
        version.location,
        _launcherExeName,
        hintDir: exeDir,
      );
      final eacPid = await _startPausedAuxiliaryProcess(
        version.location,
        _eacExeName,
        hintDir: exeDir,
      );

      final backendHost = _effectiveBackendHostForLaunchArgs();
      final backendPort = _effectiveBackendPort();
      final args =
          _createRebootLaunchArgs(
              username: launchAuth.login,
              password: launchAuth.password,
              launchTokens: hostLaunchTokens,
              host: true,
              headless: _settings.hostHeadlessEnabled,
              logging: false,
              hostPort: _effectiveGameServerPort(),
              customArgs: hostCustomArgs,
            )
            ..add('-BackendHost=$backendHost')
            ..add('-BackendPort=$backendPort');

      _log(
        'gameserver',
        'Starting with args: ${_redactSensitiveLaunchArgs(args).join(' ')}',
      );

      Process process;
      try {
        process = await Process.start(
          exe,
          args,
          workingDirectory: File(exe).parent.path,
          environment: {
            ...Platform.environment,
            'OPENSSL_ia32cap': '~0x20000000',
          },
        );
      } catch (error) {
        if (launcherPid != null) {
          _FortniteProcessState._killPidSafe(launcherPid);
        }
        if (eacPid != null) {
          _FortniteProcessState._killPidSafe(eacPid);
        }
        rethrow;
      }

      final instance = _FortniteProcessState(
        pid: process.pid,
        host: true,
        versionId: version.id,
        gameVersion: version.gameVersion,
        clientName: _normalizeClientUsername(hostUsername),
        launcherPid: launcherPid,
        eacPid: eacPid,
      );
      _gameServerInstance = instance;
      _gameServerProcess = process;
      _attachProcessLogs(
        process,
        source: 'gameserver',
        onLine: (line, _) => _handleFortniteOutput(instance, line),
      );
      _setUiStatus(
        host: true,
        message: 'Injecting authentication patcher...',
        severity: _UiStatusSeverity.info,
      );
      final report = await _injectConfiguredPatchers(
        process.pid,
        version.gameVersion,
        includeAuth: true,
        includeMemory: false,
        includeLargePak: false,
        includeUnreal: false,
        includeGameServer: false,
      );
      final failure = report.firstRequiredFailure;
      if (failure != null) {
        _setUiStatus(
          host: true,
          message: 'Failed to inject ${failure.name}.',
          severity: _UiStatusSeverity.error,
        );
      } else {
        _setUiStatus(
          host: true,
          message: 'Waiting for login...',
          severity: _UiStatusSeverity.info,
        );
        unawaited(_scheduleHostFallbackPostLoginInjections(instance));
      }
      _log(
        'gameserver',
        'Automatic game server starting (pid ${process.pid}).',
      );
      process.exitCode.then((code) => _handleFortniteExit(instance, code));
      if (mounted) _toast('Game server launching...');
      return instance;
    } catch (error) {
      _log('gameserver', 'Failed to start automatic game server: $error');
      if (mounted) _toast('Failed to start automatic game server');
      return null;
    }
  }

  Future<void> _scheduleHostFallbackPostLoginInjections(
    _FortniteProcessState state,
  ) async {
    if (!state.host) return;
    if (state.postLoginInjected) return;

    // Dedicated/headless hosting flows may never emit the UI-based login
    // markers used by `_isLoginCompleteSignal`. As a safety net, attempt
    // post-login injections after a short delay if the server is still running.
    await Future<void>.delayed(const Duration(seconds: 12));
    if (state.killed || state.exited) return;
    if (state.postLoginInjected) return;

    state.launched = true;
    state.postLoginInjected = true;
    state.postLoginInferredFromFallback = true;
    _log(
      'gameserver',
      'Login marker not seen. Running fallback post-login injections...',
    );
    _setUiStatus(
      host: true,
      message: 'Finalizing host launch...',
      severity: _UiStatusSeverity.info,
    );
    unawaited(_performPostLoginInjections(state));
  }

  String _normalizeClientUsername(String username) {
    var normalized = username.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (normalized.isEmpty) normalized = 'Player';
    return normalized;
  }

  String? _launchUsernameValidationError({
    required String username,
    required bool host,
  }) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return host ? 'Host username is required.' : 'Username is required.';
    }
    final normalized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (normalized.isEmpty) {
      return host
          ? 'Host username is invalid. Use at least one letter or number.'
          : 'Username is invalid. Use at least one letter or number.';
    }
    return null;
  }

  String _buildRebootLoginUsername(String username) {
    final normalized = _normalizeClientUsername(username);
    return '$normalized@atlas.dev';
  }

  String _usernameFromEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    final atIndex = trimmed.indexOf('@');
    final local = atIndex == -1 ? trimmed : trimmed.substring(0, atIndex);
    return local.trim();
  }

  static const String _emailAuthRemoteBackendRequiredMessage =
      'Email/password authentication requires Backend Type set to Remote.';
  static const String _emailAuthRemoteHostRequiredMessage =
      'Email/password authentication requires a non-local Remote backend host.';

  String? _emailPasswordBackendValidationError() {
    if (!_settings.profileUseEmailPasswordAuth) return null;
    if (_settings.backendConnectionType != BackendConnectionType.remote) {
      return _emailAuthRemoteBackendRequiredMessage;
    }
    if (_effectiveBackendHost().trim().isEmpty) {
      return _emailAuthRemoteHostRequiredMessage;
    }
    return null;
  }

  bool _forceRemoteBackendForEmailPasswordAuth() {
    if (!_settings.profileUseEmailPasswordAuth) return false;
    if (_settings.backendConnectionType == BackendConnectionType.remote) {
      return false;
    }
    _settings = _settings.copyWith(
      backendConnectionType: BackendConnectionType.remote,
      backendHost: '',
    );
    _backendHostController.text = _effectiveBackendHost();
    return true;
  }

  bool _isLikelyEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  String? _profileAuthValidationError({
    required bool useEmailPassword,
    required String email,
    required String password,
  }) {
    if (!useEmailPassword) return null;
    if (!_isLikelyEmail(email)) {
      return 'Profile email is invalid. Enter a valid email address.';
    }
    if (password.trim().isEmpty) {
      return 'Profile password is required when email login is enabled.';
    }
    return null;
  }

  _LaunchAuthCredentials? _resolveLaunchAuthCredentials({
    required String username,
    required bool host,
  }) {
    final useEmailPassword = _settings.profileUseEmailPasswordAuth;
    final email = _settings.profileAuthEmail.trim();
    final password = _settings.profileAuthPassword;
    final validationError = _profileAuthValidationError(
      useEmailPassword: useEmailPassword,
      email: email,
      password: password,
    );
    if (validationError != null) {
      _setUiStatus(
        host: host,
        message: validationError,
        severity: _UiStatusSeverity.error,
      );
      if (mounted) _toast(validationError);
      return null;
    }

    final backendValidationError = _emailPasswordBackendValidationError();
    if (useEmailPassword && backendValidationError != null) {
      _setUiStatus(
        host: host,
        message: backendValidationError,
        severity: _UiStatusSeverity.error,
      );
      if (mounted) _toast(backendValidationError);
      return null;
    }

    if (useEmailPassword) {
      return _LaunchAuthCredentials(login: email, password: password);
    }

    final usernameError = _launchUsernameValidationError(
      username: username,
      host: host,
    );
    if (usernameError != null) {
      _setUiStatus(
        host: host,
        message: usernameError,
        severity: _UiStatusSeverity.error,
      );
      if (mounted) _toast(usernameError);
      return null;
    }

    return _LaunchAuthCredentials(
      login: _buildRebootLoginUsername(username),
      password: 'Rebooted',
    );
  }

  String? _normalizeOptionalLaunchToken(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _extractLaunchArgValue(List<String> args, String argumentName) {
    final prefix = '-${argumentName.toUpperCase()}=';
    for (final arg in args) {
      final trimmed = arg.trim();
      if (trimmed.length <= prefix.length) continue;
      if (trimmed.toUpperCase().startsWith(prefix)) {
        final value = trimmed.substring(prefix.length).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  _LaunchSessionTokens _resolveLaunchSessionTokens({
    required String customArgs,
  }) {
    final parsedArgs = _splitLaunchArguments(customArgs);
    final argFltoken = _normalizeOptionalLaunchToken(
      _extractLaunchArgValue(parsedArgs, 'fltoken'),
    );
    final argCaldera = _normalizeOptionalLaunchToken(
      _extractLaunchArgValue(parsedArgs, 'caldera'),
    );

    final envFltoken = _normalizeOptionalLaunchToken(
      Platform.environment['ATLAS_FLTOKEN'],
    );
    final envCaldera = _normalizeOptionalLaunchToken(
      Platform.environment['ATLAS_CALDERA'],
    );

    final resolvedFltoken = argFltoken ?? envFltoken;
    final resolvedCaldera = argCaldera ?? envCaldera;
    if (resolvedFltoken == null && resolvedCaldera == null) {
      return const _LaunchSessionTokens(
        fltoken: _legacyLaunchFltoken,
        caldera: _legacyLaunchCalderaToken,
      );
    }

    return _LaunchSessionTokens(
      fltoken: resolvedFltoken,
      caldera: resolvedCaldera,
    );
  }

  bool _isLegacyLaunchTokenPair(_LaunchSessionTokens tokens) {
    return tokens.fltoken == _legacyLaunchFltoken &&
        tokens.caldera == _legacyLaunchCalderaToken;
  }

  Map<String, dynamic>? _decodeJwtPayloadMap(String token) {
    final segments = token.split('.');
    if (segments.length != 3) return null;
    final payloadSegment = segments[1].trim();
    if (payloadSegment.isEmpty) return null;

    try {
      final normalized = base64Url.normalize(payloadSegment);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is Map<String, dynamic>) return payload;
      if (payload is Map) {
        return payload.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String? _validateLaunchSessionTokens(_LaunchSessionTokens tokens) {
    if (!tokens.hasAny) return null;
    if (!tokens.hasBoth) {
      return 'Launch tokens are incomplete. Provide both -fltoken and -caldera.';
    }

    final fltoken = tokens.fltoken!;
    if (!RegExp(r'^[A-Za-z0-9._-]{8,256}$').hasMatch(fltoken)) {
      return 'Launch token (-fltoken) format is invalid.';
    }

    final caldera = tokens.caldera!;
    if (!RegExp(
      r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
    ).hasMatch(caldera)) {
      return 'Launch token (-caldera) format is invalid.';
    }

    final payload = _decodeJwtPayloadMap(caldera);
    if (payload == null) {
      return 'Launch token (-caldera) payload could not be decoded.';
    }

    final accountId = payload['account_id']?.toString().trim() ?? '';
    if (accountId.isEmpty) {
      return 'Launch token (-caldera) is missing account_id.';
    }

    final generatedValue = payload['generated'];
    int? generatedUnixSeconds;
    if (generatedValue is int) {
      generatedUnixSeconds = generatedValue;
    } else if (generatedValue is num) {
      generatedUnixSeconds = generatedValue.toInt();
    } else if (generatedValue is String) {
      generatedUnixSeconds = int.tryParse(generatedValue);
    }
    if (generatedUnixSeconds == null || generatedUnixSeconds <= 0) {
      return 'Launch token (-caldera) is missing a valid generated timestamp.';
    }

    final generatedAt = DateTime.fromMillisecondsSinceEpoch(
      generatedUnixSeconds * 1000,
      isUtc: true,
    );
    final now = DateTime.now().toUtc();
    if (generatedAt.isAfter(now.add(_maxLaunchTokenClockSkew))) {
      return 'Launch token (-caldera) timestamp is in the future.';
    }
    if (!_isLegacyLaunchTokenPair(tokens) &&
        now.difference(generatedAt) > _maxLaunchTokenAge) {
      return 'Launch token (-caldera) is stale '
          '(generated ${generatedAt.toIso8601String()} UTC).';
    }

    return null;
  }

  List<String> _removeLaunchTokenArgs(List<String> args) {
    return args
        .where((arg) {
          final upper = arg.toUpperCase();
          if (upper.startsWith('-FLTOKEN=')) return false;
          if (upper.startsWith('-CALDERA=')) return false;
          return true;
        })
        .toList(growable: false);
  }

  List<String> _redactSensitiveLaunchArgs(List<String> args) {
    return args
        .map((arg) {
          final upper = arg.toUpperCase();
          if (upper.startsWith('-FLTOKEN=')) {
            return '-FLTOKEN=<redacted>';
          }
          if (upper.startsWith('-CALDERA=')) {
            return '-CALDERA=<redacted>';
          }
          if (upper.startsWith('-AUTH_LOGIN=')) {
            return '-AUTH_LOGIN=<redacted>';
          }
          if (upper.startsWith('-AUTH_PASSWORD=')) {
            return '-AUTH_PASSWORD=<redacted>';
          }
          return arg;
        })
        .toList(growable: false);
  }

  List<String> _createRebootLaunchArgs({
    required String username,
    required String password,
    required _LaunchSessionTokens launchTokens,
    bool host = false,
    bool headless = false,
    bool logging = false,
    int? hostPort,
    String customArgs = '',
  }) {
    final resolvedPassword = password.trim().isEmpty ? 'Rebooted' : password;
    final args = <String>[
      '-epicapp=Fortnite',
      '-epicenv=Prod',
      '-epiclocale=en-us',
      '-epicportal',
      '-skippatchcheck',
      '-nobe',
      '-fromfl=eac',
      '-AUTH_LOGIN=$username',
      '-AUTH_PASSWORD=$resolvedPassword',
      '-AUTH_TYPE=epic',
    ];
    if (launchTokens.hasBoth) {
      args.add('-fltoken=${launchTokens.fltoken!}');
      args.add('-caldera=${launchTokens.caldera!}');
    }
    if (logging) args.add('-log');
    if (host) {
      args.add('-nosplash');
      args.add('-nosound');
      if (hostPort != null && hostPort > 0) {
        args.add('-Port=$hostPort');
      }
      if (headless) {
        args.add('-nullrhi');
      }
    }
    final extras = _removeLaunchTokenArgs(_splitLaunchArguments(customArgs));
    if (extras.isNotEmpty) {
      args.addAll(extras);
    }
    return args;
  }

  List<String> _splitLaunchArguments(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const <String>[];

    final args = <String>[];
    final buffer = StringBuffer();
    String? activeQuote;

    void flush() {
      if (buffer.isEmpty) return;
      args.add(buffer.toString());
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final isQuote = char == '"' || char == "'";
      if (isQuote) {
        if (activeQuote == null) {
          activeQuote = char;
          continue;
        }
        if (activeQuote == char) {
          activeQuote = null;
          continue;
        }
      }

      if (activeQuote == null && RegExp(r'\s').hasMatch(char)) {
        flush();
        continue;
      }
      buffer.write(char);
    }
    flush();
    return args;
  }

  // Binary patch patterns for headless mode
  // Original string: -invitesession -invitefrom -party_joiningfo_token -replay
  static final Uint8List _originalHeadlessBytes = Uint8List.fromList([
    45,
    0,
    105,
    0,
    110,
    0,
    118,
    0,
    105,
    0,
    116,
    0,
    101,
    0,
    115,
    0,
    101,
    0,
    115,
    0,
    115,
    0,
    105,
    0,
    111,
    0,
    110,
    0,
    32,
    0,
    45,
    0,
    105,
    0,
    110,
    0,
    118,
    0,
    105,
    0,
    116,
    0,
    101,
    0,
    102,
    0,
    114,
    0,
    111,
    0,
    109,
    0,
    32,
    0,
    45,
    0,
    112,
    0,
    97,
    0,
    114,
    0,
    116,
    0,
    121,
    0,
    95,
    0,
    106,
    0,
    111,
    0,
    105,
    0,
    110,
    0,
    105,
    0,
    110,
    0,
    102,
    0,
    111,
    0,
    95,
    0,
    116,
    0,
    111,
    0,
    107,
    0,
    101,
    0,
    110,
    0,
    32,
    0,
    45,
    0,
    114,
    0,
    101,
    0,
    112,
    0,
    108,
    0,
    97,
    0,
    121,
    0,
  ]);

  // Patched string: -log -nosplash -nosound -nullrhi -useolditemcards
  static final Uint8List _patchedHeadlessBytes = Uint8List.fromList([
    45,
    0,
    108,
    0,
    111,
    0,
    103,
    0,
    32,
    0,
    45,
    0,
    110,
    0,
    111,
    0,
    115,
    0,
    112,
    0,
    108,
    0,
    97,
    0,
    115,
    0,
    104,
    0,
    32,
    0,
    45,
    0,
    110,
    0,
    111,
    0,
    115,
    0,
    111,
    0,
    117,
    0,
    110,
    0,
    100,
    0,
    32,
    0,
    45,
    0,
    110,
    0,
    117,
    0,
    108,
    0,
    108,
    0,
    114,
    0,
    104,
    0,
    105,
    0,
    32,
    0,
    45,
    0,
    117,
    0,
    115,
    0,
    101,
    0,
    111,
    0,
    108,
    0,
    100,
    0,
    105,
    0,
    116,
    0,
    101,
    0,
    109,
    0,
    99,
    0,
    97,
    0,
    114,
    0,
    100,
    0,
    115,
    0,
    32,
    0,
    32,
    0,
    32,
    0,
    32,
    0,
    32,
    0,
    32,
    0,
    32,
    0,
  ]);

  Future<bool> _patchExecutableForHeadless(String exePath) async {
    return Isolate.run(() async {
      try {
        final file = File(exePath);
        if (!file.existsSync()) return false;

        final original = _originalHeadlessBytes;
        final patched = _patchedHeadlessBytes;

        if (original.length != patched.length) {
          throw Exception('Patch length mismatch');
        }

        final bytes = await file.readAsBytes();
        var patchOffset = -1;
        var matchCount = 0;

        // Find the original pattern in the exe
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] == original[matchCount]) {
            if (patchOffset == -1) patchOffset = i;
            matchCount++;
            if (matchCount == original.length) break;
          } else {
            patchOffset = -1;
            matchCount = 0;
          }
        }

        if (patchOffset == -1) {
          // Pattern not found - might be already patched or different version
          return false;
        }

        // Apply the patch
        for (var i = 0; i < patched.length; i++) {
          bytes[patchOffset + i] = patched[i];
        }

        await file.writeAsBytes(bytes, flush: true);
        return true;
      } catch (error) {
        return false;
      }
    });
  }

  Future<void> _deleteAftermathCrashDlls(String buildRootPath) async {
    if (!_settings.deleteAftermathOnLaunch) return;

    final normalizedRoot = _normalizePath(buildRootPath);
    if (_afterMathCleanedRoots.contains(normalizedRoot)) return;
    _afterMathCleanedRoots.add(normalizedRoot);

    final matches = await _findAllRecursiveFiles(
      buildRootPath,
      _aftermathDllName,
      maxResults: 32,
    );
    for (final path in matches) {
      try {
        await File(path).delete();
        _log('game', 'Removed $_aftermathDllName from ${_basename(path)}.');
      } catch (_) {
        // Ignore locked files.
      }
    }
  }

  Directory _discordRpcTargetDirectoryForBuildRoot(String buildRoot) {
    return Directory(
      _joinPath([buildRoot, ..._discordRpcTargetRelativeDirectory]),
    );
  }

  Future<void> _syncCustomDiscordRpcDllForBuild(
    VersionEntry launchVersion,
  ) async {
    final buildRoot = launchVersion.location.trim();
    if (buildRoot.isEmpty || !_isBuildRootValid(buildRoot)) {
      _log(
        'discord',
        'Skipping Discord RPC replacement. Invalid build root: $buildRoot',
      );
      return;
    }

    final sourcePath = await _ensureBundledDll(
      bundledAssetPath: _discordRpcBundledAssetPath,
      bundledFileName: _discordRpcDllName,
      label: 'Discord RPC override',
    );
    final resolvedSourcePath = sourcePath?.trim() ?? '';
    if (resolvedSourcePath.isEmpty || !File(resolvedSourcePath).existsSync()) {
      _log(
        'discord',
        'Skipping Discord RPC replacement. Custom DLL not found at $_discordRpcBundledAssetPath.',
      );
      return;
    }

    final sourceFile = File(resolvedSourcePath);
    final targetDirectory = _discordRpcTargetDirectoryForBuildRoot(buildRoot);
    final targetPath = _joinPath([targetDirectory.path, _discordRpcDllName]);
    final originalPath = _joinPath([
      targetDirectory.path,
      _discordRpcOriginalDllName,
    ]);
    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    final targetFile = File(targetPath);
    final originalFile = File(originalPath);
    final normalizedBuildRoot = _normalizePath(buildRoot);

    try {
      await targetDirectory.create(recursive: true);
      if (!await originalFile.exists()) {
        if (!await targetFile.exists()) {
          _log(
            'discord',
            'Skipped $buildRoot: missing both $_discordRpcDllName and $_discordRpcOriginalDllName.',
          );
          return;
        }

        final targetAlreadyCustom = await _filesBinaryEqual(
          sourceFile,
          targetFile,
        );
        if (targetAlreadyCustom) {
          // Already replaced earlier (for example a previous launch). Track so
          // close-time restore can still recover the original DLL.
          _discordRpcReplacedBuildRootsByNormalized[normalizedBuildRoot] =
              buildRoot;
          _log(
            'discord',
            'Using existing custom $_discordRpcDllName in $buildRoot.',
          );
          return;
        }

        await targetFile.rename(originalPath);
        _log(
          'discord',
          'Backed up original $_discordRpcDllName as $_discordRpcOriginalDllName for $buildRoot.',
        );
      }

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await sourceFile.copy(tempPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetPath);
      _discordRpcReplacedBuildRootsByNormalized[normalizedBuildRoot] =
          buildRoot;
      _log('discord', 'Discord RPC replacement complete for $buildRoot.');
    } catch (error) {
      _log(
        'discord',
        'Failed to replace $_discordRpcDllName in $buildRoot: $error',
      );
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup failures.
      }
    }
  }

  Future<List<String>> _discoverStaleDiscordRpcReplacementRoots(
    File customSourceFile,
  ) async {
    final roots = <String>[];
    final seen = <String>{};
    for (final version in _settings.versions) {
      final buildRoot = version.location.trim();
      if (buildRoot.isEmpty || !_isBuildRootValid(buildRoot)) continue;
      final normalized = _normalizePath(buildRoot);
      if (!seen.add(normalized)) continue;

      final targetDirectory = _discordRpcTargetDirectoryForBuildRoot(buildRoot);
      final targetFile = File(
        _joinPath([targetDirectory.path, _discordRpcDllName]),
      );
      final originalFile = File(
        _joinPath([targetDirectory.path, _discordRpcOriginalDllName]),
      );
      if (!await targetFile.exists() || !await originalFile.exists()) continue;
      if (await _filesBinaryEqual(customSourceFile, targetFile)) {
        roots.add(buildRoot);
      }
    }
    return roots;
  }

  Future<bool> _anyFortniteProcessRunningSystemWide() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq $_shippingExeName',
      ], runInShell: true);
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      return output.contains(_shippingExeName.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreOriginalDiscordRpcDllAcrossBuildsIfIdle() async {
    if (_discordRpcRestoreInFlight) return;
    if (_hasRunningGameClient) return;
    if (_gameServerProcess != null) return;
    if (await _anyFortniteProcessRunningSystemWide()) return;

    final sourcePath = await _ensureBundledDll(
      bundledAssetPath: _discordRpcBundledAssetPath,
      bundledFileName: _discordRpcDllName,
      label: 'Discord RPC override',
    );
    final resolvedSourcePath = sourcePath?.trim() ?? '';
    final customSourceFile = resolvedSourcePath.isNotEmpty
        ? File(resolvedSourcePath)
        : null;

    final candidateRequiresCustomMatchByNormalized = <String, bool>{};
    for (final entry in _discordRpcReplacedBuildRootsByNormalized.entries) {
      candidateRequiresCustomMatchByNormalized[entry.key] = false;
    }
    if (customSourceFile != null && await customSourceFile.exists()) {
      final staleRoots = await _discoverStaleDiscordRpcReplacementRoots(
        customSourceFile,
      );
      for (final root in staleRoots) {
        final normalized = _normalizePath(root);
        candidateRequiresCustomMatchByNormalized.putIfAbsent(
          normalized,
          () => true,
        );
      }
    }

    if (candidateRequiresCustomMatchByNormalized.isEmpty) return;

    _discordRpcRestoreInFlight = true;
    try {
      var restored = 0;
      var failed = 0;
      var skipped = 0;

      for (final entry in candidateRequiresCustomMatchByNormalized.entries) {
        final normalized = entry.key;
        final requireCustomMatch = entry.value;
        var buildRoot =
            _discordRpcReplacedBuildRootsByNormalized[normalized] ?? '';
        if (buildRoot.trim().isEmpty) {
          for (final version in _settings.versions) {
            if (_normalizePath(version.location) != normalized) continue;
            buildRoot = version.location;
            break;
          }
        }
        if (buildRoot.trim().isEmpty) {
          skipped++;
          _discordRpcReplacedBuildRootsByNormalized.remove(normalized);
          continue;
        }

        final targetDirectory = _discordRpcTargetDirectoryForBuildRoot(
          buildRoot,
        );
        final targetFile = File(
          _joinPath([targetDirectory.path, _discordRpcDllName]),
        );
        final originalFile = File(
          _joinPath([targetDirectory.path, _discordRpcOriginalDllName]),
        );

        try {
          if (!await originalFile.exists()) {
            skipped++;
            _discordRpcReplacedBuildRootsByNormalized.remove(normalized);
            continue;
          }
          if (requireCustomMatch) {
            if (customSourceFile == null ||
                !await customSourceFile.exists() ||
                !await targetFile.exists() ||
                !await _filesBinaryEqual(customSourceFile, targetFile)) {
              skipped++;
              continue;
            }
          }
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await originalFile.copy(targetFile.path);
          restored++;
          _discordRpcReplacedBuildRootsByNormalized.remove(normalized);
        } catch (error) {
          failed++;
          _log(
            'discord',
            'Failed to restore $_discordRpcDllName in $buildRoot: $error',
          );
        }
      }

      _log(
        'discord',
        'Discord RPC restore complete: $restored restored, $failed failed, $skipped skipped.',
      );
    } finally {
      _discordRpcRestoreInFlight = false;
    }
  }

  Future<bool> _filesBinaryEqual(File first, File second) async {
    try {
      if (!await first.exists() || !await second.exists()) return false;
      final firstLength = await first.length();
      final secondLength = await second.length();
      if (firstLength != secondLength) return false;

      final firstBytes = await first.readAsBytes();
      final secondBytes = await second.readAsBytes();
      if (firstBytes.length != secondBytes.length) return false;
      for (var index = 0; index < firstBytes.length; index++) {
        if (firstBytes[index] != secondBytes[index]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _findAllRecursiveFiles(
    String rootPath,
    String fileName, {
    int maxResults = 64,
  }) async {
    return Isolate.run(() async {
      final target = fileName.toLowerCase();
      final matches = <String>[];
      final root = Directory(rootPath);
      if (!root.existsSync()) return matches;

      try {
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final lowerPath = entity.path.toLowerCase();
            if (!lowerPath.endsWith('\\$target') &&
                !lowerPath.endsWith('/$target')) {
              continue;
            }
            matches.add(entity.path);
            if (matches.length >= maxResults) break;
          }
        }
      } catch (_) {
        // Ignore unreadable folders.
      }

      return matches;
    });
  }

  Future<int?> _startPausedAuxiliaryProcess(
    String buildRootPath,
    String exeName, {
    String? hintDir,
  }) async {
    String? executablePath;
    if (hintDir != null) {
      final candidate = _joinPath([hintDir, exeName]);
      if (File(candidate).existsSync()) {
        executablePath = candidate;
      }
    }
    executablePath ??= await _findRecursive(buildRootPath, exeName);
    if (executablePath == null) return null;
    try {
      final process = await Process.start(
        executablePath,
        const <String>[],
        workingDirectory: File(executablePath).parent.path,
        environment: {
          ...Platform.environment,
          'OPENSSL_ia32cap': '~0x20000000',
        },
      );
      final suspended = _suspendProcess(process.pid);
      if (suspended) {
        _log('game', 'Started and suspended $exeName (pid ${process.pid}).');
      } else {
        _log('game', 'Started $exeName (pid ${process.pid}).');
      }
      return process.pid;
    } catch (error) {
      _log('game', 'Failed to start $exeName: $error');
      return null;
    }
  }

  bool _suspendProcess(int pid) {
    if (!Platform.isWindows) return false;
    final processHandle = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
    if (processHandle == NULL) return false;
    try {
      final ntdll = ffi.DynamicLibrary.open('ntdll.dll');
      final ntSuspend = ntdll
          .lookupFunction<
            ffi.Int32 Function(ffi.IntPtr hWnd),
            int Function(int hWnd)
          >('NtSuspendProcess');
      return ntSuspend(processHandle) == 0;
    } catch (_) {
      return false;
    } finally {
      CloseHandle(processHandle);
    }
  }

  Future<_InjectionReport> _injectConfiguredPatchers(
    int gamePid,
    String gameVersion, {
    bool includeAuth = true,
    bool includeMemory = true,
    bool includeLargePak = false,
    bool includeUnreal = true,
    bool includeGameServer = false,
  }) async {
    final attempts = <_InjectionAttempt>[];

    // Inject authentication patcher first (must be done sequentially)
    if (includeAuth) {
      final authPath = _settings.authenticationPatcherPath.trim();
      if (authPath.isEmpty) {
        _log(
          'game',
          'Authentication patcher path is empty. Launch may fail on stock builds.',
        );
        attempts.add(
          const _InjectionAttempt(
            name: 'authentication patcher',
            required: true,
            attempted: false,
            success: false,
            error: 'Not configured.',
          ),
        );
      } else {
        attempts.add(
          await _injectAuthenticationPatcherWithRetry(
            gamePid: gamePid,
            authPath: authPath,
          ),
        );
      }
    }

    // Parallelize non-dependent patcher injections for better low-end PC performance
    final parallelInjections = <Future<_InjectionAttempt>>[];

    if (includeMemory && _isChapterOneVersion(gameVersion)) {
      final memoryPath = _settings.memoryPatcherPath.trim();
      if (memoryPath.isEmpty) {
        parallelInjections.add(
          Future.value(
            const _InjectionAttempt(
              name: 'memory patcher',
              required: false,
              attempted: false,
              success: true,
              skippedReason: 'Not configured.',
            ),
          ),
        );
      } else {
        parallelInjections.add(
          _injectSinglePatcher(
            gamePid: gamePid,
            patcherPath: memoryPath,
            patcherName: 'memory patcher',
            required: false,
          ),
        );
      }
    }

    if (includeLargePak) {
      final pakPath = _settings.largePakPatcherFilePath.trim();
      if (pakPath.isEmpty) {
        _log('gameserver', 'Large pak patcher is enabled but not configured.');
        parallelInjections.add(
          Future.value(
            const _InjectionAttempt(
              name: 'large pak patcher',
              required: false,
              attempted: false,
              success: false,
              error: 'Not configured.',
            ),
          ),
        );
      } else {
        parallelInjections.add(
          _injectSinglePatcher(
            gamePid: gamePid,
            patcherPath: pakPath,
            patcherName: 'large pak patcher',
            required: false,
          ),
        );
      }
    }

    if (includeUnreal) {
      final unrealPath = _settings.unrealEnginePatcherPath.trim();
      if (unrealPath.isEmpty) {
        parallelInjections.add(
          Future.value(
            const _InjectionAttempt(
              name: 'unreal engine patcher',
              required: false,
              attempted: false,
              success: true,
              skippedReason: 'Not configured.',
            ),
          ),
        );
      } else {
        parallelInjections.add(
          _injectSinglePatcher(
            gamePid: gamePid,
            patcherPath: unrealPath,
            patcherName: 'unreal engine patcher',
            required: false,
          ),
        );
      }
    }

    if (includeGameServer) {
      final gameServerPath = _settings.gameServerFilePath.trim();
      if (gameServerPath.isNotEmpty) {
        parallelInjections.add(
          _injectGameServerPatcherWithRetry(
            gamePid: gamePid,
            gameServerPath: gameServerPath,
          ),
        );
      } else {
        _log('game', 'Game server patcher path is empty.');
        parallelInjections.add(
          Future.value(
            const _InjectionAttempt(
              name: 'game server patcher',
              required: true,
              attempted: false,
              success: false,
              error: 'Not configured.',
            ),
          ),
        );
      }
    }

    // Wait for all parallel injections to complete concurrently
    if (parallelInjections.isNotEmpty) {
      attempts.addAll(await Future.wait(parallelInjections));
    }

    return _InjectionReport(attempts);
  }

  Future<_InjectionAttempt> _injectGameServerPatcherWithRetry({
    required int gamePid,
    required String gameServerPath,
  }) async {
    _InjectionAttempt attempt = await _injectSinglePatcher(
      gamePid: gamePid,
      patcherPath: gameServerPath,
      patcherName: 'game server patcher',
      required: true,
    );
    if (attempt.success || !attempt.attempted) return attempt;

    for (var retry = 2; retry <= _gameServerInjectionMaxAttempts; retry++) {
      _log(
        'game',
        'Game server patcher injection retry $retry/$_gameServerInjectionMaxAttempts.',
      );
      // Use exponential backoff instead of fixed delay for better low-end PC performance
      final delayMs = _calculateExponentialBackoffMs(
        retry,
        _gameServerInjectionRetryDelayMs,
        _gameServerInjectionMaxRetryDelayMs,
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      attempt = await _injectSinglePatcher(
        gamePid: gamePid,
        patcherPath: gameServerPath,
        patcherName: 'game server patcher',
        required: true,
      );
      if (attempt.success || !attempt.attempted) return attempt;
    }

    final baseError = attempt.error ?? 'Unknown error.';
    return _InjectionAttempt(
      name: attempt.name,
      required: attempt.required,
      attempted: attempt.attempted,
      success: false,
      error: '$baseError (after $_gameServerInjectionMaxAttempts attempts)',
    );
  }

  Future<_InjectionAttempt> _injectAuthenticationPatcherWithRetry({
    required int gamePid,
    required String authPath,
  }) async {
    await Future<void>.delayed(
      const Duration(milliseconds: _authInjectionInitialDelayMs),
    );

    Future<String> repairAuthPathIfNeeded(String configured) async {
      final candidate = configured.trim();
      if (candidate.isNotEmpty && File(candidate).existsSync()) {
        return candidate;
      }

      final bundledPath = await _ensureBundledDll(
        bundledAssetPath: 'assets/dlls/Tellurium.dll',
        bundledFileName: 'Tellurium.dll',
        label: 'authentication patcher',
      );
      final nextPath = bundledPath?.trim() ?? '';
      if (nextPath.isEmpty) return candidate;

      _log(
        'settings',
        'Repairing authentication patcher path. Using bundled default at $nextPath.',
      );
      if (mounted) {
        setState(() {
          _settings = _settings.copyWith(authenticationPatcherPath: nextPath);
          _authenticationPatcherController.text = nextPath;
        });
      } else {
        _settings = _settings.copyWith(authenticationPatcherPath: nextPath);
        _authenticationPatcherController.text = nextPath;
      }
      try {
        await _saveSettings(toast: false, applyControllers: false);
      } catch (error) {
        _log(
          'settings',
          'Failed to persist repaired auth patcher path: $error',
        );
      }
      return nextPath;
    }

    var resolvedAuthPath = await repairAuthPathIfNeeded(authPath);
    _InjectionAttempt attempt = await _injectSinglePatcher(
      gamePid: gamePid,
      patcherPath: resolvedAuthPath,
      patcherName: 'authentication patcher',
      required: true,
    );
    if (attempt.success || !attempt.attempted) return attempt;

    for (var retry = 2; retry <= _authInjectionMaxAttempts; retry++) {
      _log(
        'game',
        'Authentication patcher injection retry $retry/$_authInjectionMaxAttempts.',
      );
      // Use exponential backoff instead of fixed delay for better low-end PC performance
      final delayMs = _calculateExponentialBackoffMs(
        retry,
        _authInjectionRetryDelayMs,
        _authInjectionMaxRetryDelayMs,
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      resolvedAuthPath = await repairAuthPathIfNeeded(resolvedAuthPath);
      attempt = await _injectSinglePatcher(
        gamePid: gamePid,
        patcherPath: resolvedAuthPath,
        patcherName: 'authentication patcher',
        required: true,
      );
      if (attempt.success || !attempt.attempted) return attempt;
    }

    final baseError = attempt.error ?? 'Unknown error.';
    return _InjectionAttempt(
      name: attempt.name,
      required: attempt.required,
      attempted: attempt.attempted,
      success: false,
      error: '$baseError (after $_authInjectionMaxAttempts attempts)',
    );
  }

  bool _isChapterOneVersion(String version) {
    final match = RegExp(r'\d+').firstMatch(version);
    final major = int.tryParse(match?.group(0) ?? '');
    if (major == null) return true;
    return major < 10;
  }

  Future<_InjectionAttempt> _injectSinglePatcher({
    required int gamePid,
    required String patcherPath,
    required String patcherName,
    required bool required,
  }) async {
    final path = patcherPath.trim();
    if (path.isEmpty) {
      return _InjectionAttempt(
        name: patcherName,
        required: required,
        attempted: false,
        success: !required,
        error: required ? 'Not configured.' : null,
        skippedReason: required ? null : 'Not configured.',
      );
    }
    final file = File(path);
    if (!file.existsSync()) {
      _log('game', 'Cannot inject $patcherName: file not found at $path.');
      return _InjectionAttempt(
        name: patcherName,
        required: required,
        attempted: false,
        success: false,
        error: 'File not found.',
      );
    }
    if (!path.toLowerCase().endsWith('.dll')) {
      _log('game', 'Cannot inject $patcherName: file is not a DLL.');
      return _InjectionAttempt(
        name: patcherName,
        required: required,
        attempted: false,
        success: false,
        error: 'Not a DLL.',
      );
    }

    try {
      await _injectDllIntoProcess(gamePid, path);
      _log('game', 'Injected $patcherName.');
      return _InjectionAttempt(
        name: patcherName,
        required: required,
        attempted: true,
        success: true,
      );
    } catch (error) {
      _log('game', 'Failed to inject $patcherName: $error');
      return _InjectionAttempt(
        name: patcherName,
        required: required,
        attempted: true,
        success: false,
        error: error.toString(),
      );
    }
  }

  Future<void> _injectDllIntoProcess(int pid, String dllPath) async {
    if (!Platform.isWindows) return;
    final dllFile = File(dllPath);
    if (!dllFile.existsSync()) {
      throw 'DLL not found: $dllPath';
    }
    // WinAPI calls (notably WaitForSingleObject) can block the UI isolate, so
    // do the injection work in a background isolate.
    await Isolate.run(() {
      const waitObject0 = 0x00000000;
      const waitTimeout = 0x00000102;

      final processHandle = OpenProcess(
        PROCESS_CREATE_THREAD |
            PROCESS_QUERY_INFORMATION |
            PROCESS_VM_OPERATION |
            PROCESS_VM_WRITE |
            PROCESS_VM_READ,
        FALSE,
        pid,
      );
      if (processHandle == NULL) {
        throw 'OpenProcess failed for pid $pid';
      }

      final kernelModuleName = 'KERNEL32.DLL'.toNativeUtf16();
      final loadLibraryProcName = 'LoadLibraryW'.toNativeUtf8();
      final dllPathNative = dllPath.toNativeUtf16();

      try {
        final kernelModule = GetModuleHandle(kernelModuleName);
        if (kernelModule == NULL) {
          throw 'GetModuleHandle failed.';
        }

        final processAddress = GetProcAddress(
          kernelModule,
          loadLibraryProcName,
        );
        if (processAddress == ffi.nullptr) {
          throw 'GetProcAddress failed for LoadLibraryW.';
        }

        final bytesLength = (dllPath.length + 1) * 2;
        final remoteAddress = VirtualAllocEx(
          processHandle,
          ffi.nullptr,
          bytesLength,
          MEM_COMMIT | MEM_RESERVE,
          PAGE_READWRITE,
        );
        if (remoteAddress == ffi.nullptr) {
          throw 'VirtualAllocEx failed.';
        }

        final writeMemoryResult = WriteProcessMemory(
          processHandle,
          remoteAddress,
          dllPathNative.cast(),
          bytesLength,
          ffi.nullptr,
        );
        if (writeMemoryResult != 1) {
          throw 'WriteProcessMemory failed.';
        }

        final createThreadResult = CreateRemoteThread(
          processHandle,
          ffi.nullptr,
          0,
          processAddress.cast<ffi.NativeFunction<LPTHREAD_START_ROUTINE>>(),
          remoteAddress,
          0,
          ffi.nullptr,
        );
        if (createThreadResult == NULL) {
          throw 'CreateRemoteThread failed.';
        }

        try {
          final waitResult = WaitForSingleObject(
            createThreadResult,
            _dllInjectionWaitMs,
          );
          if (waitResult == waitTimeout) {
            throw 'Injection timed out.';
          }
          if (waitResult != waitObject0) {
            throw 'WaitForSingleObject failed (code $waitResult).';
          }

          final exitCode = calloc<ffi.Uint32>();
          try {
            // The win32 package doesn't currently expose GetExitCodeThread, so
            // bind it directly. We only need to know whether LoadLibraryW
            // returned non-zero.
            final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
            final getExitCodeThread = kernel32
                .lookupFunction<
                  ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<ffi.Uint32>),
                  int Function(int, ffi.Pointer<ffi.Uint32>)
                >('GetExitCodeThread');

            final ok = getExitCodeThread(createThreadResult, exitCode);
            if (ok == 0) throw 'GetExitCodeThread failed.';
            if (exitCode.value == 0) {
              throw 'LoadLibraryW returned 0 (DLL failed to load).';
            }
          } finally {
            calloc.free(exitCode);
          }
        } finally {
          VirtualFreeEx(processHandle, remoteAddress, 0, MEM_RELEASE);
          CloseHandle(createThreadResult);
        }
      } finally {
        calloc.free(kernelModuleName);
        calloc.free(loadLibraryProcName);
        calloc.free(dllPathNative);
        CloseHandle(processHandle);
      }
    });
  }

  Future<void> _closeFortnite() async {
    if (_gameAction != _GameActionState.idle) return;
    setState(() => _gameAction = _GameActionState.closing);
    try {
      if (!Platform.isWindows) {
        _toast('Close Fortnite is only available on Windows');
        return;
      }
      final instances = <_FortniteProcessState>[
        ...?_gameInstance == null
            ? null
            : <_FortniteProcessState>[_gameInstance!],
        ..._extraGameInstances,
      ];
      final process = _gameProcess;
      if (instances.isEmpty && process == null) {
        _clearUiStatus(host: false);
        return;
      }
      _setUiStatus(
        host: false,
        message: 'Closing Fortnite...',
        severity: _UiStatusSeverity.info,
      );

      final pids = <int>{if (process != null) process.pid};

      for (final instance in instances) {
        pids.add(instance.pid);
        if (instance.launcherPid != null) pids.add(instance.launcherPid!);
        if (instance.eacPid != null) pids.add(instance.eacPid!);
        instance.kill(includeChild: false);
      }
      if (instances.isEmpty && process != null) {
        _FortniteProcessState._killPidSafe(process.pid);
      }

      for (final pid in pids) {
        try {
          await Process.run('taskkill', [
            '/F',
            '/PID',
            '$pid',
          ], runInShell: true);
        } catch (_) {
          // Ignore already-closed processes.
        }
      }

      _gameInstance = null;
      _gameProcess = null;
      _extraGameInstances.clear();
      _log('game', 'Close Fortnite command executed.');
      if (mounted) _toast('Fortnite closed');
    } finally {
      _clearUiStatus(host: false);
      if (mounted) setState(() => _gameAction = _GameActionState.idle);
      _syncLauncherDiscordPresence();
    }
  }

  Future<void> _closeHosting() async {
    if (_gameAction != _GameActionState.idle) return;
    if (_gameServerLaunching) return;
    if (!Platform.isWindows) {
      _toast('Hosting close is only available on Windows');
      return;
    }

    final instance = _gameServerInstance;
    final process = _gameServerProcess;
    if (instance == null && process == null) {
      _clearUiStatus(host: true);
      return;
    }

    _setUiStatus(
      host: true,
      message: 'Stopping game server...',
      severity: _UiStatusSeverity.info,
    );

    final pids = <int>{
      if (instance != null) instance.pid,
      if (instance?.launcherPid != null) instance!.launcherPid!,
      if (instance?.eacPid != null) instance!.eacPid!,
      if (process != null) process.pid,
    };

    if (instance != null) {
      instance.killAll();
    } else if (process != null) {
      _FortniteProcessState._killPidSafe(process.pid);
    }

    for (final pid in pids) {
      try {
        await Process.run('taskkill', ['/F', '/PID', '$pid'], runInShell: true);
      } catch (_) {
        // Ignore already-closed processes.
      }
    }

    _gameServerInstance = null;
    _gameServerProcess = null;
    _stopHostingWhenNoClientsRemain = false;
    _clearUiStatus(host: true);
    _log('gameserver', 'Close hosting command executed.');
    if (mounted) _toast('Game server closed');
    _syncLauncherDiscordPresence();
  }

  Future<void> _importVersion() async {
    final importRequest = await _promptImportBuildDialog();
    if (importRequest == null) return;

    if (_isVersionLocationImported(importRequest.buildRootPath)) {
      final existing = _settings.versions.firstWhere(
        (entry) =>
            _normalizePath(entry.location) ==
            _normalizePath(importRequest.buildRootPath),
      );
      setState(() {
        _settings = _settings.copyWith(selectedVersionId: existing.id);
      });
      await _saveSettings(toast: false);
      _toast('That build folder is already imported');
      return;
    }

    final executable = await _findBuildExecutable(importRequest.buildRootPath);
    if (executable == null) {
      _toast('Fortnite executable not found inside selected build');
      return;
    }

    final gameVersionFromName = _deriveVersion(importRequest.buildName);
    final resolvedGameVersion = gameVersionFromName == 'Unknown'
        ? _deriveVersion(importRequest.buildRootPath)
        : gameVersionFromName;
    final splashImagePath = await _findBuildSplashImage(
      importRequest.buildRootPath,
      gameVersionHint: resolvedGameVersion,
      buildNameHint: importRequest.buildName,
    );

    final version = VersionEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(90000)}',
      name: importRequest.buildName,
      gameVersion: resolvedGameVersion,
      location: importRequest.buildRootPath,
      executablePath: executable,
      splashImagePath: splashImagePath ?? '',
    );
    setState(() {
      _settings = _settings.copyWith(
        versions: [..._settings.versions, version],
        selectedVersionId: version.id,
      );
    });
    _syncLibraryActionsNudgePulse();
    await _saveSettings(toast: false);
    if (mounted) _toast('Version imported');
  }

  Future<void> _importManyVersionsFromParent(String parentPath) async {
    final rootPath = parentPath.trim();
    if (rootPath.isEmpty) return;

    final buildRoots = await _discoverBuildRoots(rootPath);
    if (buildRoots.length < 2) {
      _toast(
        'Select a folder that contains multiple build folders with FortniteGame and Engine',
      );
      return;
    }

    await _importManyVersionsFromFolders(buildRoots);
  }

  Future<List<String>> _discoverBuildRoots(String parentPath) async {
    final parent = Directory(parentPath);
    if (!parent.existsSync()) return const <String>[];

    const maxDepth = 4;
    const maxDirectories = 1600;

    final queue = <_DirectoryDepth>[
      _DirectoryDepth(directory: parent, depth: 0),
    ];
    final seenDirectories = <String>{_normalizePath(parent.path)};
    final discoveredRoots = <String>[];
    final discoveredNormalized = <String>{};
    var scannedDirectories = 0;

    while (queue.isNotEmpty && scannedDirectories < maxDirectories) {
      final current = queue.removeLast();
      scannedDirectories++;

      try {
        await for (final entity in current.directory.list(followLinks: false)) {
          if (entity is! Directory) continue;
          if (_isIgnoredSplashDirectory(entity.path)) continue;

          final normalizedPath = _normalizePath(entity.path);
          if (!seenDirectories.add(normalizedPath)) continue;

          if (_isBuildRootValid(entity.path)) {
            if (discoveredNormalized.add(normalizedPath)) {
              discoveredRoots.add(entity.path);
            }
            continue;
          }

          if (current.depth < maxDepth) {
            queue.add(
              _DirectoryDepth(directory: entity, depth: current.depth + 1),
            );
          }
        }
      } catch (_) {
        // Skip unreadable folders.
      }
    }

    discoveredRoots.sort(
      (left, right) =>
          _compareVersionStrings(_basename(left), _basename(right)),
    );
    return discoveredRoots;
  }

  Future<void> _importManyVersionsFromFolders(Iterable<String> folders) async {
    final normalizedSelection = <String>{};
    final selectedFolders = <String>[];
    for (final folder in folders) {
      final trimmed = folder.trim();
      if (trimmed.isEmpty) continue;
      final normalized = _normalizePath(trimmed);
      if (!normalizedSelection.add(normalized)) continue;
      selectedFolders.add(trimmed);
    }

    if (selectedFolders.isEmpty) {
      _toast('No build folders selected');
      return;
    }

    final existingLocations = _settings.versions
        .map((entry) => _normalizePath(entry.location))
        .toSet();
    final imported = <VersionEntry>[];
    var skippedDuplicates = 0;
    var skippedInvalid = 0;

    for (final root in selectedFolders) {
      final normalizedRoot = _normalizePath(root);
      if (existingLocations.contains(normalizedRoot)) {
        skippedDuplicates++;
        continue;
      }
      if (!_isBuildRootValid(root)) {
        skippedInvalid++;
        continue;
      }

      final executable = await _findBuildExecutable(root);
      if (executable == null) {
        skippedInvalid++;
        continue;
      }

      final buildName = _basename(root);
      final gameVersionFromName = _deriveVersion(buildName);
      final resolvedGameVersion = gameVersionFromName == 'Unknown'
          ? _deriveVersion(root)
          : gameVersionFromName;
      final splashImagePath = await _findBuildSplashImage(
        root,
        gameVersionHint: resolvedGameVersion,
        buildNameHint: buildName,
      );

      imported.add(
        VersionEntry(
          id: '${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(90000)}',
          name: buildName,
          gameVersion: resolvedGameVersion,
          location: root,
          executablePath: executable,
          splashImagePath: splashImagePath ?? '',
        ),
      );
      existingLocations.add(normalizedRoot);
    }

    if (imported.isEmpty) {
      final details = [
        if (skippedDuplicates > 0) '$skippedDuplicates duplicate',
        if (skippedInvalid > 0) '$skippedInvalid invalid',
      ].join(', ');
      _toast(
        details.isEmpty
            ? 'No builds imported'
            : 'No builds imported ($details)',
      );
      return;
    }

    setState(() {
      _settings = _settings.copyWith(
        versions: [..._settings.versions, ...imported],
        selectedVersionId: imported.last.id,
      );
    });
    _syncLibraryActionsNudgePulse();
    await _saveSettings(toast: false);

    final summaryParts = <String>[
      'Imported ${imported.length} build${imported.length == 1 ? '' : 's'}',
      if (skippedDuplicates > 0) '$skippedDuplicates duplicate',
      if (skippedInvalid > 0) '$skippedInvalid invalid',
    ];
    _toast(summaryParts.join(' | '));
  }

  Future<void> _editVersion(VersionEntry entry) async {
    final editRequest = await _promptImportBuildDialog(
      title: 'Edit Build',
      description:
          'Update your build name and root folder. The folder must include FortniteGame and Engine.',
      confirmLabel: 'Save',
      headerIcon: Icons.edit_rounded,
      confirmIcon: Icons.save_rounded,
      initialBuildName: entry.name,
      initialBuildRootPath: entry.location,
      allowBulkImport: false,
    );
    if (editRequest == null) return;

    if (_isVersionLocationImported(
      editRequest.buildRootPath,
      excludeVersionId: entry.id,
    )) {
      _toast('Another imported build already uses that folder');
      return;
    }

    final executable = await _findBuildExecutable(editRequest.buildRootPath);
    if (executable == null) {
      _toast('Fortnite executable not found inside selected build');
      return;
    }

    final gameVersionFromName = _deriveVersion(editRequest.buildName);
    final resolvedGameVersion = gameVersionFromName == 'Unknown'
        ? _deriveVersion(editRequest.buildRootPath)
        : gameVersionFromName;
    final splashImagePath = await _findBuildSplashImage(
      editRequest.buildRootPath,
      gameVersionHint: resolvedGameVersion,
      buildNameHint: editRequest.buildName,
    );

    setState(() {
      _settings = _settings.copyWith(
        versions: _settings.versions.map((version) {
          if (version.id != entry.id) return version;
          return version.copyWith(
            name: editRequest.buildName,
            gameVersion: resolvedGameVersion,
            location: editRequest.buildRootPath,
            executablePath: executable,
            splashImagePath: splashImagePath ?? '',
          );
        }).toList(),
      );
    });
    await _saveSettings(toast: false);
    if (mounted) _toast('Version updated');
  }

  Future<_BuildImportRequest?> _promptImportBuildDialog({
    String title = 'Import Installation',
    String description =
        'Select your Fortnite installation path to import an existing version.',
    String confirmLabel = 'Import',
    IconData headerIcon = Icons.add_box_rounded,
    IconData confirmIcon = Icons.download_done_rounded,
    String initialBuildName = '',
    String initialBuildRootPath = '',
    bool allowBulkImport = true,
  }) async {
    final nameController = TextEditingController(text: initialBuildName);
    final folderController = TextEditingController(text: initialBuildRootPath);
    final nameFocusNode = FocusNode();
    final folderFocusNode = FocusNode();
    String validation = '';
    // Bulk import uses a 2-step flow (path -> name). Edit flow stays single step.
    var step = allowBulkImport ? 0 : 1;

    try {
      return await showGeneralDialog<_BuildImportRequest>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var dismissQueued = false;
          return SafeArea(
            child: Center(
              child: StatefulBuilder(
                builder: (dialogContext, setDialogState) {
                  Future<void> pickBuildFolder() async {
                    final path = await FilePicker.platform.getDirectoryPath(
                      dialogTitle:
                          'Select build root (must contain FortniteGame and Engine)',
                    );
                    if (path == null || path.isEmpty) return;
                    folderController.text = path;
                    if (nameController.text.trim().isEmpty) {
                      nameController.text = _basename(path);
                    }
                    setDialogState(() => validation = '');
                  }

                  void dismissDialogSafely([_BuildImportRequest? result]) {
                    if (dismissQueued) return;
                    dismissQueued = true;
                    FocusManager.instance.primaryFocus?.unfocus();
                    // Let focus/overlays settle before popping. Popping on the same
                    // frame as an Escape key press can intermittently trigger
                    // `InheritedElement.debugDeactivated` assertions on desktop.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop(result);
                      });
                    });
                  }

                  final stepDescription = step == 0
                      ? description
                      : allowBulkImport
                      ? 'Name your build and confirm its root folder.'
                      : description;
                  final secondary = Theme.of(
                    dialogContext,
                  ).colorScheme.secondary;
                  final maxHeight = min(
                    640.0,
                    MediaQuery.sizeOf(dialogContext).height - 40,
                  );

                  return Focus(
                    autofocus: true,
                    onKeyEvent: (_, event) {
                      if ((event is KeyDownEvent) &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        if (nameFocusNode.hasFocus ||
                            folderFocusNode.hasFocus) {
                          nameFocusNode.unfocus();
                          folderFocusNode.unfocus();
                          return KeyEventResult.handled;
                        }
                        dismissDialogSafely();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 620,
                          maxHeight: maxHeight,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _dialogSurfaceColor(dialogContext),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: _onSurface(dialogContext, 0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _dialogShadowColor(dialogContext),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      headerIcon,
                                      color: _onSurface(dialogContext, 0.94),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w700,
                                        color: _onSurface(dialogContext, 0.96),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stepDescription,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: _onSurface(
                                              dialogContext,
                                              0.74,
                                            ),
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        if (step == 0) ...[
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              color: _adaptiveScrimColor(
                                                dialogContext,
                                                darkAlpha: 0.08,
                                                lightAlpha: 0.20,
                                              ),
                                              border: Border.all(
                                                color: _onSurface(
                                                  dialogContext,
                                                  0.1,
                                                ),
                                              ),
                                            ),
                                            child: Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Select the path that contains both',
                                                  style: TextStyle(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.82,
                                                    ),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 7,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: _adaptiveScrimColor(
                                                      dialogContext,
                                                      darkAlpha: 0.1,
                                                      lightAlpha: 0.22,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.1,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.folder_rounded,
                                                        size: 16,
                                                        color: _onSurface(
                                                          dialogContext,
                                                          0.88,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'FortniteGame',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: _onSurface(
                                                            dialogContext,
                                                            0.92,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 7,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: _adaptiveScrimColor(
                                                      dialogContext,
                                                      darkAlpha: 0.1,
                                                      lightAlpha: 0.22,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.1,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.folder_rounded,
                                                        size: 16,
                                                        color: _onSurface(
                                                          dialogContext,
                                                          0.88,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Engine',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: _onSurface(
                                                            dialogContext,
                                                            0.92,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  'folders.',
                                                  style: TextStyle(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.82,
                                                    ),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  focusNode: folderFocusNode,
                                                  controller: folderController,
                                                  onChanged: (_) =>
                                                      setDialogState(
                                                        () => validation = '',
                                                      ),
                                                  style: TextStyle(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.92,
                                                    ),
                                                  ),
                                                  cursorColor: secondary,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'Choose your path!',
                                                    hintStyle: TextStyle(
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.48,
                                                      ),
                                                    ),
                                                    prefixIcon: Icon(
                                                      Icons.folder_rounded,
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.78,
                                                      ),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        _adaptiveScrimColor(
                                                          dialogContext,
                                                          darkAlpha: 0.1,
                                                          lightAlpha: 0.2,
                                                        ),
                                                    isDense: true,
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 13,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          borderSide: BorderSide(
                                                            color: _onSurface(
                                                              dialogContext,
                                                              0.12,
                                                            ),
                                                          ),
                                                        ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          borderSide:
                                                              BorderSide(
                                                                color: secondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.95,
                                                                    ),
                                                                width: 1.2,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              OutlinedButton(
                                                onPressed: pickBuildFolder,
                                                style: OutlinedButton.styleFrom(
                                                  shape: const StadiumBorder(),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    46,
                                                  ),
                                                  foregroundColor: _onSurface(
                                                    dialogContext,
                                                    0.92,
                                                  ),
                                                  backgroundColor:
                                                      _adaptiveScrimColor(
                                                        dialogContext,
                                                        darkAlpha: 0.08,
                                                        lightAlpha: 0.16,
                                                      ),
                                                  side: BorderSide(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.14,
                                                    ),
                                                  ),
                                                ),
                                                child: const Text('Browse'),
                                              ),
                                            ],
                                          ),
                                        ] else ...[
                                          Text(
                                            'Build Name',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: _onSurface(
                                                dialogContext,
                                                0.82,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          TextField(
                                            focusNode: nameFocusNode,
                                            controller: nameController,
                                            onChanged: (_) => setDialogState(
                                              () => validation = '',
                                            ),
                                            style: TextStyle(
                                              color: _onSurface(
                                                dialogContext,
                                                0.92,
                                              ),
                                            ),
                                            cursorColor: secondary,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'e.g. Chapter 2 Season 4',
                                              hintStyle: TextStyle(
                                                color: _onSurface(
                                                  dialogContext,
                                                  0.48,
                                                ),
                                              ),
                                              prefixIcon: Icon(
                                                Icons.edit_rounded,
                                                color: _onSurface(
                                                  dialogContext,
                                                  0.72,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor: _adaptiveScrimColor(
                                                dialogContext,
                                                darkAlpha: 0.1,
                                                lightAlpha: 0.2,
                                              ),
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 13,
                                                  ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: BorderSide(
                                                  color: _onSurface(
                                                    dialogContext,
                                                    0.12,
                                                  ),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: BorderSide(
                                                  color: secondary.withValues(
                                                    alpha: 0.95,
                                                  ),
                                                  width: 1.2,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Build Root Folder',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: _onSurface(
                                                dialogContext,
                                                0.82,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  focusNode: folderFocusNode,
                                                  controller: folderController,
                                                  onChanged: (_) =>
                                                      setDialogState(
                                                        () => validation = '',
                                                      ),
                                                  style: TextStyle(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.92,
                                                    ),
                                                  ),
                                                  cursorColor: secondary,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        r'D:\Builds\Fortnite\14.60',
                                                    hintStyle: TextStyle(
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.48,
                                                      ),
                                                    ),
                                                    prefixIcon: Icon(
                                                      Icons.folder_rounded,
                                                      color: _onSurface(
                                                        dialogContext,
                                                        0.78,
                                                      ),
                                                    ),
                                                    filled: true,
                                                    fillColor:
                                                        _adaptiveScrimColor(
                                                          dialogContext,
                                                          darkAlpha: 0.1,
                                                          lightAlpha: 0.2,
                                                        ),
                                                    isDense: true,
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 13,
                                                        ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          borderSide: BorderSide(
                                                            color: _onSurface(
                                                              dialogContext,
                                                              0.12,
                                                            ),
                                                          ),
                                                        ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          borderSide:
                                                              BorderSide(
                                                                color: secondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.95,
                                                                    ),
                                                                width: 1.2,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              OutlinedButton(
                                                onPressed: pickBuildFolder,
                                                style: OutlinedButton.styleFrom(
                                                  shape: const StadiumBorder(),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    46,
                                                  ),
                                                  foregroundColor: _onSurface(
                                                    dialogContext,
                                                    0.92,
                                                  ),
                                                  backgroundColor:
                                                      _adaptiveScrimColor(
                                                        dialogContext,
                                                        darkAlpha: 0.08,
                                                        lightAlpha: 0.16,
                                                      ),
                                                  side: BorderSide(
                                                    color: _onSurface(
                                                      dialogContext,
                                                      0.14,
                                                    ),
                                                  ),
                                                ),
                                                child: const Text('Browse'),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (validation.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            validation,
                                            style: const TextStyle(
                                              color: Color(0xFFFF9CB0),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (step == 0) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () {
                                        final path = folderController.text
                                            .trim();
                                        if (!_isBuildRootValid(path)) {
                                          setDialogState(() {
                                            validation =
                                                'Select a folder that contains FortniteGame and Engine.';
                                          });
                                          return;
                                        }
                                        if (nameController.text
                                            .trim()
                                            .isEmpty) {
                                          nameController.text = _basename(path);
                                        }
                                        setDialogState(() {
                                          validation = '';
                                          step = 1;
                                        });
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: secondary.withValues(
                                          alpha: 0.92,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 14,
                                        ),
                                        minimumSize: const Size.fromHeight(52),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'Next',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(Icons.arrow_forward_rounded),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      if (allowBulkImport)
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            final parentPath = await FilePicker
                                                .platform
                                                .getDirectoryPath(
                                                  dialogTitle:
                                                      'Select a folder that contains multiple build folders',
                                                );
                                            if (parentPath == null ||
                                                parentPath.trim().isEmpty) {
                                              return;
                                            }
                                            if (!dialogContext.mounted ||
                                                !mounted) {
                                              return;
                                            }
                                            dismissDialogSafely();
                                            if (!mounted) return;
                                            await _importManyVersionsFromParent(
                                              parentPath,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.playlist_add_rounded,
                                          ),
                                          label: const Text(
                                            'Import multiple builds',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            shape: const StadiumBorder(),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 11,
                                            ),
                                            side: BorderSide(
                                              color: _onSurface(
                                                dialogContext,
                                                0.14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: dismissDialogSafely,
                                        child: const Text('Cancel'),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      if (allowBulkImport)
                                        TextButton.icon(
                                          onPressed: () => setDialogState(() {
                                            validation = '';
                                            step = 0;
                                          }),
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                          ),
                                          label: const Text('Back'),
                                        ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: dismissDialogSafely,
                                        child: const Text('Cancel'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.icon(
                                        onPressed: () {
                                          final name = nameController.text
                                              .trim();
                                          final path = folderController.text
                                              .trim();
                                          if (name.isEmpty) {
                                            setDialogState(() {
                                              validation =
                                                  'Build name is required.';
                                            });
                                            return;
                                          }
                                          if (!_isBuildRootValid(path)) {
                                            setDialogState(() {
                                              validation =
                                                  'Pick a folder containing FortniteGame and Engine.';
                                            });
                                            return;
                                          }
                                          dismissDialogSafely(
                                            _BuildImportRequest(
                                              buildName: name,
                                              buildRootPath: path,
                                            ),
                                          );
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: secondary.withValues(
                                            alpha: 0.92,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: const StadiumBorder(),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 13,
                                          ),
                                        ),
                                        icon: Icon(confirmIcon),
                                        label: Text(confirmLabel),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3.2 * curved.value,
                          sigmaY: 3.2 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    } finally {
      nameFocusNode.dispose();
      folderFocusNode.dispose();
      nameController.dispose();
      folderController.dispose();
    }
  }

  bool _isBuildRootValid(String rootPath) {
    if (rootPath.trim().isEmpty) return false;
    final root = Directory(rootPath);
    if (!root.existsSync()) return false;
    final fortniteGame = Directory(_joinPath([rootPath, 'FortniteGame']));
    final engine = Directory(_joinPath([rootPath, 'Engine']));
    return fortniteGame.existsSync() && engine.existsSync();
  }

  bool _isVersionLocationImported(String path, {String? excludeVersionId}) {
    final normalized = _normalizePath(path);
    return _settings.versions.any((entry) {
      if (excludeVersionId != null && entry.id == excludeVersionId) {
        return false;
      }
      return _normalizePath(entry.location) == normalized;
    });
  }

  String _normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  Future<String?> _findBuildExecutable(String buildRootPath) async {
    final expectedPath = _joinPath([
      buildRootPath,
      'FortniteGame',
      'Binaries',
      'Win64',
      _shippingExeName,
    ]);
    if (File(expectedPath).existsSync()) return expectedPath;

    final fortniteGameRoot = _joinPath([buildRootPath, 'FortniteGame']);
    if (Directory(fortniteGameRoot).existsSync()) {
      final foundInFortniteGame = await _findRecursive(
        fortniteGameRoot,
        _shippingExeName,
      );
      if (foundInFortniteGame != null) return foundInFortniteGame;
    }

    return _findRecursive(buildRootPath, _shippingExeName);
  }

  Future<String?> _findBuildSplashImage(
    String buildRootPath, {
    String? gameVersionHint,
    String? buildNameHint,
  }) async {
    final root = Directory(buildRootPath);
    if (!root.existsSync()) return null;

    final tokens = _buildSplashHintTokens(
      gameVersionHint: gameVersionHint,
      buildNameHint: buildNameHint,
      buildRootPath: buildRootPath,
    );

    final priorityDirectories = <String>[
      _joinPath([buildRootPath, 'FortniteGame', 'Content', 'Splash']),
      _joinPath([buildRootPath, 'FortniteGame', 'Content', 'Athena']),
      _joinPath([buildRootPath, 'FortniteGame', 'Content', 'UI']),
      _joinPath([buildRootPath, 'FortniteGame', 'Content']),
      buildRootPath,
    ];

    String? bestPath;
    var bestScore = double.negativeInfinity;
    var scannedDirectories = 0;

    for (final directoryPath in priorityDirectories) {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) continue;

      final scan = await _scanSplashCandidates(
        root: directory,
        tokens: tokens,
        maxDirectories: directoryPath == buildRootPath ? 220 : 160,
      );
      scannedDirectories += scan.scannedDirectories;

      if (scan.bestPath != null && scan.bestScore > bestScore) {
        bestPath = scan.bestPath;
        bestScore = scan.bestScore;
      }

      if (bestScore >= 180 || scannedDirectories >= 650) break;
    }

    return bestScore >= 40 ? bestPath : null;
  }

  Future<_SplashScanResult> _scanSplashCandidates({
    required Directory root,
    required Set<String> tokens,
    required int maxDirectories,
  }) async {
    final queue = <_DirectoryDepth>[_DirectoryDepth(directory: root, depth: 0)];

    String? bestPath;
    var bestScore = double.negativeInfinity;
    var scannedDirectories = 0;

    while (queue.isNotEmpty && scannedDirectories < maxDirectories) {
      final current = queue.removeLast();
      scannedDirectories++;

      try {
        await for (final entity in current.directory.list(followLinks: false)) {
          if (entity is File) {
            final score = _scoreSplashCandidate(entity.path, tokens);
            if (score > bestScore) {
              bestScore = score;
              bestPath = entity.path;
            }
            continue;
          }
          if (entity is Directory && current.depth < 6) {
            if (_isIgnoredSplashDirectory(entity.path)) continue;
            queue.add(
              _DirectoryDepth(directory: entity, depth: current.depth + 1),
            );
          }
        }
      } catch (_) {
        // Skip unreadable folders.
      }
    }

    return _SplashScanResult(
      bestPath: bestPath,
      bestScore: bestScore,
      scannedDirectories: scannedDirectories,
    );
  }

  double _scoreSplashCandidate(String filePath, Set<String> tokens) {
    final lowerPath = filePath.toLowerCase();
    if (!_splashImageExtensions.any(lowerPath.endsWith)) {
      return double.negativeInfinity;
    }

    var score = 0.0;
    if (lowerPath.contains('splash')) score += 180;
    if (lowerPath.contains('loading')) score += 135;
    if (lowerPath.contains('loadingscreen')) score += 145;
    if (lowerPath.contains('keyart')) score += 70;
    if (lowerPath.contains('frontend')) score += 42;
    if (lowerPath.contains('athena')) score += 32;
    if (lowerPath.contains('season')) score += 24;
    if (lowerPath.contains('chapter')) score += 24;
    if (lowerPath.contains('battlepass')) score += 15;
    if (lowerPath.contains('background')) score += 14;

    if (lowerPath.contains('icon') ||
        lowerPath.contains('thumb') ||
        lowerPath.contains('thumbnail') ||
        lowerPath.contains('logo') ||
        lowerPath.contains('banner')) {
      score -= 55;
    }
    if (lowerPath.contains('small') ||
        lowerPath.contains('_sm') ||
        lowerPath.contains('preview')) {
      score -= 24;
    }
    if (lowerPath.contains('\\engine\\') || lowerPath.contains('/engine/')) {
      score -= 16;
    }

    for (final token in tokens) {
      if (token.isNotEmpty && lowerPath.contains(token)) score += 34;
    }

    try {
      final fileLength = File(filePath).lengthSync();
      if (fileLength < 60 * 1024) score -= 30;
      if (fileLength > 250 * 1024) score += 18;
      if (fileLength > 600 * 1024) score += 24;
      if (fileLength > 1024 * 1024) score += 20;
    } catch (_) {
      // Keep scoring based on path when size cannot be read.
    }

    return score;
  }

  Set<String> _buildSplashHintTokens({
    String? gameVersionHint,
    String? buildNameHint,
    required String buildRootPath,
  }) {
    final source = [
      gameVersionHint ?? '',
      buildNameHint ?? '',
      _basename(buildRootPath),
    ].join(' ').toLowerCase();

    final tokens = <String>{};
    for (final match in RegExp(r'\d+(?:\.\d+)?').allMatches(source)) {
      final value = match.group(0)!;
      tokens.add(value);
      tokens.add(value.replaceAll('.', ''));
      tokens.add(value.replaceAll('.', '_'));
      tokens.add(value.replaceAll('.', '-'));
      if (value.contains('.')) {
        tokens.add(value.split('.').first);
      }
    }

    final words = source
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length >= 4 || RegExp(r'\d').hasMatch(word)) {
        tokens.add(word);
      }
    }

    tokens.removeWhere((token) {
      return token.isEmpty ||
          token == 'fortnite' ||
          token == 'fortnitegame' ||
          token == 'engine' ||
          token == 'content' ||
          token == 'build' ||
          token == 'version';
    });

    return tokens;
  }

  bool _isIgnoredSplashDirectory(String path) {
    final lower = _basename(path).toLowerCase();
    return lower == '.git' ||
        lower == '.vs' ||
        lower == 'binaries' ||
        lower == 'cache' ||
        lower == 'deriveddatacache' ||
        lower == 'intermediate' ||
        lower == 'logs' ||
        lower == 'paks' ||
        lower == 'plugins' ||
        lower == 'saved';
  }

  Future<void> _removeVersion(String id) async {
    setState(() {
      final remaining = _settings.versions
          .where((element) => element.id != id)
          .toList();
      final selected =
          remaining.any((element) => element.id == _settings.selectedVersionId)
          ? _settings.selectedVersionId
          : (remaining.isNotEmpty ? remaining.first.id : '');
      _settings = _settings.copyWith(
        versions: remaining,
        selectedVersionId: selected,
      );
    });
    _syncLibraryActionsNudgePulse();
    await _saveSettings(toast: false);
  }

  Future<void> _clearAllVersions() async {
    if (_settings.versions.isEmpty) return;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogSurfaceColor(dialogContext),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _onSurface(dialogContext, 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: _dialogShadowColor(dialogContext),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clear all builds?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _onSurface(dialogContext, 0.96),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This will remove every imported build from the list.',
                          style: TextStyle(
                            color: _onSurface(dialogContext, 0.84),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB3261E),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Clear all'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _settings = _settings.copyWith(
        versions: const <VersionEntry>[],
        selectedVersionId: '',
      );
      _librarySearchController.clear();
      _versionSearchQuery = '';
    });
    _syncLibraryActionsNudgePulse();
    await _saveSettings(toast: false);
    if (mounted) _toast('All builds cleared');
  }

  Future<void> _pickAvatar() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Select profile picture',
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _settings = _settings.copyWith(profileAvatarPath: path));
    await _saveSettings(toast: false);
  }

  Future<void> _pickBackground() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Select background image',
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _settings = _settings.copyWith(backgroundImagePath: path));
    await _saveSettings(toast: false);
  }

  Future<void> _clearBackground() async {
    setState(() => _settings = _settings.copyWith(backgroundImagePath: ''));
    await _saveSettings(toast: false);
  }

  Future<void> _clearAvatar() async {
    setState(() => _settings = _settings.copyWith(profileAvatarPath: ''));
    await _saveSettings(toast: false);
  }

  Future<void> _openPath(String target) async {
    if (target.trim().isEmpty) return;
    if (!Platform.isWindows) return;
    await Process.start('explorer', [target], runInShell: true);
  }

  Future<void> _openLogs() => _openPath(_logFile.path);

  Future<void> _openInternalFiles() => _openPath(_dataDir.path);

  Future<void> _resetLauncher() async {
    if (!mounted) return;
    if (_gameAction != _GameActionState.idle ||
        _gameProcess != null ||
        _gameServerProcess != null ||
        _atlasBackendProcess != null) {
      _toast('Close Fortnite, game server, and backend before resetting');
      return;
    }

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogSurfaceColor(dialogContext),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _onSurface(dialogContext, 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: _dialogShadowColor(dialogContext),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reset launcher?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _onSurface(dialogContext, 0.96),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This will restore ATLAS Link to a default state and make it feel like a fresh install.',
                          style: TextStyle(
                            color: _onSurface(dialogContext, 0.86),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'It will:',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _onSurface(dialogContext, 0.9),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '- Clear imported builds\n'
                          '- Reset profile (name + PFP) and show first-run setup again\n'
                          '- Reset launch options, backend settings, visuals, and DLL paths\n'
                          '- Clear saved backends\n'
                          '- Clear internal caches (installer + bundled DLL copies)\n'
                          '- Clear launcher logs',
                          style: TextStyle(
                            color: _onSurface(dialogContext, 0.82),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB3261E),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: const Text('Reset'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _performLauncherReset();
  }

  Future<void> _performLauncherReset() async {
    _log('settings', 'Launcher reset started.');

    try {
      await _stopBackendProxy();
    } catch (_) {
      // Ignore proxy shutdown issues during reset.
    }

    _gameServerCrashStatusClearTimer?.cancel();
    _gameServerCrashStatusClearTimer = null;

    _pollTimer?.cancel();
    _pollTimer = null;
    _runtimePollingStarted = false;

    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    _flushLogBuffer();
    try {
      await _logWriteChain;
    } catch (_) {
      // Ignore pending log write failures.
    }

    Future<void> deleteDir(Directory dir) async {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup failures (locks, permissions, etc.).
      }
    }

    Future<void> deleteFile(File file) async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Ignore cleanup failures (locks, permissions, etc.).
      }
    }

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      final legacyDir = Directory(
        _joinPath([appData, _legacyLauncherDataDirName]),
      );
      if (_normalizePath(legacyDir.path) != _normalizePath(_dataDir.path)) {
        await deleteDir(legacyDir);
      }
    }

    await deleteDir(Directory(_joinPath([_dataDir.path, 'backend-installer'])));
    await deleteDir(
      Directory(_joinPath([_dataDir.path, 'launcher-installer'])),
    );
    await deleteDir(Directory(_joinPath([_dataDir.path, 'dlls'])));
    await deleteFile(_installStateFile);
    await deleteFile(_settingsFile);
    await deleteFile(_logFile);

    _logs.clear();
    _logWriteBuffer.clear();
    _afterMathCleanedRoots.clear();
    _discordRpcReplacedBuildRootsByNormalized.clear();
    _discordRpcRestoreInFlight = false;

    final defaults = LauncherSettings.defaults();
    if (mounted) {
      setState(() {
        _settings = defaults;
        _installState = LauncherInstallState.defaults();
        _tab = LauncherTab.home;
        _settingsReturnTab = LauncherTab.home;
        _settingsSection = SettingsSection.profile;
        _homeHeroIndex = 0;
        _showStartup = defaults.startupAnimationEnabled;
        _startupConfigResolved = true;
        _backendOnline = false;
        _checkingLauncherUpdate = false;
        _checkingBundledDllDefaultsUpdate = false;
        _bundledDllDefaultsUpdateAvailable = false;
        _updatingDefaultDlls = false;
        _bundledDllUpdatedFileNames = <String>{};
        _bundledDllRemoteAssetsByName = <String, _BundledDllRemoteAsset>{};
        _launcherUpdateDialogVisible = false;
        _launcherUpdateAutoCheckQueued = false;
        _launcherUpdateAutoChecked = false;
        _launcherUpdateInstallerCleanupWatcherActive = false;
        _gameInstance = null;
        _extraGameInstances.clear();
        _gameServerInstance = null;
        _gameUiStatus = null;
        _gameServerUiStatus = null;
        _atlasBackendActionBusy = false;
        _gameAction = _GameActionState.idle;
        _gameServerLaunching = false;
        _gameProcess = null;
        _gameServerProcess = null;
        _atlasBackendProcess = null;
        _atlasBackendInstallDialogContext = null;
        _atlasBackendInstallDialogVisible = false;
        _atlasBackendInstallCleanupWatcherActive = false;
        _profileSetupDialogVisible = false;
        _profileSetupDialogQueued = false;
        _discordRpcReplacedBuildRootsByNormalized.clear();
        _discordRpcRestoreInFlight = false;
        _sortedVersionsSource = null;
        _sortedVersionsCache = const <VersionEntry>[];
        _versionSearchQuery = '';
      });
    } else {
      _settings = defaults;
      _installState = LauncherInstallState.defaults();
      _tab = LauncherTab.home;
      _settingsReturnTab = LauncherTab.home;
      _settingsSection = SettingsSection.profile;
      _homeHeroIndex = 0;
      _showStartup = defaults.startupAnimationEnabled;
      _startupConfigResolved = true;
      _backendOnline = false;
      _checkingLauncherUpdate = false;
      _checkingBundledDllDefaultsUpdate = false;
      _bundledDllDefaultsUpdateAvailable = false;
      _updatingDefaultDlls = false;
      _bundledDllUpdatedFileNames = <String>{};
      _bundledDllRemoteAssetsByName = <String, _BundledDllRemoteAsset>{};
      _launcherUpdateDialogVisible = false;
      _launcherUpdateAutoCheckQueued = false;
      _launcherUpdateAutoChecked = false;
      _launcherUpdateInstallerCleanupWatcherActive = false;
      _gameInstance = null;
      _extraGameInstances.clear();
      _gameServerInstance = null;
      _gameUiStatus = null;
      _gameServerUiStatus = null;
      _atlasBackendActionBusy = false;
      _gameAction = _GameActionState.idle;
      _gameServerLaunching = false;
      _gameProcess = null;
      _gameServerProcess = null;
      _atlasBackendProcess = null;
      _atlasBackendInstallDialogContext = null;
      _atlasBackendInstallDialogVisible = false;
      _atlasBackendInstallCleanupWatcherActive = false;
      _profileSetupDialogVisible = false;
      _profileSetupDialogQueued = false;
      _discordRpcReplacedBuildRootsByNormalized.clear();
      _discordRpcRestoreInFlight = false;
      _sortedVersionsSource = null;
      _sortedVersionsCache = const <VersionEntry>[];
      _versionSearchQuery = '';
    }

    _librarySearchController.clear();

    if (mounted) widget.onDarkModeChanged(_settings.darkModeEnabled);
    _syncControllers();
    _shellEntranceController.stop();
    _shellEntranceController.value = _showStartup ? 0.0 : 1.0;
    _libraryActionsNudgeController.stop();
    _libraryActionsNudgeController.value = 0.0;

    // Restore bundled DLL defaults (Magnesium/memory/Tellurium/console) after
    // clearing internal files.
    await _applyBundledDllDefaults();
    await _saveSettings(toast: false);
    unawaited(_checkForBundledDllDefaultUpdates(silent: true));

    _installState = _installState.copyWith(
      lastSeenLauncherVersion: _launcherVersion,
    );
    try {
      await _saveInstallState();
    } catch (error) {
      _log('settings', 'Failed to save install state: $error');
    }

    if (!_showStartup) {
      _startRuntimeRefreshLoopIfNeeded();
    }

    _syncLauncherDiscordPresence();
    if (mounted) _toast('Launcher reset');
    _log('settings', 'Launcher reset completed.');
  }

  Future<String?> _pickSingleFile({
    required String dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Future<void> _updateAllDefaultDlls() async {
    if (_updatingDefaultDlls) return;
    if (mounted) {
      setState(() {
        _updatingDefaultDlls = true;
      });
    } else {
      _updatingDefaultDlls = true;
    }

    try {
      final remoteAssets = await _fetchBundledDllRemoteAssets(
        forceRefresh: true,
      );
      final sharedRemoteAssets = remoteAssets.isEmpty ? null : remoteAssets;

      await _resetBundledDllPathToLatest(
        spec: _bundledDllSpecByFileName('console.dll'),
        applySetting: (settings, path) =>
            settings.copyWith(unrealEnginePatcherPath: path),
        controller: _unrealEnginePatcherController,
        checkForUpdatesAfter: false,
        remoteAssets: sharedRemoteAssets,
      );
      await _resetBundledDllPathToLatest(
        spec: _bundledDllSpecByFileName('Tellurium.dll'),
        applySetting: (settings, path) =>
            settings.copyWith(authenticationPatcherPath: path),
        controller: _authenticationPatcherController,
        checkForUpdatesAfter: false,
        remoteAssets: sharedRemoteAssets,
      );
      await _resetBundledDllPathToLatest(
        spec: _bundledDllSpecByFileName('memory.dll'),
        applySetting: (settings, path) =>
            settings.copyWith(memoryPatcherPath: path),
        controller: _memoryPatcherController,
        checkForUpdatesAfter: false,
        remoteAssets: sharedRemoteAssets,
      );
      await _resetBundledDllPathToLatest(
        spec: _bundledDllSpecByFileName('Magnesium.dll'),
        applySetting: (settings, path) =>
            settings.copyWith(gameServerFilePath: path),
        controller: _gameServerFileController,
        checkForUpdatesAfter: false,
        remoteAssets: sharedRemoteAssets,
      );
      await _resetBundledDllPathToLatest(
        spec: _bundledDllSpecByFileName('LargePakPatch.dll'),
        applySetting: (settings, path) =>
            settings.copyWith(largePakPatcherFilePath: path),
        controller: _largePakPatcherController,
        checkForUpdatesAfter: false,
        remoteAssets: sharedRemoteAssets,
      );

      await _checkForBundledDllDefaultUpdates(silent: true);
      if (mounted) {
        _toast('Default DLL update completed');
      }
    } catch (error) {
      _log('settings', 'Failed to update all default DLLs: $error');
      if (mounted) {
        _toast('Failed to update all default DLLs');
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingDefaultDlls = false;
        });
      } else {
        _updatingDefaultDlls = false;
      }
    }
  }

  Future<void> _pickUnrealEnginePatcher() async {
    final path = await _pickSingleFile(
      dialogTitle: 'Select Unreal Engine Patcher',
      allowedExtensions: const ['dll'],
    );
    if (path == null) return;
    setState(() {
      _settings = _settings.copyWith(unrealEnginePatcherPath: path);
      _unrealEnginePatcherController.text = path;
    });
    await _saveSettings(toast: false);
    unawaited(
      _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
    );
  }

  Future<void> _clearUnrealEnginePatcher() async {
    await _resetBundledDllPathToLatest(
      spec: _bundledDllSpecByFileName('console.dll'),
      applySetting: (settings, path) =>
          settings.copyWith(unrealEnginePatcherPath: path),
      controller: _unrealEnginePatcherController,
    );
  }

  Future<void> _pickAuthenticationPatcher() async {
    final path = await _pickSingleFile(
      dialogTitle: 'Select authentication patcher',
      allowedExtensions: const ['dll'],
    );
    if (path == null) return;
    setState(() {
      _settings = _settings.copyWith(authenticationPatcherPath: path);
      _authenticationPatcherController.text = path;
    });
    await _saveSettings(toast: false);
    unawaited(
      _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
    );
  }

  Future<void> _clearAuthenticationPatcher() async {
    await _resetBundledDllPathToLatest(
      spec: _bundledDllSpecByFileName('Tellurium.dll'),
      applySetting: (settings, path) =>
          settings.copyWith(authenticationPatcherPath: path),
      controller: _authenticationPatcherController,
    );
  }

  Future<void> _pickMemoryPatcher() async {
    final path = await _pickSingleFile(
      dialogTitle: 'Select memory patcher',
      allowedExtensions: const ['dll'],
    );
    if (path == null) return;
    setState(() {
      _settings = _settings.copyWith(memoryPatcherPath: path);
      _memoryPatcherController.text = path;
    });
    await _saveSettings(toast: false);
    unawaited(
      _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
    );
  }

  Future<void> _clearMemoryPatcher() async {
    await _resetBundledDllPathToLatest(
      spec: _bundledDllSpecByFileName('memory.dll'),
      applySetting: (settings, path) =>
          settings.copyWith(memoryPatcherPath: path),
      controller: _memoryPatcherController,
    );
  }

  Future<void> _pickGameServerFile() async {
    final path = await _pickSingleFile(
      dialogTitle: 'Select game server DLL',
      allowedExtensions: const ['dll'],
    );
    if (path == null) return;
    setState(() {
      _settings = _settings.copyWith(gameServerFilePath: path);
      _gameServerFileController.text = path;
    });
    await _saveSettings(toast: false);
    unawaited(
      _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
    );
  }

  Future<void> _clearGameServerFile() async {
    await _resetBundledDllPathToLatest(
      spec: _bundledDllSpecByFileName('Magnesium.dll'),
      applySetting: (settings, path) =>
          settings.copyWith(gameServerFilePath: path),
      controller: _gameServerFileController,
    );
  }

  Future<void> _pickLargePakPatcherFile() async {
    final path = await _pickSingleFile(
      dialogTitle: 'Select large pak patcher DLL',
      allowedExtensions: const ['dll'],
    );
    if (path == null) return;
    setState(() {
      _settings = _settings.copyWith(largePakPatcherFilePath: path);
      _largePakPatcherController.text = path;
    });
    await _saveSettings(toast: false);
    unawaited(
      _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
    );
  }

  Future<void> _clearLargePakPatcherFile() async {
    await _resetBundledDllPathToLatest(
      spec: _bundledDllSpecByFileName('LargePakPatch.dll'),
      applySetting: (settings, path) =>
          settings.copyWith(largePakPatcherFilePath: path),
      controller: _largePakPatcherController,
    );
  }

  Future<void> _openUrl(String url) async {
    if (!Platform.isWindows) return;
    await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
  }

  void _toast(String message) {
    if (!mounted) return;

    if (!_ensureToastOverlayReady()) return;
    _toastHostKey.currentState?.show(message);
  }

  bool _ensureToastOverlayReady() {
    if (!mounted) return false;
    if (_toastOverlayEntry != null) return true;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;

    _toastOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final safePadding = MediaQuery.of(overlayContext).padding;
        return Positioned(
          right: 18 + safePadding.right,
          bottom: 18 + safePadding.bottom,
          child: Material(
            color: Colors.transparent,
            child: _ToastOverlayHost(
              key: _toastHostKey,
              onEmpty: () {
                _toastOverlayEntry?.remove();
                _toastOverlayEntry = null;
              },
            ),
          ),
        );
      },
    );
    overlay.insert(_toastOverlayEntry!);
    return true;
  }

  void _toastProgress(
    String message, {
    required double? progress,
    required bool indeterminate,
  }) {
    if (!mounted) return;
    if (!_ensureToastOverlayReady()) return;
    _toastHostKey.currentState?.showProgress(
      message,
      progress: progress,
      indeterminate: indeterminate,
    );
  }

  void _toastProgressDismiss() {
    if (!mounted) return;
    _toastHostKey.currentState?.dismissProgressSoon();
  }

  ImageProvider<Object> _backgroundImage() {
    final selected = _settings.backgroundImagePath;
    if (selected.isNotEmpty && File(selected).existsSync()) {
      return FileImage(File(selected));
    }
    return const AssetImage('assets/images/atlas_default_background.webp');
  }

  ImageProvider<Object> _profileImage() {
    final selected = _settings.profileAvatarPath;
    if (selected.isNotEmpty && File(selected).existsSync()) {
      return FileImage(File(selected));
    }
    return const AssetImage('assets/images/default_pfp.png');
  }

  ImageProvider<Object> _libraryCoverImage(VersionEntry? version) {
    if (version == null) {
      return const AssetImage('assets/images/missingbuild.webp');
    }

    final selected = version.splashImagePath.trim();
    if (selected.isNotEmpty) {
      return FileImage(File(selected));
    }
    return const AssetImage('assets/images/library_cover.png');
  }

  int _compareVersionStrings(String a, String b) {
    final partsA = RegExp(r'\d+')
        .allMatches(a)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();
    final partsB = RegExp(r'\d+')
        .allMatches(b)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();

    final maxLength = max(partsA.length, partsB.length);
    for (var i = 0; i < maxLength; i++) {
      final valueA = i < partsA.length ? partsA[i] : 0;
      final valueB = i < partsB.length ? partsB[i] : 0;
      if (valueA != valueB) return valueA.compareTo(valueB);
    }

    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final blurSigma = _settings.backgroundBlur.clamp(0.0, 30.0).toDouble();
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final background = DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: _backgroundImage(),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
                if (blurSigma <= 0.01) return background;
                return ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: background,
                );
              },
            ),
          ),
          Positioned.fill(
            child: _settings.backgroundParticlesOpacity <= 0
                ? const SizedBox.shrink()
                : IgnorePointer(
                    child: TickerMode(
                      // Launching Fortnite can be CPU/GPU heavy. Pause the
                      // particle animation during launch/close so the launcher
                      // UI stays responsive.
                      enabled:
                          _gameAction == _GameActionState.idle &&
                          !_gameServerLaunching,
                      child: _AtlasParticleField(
                        opacity: _settings.backgroundParticlesOpacity
                            .clamp(0.0, 2.0)
                            .toDouble(),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // Keep the background dim consistent so startup doesn't "change"
                  // the perceived blur/contrast.
                  colors: [
                    _adaptiveScrimColor(
                      context,
                      darkAlpha: 0.65,
                      lightAlpha: 0.20,
                    ),
                    _adaptiveScrimColor(
                      context,
                      darkAlpha: 0.35,
                      lightAlpha: 0.08,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_startupConfigResolved && !_showStartup)
            Positioned.fill(
              child: FadeTransition(
                opacity: _shellEntranceFade,
                child: ScaleTransition(
                  scale: _shellEntranceScale,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 1080;
                          return Column(
                            children: [
                              Text(
                                _launcherBuildLabel,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _onSurface(context, 0.86),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _topBar(compact),
                              const SizedBox(height: 18),
                              Expanded(child: _tabContent()),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_startupConfigResolved && !_showStartup && _showLibraryQuickTip)
            Positioned(
              top: 104,
              right: 28,
              child: SafeArea(
                child: AnimatedOpacity(
                  opacity: _libraryImportTipFadingOut ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 290),
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: _dialogSurfaceColor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _onSurface(context, 0.12)),
                        boxShadow: [
                          BoxShadow(
                            color: _dialogShadowColor(context),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tips_and_updates_rounded,
                                size: 16,
                                color: _onSurface(context, 0.86),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Quick tip',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _onSurface(context, 0.92),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_libraryQuickTipStep + 1}/2',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface(context, 0.72),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: _libraryQuickTipStep == 0
                                    ? 'Next tip'
                                    : 'Got it',
                                onPressed: _advanceLibraryQuickTip,
                                icon: Icon(
                                  _libraryQuickTipStep == 0
                                      ? Icons.arrow_forward_rounded
                                      : Icons.check_rounded,
                                  size: 16,
                                ),
                                color: Theme.of(context).colorScheme.secondary,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(26, 26),
                                  padding: const EdgeInsets.all(4),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () {
                                  unawaited(_dismissLibraryImportTip());
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: _onSurface(context, 0.62),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 170),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeOut,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: KeyedSubtree(
                              key: ValueKey<int>(_libraryQuickTipStep),
                              child: _libraryQuickTipStep == 0
                                  ? Column(
                                      key: const ValueKey('library-tip-step-0'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Import a build using the + button in the top-right.',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            height: 1.28,
                                            color: _onSurface(context, 0.86),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'You can also use the download button to browse builds.',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            height: 1.28,
                                            color: _onSurface(context, 0.86),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      key: const ValueKey('library-tip-step-1'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'ATLAS Link only supports the following versions natively:',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            height: 1.28,
                                            color: _onSurface(context, 0.86),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            _buildVersionTag(
                                              context,
                                              label: 'v1.7.2',
                                              accent: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                            ),
                                            Text(
                                              '-',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _onSurface(
                                                  context,
                                                  0.78,
                                                ),
                                              ),
                                            ),
                                            _buildVersionTag(
                                              context,
                                              label: 'v30.00',
                                              accent: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Note: This is subject to change in the future',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.25,
                                            color: _onSurface(context, 0.74),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (_startupConfigResolved && !_showStartup)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.985,
                        end: 1.0,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
                child: _shouldShowLaunchProgressPopup()
                    ? RepaintBoundary(
                        key: const ValueKey('launch-progress-popup'),
                        child: _buildLaunchProgressPopup(),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('launch-progress-popup-hidden'),
                      ),
              ),
            ),
          if (_startupConfigResolved && _showStartup)
            _AtlasStartupAnimationOverlay(onFinished: _finishStartupAnimation),
        ],
      ),
    );
  }

  Widget _topBar(bool compact) {
    final username = _settings.username.trim().isEmpty
        ? 'Player'
        : _settings.username.trim();
    final left = switch (_tab) {
      LauncherTab.home => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 22),
          CircleAvatar(radius: 24, backgroundImage: _profileImage()),
          const SizedBox(width: 12),
          Text(
            '${_timeGreeting()}, $username!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _onSurface(context, 0.95),
            ),
          ),
        ],
      ),
      LauncherTab.library => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Library',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w700,
              color: _onSurface(context, 0.95),
            ),
          ),
        ],
      ),
      LauncherTab.backend => Text(
        'Backend',
        style: TextStyle(
          fontSize: 52,
          fontWeight: FontWeight.w700,
          color: _onSurface(context, 0.95),
        ),
      ),
      LauncherTab.general => Text(
        'Settings',
        style: TextStyle(
          fontSize: 52,
          fontWeight: FontWeight.w700,
          color: _onSurface(context, 0.95),
        ),
      ),
    };
    final leftAnimated = _animatedSwap(
      switchKey: _tab,
      duration: const Duration(milliseconds: 220),
      layoutAlignment: Alignment.centerLeft,
      child: left,
    );

    const showRightControls = true;
    final right = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showRightControls) ...[
          if (_tab == LauncherTab.library) ...[
            _libraryPulseGlow(
              _titleActionButton(Icons.add_rounded, () {
                unawaited(
                  _dismissLibraryImportTip(onDismissedAction: _importVersion),
                );
              }),
            ),
            const SizedBox(width: 8),
            _libraryPulseGlow(
              _titleActionButton(Icons.download_rounded, () {
                unawaited(
                  _dismissLibraryImportTip(
                    onDismissedAction: () =>
                        _openUrl('https://builds.fortforge.dev/builds'),
                  ),
                );
              }),
            ),
            const SizedBox(width: 10),
          ],
          IconButton(
            onPressed: _handleRefreshPressed,
            tooltip: 'Refresh / check updates',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _showQuickTipForCurrentTab,
            tooltip: 'Show quick tips',
            icon: const Icon(Icons.help_outline_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              unawaited(
                _switchMenu(
                  LauncherTab.general,
                  settingsSection: SettingsSection.dataManagement,
                ),
              );
            },
            tooltip: _dataManagementButtonTooltip,
            icon: _settingsActionIcon(),
          ),
        ],
      ],
    );

    final nav = _tabCapsule();
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leftAnimated,
          const SizedBox(height: 12),
          Align(alignment: Alignment.center, child: nav),
          if (showRightControls) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: right),
          ],
        ],
      );
    }
    return SizedBox(
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(alignment: Alignment.centerLeft, child: leftAnimated),
          Align(alignment: Alignment.center, child: nav),
          if (showRightControls)
            Align(alignment: Alignment.centerRight, child: right),
        ],
      ),
    );
  }

  bool get _shouldPulseLibraryActions =>
      (_tab == LauncherTab.library && _settings.versions.isEmpty) ||
      (_tab == LauncherTab.backend && _showBackendConnectionTip) ||
      _showProfileAuthQuickTip;

  void _syncLibraryActionsNudgePulse() {
    final shouldPulse = _shouldPulseLibraryActions;
    if (shouldPulse) {
      if (!_libraryActionsNudgeController.isAnimating) {
        _libraryActionsNudgeController.repeat(reverse: true);
      }
      return;
    }
    if (_libraryActionsNudgeController.isAnimating) {
      _libraryActionsNudgeController.stop();
      _libraryActionsNudgeController.value = 0.0;
    }
  }

  void _completeLibraryActionsNudge() {
    if (_settings.libraryActionsNudgeComplete) return;
    setState(() {
      _settings = _settings.copyWith(libraryActionsNudgeComplete: true);
      _installState = _installState.copyWith(libraryActionsNudgeComplete: true);
      _libraryQuickTipManualVisible = false;
      _libraryQuickTipStep = 0;
    });
    _syncLibraryActionsNudgePulse();
    unawaited(_saveInstallState());
    unawaited(_saveSettings(toast: false));
  }

  void _advanceLibraryQuickTip() {
    if (_libraryQuickTipStep == 0) {
      setState(() => _libraryQuickTipStep = 1);
      return;
    }
    unawaited(_dismissLibraryImportTip());
  }

  Future<void> _dismissLibraryImportTip({
    Future<void> Function()? onDismissedAction,
  }) async {
    if (_libraryImportTipFadingOut) return;

    if (_settings.libraryActionsNudgeComplete &&
        _libraryQuickTipManualVisible) {
      if (mounted) {
        setState(() {
          _libraryQuickTipManualVisible = false;
          _libraryQuickTipStep = 0;
        });
      } else {
        _libraryQuickTipManualVisible = false;
        _libraryQuickTipStep = 0;
      }
      if (onDismissedAction != null) await onDismissedAction();
      return;
    }

    if (_settings.libraryActionsNudgeComplete) {
      if (onDismissedAction != null) await onDismissedAction();
      return;
    }

    if (mounted) {
      setState(() {
        _libraryImportTipFadingOut = true;
      });
    } else {
      _libraryImportTipFadingOut = true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    _completeLibraryActionsNudge();

    if (mounted) {
      setState(() {
        _libraryImportTipFadingOut = false;
      });
    } else {
      _libraryImportTipFadingOut = false;
    }

    if (onDismissedAction != null) {
      await onDismissedAction();
    }
  }

  Widget _libraryPulseGlow(Widget child) {
    if (!_shouldPulseLibraryActions) return child;
    return AnimatedBuilder(
      animation: _libraryActionsNudgePulse,
      child: child,
      builder: (context, child) {
        final t = _libraryActionsNudgePulse.value;
        final outerAlpha = 0.10 + (0.14 * t);
        final innerAlpha = 0.12 + (0.20 * t);
        final outerBlur = 26.0 + (28.0 * t);
        final innerBlur = 10.0 + (14.0 * t);
        final outerSpread = 0.5 + (2.0 * t);
        final innerSpread = 0.2 + (0.9 * t);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: outerAlpha),
                blurRadius: outerBlur,
                spreadRadius: outerSpread,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: innerAlpha),
                blurRadius: innerBlur,
                spreadRadius: innerSpread,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  Widget _tipPulseGlowIf(Widget child, {required bool enabled}) {
    if (!enabled) return child;
    return AnimatedBuilder(
      animation: _libraryActionsNudgePulse,
      child: child,
      builder: (context, child) {
        final t = _libraryActionsNudgePulse.value;
        final outerAlpha = 0.10 + (0.14 * t);
        final innerAlpha = 0.12 + (0.20 * t);
        final outerBlur = 26.0 + (28.0 * t);
        final innerBlur = 10.0 + (14.0 * t);
        final outerSpread = 0.5 + (2.0 * t);
        final innerSpread = 0.2 + (0.9 * t);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: outerAlpha),
                blurRadius: outerBlur,
                spreadRadius: outerSpread,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: innerAlpha),
                blurRadius: innerBlur,
                spreadRadius: innerSpread,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  bool get _showLibraryQuickTip =>
      _tab == LauncherTab.library &&
      (_libraryQuickTipManualVisible ||
          !_settings.libraryActionsNudgeComplete ||
          _libraryImportTipFadingOut);

  bool get _showBackendConnectionTip =>
      _backendQuickTipManualVisible ||
      (!_settings.backendConnectionTipComplete &&
          !_installState.backendConnectionTipComplete);

  bool get _showProfileAuthQuickTip =>
      _tab == LauncherTab.general &&
      _settingsSection == SettingsSection.profile &&
      (_profileAuthQuickTipManualVisible ||
          !_settings.profileAuthQuickTipComplete);

  void _completeProfileAuthQuickTip() {
    if (_settings.profileAuthQuickTipComplete &&
        !_profileAuthQuickTipManualVisible) {
      return;
    }
    setState(() {
      _settings = _settings.copyWith(profileAuthQuickTipComplete: true);
      _profileAuthQuickTipManualVisible = false;
    });
    _syncLibraryActionsNudgePulse();
    unawaited(_saveSettings(toast: false, applyControllers: false));
  }

  void _showQuickTipForCurrentTab() {
    if (_tab == LauncherTab.library) {
      setState(() {
        _libraryQuickTipManualVisible = true;
        _libraryQuickTipStep = 0;
        _libraryImportTipFadingOut = false;
      });
      _syncLibraryActionsNudgePulse();
      return;
    }
    if (_tab == LauncherTab.backend) {
      setState(() {
        _backendQuickTipManualVisible = true;
        _backendQuickTipStep = 0;
      });
      _syncLibraryActionsNudgePulse();
      return;
    }
    if (_tab == LauncherTab.general &&
        _settingsSection == SettingsSection.profile) {
      setState(() {
        _profileAuthQuickTipManualVisible = true;
      });
      _syncLibraryActionsNudgePulse();
      return;
    }
    _toast('No quick tips are available on this page');
  }

  void _beginBackendTipPreviewIfNeeded() {
    _backendQuickTipOriginalType ??= _settings.backendConnectionType;
    _backendQuickTipOriginalHost ??= _settings.backendHost;
  }

  void _previewBackendTypeForTip(BackendConnectionType type) {
    _beginBackendTipPreviewIfNeeded();
    final originalHost = _backendQuickTipOriginalHost ?? _settings.backendHost;
    final previewHost = type == BackendConnectionType.local
        ? '127.0.0.1'
        : originalHost;
    setState(() {
      _settings = _settings.copyWith(
        backendConnectionType: type,
        backendHost: previewHost,
      );
      _backendHostController.text = _effectiveBackendHost();
    });
  }

  void _restoreBackendTypeAfterTipPreview() {
    final originalType = _backendQuickTipOriginalType;
    if (originalType == null) return;
    final originalHost = _backendQuickTipOriginalHost ?? _settings.backendHost;
    setState(() {
      _settings = _settings.copyWith(
        backendConnectionType: originalType,
        backendHost: originalHost,
      );
      _backendHostController.text = _effectiveBackendHost();
      _backendQuickTipOriginalType = null;
      _backendQuickTipOriginalHost = null;
    });
  }

  void _completeBackendConnectionTip() {
    if (_settings.backendConnectionTipComplete) {
      _restoreBackendTypeAfterTipPreview();
      if (_backendQuickTipManualVisible) {
        setState(() {
          _backendQuickTipManualVisible = false;
          _backendQuickTipStep = 0;
        });
      }
      return;
    }
    _restoreBackendTypeAfterTipPreview();
    setState(() {
      _settings = _settings.copyWith(backendConnectionTipComplete: true);
      _installState = _installState.copyWith(
        backendConnectionTipComplete: true,
      );
      _backendQuickTipManualVisible = false;
      _backendQuickTipStep = 0;
    });
    _syncLibraryActionsNudgePulse();
    unawaited(_saveInstallState());
    unawaited(_saveSettings(toast: false));
  }

  void _advanceBackendConnectionTip() {
    if (_backendQuickTipStep == 0) {
      _previewBackendTypeForTip(BackendConnectionType.remote);
      setState(() => _backendQuickTipStep = 1);
      return;
    }
    if (_backendQuickTipStep == 1) {
      setState(() => _backendQuickTipStep = 2);
      return;
    }
    _completeBackendConnectionTip();
  }

  Widget _backendConnectionTipCard() {
    final secondary = Theme.of(context).colorScheme.secondary;
    final stepTwo = _backendQuickTipStep == 1;
    final stepThree = _backendQuickTipStep == 2;

    Widget stepContent;
    if (!stepTwo && !stepThree) {
      stepContent = Text(
        'Running your own backend? Keep Type on Local so Link uses your local server settings.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.28,
          color: _onSurface(context, 0.86),
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (stepTwo) {
      stepContent = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Text(
            'Joining a friend\'s backend? Switch Type to Remote and paste their',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.28,
              color: _onSurface(context, 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
          InkWell(
            onTap: () => unawaited(_openUrl('https://www.radmin-vpn.com/')),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Text(
                'Radmin VPN',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          Text(
            'IP in the Host box.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.28,
              color: _onSurface(context, 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else {
      stepContent = Text(
        'You can save other backends too. Click the bookmark button next to Host to save an IP, then select a saved backend below to connect (Link will only connect if it\'s online).',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.28,
          color: _onSurface(context, 0.86),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: _dialogSurfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _onSurface(context, 0.12)),
        boxShadow: [
          BoxShadow(
            color: _dialogShadowColor(context),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_rounded,
                size: 16,
                color: _onSurface(context, 0.86),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick tip',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _onSurface(context, 0.92),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_backendQuickTipStep + 1}/3',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _onSurface(context, 0.72),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: _backendQuickTipStep < 2 ? 'Next tip' : 'Got it',
                onPressed: _advanceBackendConnectionTip,
                icon: Icon(
                  _backendQuickTipStep < 2
                      ? Icons.arrow_forward_rounded
                      : Icons.check_rounded,
                  size: 16,
                ),
                color: secondary,
                style: IconButton.styleFrom(
                  minimumSize: const Size(26, 26),
                  padding: const EdgeInsets.all(4),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _completeBackendConnectionTip,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: _onSurface(context, 0.62),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey<int>(_backendQuickTipStep),
              child: stepContent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileAuthQuickTipCard() {
    final secondary = Theme.of(context).colorScheme.secondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: _dialogSurfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _onSurface(context, 0.12)),
        boxShadow: [
          BoxShadow(
            color: _dialogShadowColor(context),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_rounded,
                size: 16,
                color: _onSurface(context, 0.86),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick tip',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _onSurface(context, 0.92),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '1/1',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _onSurface(context, 0.72),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Got it',
                onPressed: _completeProfileAuthQuickTip,
                icon: const Icon(Icons.check_rounded, size: 16),
                color: secondary,
                style: IconButton.styleFrom(
                  minimumSize: const Size(26, 26),
                  padding: const EdgeInsets.all(4),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _completeProfileAuthQuickTip,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: _onSurface(context, 0.62),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You can switch to email and password login authentication if needed.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.28,
              color: _onSurface(context, 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool _configuredDllPathMissing(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.toLowerCase().endsWith('.dll')) return false;
    return !File(trimmed).existsSync();
  }

  String? _dllRowUpdateWarningMessage(String fileNameLower) {
    final lower = fileNameLower.trim().toLowerCase();
    if (_bundledDllUpdatedFileNames.contains(lower)) {
      return 'Default update available';
    }
    return null;
  }

  bool get _hasMissingConfiguredDllPaths =>
      _configuredDllPathMissing(_settings.unrealEnginePatcherPath) ||
      _configuredDllPathMissing(_settings.authenticationPatcherPath) ||
      _configuredDllPathMissing(_settings.memoryPatcherPath) ||
      _configuredDllPathMissing(_settings.gameServerFilePath) ||
      _configuredDllPathMissing(_settings.largePakPatcherFilePath);

  bool get _showSettingsAlertBadge =>
      _bundledDllDefaultsUpdateAvailable || _hasMissingConfiguredDllPaths;

  String get _dataManagementButtonTooltip {
    final hasUpdate = _bundledDllDefaultsUpdateAvailable;
    final hasMissing = _hasMissingConfiguredDllPaths;
    if (hasUpdate && hasMissing) {
      return 'Data management (DLL updates and missing DLL warnings)';
    }
    if (hasUpdate) return 'Data management (DLL update available)';
    if (hasMissing) return 'Data management (missing DLL warning)';
    return 'Data management';
  }

  Widget _settingsActionIcon() {
    if (!_showSettingsAlertBadge) {
      return const Icon(Icons.settings_rounded);
    }
    final badgeBorder = Theme.of(context).colorScheme.surface;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.settings_rounded),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFD93025),
              shape: BoxShape.circle,
              border: Border.all(color: badgeBorder, width: 1.1),
            ),
            child: const Text(
              '!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleActionButton(IconData icon, VoidCallback onTap) {
    return _HoverScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _onSurface(context, 0.18)),
            color: _onSurface(context, 0.11),
          ),
          child: Icon(icon, color: _onSurface(context, 0.92)),
        ),
      ),
    );
  }

  Widget _tabCapsule() {
    final secondary = Theme.of(context).colorScheme.secondary;
    final dark = _isDarkTheme(context);
    final selectedBackground = dark
        ? Colors.white.withValues(alpha: 0.11)
        : secondary.withValues(alpha: 0.15);
    final selectedGradientTop = dark
        ? Colors.white.withValues(alpha: 0.12)
        : secondary.withValues(alpha: 0.20);
    final selectedGradientBottom = dark
        ? Colors.white.withValues(alpha: 0.06)
        : secondary.withValues(alpha: 0.10);
    const transparentOverlay = WidgetStatePropertyAll<Color>(
      Colors.transparent,
    );
    final selectedOutlineColor = dark
        ? Colors.white.withValues(alpha: 0.28)
        : secondary.withValues(alpha: 0.72);
    final selectedOutlineShadowColor = dark
        ? Colors.white.withValues(alpha: 0.14)
        : secondary.withValues(alpha: 0.18);

    const navTabs = <LauncherTab>[
      LauncherTab.home,
      LauncherTab.library,
      LauncherTab.backend,
    ];
    const navTabGap = 4.0;
    const navTabWidth = 74.0;
    const navTabRadius = 14.0;
    final selectedTabIndex = navTabs.indexOf(_tab);

    Widget navTabButton(LauncherTab tab) {
      final selected = _tab == tab;
      final label = switch (tab) {
        LauncherTab.home => 'Home',
        LauncherTab.library => 'Library',
        LauncherTab.backend => 'Backend',
        LauncherTab.general => 'Settings',
      };
      final icon = switch (tab) {
        LauncherTab.home => Icons.home_outlined,
        LauncherTab.library => Icons.folder_open_outlined,
        LauncherTab.backend => Icons.cloud_outlined,
        LauncherTab.general => Icons.bar_chart_rounded,
      };
      return _HoverScale(
        scale: 1.04,
        child: InkWell(
          borderRadius: BorderRadius.circular(navTabRadius),
          overlayColor: transparentOverlay,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onTap: () => unawaited(_switchMenu(tab)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints.tightFor(width: navTabWidth),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(navTabRadius),
              color: selected ? selectedBackground : Colors.transparent,
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [selectedGradientTop, selectedGradientBottom],
                    )
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: _onSurface(context, selected ? 1 : 0.70),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: _onSurface(context, selected ? 1 : 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tabStrip = Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (selectedTabIndex >= 0)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: selectedTabIndex * (navTabWidth + navTabGap),
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: navTabWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(navTabRadius),
                  border: Border.all(color: selectedOutlineColor, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: selectedOutlineShadowColor,
                      blurRadius: 18,
                      spreadRadius: 0.4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            navTabButton(navTabs[0]),
            const SizedBox(width: navTabGap),
            navTabButton(navTabs[1]),
            const SizedBox(width: navTabGap),
            navTabButton(navTabs[2]),
          ],
        ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: _glassSurfaceColor(context),
                border: Border.all(color: _onSurface(context, 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: _glassShadowColor(context),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'About ATLAS Link',
                    child: _HoverScale(
                      scale: 1.04,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        overlayColor: transparentOverlay,
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        onTap: () => unawaited(_showAboutDialog()),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Image.asset('assets/images/atlas_logo.png'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 1,
                    height: 28,
                    color: _onSurface(context, 0.18),
                  ),
                  const SizedBox(width: 4),
                  tabStrip,
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    overlayColor: transparentOverlay,
                    splashFactory: NoSplash.splashFactory,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    onTap: () => unawaited(
                      _switchMenu(
                        LauncherTab.general,
                        settingsSection: SettingsSection.profile,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundImage: _profileImage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabContent() {
    final child = switch (_tab) {
      LauncherTab.home => _homeTab(),
      LauncherTab.library => _libraryTab(),
      LauncherTab.backend => _backendTab(),
      LauncherTab.general => _generalTab(),
    };

    return child;
  }

  bool get _gameDiscordPresenceHasPriority {
    return _gameAction != _GameActionState.idle ||
        _gameServerLaunching ||
        _gameProcess != null ||
        _gameServerProcess != null ||
        _gameInstance != null ||
        _gameServerInstance != null ||
        _extraGameInstances.isNotEmpty;
  }

  String _launcherDiscordDetailsLine() {
    if (_showOnboardingDiscordPresence) {
      return 'Welcome to ATLAS!';
    }
    return switch (_tab) {
      LauncherTab.home => 'Browsing Homepage',
      LauncherTab.library => 'Browsing Library',
      LauncherTab.backend => 'Configuring Backend',
      LauncherTab.general => 'Editing Settings',
    };
  }

  String _launcherDiscordStateLine() {
    if (_showOnboardingDiscordPresence) {
      return 'Currently setting up their user profile.';
    }
    final username = _settings.username.trim().isEmpty
        ? 'Player'
        : _settings.username.trim();
    return 'Logged in as: $username';
  }

  void _syncLauncherDiscordPresence() {
    if (!Platform.isWindows) return;

    if (_gameDiscordPresenceHasPriority) {
      if (_launcherDiscordPresenceCleared) return;
      _launcherDiscordRpc.clearActivity();
      _launcherDiscordPresenceSignature = null;
      _launcherDiscordPresenceCleared = true;
      return;
    }

    final activity = LauncherDiscordActivity(
      details: _launcherDiscordDetailsLine(),
      state: _launcherDiscordStateLine(),
      startTimestampSeconds: _launcherDiscordRpc.sessionStartTimestampSeconds,
      largeImageKey: _launcherDiscordLargeImageKey,
      largeImageText: _launcherDiscordLargeImageText,
      buttons: <LauncherDiscordButton>[
        const LauncherDiscordButton(
          label: _launcherDiscordButtonLabel,
          url: _atlasLinkDiscordInvite,
        ),
        const LauncherDiscordButton(
          label: _launcherDownloadButtonLabel,
          url: _atlasLinkReleasesPage,
        ),
      ],
    );
    final signature = activity.signature;
    if (!_launcherDiscordPresenceCleared &&
        _launcherDiscordPresenceSignature == signature) {
      return;
    }

    final updated = _launcherDiscordRpc.setActivity(activity);
    if (!updated) return;

    _launcherDiscordPresenceSignature = signature;
    _launcherDiscordPresenceCleared = false;
  }

  Future<void> _switchMenu(
    LauncherTab tab, {
    SettingsSection? settingsSection,
  }) async {
    if (!mounted) return;
    if (_tab == tab &&
        (settingsSection == null || _settingsSection == settingsSection)) {
      return;
    }
    final previousTab = _tab;
    setState(() {
      if (tab == LauncherTab.general && previousTab != LauncherTab.general) {
        _settingsReturnTab = previousTab;
      }
      _tab = tab;
      if (settingsSection != null) _settingsSection = settingsSection;
    });
    if (tab == LauncherTab.general) {
      unawaited(
        _checkForBundledDllDefaultUpdates(silent: true, forceRefresh: false),
      );
    }
    _syncLibraryActionsNudgePulse();
    _syncLauncherDiscordPresence();
  }

  Widget _homeTab() {
    final featured = _homeFeaturedCards;
    final hero = featured[_homeHeroIndex % featured.length];

    return ListView(
      children: [
        _menuItemEntrance(
          menuKey: LauncherTab.home,
          index: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 2.35,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 360),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Container(
                      key: ValueKey<String>(hero.image),
                      color: Colors.black,
                      child: Image.asset(
                        hero.image,
                        fit: hero.imageFit,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.56),
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 30,
                  right: 30,
                  bottom: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hero.title,
                        style: const TextStyle(
                          fontSize: 49,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hero.category,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hero.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _openUrl(hero.buttonUrl),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.92),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 13,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(hero.buttonLabel),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(featured.length, (index) {
                      final active = index == _homeHeroIndex;
                      return GestureDetector(
                        onTap: () => _setHomeHeroIndex(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 36 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: Colors.white.withValues(
                              alpha: active ? 0.95 : 0.45,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<VersionEntry> _sortedInstalledVersions() {
    final source = _settings.versions;
    if (identical(_sortedVersionsSource, source)) return _sortedVersionsCache;

    final sorted = List<VersionEntry>.from(source)
      ..sort((a, b) {
        final byVersion = _compareVersionStrings(b.gameVersion, a.gameVersion);
        if (byVersion != 0) return byVersion;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    _sortedVersionsSource = source;
    _sortedVersionsCache = sorted;
    return sorted;
  }

  Widget _libraryTab() {
    final selected = _settings.selectedVersion;
    final selectedName = selected?.name ?? 'No Version Selected';
    final coverImage = _libraryCoverImage(selected);
    final installedVersions = _sortedInstalledVersions();
    final searchQuery = _versionSearchQuery.trim().toLowerCase();
    final filteredVersions = searchQuery.isEmpty
        ? installedVersions
        : installedVersions
              .where((entry) => entry.name.toLowerCase().contains(searchQuery))
              .toList();

    _queueLibrarySplashPrefetch(
      filteredVersions,
      signature:
          '${identityHashCode(installedVersions)}|$searchQuery|${filteredVersions.length}',
    );
    final hasRunningGameClient = _hasRunningGameClient;
    final launchActsAsClose =
        hasRunningGameClient && !_settings.allowMultipleGameClients;
    final showCloseAllGamesButton =
        hasRunningGameClient && _settings.allowMultipleGameClients;

    final topPanel = _menuItemEntrance(
      menuKey: LauncherTab.library,
      index: 0,
      child: _glass(
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final coverWidth = compact ? constraints.maxWidth : 250.0;
                  final coverCacheWidth = (coverWidth * dpr).round().clamp(
                    1,
                    4096,
                  );
                  final ImageProvider<Object> heroCoverProvider =
                      selected == null
                      ? coverImage
                      : ResizeImage(coverImage, width: coverCacheWidth);
                  final image = ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image(
                      image: heroCoverProvider,
                      width: compact ? double.infinity : 250,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/library_cover.png',
                          width: compact ? double.infinity : 250,
                          height: 300,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  );

                  final details = Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: compact ? 0 : 20,
                        top: compact ? 14 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VERSION',
                            style: TextStyle(
                              color: _onSurface(context, 0.72),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            selectedName,
                            style: const TextStyle(
                              fontSize: 47,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (selected == null)
                                OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Launch'),
                                )
                              else
                                FilledButton.icon(
                                  onPressed:
                                      _gameAction != _GameActionState.idle
                                      ? null
                                      : _onLaunchButtonPressed,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: launchActsAsClose
                                        ? const Color(0xFFDC3545)
                                        : Theme.of(context)
                                              .colorScheme
                                              .secondary
                                              .withValues(alpha: 0.92),
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.22),
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.58),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: Icon(
                                    launchActsAsClose
                                        ? Icons.stop_rounded
                                        : _gameAction ==
                                              _GameActionState.closing
                                        ? Icons.stop_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    _gameAction == _GameActionState.closing
                                        ? 'Closing...'
                                        : launchActsAsClose
                                        ? 'Close Game'
                                        : _gameAction ==
                                              _GameActionState.launching
                                        ? 'Launching...'
                                        : hasRunningGameClient &&
                                              _settings.allowMultipleGameClients
                                        ? 'Launch Client'
                                        : 'Launch',
                                  ),
                                ),
                              if (showCloseAllGamesButton)
                                FilledButton.icon(
                                  onPressed:
                                      _gameAction != _GameActionState.idle
                                      ? null
                                      : _closeFortnite,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC3545),
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.22),
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.58),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.stop_rounded),
                                  label: Text(
                                    _gameAction == _GameActionState.closing
                                        ? 'Closing...'
                                        : 'Close Games',
                                  ),
                                ),
                              if (selected == null)
                                OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.cloud_upload_rounded),
                                  label: const Text('Host'),
                                )
                              else
                                FilledButton.icon(
                                  onPressed:
                                      _gameAction != _GameActionState.idle ||
                                          _gameServerLaunching
                                      ? null
                                      : _gameServerProcess != null
                                      ? _closeHosting
                                      : _startHosting,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _gameServerProcess != null
                                        ? const Color(0xFFDC3545)
                                        : Theme.of(context)
                                              .colorScheme
                                              .secondary
                                              .withValues(alpha: 0.82),
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.22),
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.58),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: Icon(
                                    _gameServerProcess != null
                                        ? Icons.stop_rounded
                                        : Icons.cloud_upload_rounded,
                                  ),
                                  label: Text(
                                    _gameServerProcess != null
                                        ? 'Close Host'
                                        : _gameServerLaunching
                                        ? 'Starting...'
                                        : 'Host',
                                  ),
                                ),
                              OutlinedButton.icon(
                                onPressed: selected == null
                                    ? null
                                    : () => _openPath(selected.location),
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Open Folder'),
                              ),
                              OutlinedButton(
                                onPressed: _openHostOptionsDialog,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(42, 42),
                                  maximumSize: const Size(42, 42),
                                  padding: EdgeInsets.zero,
                                  shape: const CircleBorder(),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildLibraryGameStatusLine(),
                        ],
                      ),
                    ),
                  );

                  if (compact) {
                    return Column(children: [image, details]);
                  }
                  return Row(children: [image, details]);
                },
              ),
            ],
          ),
        ),
      ),
    );

    final emptyPanel = _menuItemEntrance(
      menuKey: LauncherTab.library,
      index: 1,
      child: _glass(
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _adaptiveScrimColor(
                    context,
                    darkAlpha: 0.1,
                    lightAlpha: 0.18,
                  ),
                  border: Border.all(color: _onSurface(context, 0.1)),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: _onSurface(context, 0.9),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Imported Versions Yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _onSurface(context, 0.94),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Import an existing build from the top right of the screen, using the + button or, clicking the download button to browse the build archive.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: _onSurface(context, 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget installedHeaderContent() {
      final searchInput = TextField(
        controller: _librarySearchController,
        onChanged: (value) {
          setState(() => _versionSearchQuery = value);
        },
        decoration: _backendFieldDecoration(hintText: 'Search by name')
            .copyWith(
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: _onSurface(context, 0.75),
              ),
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 40,
                height: 40,
              ),
              suffixIcon: _versionSearchQuery.trim().isEmpty
                  ? null
                  : SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        tooltip: 'Clear search',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () {
                          _librarySearchController.clear();
                          setState(() => _versionSearchQuery = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
            ),
      );
      final clearAllButton = _versionCardAction(
        icon: Icons.delete_sweep_rounded,
        tooltip: 'Clear all versions',
        onTap: () => unawaited(_clearAllVersions()),
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final compactSearchHeader = constraints.maxWidth < 780;
          if (compactSearchHeader) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Installed Versions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: searchInput),
                    const SizedBox(width: 8),
                    clearAllButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              const Expanded(
                child: Text(
                  'Installed Versions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 300, child: searchInput),
              const SizedBox(width: 8),
              clearAllButton,
            ],
          );
        },
      );
    }

    final installedVersionsPanel = SliverPadding(
      padding: const EdgeInsets.only(top: 10),
      sliver: TweenAnimationBuilder<double>(
        key: const ValueKey('menu-library-1'),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 520),
        curve: const Interval(0.08, 1.0, curve: Curves.easeOutCubic),
        builder: (context, t, child) {
          return _SliverEntrance(t: t, translateY: 12, child: child);
        },
        child: _SliverGlass(
          radius: 22,
          blurSigma: 16,
          backgroundColor: _glassSurfaceColor(context),
          borderColor: _onSurface(context, 0.08),
          borderWidth: 1.0,
          child: SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(child: installedHeaderContent()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (filteredVersions.isEmpty)
                  SliverToBoxAdapter(
                    child: Text(
                      'No installed versions match "$_versionSearchQuery".',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  )
                else
                  SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      final columns = width >= 1500
                          ? 3
                          : width >= 980
                          ? 2
                          : 1;
                      const spacing = 10.0;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          mainAxisExtent: 116,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _installedVersionCard(filteredVersions[index]),
                          childCount: filteredVersions.length,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return CustomScrollView(
      controller: _libraryScrollController,
      slivers: [
        SliverToBoxAdapter(child: topPanel),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (installedVersions.isEmpty) SliverToBoxAdapter(child: emptyPanel),
        if (installedVersions.isNotEmpty) ...[
          installedVersionsPanel,
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
        ],
      ],
    );
  }

  void _queueLibrarySplashPrefetch(
    List<VersionEntry> versions, {
    required String signature,
  }) {
    if (!mounted) return;
    if (_tab != LauncherTab.library) return;
    if (versions.isEmpty) return;
    if (_librarySplashPrefetchQueued) return;
    if (_librarySplashPrefetchSignature == signature) return;

    _librarySplashPrefetchSignature = signature;
    _librarySplashPrefetchQueued = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _librarySplashPrefetchQueued = false;
      if (!mounted) return;

      // Pre-cache the first batch of splash images so scrolling feels instant.
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final cacheWidth = (520 * dpr).round().clamp(1, 4096);
      final count = min(8, versions.length);

      unawaited(() async {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        for (var i = 0; i < count; i++) {
          if (!mounted) return;
          if (_tab != LauncherTab.library) return;
          final provider = ResizeImage(
            _libraryCoverImage(versions[i]),
            width: cacheWidth,
          );
          try {
            await precacheImage(provider, context);
          } catch (_) {
            // Ignore bad images.
          }
          // Yield to the UI thread to avoid jank.
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
      }());
    });
  }

  Widget _installedVersionCard(VersionEntry entry) {
    final active = _settings.selectedVersionId == entry.id;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;
    final splashImage = _libraryCoverImage(entry);
    final cardRadius = BorderRadius.circular(18);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 520.0;
        final bgCacheWidth = (maxWidth * dpr).round().clamp(1, 4096);
        final thumbCache = (72 * dpr).round().clamp(1, 1024);
        final bgProvider = ResizeImage(splashImage, width: bgCacheWidth);
        final thumbProvider = ResizeImage(splashImage, width: thumbCache);

        return _HoverScale(
          scale: 1.01,
          child: InkWell(
            borderRadius: cardRadius,
            onTap: () {
              if (active) return;
              setState(() {
                _settings = _settings.copyWith(selectedVersionId: entry.id);
              });
              unawaited(_saveSettings(toast: false));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 116,
              decoration: BoxDecoration(
                borderRadius: cardRadius,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: secondary.withValues(alpha: 0.34),
                          blurRadius: 24,
                          spreadRadius: 0.7,
                        ),
                        BoxShadow(
                          color: _adaptiveScrimColor(
                            context,
                            darkAlpha: 0.30,
                            lightAlpha: 0.10,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: _adaptiveScrimColor(
                            context,
                            darkAlpha: 0.18,
                            lightAlpha: 0.08,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: cardRadius,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                        child: Image(
                          image: bgProvider,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              'assets/images/library_cover.png',
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.low,
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.58,
                                lightAlpha: 0.36,
                              ),
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.48,
                                lightAlpha: 0.24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: cardRadius,
                            border: Border.all(
                              color: active
                                  ? secondary.withValues(alpha: 0.78)
                                  : onSurface.withValues(alpha: 0.20),
                              width: active ? 1.2 : 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image(
                              image: thumbProvider,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.low,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/library_cover.png',
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.low,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: onSurface.withValues(alpha: 0.98),
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: _adaptiveScrimColor(
                                      context,
                                      darkAlpha: 0.24,
                                      lightAlpha: 0.30,
                                    ),
                                    border: Border.all(
                                      color: onSurface.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Text(
                                    entry.gameVersion,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: onSurface.withValues(alpha: 0.95),
                                      fontWeight: FontWeight.w700,
                                      height: 1.05,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (active) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: secondary.withValues(alpha: 0.9),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _versionCardAction(
                            icon: Icons.edit_rounded,
                            tooltip: 'Edit build',
                            onTap: () => _editVersion(entry),
                          ),
                          const SizedBox(width: 6),
                          _versionCardAction(
                            icon: Icons.delete_outline_rounded,
                            tooltip: 'Remove build',
                            onTap: () => _removeVersion(entry.id),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _versionCardAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        color: onSurface.withValues(alpha: 0.92),
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          backgroundColor: _adaptiveScrimColor(
            context,
            darkAlpha: 0.22,
            lightAlpha: 0.24,
          ),
          side: BorderSide(color: onSurface.withValues(alpha: 0.24)),
        ),
      ),
    );
  }

  Widget _backendTab() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;
    final resolvedHost = _effectiveBackendHost().trim();
    final hostLabel = resolvedHost.isEmpty ? '127.0.0.1' : resolvedHost;
    final portLabel = _effectiveBackendPort().toString();
    final endpointLabel = '$hostLabel:$portLabel';
    final statusLabel = _backendOnline
        ? 'Connected on $endpointLabel'
        : 'Waiting on $endpointLabel';
    final backendLaunchLabel = _atlasBackendActionBusy
        ? 'Preparing ATLAS Backend...'
        : _atlasBackendProcess != null
        ? 'ATLAS Backend running'
        : 'Launch ATLAS Backend';

    if (_showBackendConnectionTip &&
        _backendQuickTipStep == 0 &&
        _backendQuickTipOriginalType == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_showBackendConnectionTip ||
            _backendQuickTipStep != 0 ||
            _backendQuickTipOriginalType != null) {
          return;
        }
        _previewBackendTypeForTip(BackendConnectionType.local);
      });
    }

    return _menuItemEntrance(
      menuKey: LauncherTab.backend,
      index: 0,
      child: _glass(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: onSurface.withValues(alpha: 0.06),
                  border: Border.all(color: onSurface.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _backendOnline
                            ? const Color(0xFF16C47F)
                            : const Color(0xFFDC3545),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _backendOnline
                          ? 'Backend reachable'
                          : 'Backend not detected',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showBackendConnectionTip) ...[
                const SizedBox(height: 12),
                _backendConnectionTipCard(),
              ],
              const SizedBox(height: 14),
              _backendSettingTile(
                icon: Icons.settings_ethernet_rounded,
                title: 'Type',
                subtitle: _settings.profileUseEmailPasswordAuth
                    ? 'Remote is required while email/password login is enabled'
                    : 'The type of backend to use when logging into Fortnite',
                trailing: _tipPulseGlowIf(
                  DropdownButtonFormField<BackendConnectionType>(
                    initialValue: _settings.backendConnectionType,
                    decoration: _backendFieldDecoration(),
                    items: BackendConnectionType.values.map((type) {
                      final localBlocked =
                          _settings.profileUseEmailPasswordAuth &&
                          type == BackendConnectionType.local;
                      return DropdownMenuItem<BackendConnectionType>(
                        value: type,
                        enabled: !localBlocked,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: (type) {
                      if (type == null) return;
                      unawaited(_setBackendConnectionType(type));
                    },
                  ),
                  enabled:
                      _showBackendConnectionTip && _backendQuickTipStep < 2,
                ),
              ),
              if (_settings.backendConnectionType ==
                  BackendConnectionType.remote)
                const SizedBox(height: 8),
              if (_settings.backendConnectionType ==
                  BackendConnectionType.remote)
                _backendSettingTile(
                  icon: Icons.language_rounded,
                  title: 'Host',
                  subtitle: 'The hostname of the backend',
                  trailing: TextField(
                    controller: _backendHostController,
                    keyboardType: TextInputType.url,
                    decoration:
                        _backendFieldDecoration(
                          hintText: 'Enter IP Here',
                        ).copyWith(
                          suffixIconConstraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          suffixIcon: _tipPulseGlowIf(
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton(
                                tooltip: 'Save backend',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 40,
                                  height: 40,
                                ),
                                onPressed: () =>
                                    unawaited(_saveCurrentRemoteBackend()),
                                icon: const Icon(
                                  Icons.bookmark_add_rounded,
                                  size: 18,
                                ),
                              ),
                            ),
                            enabled:
                                _showBackendConnectionTip &&
                                _backendQuickTipStep == 2,
                          ),
                        ),
                    onChanged: (value) {
                      final trimmed = value.trim();
                      if (trimmed.isNotEmpty && _isLocalHost(trimmed)) {
                        setState(() {
                          _settings = _settings.copyWith(backendHost: '');
                        });
                        if (_backendHostController.text.isNotEmpty) {
                          _backendHostController.value = const TextEditingValue(
                            text: '',
                          );
                        }
                        unawaited(_saveSettings(toast: false));
                        unawaited(_refreshRuntime());
                        if (mounted) {
                          _toast(
                            'Remote backend host cannot be localhost. Use an external host or IP',
                          );
                        }
                        return;
                      }
                      setState(() {
                        _settings = _settings.copyWith(backendHost: trimmed);
                      });
                      unawaited(_saveSettings(toast: false));
                      unawaited(_refreshRuntime());
                    },
                  ),
                ),
              const SizedBox(height: 8),
              _backendSettingTile(
                icon: Icons.numbers_rounded,
                title: 'Port',
                subtitle: 'The port of the backend',
                trailing: TextField(
                  controller: _backendPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _backendFieldDecoration(hintText: '3551'),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed == null || parsed <= 0) return;
                    setState(() {
                      _settings = _settings.copyWith(backendPort: parsed);
                    });
                    unawaited(_saveSettings(toast: false));
                    unawaited(_refreshRuntime());
                  },
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactActions = constraints.maxWidth < 980;
                  final backendLaunchEnabled =
                      _settings.backendConnectionType ==
                          BackendConnectionType.local &&
                      !_atlasBackendActionBusy &&
                      _atlasBackendProcess == null &&
                      !_backendOnline;
                  const buttonTextStyle = TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  );

                  final launchButton = FilledButton.icon(
                    onPressed: backendLaunchEnabled
                        ? _launchManagedAtlasBackend
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: secondary.withValues(alpha: 0.92),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: onSurface.withValues(
                        alpha: 0.15,
                      ),
                      disabledForegroundColor: onSurface.withValues(
                        alpha: 0.58,
                      ),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder(),
                      textStyle: buttonTextStyle,
                      elevation: 0,
                    ),
                    icon: Icon(
                      _atlasBackendProcess != null
                          ? Icons.check_circle_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(backendLaunchLabel),
                  );

                  final checkButton = FilledButton.tonalIcon(
                    onPressed: _checkBackendNow,
                    style: FilledButton.styleFrom(
                      backgroundColor: secondary.withValues(alpha: 0.92),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: onSurface.withValues(
                        alpha: 0.15,
                      ),
                      disabledForegroundColor: onSurface.withValues(
                        alpha: 0.58,
                      ),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder(),
                      textStyle: buttonTextStyle,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.network_check_rounded, size: 18),
                    label: const Text('Check backend'),
                  );

                  final resetButton = OutlinedButton.icon(
                    onPressed: _resetBackendPreferences,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: onSurface.withValues(alpha: 0.9),
                      side: BorderSide(
                        color: onSurface.withValues(alpha: 0.22),
                      ),
                      backgroundColor: onSurface.withValues(alpha: 0.03),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder(),
                      textStyle: buttonTextStyle,
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset'),
                  );

                  if (compactActions) {
                    return Column(
                      children: [
                        launchButton,
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: checkButton),
                            const SizedBox(width: 10),
                            Expanded(child: resetButton),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 2, child: launchButton),
                      const SizedBox(width: 10),
                      Expanded(child: checkButton),
                      const SizedBox(width: 10),
                      Expanded(child: resetButton),
                    ],
                  );
                },
              ),
              if (_settings.backendConnectionType ==
                  BackendConnectionType.remote) ...[
                const SizedBox(height: 14),
                if (_settings.savedBackends.isEmpty)
                  _savedBackendsPanel()
                else
                  Expanded(child: _savedBackendsPanel()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchManagedAtlasBackend() async {
    if (_atlasBackendActionBusy) return;
    if (!Platform.isWindows) {
      _toast('Launching ATLAS Backend is only available on Windows');
      return;
    }
    if (_atlasBackendProcess != null) {
      _toast('ATLAS Backend is already running');
      await _checkBackendNow();
      return;
    }

    setState(() => _atlasBackendActionBusy = true);
    try {
      var backendExePath = await _findInstalledAtlasBackendExecutable();
      if (backendExePath == null) {
        final installChoice = await _promptInstallAtlasBackend();
        if (installChoice == 'install' && backendExePath == null) {
          // Let the dialog finish its close animation before we start I/O work.
          await Future<void>.delayed(const Duration(milliseconds: 280));
          await _installAtlasBackendNormally();
          return;
        }
        if (backendExePath == null) return;
      }

      unawaited(_cleanupAtlasBackendInstallerIfBackendDetected());
      final backendExe = File(backendExePath);
      final workingDir = backendExe.parent.path;
      _log('backend', 'Starting installed ATLAS Backend from $backendExePath');
      final process = await Process.start(
        backendExePath,
        const <String>[],
        workingDirectory: workingDir,
        runInShell: true,
        environment: {...Platform.environment},
      );
      _atlasBackendProcess = process;
      _attachProcessLogs(process, source: 'backend');
      process.exitCode.then((code) {
        _log('backend', 'ATLAS Backend exited with code $code.');
        if (identical(_atlasBackendProcess, process)) {
          if (mounted) {
            setState(() => _atlasBackendProcess = null);
          } else {
            _atlasBackendProcess = null;
          }
        }
      });
      await _rememberBackendExecutablePath(backendExePath);

      if (mounted) _toast('ATLAS Backend launched');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await _refreshRuntime();
    } catch (error) {
      _log('backend', 'Failed to launch managed ATLAS Backend: $error');
      if (mounted) _toast('Failed to launch ATLAS Backend');
    } finally {
      if (mounted) {
        setState(() => _atlasBackendActionBusy = false);
      } else {
        _atlasBackendActionBusy = false;
      }
    }
  }

  Future<void> _rememberBackendExecutablePath(String exePath) async {
    final workingDir = File(exePath).parent.path;
    if (mounted) {
      setState(() {
        _settings = _settings.copyWith(backendWorkingDirectory: workingDir);
        _backendDirController.text = workingDir;
      });
    } else {
      _settings = _settings.copyWith(backendWorkingDirectory: workingDir);
      _backendDirController.text = workingDir;
    }
    await _saveSettings(toast: false);
  }

  Future<String> _promptInstallAtlasBackend() async {
    if (!mounted) return 'cancel';
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final secondary = Theme.of(dialogContext).colorScheme.secondary;
        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  decoration: BoxDecoration(
                    color: _dialogSurfaceColor(dialogContext),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _onSurface(dialogContext, 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: _dialogShadowColor(dialogContext),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ATLAS Backend Not Found',
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface(dialogContext, 0.95),
                                ),
                              ),
                            ),
                            _buildVersionTag(
                              dialogContext,
                              label: 'Missing',
                              accent: const Color(0xFFDC3545),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ATLAS Backend was not found in installed apps. Install it now as a normal standalone app?',
                          style: TextStyle(
                            color: _onSurface(dialogContext, 0.82),
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: _adaptiveScrimColor(
                              dialogContext,
                              darkAlpha: 0.08,
                              lightAlpha: 0.18,
                            ),
                            border: Border.all(
                              color: _onSurface(dialogContext, 0.1),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: _onSurface(dialogContext, 0.82),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Link will download the latest installer and open setup. After setup finishes, come back and click Launch ATLAS Backend again.',
                                  style: TextStyle(
                                    color: _onSurface(dialogContext, 0.78),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop('cancel'),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop('install'),
                              style: FilledButton.styleFrom(
                                backgroundColor: secondary.withValues(
                                  alpha: 0.92,
                                ),
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 18,
                              ),
                              label: const Text('Install Now'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );
    return result ?? 'cancel';
  }

  Future<bool> _installAtlasBackendNormally() async {
    if (!Platform.isWindows) return false;
    final tempDir = Directory(_joinPath([_dataDir.path, 'backend-installer']));
    var keepInstallerFolder = false;
    var downloadedInstaller = false;
    _showAtlasBackendInstallDialog(
      message: 'Resolving installer...',
      progress: null,
    );
    try {
      final fetchedInstallerUrl = await _fetchAtlasBackendInstallerUrl();
      if (fetchedInstallerUrl == null) {
        _log(
          'backend',
          'Unable to resolve backend installer URL from releases.',
        );
        _updateAtlasBackendInstallDialog(
          message: 'Installer not found. Opening release page...',
          progress: null,
        );
        if (mounted) _toast('Unable to resolve backend installer URL');
        await _openUrl(_atlasBackendLatestReleasePage);
        return false;
      }
      var installerUrl = fetchedInstallerUrl;

      await tempDir.parent.create(recursive: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      _updateAtlasBackendInstallDialog(
        message: 'Preparing download...',
        progress: null,
      );

      final initialUri = Uri.tryParse(installerUrl);
      final initialLowerPath = (initialUri?.path ?? installerUrl).toLowerCase();
      var extension = initialLowerPath.endsWith('.msi')
          ? '.msi'
          : initialLowerPath.endsWith('.exe')
          ? '.exe'
          // Prefer MSI if the URL has no usable extension (common with redirects).
          : '.msi';
      var installerFile = File(
        _joinPath([tempDir.path, 'atlas-backend-installer$extension']),
      );

      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (attempt > 1) {
          _updateAtlasBackendInstallDialog(
            message: 'Retrying download... (attempt $attempt/$maxAttempts)',
            progress: null,
          );
          final refreshed = await _fetchAtlasBackendInstallerUrl();
          if (refreshed != null) installerUrl = refreshed;
        }

        final uriNow = Uri.tryParse(installerUrl);
        final lowerPathNow = (uriNow?.path ?? installerUrl).toLowerCase();
        final nextExtension = lowerPathNow.endsWith('.msi')
            ? '.msi'
            : lowerPathNow.endsWith('.exe')
            ? '.exe'
            : extension;
        if (nextExtension != extension) {
          extension = nextExtension;
          installerFile = File(
            _joinPath([tempDir.path, 'atlas-backend-installer$extension']),
          );
        }

        _log(
          'backend',
          'Downloading ATLAS Backend installer (attempt $attempt/$maxAttempts) from $installerUrl',
        );
        try {
          await _downloadToFile(
            installerUrl,
            installerFile,
            onProgress: (receivedBytes, totalBytes) {
              if (totalBytes == null || totalBytes <= 0) {
                _updateAtlasBackendInstallDialog(
                  message:
                      'Downloading installer... ${_formatByteSize(receivedBytes)}',
                  progress: null,
                );
                return;
              }
              final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
              _updateAtlasBackendInstallDialog(
                message:
                    'Downloading installer... ${_formatByteSize(receivedBytes)} / ${_formatByteSize(totalBytes)}',
                progress: progress.toDouble(),
              );
            },
          );
          break;
        } catch (error) {
          _log(
            'backend',
            'Backend installer download attempt $attempt failed: $error',
          );
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }

      final detectedExtension = await _detectWindowsInstallerExtension(
        installerFile,
      );
      if (detectedExtension != null && detectedExtension != extension) {
        _log(
          'backend',
          'Installer type mismatch: expected $extension but detected $detectedExtension. Renaming.',
        );
        final corrected = File(
          _joinPath([
            tempDir.path,
            'atlas-backend-installer$detectedExtension',
          ]),
        );
        try {
          if (await corrected.exists()) await corrected.delete();
        } catch (_) {
          // Ignore pre-clean failures.
        }
        try {
          installerFile = await installerFile.rename(corrected.path);
          extension = detectedExtension;
        } catch (_) {
          try {
            await installerFile.copy(corrected.path);
            installerFile = corrected;
            extension = detectedExtension;
          } catch (_) {
            // Keep the original file name; still use the detected type for launch.
            extension = detectedExtension;
          }
        }
      }

      downloadedInstaller = true;

      _updateAtlasBackendInstallDialog(
        message: 'Launching setup...',
        progress: 1,
      );
      _log('backend', 'Launching setup installer: ${installerFile.path}');

      if (extension == '.msi') {
        await Process.start('msiexec', [
          '/i',
          installerFile.path,
        ], runInShell: true);
      } else {
        await Process.start(
          installerFile.path,
          const <String>[],
          runInShell: true,
        );
      }
      keepInstallerFolder = true;
      unawaited(_watchAtlasBackendInstallAndCleanup(tempDir.path));
      await _hideAtlasBackendInstallDialog();
      if (mounted) {
        _toast(
          'ATLAS Backend setup launched. Finish setup, then click Launch ATLAS Backend again',
        );
      }
      return true;
    } catch (error) {
      await _hideAtlasBackendInstallDialog();
      _log('backend', 'ATLAS Backend install failed: $error');
      if (mounted) _toast('Failed to install ATLAS Backend');
      if (!downloadedInstaller) {
        try {
          if (mounted) _toast('Opening ATLAS Backend release page...');
          await _openUrl(_atlasBackendLatestReleasePage);
        } catch (_) {
          // Ignore browser launch failures.
        }
      }
      return false;
    } finally {
      await _hideAtlasBackendInstallDialog();
      try {
        if (!keepInstallerFolder && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // Ignore temp cleanup failures.
      }
    }
  }

  Future<void> _watchAtlasBackendInstallAndCleanup(
    String installerDirPath,
  ) async {
    if (_atlasBackendInstallCleanupWatcherActive) return;
    _atlasBackendInstallCleanupWatcherActive = true;
    try {
      for (var attempt = 0; attempt < 120; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final installedPath = await _findInstalledAtlasBackendExecutable();
        if (installedPath == null) continue;
        final cleaned = await _cleanupAtlasBackendInstallerDirectory(
          installerDirPath,
        );
        if (cleaned) {
          _log(
            'backend',
            'ATLAS Backend detected at $installedPath. Installer cache cleaned.',
          );
          return;
        }
      }
      _log(
        'backend',
        'ATLAS Backend install watcher timed out before detecting installation.',
      );
    } catch (error) {
      _log('backend', 'ATLAS Backend install watcher failed: $error');
    } finally {
      _atlasBackendInstallCleanupWatcherActive = false;
    }
  }

  Future<void> _cleanupAtlasBackendInstallerIfBackendDetected() async {
    if (!Platform.isWindows) return;
    try {
      final installerDir = _atlasBackendInstallerDirectory();
      if (!await installerDir.exists()) return;
      final installedPath = await _findInstalledAtlasBackendExecutable();
      if (installedPath == null) return;
      final cleaned = await _cleanupAtlasBackendInstallerDirectory(
        installerDir.path,
      );
      if (cleaned) {
        _log(
          'backend',
          'Cleaned stale backend installer cache after detecting $installedPath.',
        );
      } else {
        _log(
          'backend',
          'Could not clean stale backend installer cache yet; scheduling retries.',
        );
        unawaited(_watchAtlasBackendInstallAndCleanup(installerDir.path));
      }
    } catch (error) {
      _log('backend', 'Failed to clean stale backend installer cache: $error');
    }
  }

  Directory _atlasBackendInstallerDirectory() {
    return Directory(_joinPath([_dataDir.path, 'backend-installer']));
  }

  Future<bool> _cleanupAtlasBackendInstallerDirectory(String path) async {
    final dir = Directory(path);
    var lockWarningLogged = false;
    const maxAttempts = 24;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!await dir.exists()) return true;
      try {
        await dir.delete(recursive: true);
        return true;
      } catch (error) {
        final lower = error.toString().toLowerCase();
        final isLockContention =
            lower.contains('being used by another process') ||
            lower.contains('errno = 32');
        if (isLockContention && !lockWarningLogged) {
          _log(
            'backend',
            'Installer cache is still in use; retrying cleanup shortly.',
          );
          lockWarningLogged = true;
        } else if (!isLockContention) {
          _log(
            'backend',
            'Unexpected installer cache cleanup error on attempt $attempt/$maxAttempts: $error',
          );
        }
        if (attempt == maxAttempts) {
          _log(
            'backend',
            'Unable to clean backend installer cache after $maxAttempts attempts.',
          );
          return false;
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    return !await dir.exists();
  }

  Directory _launcherUpdateInstallerDirectory() {
    return Directory(_joinPath([_dataDir.path, 'launcher-installer']));
  }

  Future<void> _cleanupLauncherUpdateInstallerCacheOnLaunch() async {
    if (!Platform.isWindows) return;
    if (_launcherUpdateInstallerCleanupWatcherActive) return;
    _launcherUpdateInstallerCleanupWatcherActive = true;
    try {
      final dir = _launcherUpdateInstallerDirectory();
      if (!await dir.exists()) return;

      var lockWarningLogged = false;
      const maxAttempts = 24;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (!await dir.exists()) return;
        try {
          await dir.delete(recursive: true);
          _log('launcher', 'Cleaned launcher update installer cache.');
          return;
        } catch (error) {
          final lower = error.toString().toLowerCase();
          final isLockContention =
              lower.contains('being used by another process') ||
              lower.contains('errno = 32');
          if (isLockContention && !lockWarningLogged) {
            _log(
              'launcher',
              'Launcher update installer cache is still in use; retrying cleanup shortly.',
            );
            lockWarningLogged = true;
          } else if (!isLockContention) {
            _log(
              'launcher',
              'Unexpected launcher update cache cleanup error on attempt $attempt/$maxAttempts: $error',
            );
          }
          if (attempt == maxAttempts) {
            _log(
              'launcher',
              'Unable to clean launcher update installer cache after $maxAttempts attempts.',
            );
            return;
          }
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
    } catch (error) {
      _log(
        'launcher',
        'Failed to clean launcher update installer cache: $error',
      );
    } finally {
      _launcherUpdateInstallerCleanupWatcherActive = false;
    }
  }

  void _showAtlasBackendInstallDialog({
    required String message,
    double? progress,
  }) {
    _updateAtlasBackendInstallDialog(message: message, progress: progress);
    if (!mounted || _atlasBackendInstallDialogVisible) return;
    _atlasBackendInstallDialogVisible = true;
    _atlasBackendInstallDialogContext = null;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          _atlasBackendInstallDialogContext = dialogContext;
          return SafeArea(
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _dialogSurfaceColor(dialogContext),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _onSurface(dialogContext, 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: _dialogShadowColor(dialogContext),
                          blurRadius: 30,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: ValueListenableBuilder<_BackendInstallProgress>(
                        valueListenable: _atlasBackendInstallProgress,
                        builder: (context, state, _) {
                          final progressValue = state.progress;
                          final progressLabel = progressValue == null
                              ? 'Starting...'
                              : '${(progressValue * 100).toStringAsFixed(0)}%';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Installing ATLAS Backend',
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface(dialogContext, 0.95),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                state.message,
                                style: TextStyle(
                                  color: _onSurface(dialogContext, 0.84),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progressValue,
                                  minHeight: 10,
                                  backgroundColor: _onSurface(
                                    dialogContext,
                                    0.12,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(
                                      dialogContext,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  progressLabel,
                                  style: TextStyle(
                                    color: _onSurface(dialogContext, 0.72),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _settings.popupBackgroundBlurEnabled
                    ? BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 3.2 * curved.value,
                          sigmaY: 3.2 * curved.value,
                        ),
                        child: Container(
                          color: _dialogBarrierColor(
                            dialogContext,
                            curved.value,
                          ),
                        ),
                      )
                    : Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
              ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      ).whenComplete(() {
        _atlasBackendInstallDialogContext = null;
        _atlasBackendInstallDialogVisible = false;
      }),
    );
  }

  void _updateAtlasBackendInstallDialog({
    required String message,
    double? progress,
  }) {
    final normalized = progress?.clamp(0.0, 1.0).toDouble();
    _atlasBackendInstallProgress.value = _BackendInstallProgress(
      message: message,
      progress: normalized,
    );
  }

  Future<void> _hideAtlasBackendInstallDialog() async {
    if (!_atlasBackendInstallDialogVisible) return;
    for (var attempt = 0; attempt < 8; attempt++) {
      final dialogContext = _atlasBackendInstallDialogContext;
      if (dialogContext != null) {
        if (!dialogContext.mounted) {
          _atlasBackendInstallDialogContext = null;
          _atlasBackendInstallDialogVisible = false;
          return;
        }
        _atlasBackendInstallDialogContext = null;
        _atlasBackendInstallDialogVisible = false;
        Navigator.of(dialogContext, rootNavigator: true).pop();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!_atlasBackendInstallDialogVisible) return;
    }
    _atlasBackendInstallDialogVisible = false;
    _atlasBackendInstallDialogContext = null;
  }

  Future<String?> _fetchAtlasBackendInstallerUrl() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'ATLAS-Link';
    try {
      String? pickInstallerFromAssets(dynamic assets) {
        if (assets is! List) return null;
        String? atlasInstallerMsi;
        String? installerMsi;
        String? atlasMsi;
        String? firstMsi;
        String? atlasSetupExe;
        String? setupExe;
        String? atlasExe;
        String? firstExe;
        for (final asset in assets) {
          if (asset is! Map<String, dynamic>) continue;
          final name = (asset['name'] ?? '').toString().toLowerCase();
          final url = (asset['browser_download_url'] ?? '').toString().trim();
          if (url.isEmpty) continue;

          final isAtlasAsset =
              name.contains('atlas') || name.contains('backend');
          final isInstaller =
              name.contains('setup') ||
              name.contains('installer') ||
              name.contains('install');
          if (name.endsWith('.msi')) {
            if (isInstaller && isAtlasAsset) {
              atlasInstallerMsi ??= url;
            } else if (isInstaller) {
              installerMsi ??= url;
            } else if (isAtlasAsset) {
              atlasMsi ??= url;
            } else {
              firstMsi ??= url;
            }
            continue;
          }
          if (name.endsWith('.exe')) {
            if (isInstaller && isAtlasAsset) {
              atlasSetupExe ??= url;
            } else if (isInstaller) {
              setupExe ??= url;
            } else if (isAtlasAsset) {
              atlasExe ??= url;
            } else {
              firstExe ??= url;
            }
          }
        }
        // Prefer MSI now that backend is distributed as an MSI again.
        return atlasInstallerMsi ??
            installerMsi ??
            atlasMsi ??
            firstMsi ??
            atlasSetupExe ??
            setupExe ??
            atlasExe ??
            firstExe;
      }

      Future<dynamic> fetchGitHubJson(String url) async {
        final request = await client.getUrl(Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 8;
        request.headers.set('Accept', 'application/vnd.github+json');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          final remaining = response.headers.value('x-ratelimit-remaining');
          final hint = remaining == null || remaining.trim().isEmpty
              ? ''
              : ' (rate remaining $remaining)';
          _log(
            'backend',
            'GitHub API request failed ($url): HTTP ${response.statusCode}$hint',
          );
          return null;
        }
        if (body.trim().isEmpty) return null;
        try {
          return jsonDecode(body);
        } catch (_) {
          return null;
        }
      }

      final latest = await fetchGitHubJson(_atlasBackendLatestReleaseApi);
      if (latest is Map<String, dynamic>) {
        final picked = pickInstallerFromAssets(latest['assets']);
        if (picked != null) return picked;
      }

      // Fallback: scan recent releases in case /latest is missing assets, points
      // at an older tag, or the installer was attached to a different release.
      final recent = await fetchGitHubJson(
        'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases?per_page=12',
      );
      if (recent is! List) return null;

      String? scanReleases({required bool includePrerelease}) {
        for (final release in recent) {
          if (release is! Map<String, dynamic>) continue;
          if (release['draft'] == true) continue;
          if (!includePrerelease && release['prerelease'] == true) continue;
          final picked = pickInstallerFromAssets(release['assets']);
          if (picked != null) return picked;
        }
        return null;
      }

      return scanReleases(includePrerelease: false) ??
          scanReleases(includePrerelease: true);
    } catch (error) {
      _log('backend', 'Failed to resolve backend installer URL: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadToFile(
    String url,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'ATLAS-Link';
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 8;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw 'Download failed (HTTP ${response.statusCode}).';
      }
      sink = destination.openWrite();
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : null;
      var receivedBytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<String?> _detectWindowsInstallerExtension(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final header = await raf.read(8);
      if (header.length >= 2 && header[0] == 0x4D && header[1] == 0x5A) {
        return '.exe';
      }
      const oleMagic = <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
      if (header.length >= 8) {
        var matchesOle = true;
        for (var i = 0; i < oleMagic.length; i++) {
          if (header[i] != oleMagic[i]) {
            matchesOle = false;
            break;
          }
        }
        if (matchesOle) return '.msi';
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {
        // Ignore header read close failures.
      }
    }
  }

  String _formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024.0;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final digits = value >= 100
        ? 0
        : value >= 10
        ? 1
        : 2;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  Future<String?> _findInstalledAtlasBackendExecutable() async {
    final candidates = <String>[];
    void addWithNames(String? dirPath) {
      if (dirPath == null || dirPath.trim().isEmpty) return;
      candidates.add(_joinPath([dirPath, 'ATLAS Backend.exe']));
      candidates.add(_joinPath([dirPath, 'ATLAS-Backend.exe']));
      candidates.add(_joinPath([dirPath, 'ATLAS.exe']));
    }

    final configuredPath = _settings.backendWorkingDirectory.trim();
    if (configuredPath.isNotEmpty) {
      final normalizedConfigured = configuredPath.replaceAll('\\', '/');
      if (normalizedConfigured.toLowerCase().endsWith('.exe') &&
          File(configuredPath).existsSync()) {
        return configuredPath;
      }
      addWithNames(configuredPath);
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    final programFiles = Platform.environment['ProgramFiles'];
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    addWithNames(
      localAppData == null
          ? null
          : _joinPath([localAppData, 'Programs', 'ATLAS Backend']),
    );
    addWithNames(
      localAppData == null
          ? null
          : _joinPath([localAppData, 'Programs', 'ATLAS-Backend']),
    );
    addWithNames(
      localAppData == null ? null : _joinPath([localAppData, 'ATLAS Backend']),
    );
    addWithNames(
      localAppData == null
          ? null
          : _joinPath([localAppData, 'ATLAS Backend', 'ATLAS Backend']),
    );
    addWithNames(
      localAppData == null ? null : _joinPath([localAppData, 'ATLAS']),
    );
    addWithNames(
      programFiles == null ? null : _joinPath([programFiles, 'ATLAS Backend']),
    );
    addWithNames(
      programFiles == null ? null : _joinPath([programFiles, 'ATLAS-Backend']),
    );
    addWithNames(
      programFilesX86 == null
          ? null
          : _joinPath([programFilesX86, 'ATLAS Backend']),
    );
    addWithNames(
      programFilesX86 == null
          ? null
          : _joinPath([programFilesX86, 'ATLAS-Backend']),
    );

    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = candidate.toLowerCase();
      if (!seen.add(normalized)) continue;
      if (File(candidate).existsSync()) return candidate;
    }

    final appData = Platform.environment['APPDATA'];
    final scanRoots = <String>[
      if (localAppData != null && localAppData.trim().isNotEmpty)
        _joinPath([localAppData, 'Programs']),
      if (localAppData != null && localAppData.trim().isNotEmpty) localAppData,
      if (appData != null && appData.trim().isNotEmpty) appData,
      if (programFiles != null && programFiles.trim().isNotEmpty) programFiles,
      if (programFilesX86 != null && programFilesX86.trim().isNotEmpty)
        programFilesX86,
    ];
    for (final root in scanRoots) {
      final found = await _scanForAtlasBackendExecutableUnder(
        root,
        maxDepth: root.toLowerCase().endsWith('programs') ? 4 : 3,
      );
      if (found != null) return found;
    }

    return _findInstalledAtlasBackendExecutableFromRegistry();
  }

  Future<String?> _scanForAtlasBackendExecutableUnder(
    String rootPath, {
    int maxDepth = 3,
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return null;

    final queue = ListQueue<_DirectoryDepth>()
      ..add(_DirectoryDepth(directory: root, depth: 0));
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      try {
        await for (final entity in current.directory.list(followLinks: false)) {
          if (entity is File) {
            final fileName = _basename(entity.path).toLowerCase();
            final lowerPath = entity.path.toLowerCase();
            if (fileName.endsWith('.exe') &&
                ((fileName.contains('atlas') && fileName.contains('backend')) ||
                    (fileName == 'atlas.exe' &&
                        (lowerPath.contains('\\atlas backend\\') ||
                            lowerPath.contains('/atlas backend/'))))) {
              return entity.path;
            }
          } else if (entity is Directory && current.depth < maxDepth) {
            queue.add(
              _DirectoryDepth(directory: entity, depth: current.depth + 1),
            );
          }
        }
      } catch (_) {
        // Skip unreadable directories.
      }
    }
    return null;
  }

  Future<String?> _findInstalledAtlasBackendExecutableFromRegistry() async {
    const script = r'''
$paths = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$entries = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -like '*ATLAS*' }
foreach ($entry in $entries) {
  if ($entry.DisplayIcon) {
    Write-Output $entry.DisplayIcon
  }
  if ($entry.InstallLocation) {
    $loc = $entry.InstallLocation.ToString().Trim()
    Write-Output (Join-Path $loc 'ATLAS Backend.exe')
    Write-Output (Join-Path $loc 'ATLAS-Backend.exe')
    Write-Output (Join-Path $loc 'ATLAS.exe')
  }
}
$appPathRoots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\*.exe',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\*.exe',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\*.exe'
)
$appPaths = Get-ItemProperty -Path $appPathRoots -ErrorAction SilentlyContinue |
  Where-Object { $_.PSChildName -like '*atlas*backend*.exe' }
foreach ($app in $appPaths) {
  if ($app.'(default)') {
    Write-Output $app.'(default)'
  }
  if ($app.Path) {
    $loc = $app.Path.ToString().Trim()
    Write-Output (Join-Path $loc 'ATLAS Backend.exe')
    Write-Output (Join-Path $loc 'ATLAS-Backend.exe')
  }
}
''';
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], runInShell: true);
      if (result.exitCode != 0) return null;
      final lines = result.stdout.toString().split(RegExp(r'\r?\n'));
      for (final raw in lines) {
        var candidate = raw.trim();
        if (candidate.isEmpty) continue;
        candidate = candidate.replaceAll('"', '');
        candidate = candidate.replaceFirst(RegExp(r',\s*\d+$'), '');
        if (File(candidate).existsSync()) return candidate;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkBackendNow() async {
    if (_settings.backendConnectionType == BackendConnectionType.remote) {
      final host = _backendHostController.text.trim();
      if (host.isEmpty || _isLocalHost(host)) {
        _toast('Remote host is required and cannot be localhost');
        return;
      }
    }
    await _saveSettings(toast: false);
    await _refreshRuntime(force: true);
    if (!mounted) return;
    final configured = '${_effectiveBackendHost()}:${_effectiveBackendPort()}';
    final effective = '$_defaultBackendHost:$_defaultBackendPort';
    if (_backendOnline) {
      _toast('Connected to backend on $effective (configured: $configured)');
    } else {
      _toast('No backend detected (configured: $configured)');
    }
  }

  Future<void> _resetBackendPreferences() async {
    final requireRemote = _settings.profileUseEmailPasswordAuth;
    setState(() {
      _settings = _settings.copyWith(
        backendConnectionType: requireRemote
            ? BackendConnectionType.remote
            : BackendConnectionType.local,
        backendHost: requireRemote ? '' : '127.0.0.1',
        backendPort: 3551,
      );
      _backendHostController.text = _effectiveBackendHost();
      _backendPortController.text = _effectiveBackendPort().toString();
    });
    await _saveSettings(toast: false);
    await _refreshRuntime();
    if (mounted) {
      _toast(
        requireRemote
            ? 'Backend settings reset. Remote remains required for email/password auth.'
            : 'Backend settings reset',
      );
    }
  }

  String _backendHostKey(String host) {
    final normalized = host
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^https://', caseSensitive: false), '')
        .split('/')
        .first;
    final bare = normalized.startsWith('[')
        ? normalized.split(']').first.replaceFirst('[', '')
        : normalized.split(':').first;
    return bare.trim();
  }

  Future<void> _saveCurrentRemoteBackend() async {
    if (!mounted) return;
    if (_settings.backendConnectionType != BackendConnectionType.remote) return;

    final host = _backendHostController.text.trim();
    if (host.isEmpty) {
      _toast('Enter a backend host first');
      return;
    }
    if (_isLocalHost(host)) {
      _toast('Remote backend host cannot be localhost');
      return;
    }

    final port =
        int.tryParse(_backendPortController.text.trim()) ??
        _effectiveBackendPort();
    if (port <= 0 || port > 65535) {
      _toast('Enter a valid backend port');
      return;
    }

    final name = await _promptSavedBackendName();
    if (!mounted) return;
    final trimmedName = (name ?? '').trim();
    if (trimmedName.isEmpty) return;

    final next = List<SavedBackend>.from(_settings.savedBackends);
    final lower = trimmedName.toLowerCase();
    final nameConflict = next.any(
      (entry) => entry.name.trim().toLowerCase() == lower,
    );
    if (nameConflict) {
      _toast('A saved backend with that name already exists');
      return;
    }

    final hostKey = _backendHostKey(host);
    final endpointConflict = next.any(
      (entry) => _backendHostKey(entry.host) == hostKey && entry.port == port,
    );
    if (endpointConflict) {
      _toast('That backend (IP + port) is already saved');
      return;
    }

    final entry = SavedBackend(name: trimmedName, host: host, port: port);
    next.add(entry);

    setState(() {
      _settings = _settingsWithSavedBackendsForActiveProfile(next);
    });
    await _saveSettings(toast: false, applyControllers: false);
    if (mounted) _toast('Saved backend: ${entry.name}');
  }

  Future<void> _editSavedBackend(SavedBackend entry) async {
    if (!mounted) return;
    final index = _settings.savedBackends.indexWhere(
      (candidate) =>
          candidate.name == entry.name &&
          candidate.host == entry.host &&
          candidate.port == entry.port,
    );
    if (index < 0) return;

    final others = <SavedBackend>[];
    for (var i = 0; i < _settings.savedBackends.length; i++) {
      if (i == index) continue;
      others.add(_settings.savedBackends[i]);
    }

    final updated = await _promptEditSavedBackend(entry, others: others);
    if (!mounted) return;
    if (updated == null) return;

    final next = List<SavedBackend>.from(_settings.savedBackends);
    next[index] = updated;
    setState(() {
      _settings = _settingsWithSavedBackendsForActiveProfile(next);
    });
    await _saveSettings(toast: false, applyControllers: false);
    if (mounted) _toast('Updated backend: ${updated.name}');
  }

  Future<SavedBackend?> _promptEditSavedBackend(
    SavedBackend entry, {
    required List<SavedBackend> others,
  }) async {
    if (!mounted) return null;

    final nameController = TextEditingController(text: entry.name);
    final hostController = TextEditingController(text: entry.host);
    final portController = TextEditingController(text: entry.port.toString());
    var nameError = '';
    var hostError = '';
    var portError = '';

    void clearErrors(StateSetter setDialogState) {
      if (nameError.isEmpty && hostError.isEmpty && portError.isEmpty) return;
      setDialogState(() {
        nameError = '';
        hostError = '';
        portError = '';
      });
    }

    final result = await showGeneralDialog<SavedBackend>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final onSurface = Theme.of(dialogContext).colorScheme.onSurface;
        final secondary = Theme.of(dialogContext).colorScheme.secondary;
        final maxHeight = min(
          640.0,
          MediaQuery.sizeOf(dialogContext).height - 40,
        );

        void submit(StateSetter setDialogState) {
          final name = nameController.text.trim();
          final host = hostController.text.trim();
          final portRaw = portController.text.trim();

          var nextNameError = '';
          var nextHostError = '';
          var nextPortError = '';

          if (name.isEmpty) nextNameError = 'Name is required';
          if (host.isEmpty) nextHostError = 'Host is required';
          if (host.isNotEmpty && _isLocalHost(host)) {
            nextHostError = 'Host cannot be localhost';
          }

          final parsedPort = int.tryParse(portRaw);
          if (parsedPort == null || parsedPort <= 0 || parsedPort > 65535) {
            nextPortError = 'Invalid port';
          }

          if (nextNameError.isEmpty) {
            final lower = name.toLowerCase();
            final nameConflict = others.any(
              (other) => other.name.trim().toLowerCase() == lower,
            );
            if (nameConflict) {
              nextNameError = 'Name already exists';
            }
          }

          if (nextHostError.isEmpty && nextPortError.isEmpty) {
            final hostKey = _backendHostKey(host);
            final endpointConflict = others.any(
              (other) =>
                  _backendHostKey(other.host) == hostKey &&
                  other.port == parsedPort,
            );
            if (endpointConflict) {
              nextHostError = 'Backend already saved';
            }
          }

          if (nextNameError.isNotEmpty ||
              nextHostError.isNotEmpty ||
              nextPortError.isNotEmpty) {
            setDialogState(() {
              nameError = nextNameError;
              hostError = nextHostError;
              portError = nextPortError;
            });
            return;
          }

          Navigator.of(
            dialogContext,
          ).pop(SavedBackend(name: name, host: host, port: parsedPort!));
        }

        InputDecoration fieldDecoration({
          required String label,
          required String error,
          String? hint,
        }) {
          return InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: _onSurface(dialogContext, 0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _onSurface(dialogContext, 0.18)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _onSurface(dialogContext, 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: secondary, width: 1.2),
            ),
            errorText: error.isEmpty ? null : error,
          );
        }

        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: maxHeight,
                ),
                child: StatefulBuilder(
                  builder: (dialogContext, setDialogState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: _dialogSurfaceColor(dialogContext),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _onSurface(dialogContext, 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _dialogShadowColor(dialogContext),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.edit_rounded,
                                  color: _onSurface(dialogContext, 0.94),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Edit Saved Backend',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    color: _onSurface(dialogContext, 0.96),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Update the saved backend name and endpoint. Names and IP:port must be unique.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: _onSurface(dialogContext, 0.74),
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: nameController,
                                      textInputAction: TextInputAction.next,
                                      onChanged: (_) =>
                                          clearErrors(setDialogState),
                                      decoration: fieldDecoration(
                                        label: 'Name',
                                        hint: 'Players Backend',
                                        error: nameError,
                                      ),
                                      style: TextStyle(color: onSurface),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: hostController,
                                      keyboardType: TextInputType.url,
                                      textInputAction: TextInputAction.next,
                                      onChanged: (_) =>
                                          clearErrors(setDialogState),
                                      decoration: fieldDecoration(
                                        label: 'Host',
                                        hint: 'Enter IP Here',
                                        error: hostError,
                                      ),
                                      style: TextStyle(color: onSurface),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: portController,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onChanged: (_) =>
                                          clearErrors(setDialogState),
                                      onSubmitted: (_) =>
                                          submit(setDialogState),
                                      decoration: fieldDecoration(
                                        label: 'Port',
                                        hint: '3551',
                                        error: portError,
                                      ),
                                      style: TextStyle(color: onSurface),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => Navigator.of(
                                            dialogContext,
                                          ).pop(null),
                                          child: const Text('Cancel'),
                                        ),
                                        const SizedBox(width: 10),
                                        FilledButton.icon(
                                          onPressed: () =>
                                              submit(setDialogState),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: secondary
                                                .withValues(alpha: 0.92),
                                            foregroundColor: Colors.white,
                                            shape: const StadiumBorder(),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 12,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.save_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    hostController.dispose();
    portController.dispose();
    return result;
  }

  Future<String?> _promptSavedBackendName() async {
    if (!mounted) return null;

    final controller = TextEditingController();
    final focusNode = FocusNode();

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final onSurface = Theme.of(dialogContext).colorScheme.onSurface;
        final secondary = Theme.of(dialogContext).colorScheme.secondary;
        var validation = '';

        void submit(StateSetter setDialogState) {
          final name = controller.text.trim();
          if (name.isEmpty) {
            setDialogState(() => validation = 'Name is required');
            return;
          }
          Navigator.of(dialogContext).pop(name);
        }

        return SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: StatefulBuilder(
                  builder: (dialogContext, setDialogState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: _dialogSurfaceColor(dialogContext),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _onSurface(dialogContext, 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _dialogShadowColor(dialogContext),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.bookmark_add_rounded),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Save Backend',
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w700,
                                      color: _onSurface(dialogContext, 0.95),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) {
                                if (validation.isEmpty) return;
                                setDialogState(() => validation = '');
                              },
                              onSubmitted: (_) => submit(setDialogState),
                              decoration: InputDecoration(
                                labelText: 'Name',
                                hintText: 'Players Backend',
                                isDense: true,
                                filled: true,
                                fillColor: _onSurface(dialogContext, 0.06),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _onSurface(dialogContext, 0.18),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _onSurface(dialogContext, 0.18),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: secondary,
                                    width: 1.2,
                                  ),
                                ),
                                errorText: validation.isEmpty
                                    ? null
                                    : validation,
                              ),
                              style: TextStyle(color: onSurface),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(null),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: () => submit(setDialogState),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: secondary.withValues(
                                      alpha: 0.92,
                                    ),
                                    foregroundColor: Colors.white,
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.save_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: _settings.popupBackgroundBlurEnabled
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 3.2 * curved.value,
                        sigmaY: 3.2 * curved.value,
                      ),
                      child: Container(
                        color: _dialogBarrierColor(dialogContext, curved.value),
                      ),
                    )
                  : Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );

    focusNode.dispose();
    controller.dispose();
    return result;
  }

  Future<void> _removeSavedBackend(SavedBackend entry) async {
    final next = List<SavedBackend>.from(_settings.savedBackends)
      ..removeWhere(
        (candidate) =>
            candidate.name == entry.name &&
            candidate.host == entry.host &&
            candidate.port == entry.port,
      );
    if (next.length == _settings.savedBackends.length) return;

    if (mounted) {
      setState(() {
        _settings = _settingsWithSavedBackendsForActiveProfile(next);
      });
    } else {
      _settings = _settingsWithSavedBackendsForActiveProfile(next);
    }
    await _saveSettings(toast: false, applyControllers: false);
    if (mounted) _toast('Removed backend: ${entry.name}');
  }

  Future<void> _clearAllSavedBackends() async {
    if (_settings.savedBackends.isEmpty) return;
    _savedBackendSearchController.clear();
    _savedBackendSearchQuery = '';
    if (mounted) {
      setState(() {
        _settings = _settingsWithSavedBackendsForActiveProfile(
          const <SavedBackend>[],
        );
      });
    } else {
      _settings = _settingsWithSavedBackendsForActiveProfile(
        const <SavedBackend>[],
      );
    }
    await _saveSettings(toast: false, applyControllers: false);
    if (mounted) _toast('Cleared saved backends');
  }

  Widget _savedBackendsPanel() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final saved = _settings.savedBackends;
    final query = _savedBackendSearchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? saved
        : saved.where((entry) {
            final name = entry.name.toLowerCase();
            final host = entry.host.toLowerCase();
            final port = entry.port.toString();
            return name.contains(query) ||
                host.contains(query) ||
                port.contains(query) ||
                '$host:$port'.contains(query);
          }).toList();

    final emptyState = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: _adaptiveScrimColor(context, darkAlpha: 0.10, lightAlpha: 0.18),
        border: Border.all(color: _onSurface(context, 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _adaptiveScrimColor(
                context,
                darkAlpha: 0.10,
                lightAlpha: 0.18,
              ),
              border: Border.all(color: _onSurface(context, 0.10)),
            ),
            child: Icon(
              Icons.bookmarks_outlined,
              color: _onSurface(context, 0.90),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Saved Backends Yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _onSurface(context, 0.94),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Switch Type to Remote, enter an IP, then click the bookmark button next to Host to save it.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: _onSurface(context, 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget header() {
      final title = Text(
        'Saved Backends',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: onSurface.withValues(alpha: 0.92),
        ),
      );

      if (saved.isEmpty) return title;

      final searchInput = TextField(
        controller: _savedBackendSearchController,
        onChanged: (value) => setState(() => _savedBackendSearchQuery = value),
        decoration: _backendFieldDecoration(hintText: 'Search saved backends')
            .copyWith(
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: onSurface.withValues(alpha: 0.75),
              ),
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 40,
                height: 40,
              ),
              suffixIcon: _savedBackendSearchQuery.trim().isEmpty
                  ? null
                  : SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        tooltip: 'Clear search',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        onPressed: () {
                          _savedBackendSearchController.clear();
                          setState(() => _savedBackendSearchQuery = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
            ),
      );

      final clearAllIconButton = _versionCardAction(
        icon: Icons.delete_sweep_rounded,
        tooltip: 'Clear all saved backends',
        onTap: () => unawaited(_clearAllSavedBackends()),
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: searchInput),
                    const SizedBox(width: 8),
                    clearAllIconButton,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              SizedBox(width: 290, child: searchInput),
              const SizedBox(width: 8),
              clearAllIconButton,
            ],
          );
        },
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: onSurface.withValues(alpha: 0.04),
        border: Border.all(color: onSurface.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(),
          const SizedBox(height: 8),
          if (saved.isEmpty)
            emptyState
          else
            Expanded(
              child: filtered.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'No saved backends match your search.',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return FutureBuilder<Uri?>(
                          future: _pingBackend(entry.host, entry.port),
                          builder: (context, snapshot) {
                            final checking =
                                snapshot.connectionState ==
                                ConnectionState.waiting;
                            final online = snapshot.data != null;

                            final statusColor = checking
                                ? onSurface.withValues(alpha: 0.35)
                                : online
                                ? const Color(0xFF16C47F)
                                : const Color(0xFFDC3545);
                            final statusTooltip = checking
                                ? 'Checking...'
                                : online
                                ? 'Online'
                                : 'Offline';

                            return Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  if (!online) {
                                    _toast('Backend is offline');
                                    return;
                                  }
                                  setState(() {
                                    _settings = _settings.copyWith(
                                      backendConnectionType:
                                          BackendConnectionType.remote,
                                      backendHost: entry.host,
                                      backendPort: entry.port,
                                    );
                                    _backendHostController.text = entry.host;
                                    _backendPortController.text = entry.port
                                        .toString();
                                  });
                                  await _saveSettings(
                                    toast: false,
                                    applyControllers: false,
                                  );
                                  await _refreshRuntime(force: true);
                                  if (mounted) {
                                    _toast(
                                      'Connected to ${entry.host}:${entry.port}',
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: onSurface.withValues(alpha: 0.04),
                                    border: Border.all(
                                      color: onSurface.withValues(alpha: 0.10),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Tooltip(
                                        message: statusTooltip,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: onSurface.withValues(
                                                  alpha: 0.92,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${entry.host}:${entry.port}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: onSurface.withValues(
                                                  alpha: 0.72,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _versionCardAction(
                                        icon: Icons.edit_rounded,
                                        tooltip: 'Edit backend',
                                        onTap: () =>
                                            unawaited(_editSavedBackend(entry)),
                                      ),
                                      const SizedBox(width: 6),
                                      _versionCardAction(
                                        icon: Icons.delete_outline_rounded,
                                        tooltip: 'Delete backend',
                                        onTap: () => unawaited(
                                          _removeSavedBackend(entry),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _backendSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    double trailingWidth = 240,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: onSurface.withValues(alpha: 0.045),
        border: Border.all(color: onSurface.withValues(alpha: 0.10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.78),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: textTheme.bodyMedium?.copyWith(
                              color: onSurface.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: trailing),
              ],
            );
          }

          return Row(
            children: [
              Icon(icon, size: 18, color: onSurface.withValues(alpha: 0.78)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(width: trailingWidth, child: trailing),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _backendFieldDecoration({String? hintText}) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.45)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.secondary,
          width: 1.2,
        ),
      ),
      filled: true,
      fillColor: onSurface.withValues(alpha: 0.06),
    );
  }

  Widget _dataPathPicker({
    required TextEditingController controller,
    required String placeholder,
    required ValueChanged<String> onChanged,
    required VoidCallback onPick,
    required VoidCallback onReset,
    String? updateWarningMessage,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rawPath = controller.text.trim();
    final hasValue = rawPath.isNotEmpty;
    final display = hasValue ? controller.text : placeholder;
    final lowerPath = rawPath.toLowerCase();

    bool exists = false;
    if (hasValue) {
      try {
        exists = File(rawPath).existsSync();
      } catch (_) {
        exists = false;
      }
    }

    final looksLikeDll = hasValue ? lowerPath.endsWith('.dll') : true;
    final showMissing = hasValue && looksLikeDll && !exists;
    final showTypeWarning = hasValue && !looksLikeDll;

    Widget? statusIcon;
    if (showMissing) {
      statusIcon = Tooltip(
        message: 'File missing',
        child: Icon(
          Icons.error_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (showTypeWarning) {
      statusIcon = Tooltip(
        message: 'Not a DLL',
        child: Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: const Color(0xFFE7A008),
        ),
      );
    } else if (updateWarningMessage != null &&
        updateWarningMessage.isNotEmpty) {
      statusIcon = Tooltip(
        message: updateWarningMessage,
        child: Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: const Color(0xFFE7A008),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: display,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: _backendFieldDecoration(hintText: placeholder),
              style: TextStyle(color: onSurface.withValues(alpha: 0.9)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (statusIcon != null) ...[statusIcon, const SizedBox(width: 8)],
        IconButton(
          onPressed: onPick,
          tooltip: 'Choose file',
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(42, 42),
            backgroundColor: onSurface.withValues(alpha: 0.06),
            foregroundColor: onSurface.withValues(alpha: 0.9),
            side: BorderSide(color: onSurface.withValues(alpha: 0.18)),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: hasValue ? onReset : null,
          tooltip: 'Reset path',
          icon: const Icon(Icons.refresh_rounded, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(42, 42),
            backgroundColor: onSurface.withValues(alpha: 0.06),
            foregroundColor: onSurface.withValues(alpha: 0.9),
            side: BorderSide(color: onSurface.withValues(alpha: 0.18)),
          ),
        ),
      ],
    );
  }

  Widget _generalTab() {
    final username = _settings.username.trim().isEmpty
        ? 'Player'
        : _settings.username.trim();
    final rawProfileAuthValidationError = _profileAuthValidationError(
      useEmailPassword: _settings.profileUseEmailPasswordAuth,
      email: _profileAuthEmailController.text.trim(),
      password: _profileAuthPasswordController.text,
    );
    final profileAuthValidationError = _profileAuthValidationAttempted
        ? rawProfileAuthValidationError
        : null;
    final sectionTitleStyle = Theme.of(context).textTheme.titleLarge;

    Widget body;
    switch (_settingsSection) {
      case SettingsSection.profile:
        body = _glass(
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile', style: sectionTitleStyle),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactProfile = constraints.maxWidth < 620;
                    final avatarSize = compactProfile ? 96.0 : 112.0;
                    final nameStyle = TextStyle(
                      fontSize: compactProfile ? 42 : 48,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    );

                    final avatar = ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image(
                        image: _profileImage(),
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                      ),
                    );

                    Widget buildAuthSwitchButton() {
                      return _tipPulseGlowIf(
                        Tooltip(
                          message: 'Switch Login Authentication',
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 40,
                                height: 40,
                              ),
                              onPressed: () {
                                var forcedRemote = false;
                                final shouldCompleteQuickTip =
                                    _showProfileAuthQuickTip;
                                setState(() {
                                  final nextAuthMode =
                                      !_settings.profileUseEmailPasswordAuth;
                                  _settings = _settings.copyWith(
                                    profileUseEmailPasswordAuth: nextAuthMode,
                                  );
                                  if (nextAuthMode) {
                                    forcedRemote =
                                        _forceRemoteBackendForEmailPasswordAuth();
                                  }
                                  if (!nextAuthMode) {
                                    _showProfileAuthPassword = false;
                                  }
                                  _profileAuthValidationAttempted = false;
                                });
                                if (forcedRemote && mounted) {
                                  _toast(
                                    'Email/password auth requires Remote backend. Switched to Remote.',
                                  );
                                }
                                if (shouldCompleteQuickTip) {
                                  _completeProfileAuthQuickTip();
                                }
                              },
                              icon: Icon(
                                _settings.profileUseEmailPasswordAuth
                                    ? Icons.alternate_email_rounded
                                    : Icons.person_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        enabled: _showProfileAuthQuickTip,
                      );
                    }

                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                username,
                                style: nameStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_showProfileAuthQuickTip) ...[
                          _profileAuthQuickTipCard(),
                          const SizedBox(height: 10),
                        ],
                        if (_settings.profileUseEmailPasswordAuth) ...[
                          _input(
                            label: 'Email',
                            controller: _profileAuthEmailController,
                            hint: 'name@example.com',
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(() {}),
                            suffix: buildAuthSwitchButton(),
                          ),
                          const SizedBox(height: 8),
                          _input(
                            label: 'Password',
                            controller: _profileAuthPasswordController,
                            hint: 'Set password',
                            obscureText: !_showProfileAuthPassword,
                            onChanged: (_) => setState(() {}),
                            suffix: IconButton(
                              tooltip: _showProfileAuthPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed:
                                  _profileAuthPasswordController.text.isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        _showProfileAuthPassword =
                                            !_showProfileAuthPassword;
                                      });
                                    },
                              icon: Icon(
                                _showProfileAuthPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          if (profileAuthValidationError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              profileAuthValidationError,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ] else ...[
                          _input(
                            label: 'Username',
                            controller: _usernameController,
                            hint: 'Set username',
                            onChanged: (_) => setState(() {}),
                            suffix: buildAuthSwitchButton(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Default login: ${_buildRebootLoginUsername(_usernameController.text)}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickAvatar,
                              icon: const Icon(Icons.image_rounded),
                              label: const Text('Change PFP'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _settings.profileAvatarPath.isEmpty
                                  ? null
                                  : _clearAvatar,
                              icon: const Icon(Icons.restore_rounded),
                              label: const Text('Default'),
                            ),
                            FilledButton.icon(
                              onPressed: _saveProfileSettings,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    );

                    if (compactProfile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [avatar, const SizedBox(height: 14), details],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 18),
                        Expanded(child: details),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      case SettingsSection.appearance:
        body = _glass(
          radius: 24,
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _settings.darkModeEnabled,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(darkModeEnabled: value);
                    });
                    widget.onDarkModeChanged(value);
                    unawaited(_saveSettings(toast: false));
                  },
                  title: const Text('Dark mode'),
                  subtitle: const Text('Toggle between dark and light themes.'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _settings.popupBackgroundBlurEnabled,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(
                        popupBackgroundBlurEnabled: value,
                      );
                    });
                    unawaited(_saveSettings(toast: false));
                  },
                  title: const Text('Popup background blur'),
                  subtitle: const Text('Blur the background behind popups.'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _settings.startupAnimationEnabled,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(
                        startupAnimationEnabled: value,
                      );
                    });
                    unawaited(_saveSettings(toast: false));
                  },
                  title: const Text('Startup animation'),
                  subtitle: const Text(
                    'Play the intro animation when ATLAS launches.',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background image'),
                  subtitle: Text(
                    _settings.backgroundImagePath.isEmpty
                        ? 'Default background'
                        : _settings.backgroundImagePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _settings.backgroundImagePath.isEmpty
                            ? null
                            : _clearBackground,
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _pickBackground,
                        child: const Text('Choose image'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Background blur (${_settings.backgroundBlur.toStringAsFixed(0)})',
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const min = 0.0;
                    const max = 30.0;
                    const defaultBlur = 15.0;
                    final trackWidth = constraints.maxWidth;
                    final normalized = (defaultBlur - min) / (max - min);
                    final dotX = trackWidth * normalized;
                    return SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Slider(
                            value: _settings.backgroundBlur,
                            min: min,
                            max: max,
                            divisions: 30,
                            onChanged: (value) {
                              setState(
                                () => _settings = _settings.copyWith(
                                  backgroundBlur: value,
                                ),
                              );
                            },
                            onChangeEnd: (_) =>
                                unawaited(_saveSettings(toast: false)),
                          ),
                          Positioned(
                            left: dotX - 4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Background particles (${(_settings.backgroundParticlesOpacity * 100).round()}%)',
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const min = 0.0;
                    const max = 2.0;
                    const defaultOpacity = 1.0;
                    final trackWidth = constraints.maxWidth;
                    final normalized = (defaultOpacity - min) / (max - min);
                    final dotX = trackWidth * normalized;
                    return SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Slider(
                            value: _settings.backgroundParticlesOpacity,
                            min: min,
                            max: max,
                            divisions: 20,
                            label:
                                '${(_settings.backgroundParticlesOpacity * 100).round()}%',
                            onChanged: (value) {
                              setState(
                                () => _settings = _settings.copyWith(
                                  backgroundParticlesOpacity: value,
                                ),
                              );
                            },
                            onChangeEnd: (_) =>
                                unawaited(_saveSettings(toast: false)),
                          ),
                          Positioned(
                            left: dotX - 4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      case SettingsSection.dataManagement:
        body = _glass(
          radius: 24,
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader = constraints.maxWidth < 900;
                    if (compactHeader) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Data Management', style: sectionTitleStyle),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _openInternalFiles,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E88E5),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 11,
                                  ),
                                ),
                                icon: const Icon(Icons.folder_rounded),
                                label: const Text('View Internal Files'),
                              ),
                              FilledButton.icon(
                                onPressed: _updatingDefaultDlls
                                    ? null
                                    : _updateAllDefaultDlls,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 11,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.system_update_alt_rounded,
                                ),
                                label: Text(
                                  _updatingDefaultDlls
                                      ? 'Updating defaults...'
                                      : 'Update Default DLLs',
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _resetLauncher,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB3261E),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 11,
                                  ),
                                ),
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Reset Launcher'),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Data Management',
                            style: sectionTitleStyle,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _openInternalFiles,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                          ),
                          icon: const Icon(Icons.folder_rounded),
                          label: const Text('View Internal Files'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _updatingDefaultDlls
                              ? null
                              : _updateAllDefaultDlls,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                          ),
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: Text(
                            _updatingDefaultDlls
                                ? 'Updating defaults...'
                                : 'Update Default DLLs',
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _resetLauncher,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB3261E),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Reset Launcher'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (_bundledDllDefaultsUpdateAvailable) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD93025).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD93025).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      '${_bundledDllUpdatedFileNames.length} default DLL update(s) available on GitHub. Use each row\'s reset button to apply latest.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _onSurface(context, 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_hasMissingConfiguredDllPaths) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD93025).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD93025).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'One or more configured DLL paths are missing. Use Update Default DLLs or each row\'s reset button.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _onSurface(context, 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _backendSettingTile(
                  icon: Icons.description_outlined,
                  title: 'Unreal Engine Patcher',
                  subtitle: 'Unlocks the Unreal Engine Console',
                  trailingWidth: 500,
                  trailing: _dataPathPicker(
                    controller: _unrealEnginePatcherController,
                    placeholder: 'No file selected',
                    updateWarningMessage: _dllRowUpdateWarningMessage(
                      'console.dll',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          unrealEnginePatcherPath: value.trim(),
                        );
                      });
                      unawaited(_saveSettings(toast: false));
                    },
                    onPick: _pickUnrealEnginePatcher,
                    onReset: _clearUnrealEnginePatcher,
                  ),
                ),
                const SizedBox(height: 8),
                _backendSettingTile(
                  icon: Icons.description_outlined,
                  title: 'Authentication Patcher',
                  subtitle: 'Redirects all HTTP requests to the backend',
                  trailingWidth: 500,
                  trailing: _dataPathPicker(
                    controller: _authenticationPatcherController,
                    placeholder: 'No file selected',
                    updateWarningMessage: _dllRowUpdateWarningMessage(
                      'tellurium.dll',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          authenticationPatcherPath: value.trim(),
                        );
                      });
                      unawaited(_saveSettings(toast: false));
                    },
                    onPick: _pickAuthenticationPatcher,
                    onReset: _clearAuthenticationPatcher,
                  ),
                ),
                const SizedBox(height: 8),
                _backendSettingTile(
                  icon: Icons.description_outlined,
                  title: 'Memory Patcher',
                  subtitle:
                      'Prevents the client from crashing because of a memory leak',
                  trailingWidth: 500,
                  trailing: _dataPathPicker(
                    controller: _memoryPatcherController,
                    placeholder: 'No file selected',
                    updateWarningMessage: _dllRowUpdateWarningMessage(
                      'memory.dll',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          memoryPatcherPath: value.trim(),
                        );
                      });
                      unawaited(_saveSettings(toast: false));
                    },
                    onPick: _pickMemoryPatcher,
                    onReset: _clearMemoryPatcher,
                  ),
                ),
                const SizedBox(height: 8),
                _backendSettingTile(
                  icon: Icons.description_outlined,
                  title: 'Game Server',
                  subtitle: 'The file injected to create the game server',
                  trailingWidth: 500,
                  trailing: _dataPathPicker(
                    controller: _gameServerFileController,
                    placeholder: 'No file selected',
                    updateWarningMessage: _dllRowUpdateWarningMessage(
                      'magnesium.dll',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          gameServerFilePath: value.trim(),
                        );
                      });
                      unawaited(_saveSettings(toast: false));
                    },
                    onPick: _pickGameServerFile,
                    onReset: _clearGameServerFile,
                  ),
                ),
                const SizedBox(height: 8),
                _backendSettingTile(
                  icon: Icons.description_outlined,
                  title: 'Large Pak Patcher',
                  subtitle:
                      'Injected after the game server to support large pak files',
                  trailingWidth: 500,
                  trailing: _dataPathPicker(
                    controller: _largePakPatcherController,
                    placeholder: 'No file selected',
                    updateWarningMessage: _dllRowUpdateWarningMessage(
                      'largepakpatch.dll',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          largePakPatcherFilePath: value.trim(),
                        );
                      });
                      unawaited(_saveSettings(toast: false));
                    },
                    onPick: _pickLargePakPatcherFile,
                    onReset: _clearLargePakPatcherFile,
                  ),
                ),
              ],
            ),
          ),
        );
      case SettingsSection.support:
        body = _glass(
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Support', style: sectionTitleStyle),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _showLatestLauncherUpdateNotes,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Update notes'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openUrl('https://discord.gg'),
                  icon: const Icon(Icons.discord_rounded),
                  label: const Text('Open Discord'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openLogs,
                  icon: const Icon(Icons.article_rounded),
                  label: const Text('Open Launcher Logs'),
                ),
              ],
            ),
          ),
        );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1180;
        if (compact) {
          return ListView(
            children: [
              _menuItemEntrance(
                menuKey: LauncherTab.general,
                index: 0,
                child: _settingsSidebar(compact: true),
              ),
              const SizedBox(height: 12),
              _menuItemEntrance(
                menuKey: LauncherTab.general,
                index: 1,
                child: _animatedSwap(
                  switchKey: _settingsSection,
                  duration: const Duration(milliseconds: 220),
                  child: body,
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _menuItemEntrance(
              menuKey: LauncherTab.general,
              index: 0,
              child: SizedBox(
                width: 300,
                child: _settingsSidebar(compact: false),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _menuItemEntrance(
                menuKey: LauncherTab.general,
                index: 1,
                child: _animatedSwap(
                  switchKey: _settingsSection,
                  duration: const Duration(milliseconds: 220),
                  expand: true,
                  child: body,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _animatedSwap({
    required Object switchKey,
    required Widget child,
    Offset slideBegin = Offset.zero,
    Duration duration = const Duration(milliseconds: 240),
    bool expand = false,
    AlignmentGeometry layoutAlignment = Alignment.center,
  }) {
    final keyed = KeyedSubtree(key: ValueKey(switchKey), child: child);
    if (MediaQuery.of(context).disableAnimations) return keyed;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: expand ? StackFit.expand : StackFit.loose,
          alignment: layoutAlignment,
          children: [
            ...previousChildren,
            ...?(currentChild == null ? null : [currentChild]),
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: slideBegin,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: keyed,
    );
  }

  Widget _menuItemEntrance({
    required Object menuKey,
    required int index,
    required Widget child,
  }) {
    if (MediaQuery.of(context).disableAnimations) return child;

    final delay = (0.08 * index).clamp(0.0, 0.42);
    final curve = Interval(delay, 1.0, curve: Curves.easeOutCubic);
    return TweenAnimationBuilder<double>(
      key: ValueKey('menu-$menuKey-$index'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: curve,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _settingsSidebar({required bool compact}) {
    final dark = _isDarkTheme(context);
    final selectedColor = dark
        ? Colors.white.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14);

    Widget tile({
      required SettingsSection section,
      required IconData icon,
      required String title,
    }) {
      final selected = _settingsSection == section;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _settingsSection = section);
            _syncLibraryActionsNudgePulse();
            _syncLauncherDiscordPresence();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected ? selectedColor : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: _onSurface(context, selected ? 1.0 : 0.66),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      color: _onSurface(context, selected ? 1.0 : 0.82),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _glass(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          children: [
            tile(
              section: SettingsSection.profile,
              icon: Icons.person_rounded,
              title: 'Profile',
            ),
            tile(
              section: SettingsSection.appearance,
              icon: Icons.palette_rounded,
              title: 'Appearance',
            ),
            tile(
              section: SettingsSection.dataManagement,
              icon: Icons.storage_rounded,
              title: 'Data Management',
            ),
            tile(
              section: SettingsSection.support,
              icon: Icons.help_rounded,
              title: 'Support',
            ),
            const SizedBox(height: 10),
            if (!compact)
              Container(height: 1, color: _onSurface(context, 0.12)),
            const SizedBox(height: 12),
            if (!compact)
              OutlinedButton.icon(
                onPressed: () => unawaited(_switchMenu(_settingsReturnTab)),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Back'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child, double radius = 28}) {
    final panelProgress = CurvedAnimation(
      parent: _shellEntranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: _shellEntranceController,
      builder: (context, panelChild) {
        final t = panelProgress.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: Transform.scale(scale: 0.97 + (0.03 * t), child: panelChild),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: _glassSurfaceColor(context),
              border: Border.all(color: _onSurface(context, 0.08)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    Widget? suffix,
    bool obscureText = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.94),
          ),
          cursorColor: Theme.of(context).colorScheme.secondary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            suffixIconConstraints: suffix == null
                ? null
                : const BoxConstraints.tightFor(width: 40, height: 40),
            suffixIcon: suffix,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Future<String?> _resolveExecutable(VersionEntry version) async {
    if (version.executablePath.isNotEmpty &&
        File(version.executablePath).existsSync()) {
      return version.executablePath;
    }

    final root = Directory(version.location);
    if (!root.existsSync()) return null;

    final found = await _findRecursive(version.location, _shippingExeName);
    if (found == null) return null;
    setState(() {
      _settings = _settings.copyWith(
        versions: _settings.versions
            .map(
              (entry) => entry.id == version.id
                  ? entry.copyWith(executablePath: found)
                  : entry,
            )
            .toList(),
      );
    });
    await _saveSettings(toast: false);
    return found;
  }

  Future<String?> _findRecursive(String rootPath, String fileName) async {
    // Avoid janking the UI isolate when scanning large build folders.
    return Isolate.run(() async {
      final root = Directory(rootPath);
      if (!root.existsSync()) return null;

      String basename(String path) {
        final normalized = path
            .replaceAll('\\', '/')
            .replaceAll(RegExp(r'/+$'), '');
        final parts = normalized.split('/');
        if (parts.isEmpty) return normalized;
        return parts.last;
      }

      final queue = <Directory>[root];
      final target = fileName.toLowerCase();

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        try {
          await for (final entity in current.list(followLinks: false)) {
            if (entity is File &&
                basename(entity.path).toLowerCase() == target) {
              return entity.path;
            }
            if (entity is Directory) {
              queue.add(entity);
            }
          }
        } catch (_) {
          // Skip unreadable folders.
        }
      }
      return null;
    });
  }

  String _deriveVersion(String path) {
    final match = RegExp(
      r'(\d+\.\d+(?:\.\d+)?)',
    ).firstMatch(path.replaceAll('\\', '/'));
    return match?.group(1) ?? 'Unknown';
  }

  String _basename(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final parts = normalized.split('/');
    if (parts.isEmpty) return normalized;
    return parts.last;
  }

  String _joinPath(List<String> pieces) {
    final separator = Platform.pathSeparator;
    final items = pieces.where((piece) => piece.trim().isNotEmpty).toList();
    if (items.isEmpty) return '';
    var output = items.first;
    for (var index = 1; index < items.length; index++) {
      var next = items[index];
      output = output.replaceAll(RegExp(r'[\\/]+$'), '');
      next = next.replaceAll(RegExp(r'^[\\/]+'), '');
      output = '$output$separator$next';
    }
    return output;
  }
}

class _AtlasStartupAnimationOverlay extends StatefulWidget {
  const _AtlasStartupAnimationOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_AtlasStartupAnimationOverlay> createState() =>
      _AtlasStartupAnimationOverlayState();
}

class _AtlasStartupAnimationOverlayState
    extends State<_AtlasStartupAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _overlayOpacity;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoOffsetY;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textOffsetY;
  late final Animation<double> _textBlur;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _overlayOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 90),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 10,
      ),
    ]).animate(_controller);

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.35, curve: Curves.easeOutCubic),
    );

    _logoOffsetY = Tween<double>(begin: -140.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.6, curve: Curves.easeOut),
    );

    _textOffsetY = Tween<double>(begin: 48.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _textBlur = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final textStyle = TextStyle(
      fontSize: 54,
      height: 1.0,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: dark
          ? Colors.white.withValues(alpha: 0.95)
          : _onSurface(context, 0.96),
      fontFamily: 'Coolvetica',
      fontFamilyFallback: const ['Segoe UI', 'Arial', 'Roboto'],
      shadows: [
        Shadow(
          color: dark
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Positioned.fill(
      child: AbsorbPointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: _overlayOpacity.value,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.22,
                                lightAlpha: 0.08,
                              ),
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.34,
                                lightAlpha: 0.12,
                              ),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: Offset(0, _logoOffsetY.value),
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: Image.asset(
                                'assets/images/atlas_logo.png',
                                width: 180,
                                height: 180,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Transform.translate(
                            offset: Offset(0, _textOffsetY.value),
                            child: Opacity(
                              opacity: _textOpacity.value,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: _textBlur.value,
                                  sigmaY: _textBlur.value,
                                ),
                                child: Text(
                                  'Welcome to ATLAS',
                                  textAlign: TextAlign.center,
                                  style: textStyle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AtlasParticleField extends StatefulWidget {
  const _AtlasParticleField({required this.opacity});

  final double opacity;

  @override
  State<_AtlasParticleField> createState() => _AtlasParticleFieldState();
}

class _AtlasParticleFieldState extends State<_AtlasParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_AtlasParticle> _particles;
  int _particleCount = 0;

  double _effectiveOpacityMultiplier(double intensity) {
    final x = intensity.clamp(0.0, 2.0).toDouble();
    // Calibrated to backend feel:
    // 0% -> 0.0, 100% -> 1.0, 200% -> 2.6 (stronger high-end response).
    final curved = (0.30 * x * x) + (0.70 * x);
    return curved.clamp(0.0, 2.6);
  }

  int _desiredParticleCount(double intensity) {
    final clamped = intensity.clamp(0.0, 2.0).toDouble();
    // Keep density scaling true to slider semantics: 200% = 2x 100%.
    const baseCount = 190; // 100% => 190 particles
    final count = (baseCount * clamped).round();
    return count.clamp(0, 380);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _particleCount = _desiredParticleCount(widget.opacity);
    _particles = _AtlasParticle.generate(seed: 90210, count: _particleCount);
  }

  @override
  void didUpdateWidget(covariant _AtlasParticleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextCount = _desiredParticleCount(widget.opacity);
    if (nextCount != _particleCount) {
      _particleCount = nextCount;
      _particles = _AtlasParticle.generate(seed: 90210, count: _particleCount);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AtlasParticlePainter(
          controller: _controller,
          particles: _particles,
          color: Colors.white,
          // Match backend behavior closer at the high end (150%-200%).
          opacity: _effectiveOpacityMultiplier(widget.opacity),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AtlasParticle {
  const _AtlasParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.alpha,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.glow,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double radius;
  final double alpha;
  final double twinkleSpeed;
  final double twinklePhase;
  final bool glow;

  static List<_AtlasParticle> generate({
    required int seed,
    required int count,
  }) {
    final rng = Random(seed);

    double nextDoubleRange(double min, double max) =>
        min + (max - min) * rng.nextDouble();

    final particles = <_AtlasParticle>[];
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble();
      final y = rng.nextDouble();

      final sizeRoll = rng.nextDouble();
      final radius = sizeRoll < 0.12
          ? nextDoubleRange(1.8, 2.8)
          : nextDoubleRange(0.8, 1.8);
      final baseAlpha = sizeRoll < 0.12
          ? nextDoubleRange(0.08, 0.16)
          : nextDoubleRange(0.04, 0.12);

      final speed = nextDoubleRange(0.002, 0.012) * (radius / 2.0);
      final angle = nextDoubleRange(0, pi * 2);
      final vx = cos(angle) * speed;
      final vy = sin(angle) * speed;

      final twinkleSpeed = nextDoubleRange(0.6, 1.6);
      final twinklePhase = nextDoubleRange(0, pi * 2);

      particles.add(
        _AtlasParticle(
          x: x,
          y: y,
          vx: vx,
          vy: vy,
          radius: radius,
          alpha: baseAlpha,
          twinkleSpeed: twinkleSpeed,
          twinklePhase: twinklePhase,
          glow: sizeRoll < 0.08,
        ),
      );
    }
    return particles;
  }
}

class _AtlasParticlePainter extends CustomPainter {
  _AtlasParticlePainter({
    required this.controller,
    required this.particles,
    required this.color,
    required this.opacity,
  }) : super(repaint: controller);

  final AnimationController controller;
  final List<_AtlasParticle> particles;
  final Color color;
  final double opacity;

  final Paint _paint = Paint()..isAntiAlias = true;
  final Paint _glowPaint = Paint()
    ..isAntiAlias = true
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (controller.lastElapsedDuration?.inMilliseconds ?? 0) / 1000.0;

    for (final p in particles) {
      final px = ((p.x + p.vx * t) % 1.0) * size.width;
      final py = ((p.y + p.vy * t) % 1.0) * size.height;
      final twinkle = 0.65 + 0.35 * sin(p.twinklePhase + t * p.twinkleSpeed);
      final a = (p.alpha * twinkle * opacity).clamp(0.0, 1.0);

      if (p.glow) {
        _glowPaint.color = color.withValues(alpha: a * 0.6);
        canvas.drawCircle(Offset(px, py), p.radius + 1.4, _glowPaint);
      }

      _paint.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(px, py), p.radius, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasParticlePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.particles != particles;
  }
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({required this.child, this.scale = 1.05});

  final Widget child;
  final double scale;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _SliverEntrance extends SingleChildRenderObjectWidget {
  const _SliverEntrance({
    required this.t,
    required super.child,
    this.translateY = 12,
  });

  final double t;
  final double translateY;

  @override
  RenderSliverEntrance createRenderObject(BuildContext context) {
    return RenderSliverEntrance(t: t, translateY: translateY);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverEntrance renderObject,
  ) {
    renderObject
      ..t = t
      ..translateY = translateY;
  }
}

class RenderSliverEntrance extends RenderProxySliver {
  RenderSliverEntrance({
    required double t,
    required double translateY,
    RenderSliver? child,
  }) : _t = t,
       _translateY = translateY,
       super(child);

  double _t;
  double _translateY;

  double get t => _t;
  set t(double value) {
    if (_t == value) return;
    _t = value;
    markNeedsPaint();
  }

  double get translateY => _translateY;
  set translateY(double value) {
    if (_translateY == value) return;
    _translateY = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sliver = child;
    final geom = geometry;
    if (sliver == null || geom == null || geom.paintExtent <= 0) return;

    final clamped = _t.clamp(0.0, 1.0).toDouble();
    final alpha = (clamped * 255).round().clamp(0, 255);
    if (alpha == 0) return;

    context.pushOpacity(offset, alpha, (context, offset) {
      final dy = (1 - clamped) * _translateY;
      if (dy.abs() < 0.01) {
        context.paintChild(sliver, offset);
        return;
      }
      context.pushTransform(
        needsCompositing,
        offset,
        Matrix4.translationValues(0, dy, 0),
        (context, offset) => context.paintChild(sliver, offset),
      );
    });
  }
}

class _SliverGlass extends SingleChildRenderObjectWidget {
  const _SliverGlass({
    required this.radius,
    required this.blurSigma,
    required this.backgroundColor,
    required this.borderColor,
    this.borderWidth = 1.0,
    required super.child,
  });

  final double radius;
  final double blurSigma;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;

  @override
  RenderSliverGlass createRenderObject(BuildContext context) {
    return RenderSliverGlass(
      radius: radius,
      blurSigma: blurSigma,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverGlass renderObject,
  ) {
    renderObject
      ..radius = radius
      ..blurSigma = blurSigma
      ..backgroundColor = backgroundColor
      ..borderColor = borderColor
      ..borderWidth = borderWidth;
  }
}

class RenderSliverGlass extends RenderProxySliver {
  RenderSliverGlass({
    required double radius,
    required double blurSigma,
    required Color backgroundColor,
    required Color borderColor,
    required double borderWidth,
    RenderSliver? child,
  }) : _radius = radius,
       _blurSigma = blurSigma,
       _backgroundColor = backgroundColor,
       _borderColor = borderColor,
       _borderWidth = borderWidth,
       super(child);

  double _radius;
  double _blurSigma;
  Color _backgroundColor;
  Color _borderColor;
  double _borderWidth;

  double get radius => _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  double get blurSigma => _blurSigma;
  set blurSigma(double value) {
    if (_blurSigma == value) return;
    _blurSigma = value;
    markNeedsPaint();
  }

  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    markNeedsPaint();
  }

  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor == value) return;
    _borderColor = value;
    markNeedsPaint();
  }

  double get borderWidth => _borderWidth;
  set borderWidth(double value) {
    if (_borderWidth == value) return;
    _borderWidth = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sliver = child;
    final geom = geometry;
    if (sliver == null || geom == null || geom.paintExtent <= 0) return;

    final paintExtent = geom.paintExtent;
    final rect = offset & Size(constraints.crossAxisExtent, paintExtent);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_radius));

    void paintContents(PaintingContext context, Offset offset) {
      final localRect = offset & Size(constraints.crossAxisExtent, paintExtent);
      final localRRect = RRect.fromRectAndRadius(
        localRect,
        Radius.circular(_radius),
      );
      final canvas = context.canvas;

      final bgPaint = Paint()
        ..isAntiAlias = true
        ..color = _backgroundColor;
      canvas.drawRRect(localRRect, bgPaint);

      if (_borderWidth > 0) {
        final inset = _borderWidth / 2;
        final borderRect = localRect.deflate(inset);
        final borderRadius = (_radius - inset).clamp(0.0, double.infinity);
        final borderRRect = RRect.fromRectAndRadius(
          borderRect,
          Radius.circular(borderRadius),
        );
        final borderPaint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = _borderWidth
          ..color = _borderColor;
        canvas.drawRRect(borderRRect, borderPaint);
      }

      context.paintChild(sliver, offset);
    }

    context.pushClipRRect(needsCompositing, offset, rect, rrect, (
      context,
      offset,
    ) {
      if (_blurSigma <= 0.01) {
        paintContents(context, offset);
        return;
      }
      context.pushLayer(
        BackdropFilterLayer(
          filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          blendMode: BlendMode.srcOver,
        ),
        paintContents,
        offset,
      );
    });
  }
}

Color _onSurface(BuildContext context, double opacity) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: opacity);
}

bool _isDarkTheme(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Color _glassSurfaceColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  return Colors.white.withValues(alpha: dark ? 0.06 : 0.30);
}

Color _glassShadowColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  return Colors.black.withValues(alpha: dark ? 0.24 : 0.14);
}

Color _dialogSurfaceColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  if (dark) {
    return const Color(0xFF081225).withValues(alpha: 0.96);
  }
  return const Color(0xFFF6FAFF).withValues(alpha: 0.96);
}

Color _dialogShadowColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  return Colors.black.withValues(alpha: dark ? 0.40 : 0.18);
}

Color _dialogBarrierColor(BuildContext context, double transitionValue) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  final alpha = (dark ? 0.34 : 0.22) * transitionValue;
  return base.withValues(alpha: alpha);
}

Color _adaptiveScrimColor(
  BuildContext context, {
  required double darkAlpha,
  required double lightAlpha,
}) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  return base.withValues(alpha: dark ? darkAlpha : lightAlpha);
}

class _ToastOverlayHost extends StatefulWidget {
  const _ToastOverlayHost({super.key, required this.onEmpty});

  final VoidCallback onEmpty;

  @override
  State<_ToastOverlayHost> createState() => _ToastOverlayHostState();
}

class _ToastOverlayHostState extends State<_ToastOverlayHost> {
  static const _toastDuration = Duration(seconds: 3);
  final GlobalKey<_AnimatedToastCardState> _cardKey =
      GlobalKey<_AnimatedToastCardState>();
  Timer? _timer;
  String _message = '';
  bool _progressMode = false;
  double? _progress;
  bool _progressIndeterminate = false;

  void show(String message) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    _timer?.cancel();
    _message = trimmed;
    _progressMode = false;
    _progress = null;
    _progressIndeterminate = false;

    if (mounted) {
      setState(() {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardKey.currentState?.show(_message);
    });

    _timer = Timer(_toastDuration, () {
      if (!mounted) return;
      _cardKey.currentState?.dismiss();
    });
  }

  void showProgress(
    String message, {
    required double? progress,
    required bool indeterminate,
  }) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    _timer?.cancel();
    _message = trimmed;
    _progressMode = true;
    _progress = progress;
    _progressIndeterminate = indeterminate;

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardKey.currentState?.showProgress(
        _message,
        progress: _progress,
        indeterminate: _progressIndeterminate,
      );
    });
  }

  void dismissProgressSoon() {
    if (!mounted) return;
    if (!_progressMode) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      _cardKey.currentState?.dismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: _AnimatedToastCard(
        key: _cardKey,
        initialMessage: _message,
        onDismissed: widget.onEmpty,
      ),
    );
  }
}

class _AnimatedToastCard extends StatefulWidget {
  const _AnimatedToastCard({
    super.key,
    required this.initialMessage,
    required this.onDismissed,
  });

  final String initialMessage;
  final VoidCallback onDismissed;

  @override
  State<_AnimatedToastCard> createState() => _AnimatedToastCardState();
}

class _AnimatedToastCardState extends State<_AnimatedToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _dismissing = false;
  String _message = '';
  bool _showProgressBar = false;
  double? _progress;
  bool _progressIndeterminate = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    final reverseCurve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(reverseCurve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curve);
    _message = widget.initialMessage;
    if (_message.trim().isNotEmpty) {
      _controller.forward();
    }
  }

  void show(String message) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _message = trimmed;
      _showProgressBar = false;
      _progress = null;
      _progressIndeterminate = false;
    });

    final wasHidden = _controller.value <= 0.001;
    _dismissing = false;

    // If we're mid-dismiss and a new toast arrives, keep it visible without
    // re-running an entrance animation.
    _controller.stop();
    if (wasHidden) {
      _controller
        ..value = 0
        ..forward();
    } else {
      _controller.value = 1;
    }
  }

  void showProgress(
    String message, {
    required double? progress,
    required bool indeterminate,
  }) {
    if (!mounted) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _message = trimmed;
      _showProgressBar = true;
      _progress = progress;
      _progressIndeterminate = indeterminate;
    });

    final wasHidden = _controller.value <= 0.001;
    _dismissing = false;

    _controller.stop();
    if (wasHidden) {
      _controller
        ..value = 0
        ..forward();
    } else {
      _controller.value = 1;
    }
  }

  Future<void> dismiss() async {
    if (!mounted || _dismissing) return;
    _dismissing = true;
    try {
      // Reverse uses the same slide tween, so it slides back down.
      await _controller.reverse();
    } finally {
      if (mounted) widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = _onSurface(context, 0.92);
    final barColor = Theme.of(context).colorScheme.secondary;
    final barTrack = _onSurface(context, 0.10);
    const radius = 18.0;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(context),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _dialogSurfaceColor(context),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: _onSurface(context, 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        _message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (_showProgressBar)
                      SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: _progressIndeterminate ? null : _progress,
                          backgroundColor: barTrack,
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EventCardData {
  const _EventCardData({
    required this.image,
    required this.category,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonUrl,
    this.imageFit = BoxFit.contain,
  });

  final String image;
  final String category;
  final String title;
  final String description;
  final String buttonLabel;
  final String buttonUrl;
  final BoxFit imageFit;
}

class _BuildImportRequest {
  const _BuildImportRequest({
    required this.buildName,
    required this.buildRootPath,
  });

  final String buildName;
  final String buildRootPath;
}

class _SplashScanResult {
  const _SplashScanResult({
    required this.bestPath,
    required this.bestScore,
    required this.scannedDirectories,
  });

  final String? bestPath;
  final double bestScore;
  final int scannedDirectories;
}

class _DirectoryDepth {
  const _DirectoryDepth({required this.directory, required this.depth});

  final Directory directory;
  final int depth;
}

class _BackendInstallProgress {
  const _BackendInstallProgress({
    required this.message,
    required this.progress,
  });

  final String message;
  final double? progress;
}

class _BundledDllSpec {
  const _BundledDllSpec({
    required this.assetPath,
    required this.fileName,
    required this.label,
  });

  final String assetPath;
  final String fileName;
  final String label;

  String get fileNameLower => fileName.toLowerCase();

  String get normalizedAssetPath =>
      assetPath.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
}

class _BundledDllRemoteAsset {
  const _BundledDllRemoteAsset({required this.sha, required this.downloadUrl});

  final String sha;
  final String downloadUrl;
}

class LauncherReleaseInfo {
  const LauncherReleaseInfo({
    required this.version,
    required this.downloadUrl,
    this.notes,
  });

  final String version;
  final String downloadUrl;
  final String? notes;
}

class LauncherUpdateInfo {
  const LauncherUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.notes,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String? notes;
}

class LauncherUpdateService {
  static const String _repo = 'cipherfps/ATLAS-Link';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  static Future<LauncherUpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    final release = await fetchLatestReleaseWithNotes();
    if (release == null) return null;
    if (!_isNewerVersion(release.version, currentVersion)) return null;
    return LauncherUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: release.version,
      downloadUrl: release.downloadUrl,
      notes: release.notes,
    );
  }

  static Future<LauncherReleaseInfo?> fetchLatestReleaseWithNotes() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set('User-Agent', 'ATLAS-Link');
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;

      final tag = (json['tag_name'] ?? '').toString().trim();
      if (tag.isEmpty) return null;

      final assets = json['assets'];
      final htmlUrl = (json['html_url'] ?? '').toString().trim();
      final downloadUrl = _pickDownloadUrl(assets) ?? htmlUrl;
      if (downloadUrl.isEmpty) return null;

      return LauncherReleaseInfo(
        version: tag,
        downloadUrl: downloadUrl,
        notes: json['body']?.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String? _pickDownloadUrl(dynamic assets) {
    if (assets is! List) return null;
    String? installerExe;
    String? setupExe;
    String? appExe;
    String? installerMsi;
    String? appMsi;
    String? appZip;
    String? fallback;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final url = (asset['browser_download_url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      fallback ??= url;
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final isAtlasAsset = name.contains('atlas');
      if (!isAtlasAsset) continue;
      if (name.endsWith('.exe')) {
        if (name.contains('setup') || name.contains('installer')) {
          installerExe ??= url;
        } else if (name.contains('install')) {
          setupExe ??= url;
        } else {
          appExe ??= url;
        }
        continue;
      }
      if (name.endsWith('.msi')) {
        if (name.contains('setup') || name.contains('installer')) {
          installerMsi ??= url;
        } else {
          appMsi ??= url;
        }
        continue;
      }
      if (name.endsWith('.zip')) {
        appZip ??= url;
      }
    }
    return installerExe ??
        setupExe ??
        appExe ??
        installerMsi ??
        appMsi ??
        appZip ??
        fallback;
  }

  static bool _isNewerVersion(String latest, String current) {
    return _compareVersions(
          _normalizeVersion(latest),
          _normalizeVersion(current),
        ) >
        0;
  }

  static String _normalizeVersion(String value) {
    var normalized = value.trim();
    if (normalized.toLowerCase().startsWith('v')) {
      normalized = normalized.substring(1);
    }
    final plusIndex = normalized.indexOf('+');
    if (plusIndex >= 0) {
      normalized = normalized.substring(0, plusIndex);
    }
    return normalized;
  }

  static int _compareVersions(String left, String right) {
    final leftParts = left
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final rightParts = right
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final maxLength = max(leftParts.length, rightParts.length);
    for (var i = 0; i < maxLength; i++) {
      final a = i < leftParts.length ? leftParts[i] : 0;
      final b = i < rightParts.length ? rightParts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }
}

class LauncherUpdateNotesPayload {
  const LauncherUpdateNotesPayload({
    required this.version,
    required this.notes,
  });

  final String version;
  final String notes;
}

class LauncherUpdateNotesService {
  static Future<LauncherUpdateNotesPayload?> loadNotes() async {
    final file = _findNotesFile();
    if (file == null || !file.existsSync()) return null;
    final content = await file.readAsString();
    final parsed = _parse(content);
    if (parsed.notes.trim().isEmpty) return null;
    return parsed;
  }

  static File? _findNotesFile() {
    final candidates = <String>[];
    final cwd = Directory.current.path;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add(_joinPath([exeDir, 'update-notes.md']));
    candidates.add(_joinPath([exeDir, 'update-notes.txt']));
    candidates.add(_joinPath([exeDir, '..', 'update-notes.md']));
    candidates.add(_joinPath([exeDir, '..', 'update-notes.txt']));
    candidates.add(_joinPath([exeDir, '..', '..', 'update-notes.md']));
    candidates.add(_joinPath([exeDir, '..', '..', 'update-notes.txt']));

    candidates.add(_joinPath([cwd, 'update-notes.md']));
    candidates.add(_joinPath([cwd, 'update-notes.txt']));
    candidates.add(_joinPath([cwd, '..', 'update-notes.md']));
    candidates.add(_joinPath([cwd, '..', 'update-notes.txt']));

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      candidates.add(_joinPath([appData, 'ATLAS Link', 'update-notes.md']));
      candidates.add(_joinPath([appData, 'ATLAS Link', 'update-notes.txt']));
      // Legacy path (kept for backwards compatibility with older releases).
      candidates.add(
        _joinPath([appData, 'atlas-link-launcher', 'update-notes.md']),
      );
      candidates.add(
        _joinPath([appData, 'atlas-link-launcher', 'update-notes.txt']),
      );
    }

    final seen = <String>{};
    for (final path in candidates) {
      final normalized = _normalizePath(path);
      if (!seen.add(normalized)) continue;
      final file = File(path);
      if (file.existsSync()) return file;
    }
    return null;
  }

  static LauncherUpdateNotesPayload _parse(String content) {
    final versionMatch = RegExp(
      r'<!--\s*version\s*:\s*([^\s>]+)\s*-->',
      caseSensitive: false,
    ).firstMatch(content);
    final version = (versionMatch?.group(1) ?? '').trim();
    final notes = versionMatch == null
        ? content.trim()
        : content.replaceFirst(versionMatch.group(0) ?? '', '').trim();
    return LauncherUpdateNotesPayload(version: version, notes: notes);
  }

  static String _joinPath(List<String> pieces) {
    final separator = Platform.pathSeparator;
    final items = pieces.where((piece) => piece.trim().isNotEmpty).toList();
    if (items.isEmpty) return '';
    var output = items.first;
    for (var index = 1; index < items.length; index++) {
      var next = items[index];
      output = output.replaceAll(RegExp(r'[\\/]+$'), '');
      next = next.replaceAll(RegExp(r'^[\\/]+'), '');
      output = '$output$separator$next';
    }
    return output;
  }

  static String _normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }
}

class LauncherInstallState {
  const LauncherInstallState({
    required this.profileSetupComplete,
    required this.libraryActionsNudgeComplete,
    required this.backendConnectionTipComplete,
    required this.lastSeenLauncherVersion,
  });

  final bool profileSetupComplete;
  final bool libraryActionsNudgeComplete;
  final bool backendConnectionTipComplete;
  final String lastSeenLauncherVersion;

  LauncherInstallState copyWith({
    bool? profileSetupComplete,
    bool? libraryActionsNudgeComplete,
    bool? backendConnectionTipComplete,
    String? lastSeenLauncherVersion,
  }) {
    return LauncherInstallState(
      profileSetupComplete: profileSetupComplete ?? this.profileSetupComplete,
      libraryActionsNudgeComplete:
          libraryActionsNudgeComplete ?? this.libraryActionsNudgeComplete,
      backendConnectionTipComplete:
          backendConnectionTipComplete ?? this.backendConnectionTipComplete,
      lastSeenLauncherVersion:
          lastSeenLauncherVersion ?? this.lastSeenLauncherVersion,
    );
  }

  static LauncherInstallState defaults() {
    return const LauncherInstallState(
      profileSetupComplete: false,
      libraryActionsNudgeComplete: false,
      backendConnectionTipComplete: false,
      lastSeenLauncherVersion: '',
    );
  }

  factory LauncherInstallState.fromJson(Map<String, dynamic> json) {
    bool asBool(dynamic value, bool fallback) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lowered = value.toLowerCase();
        if (lowered == 'true' || lowered == '1') return true;
        if (lowered == 'false' || lowered == '0') return false;
      }
      return fallback;
    }

    String asString(dynamic value, String fallback) {
      if (value == null) return fallback;
      if (value is String) return value;
      return value.toString();
    }

    return LauncherInstallState(
      profileSetupComplete: asBool(
        json['profileSetupComplete'] ?? json['ProfileSetupComplete'],
        false,
      ),
      libraryActionsNudgeComplete: asBool(
        json['libraryActionsNudgeComplete'] ??
            json['LibraryActionsNudgeComplete'],
        false,
      ),
      backendConnectionTipComplete: asBool(
        json['backendConnectionTipComplete'] ??
            json['BackendConnectionTipComplete'],
        true,
      ),
      lastSeenLauncherVersion: asString(
        json['lastSeenLauncherVersion'] ?? json['LastSeenLauncherVersion'],
        '',
      ).trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profileSetupComplete': profileSetupComplete,
      'libraryActionsNudgeComplete': libraryActionsNudgeComplete,
      'backendConnectionTipComplete': backendConnectionTipComplete,
      'lastSeenLauncherVersion': lastSeenLauncherVersion,
    };
  }
}

class LauncherSettings {
  const LauncherSettings({
    required this.username,
    required this.profileUseEmailPasswordAuth,
    required this.profileAuthEmail,
    required this.profileAuthPassword,
    required this.profileAuthQuickTipComplete,
    required this.profileAvatarPath,
    required this.profileSetupComplete,
    required this.libraryActionsNudgeComplete,
    required this.backendConnectionTipComplete,
    required this.darkModeEnabled,
    required this.popupBackgroundBlurEnabled,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.backgroundParticlesOpacity,
    required this.startupAnimationEnabled,
    required this.backendWorkingDirectory,
    required this.backendStartCommand,
    required this.backendConnectionType,
    required this.backendHost,
    required this.backendPort,
    required this.launchBackendOnSessionStart,
    required this.largePakPatcherEnabled,
    required this.hostUsername,
    required this.playCustomLaunchArgs,
    required this.hostCustomLaunchArgs,
    required this.allowMultipleGameClients,
    required this.hostHeadlessEnabled,
    required this.hostAutoRestartEnabled,
    required this.deleteAftermathOnLaunch,
    required this.hostPort,
    required this.unrealEnginePatcherPath,
    required this.authenticationPatcherPath,
    required this.memoryPatcherPath,
    required this.gameServerInjectType,
    required this.gameServerFilePath,
    required this.largePakPatcherFilePath,
    required this.savedBackends,
    required this.savedBackendsByProfile,
    required this.versions,
    required this.selectedVersionId,
  });

  final String username;
  final bool profileUseEmailPasswordAuth;
  final String profileAuthEmail;
  final String profileAuthPassword;
  final bool profileAuthQuickTipComplete;
  final String profileAvatarPath;
  final bool profileSetupComplete;
  final bool libraryActionsNudgeComplete;
  final bool backendConnectionTipComplete;
  final bool darkModeEnabled;
  final bool popupBackgroundBlurEnabled;
  final String backgroundImagePath;
  final double backgroundBlur;
  final double backgroundParticlesOpacity;
  final bool startupAnimationEnabled;
  final String backendWorkingDirectory;
  final String backendStartCommand;
  final BackendConnectionType backendConnectionType;
  final String backendHost;
  final int backendPort;
  final bool launchBackendOnSessionStart;
  final bool largePakPatcherEnabled;
  final String hostUsername;
  final String playCustomLaunchArgs;
  final String hostCustomLaunchArgs;
  final bool allowMultipleGameClients;
  final bool hostHeadlessEnabled;
  final bool hostAutoRestartEnabled;
  final bool deleteAftermathOnLaunch;
  final int hostPort;
  final String unrealEnginePatcherPath;
  final String authenticationPatcherPath;
  final String memoryPatcherPath;
  final GameServerInjectType gameServerInjectType;
  final String gameServerFilePath;
  final String largePakPatcherFilePath;
  final List<SavedBackend> savedBackends;
  final Map<String, List<SavedBackend>> savedBackendsByProfile;
  final List<VersionEntry> versions;
  final String selectedVersionId;

  VersionEntry? get selectedVersion {
    for (final version in versions) {
      if (version.id == selectedVersionId) return version;
    }
    return versions.isEmpty ? null : versions.first;
  }

  static String profileBackendsKey(String username) {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return 'player';
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  LauncherSettings copyWith({
    String? username,
    bool? profileUseEmailPasswordAuth,
    String? profileAuthEmail,
    String? profileAuthPassword,
    bool? profileAuthQuickTipComplete,
    String? profileAvatarPath,
    bool? profileSetupComplete,
    bool? libraryActionsNudgeComplete,
    bool? backendConnectionTipComplete,
    bool? darkModeEnabled,
    bool? popupBackgroundBlurEnabled,
    String? backgroundImagePath,
    double? backgroundBlur,
    double? backgroundParticlesOpacity,
    bool? startupAnimationEnabled,
    String? backendWorkingDirectory,
    String? backendStartCommand,
    BackendConnectionType? backendConnectionType,
    String? backendHost,
    int? backendPort,
    bool? launchBackendOnSessionStart,
    bool? largePakPatcherEnabled,
    String? hostUsername,
    String? playCustomLaunchArgs,
    String? hostCustomLaunchArgs,
    bool? allowMultipleGameClients,
    bool? hostHeadlessEnabled,
    bool? hostAutoRestartEnabled,
    bool? deleteAftermathOnLaunch,
    int? hostPort,
    String? unrealEnginePatcherPath,
    String? authenticationPatcherPath,
    String? memoryPatcherPath,
    GameServerInjectType? gameServerInjectType,
    String? gameServerFilePath,
    String? largePakPatcherFilePath,
    List<SavedBackend>? savedBackends,
    Map<String, List<SavedBackend>>? savedBackendsByProfile,
    List<VersionEntry>? versions,
    String? selectedVersionId,
  }) {
    return LauncherSettings(
      username: username ?? this.username,
      profileUseEmailPasswordAuth:
          profileUseEmailPasswordAuth ?? this.profileUseEmailPasswordAuth,
      profileAuthEmail: profileAuthEmail ?? this.profileAuthEmail,
      profileAuthPassword: profileAuthPassword ?? this.profileAuthPassword,
      profileAuthQuickTipComplete:
          profileAuthQuickTipComplete ?? this.profileAuthQuickTipComplete,
      profileAvatarPath: profileAvatarPath ?? this.profileAvatarPath,
      profileSetupComplete: profileSetupComplete ?? this.profileSetupComplete,
      libraryActionsNudgeComplete:
          libraryActionsNudgeComplete ?? this.libraryActionsNudgeComplete,
      backendConnectionTipComplete:
          backendConnectionTipComplete ?? this.backendConnectionTipComplete,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      popupBackgroundBlurEnabled:
          popupBackgroundBlurEnabled ?? this.popupBackgroundBlurEnabled,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundParticlesOpacity:
          backgroundParticlesOpacity ?? this.backgroundParticlesOpacity,
      startupAnimationEnabled:
          startupAnimationEnabled ?? this.startupAnimationEnabled,
      backendWorkingDirectory:
          backendWorkingDirectory ?? this.backendWorkingDirectory,
      backendStartCommand: backendStartCommand ?? this.backendStartCommand,
      backendConnectionType:
          backendConnectionType ?? this.backendConnectionType,
      backendHost: backendHost ?? this.backendHost,
      backendPort: backendPort ?? this.backendPort,
      launchBackendOnSessionStart:
          launchBackendOnSessionStart ?? this.launchBackendOnSessionStart,
      largePakPatcherEnabled:
          largePakPatcherEnabled ?? this.largePakPatcherEnabled,
      hostUsername: hostUsername ?? this.hostUsername,
      playCustomLaunchArgs: playCustomLaunchArgs ?? this.playCustomLaunchArgs,
      hostCustomLaunchArgs: hostCustomLaunchArgs ?? this.hostCustomLaunchArgs,
      allowMultipleGameClients:
          allowMultipleGameClients ?? this.allowMultipleGameClients,
      hostHeadlessEnabled: hostHeadlessEnabled ?? this.hostHeadlessEnabled,
      hostAutoRestartEnabled:
          hostAutoRestartEnabled ?? this.hostAutoRestartEnabled,
      deleteAftermathOnLaunch:
          deleteAftermathOnLaunch ?? this.deleteAftermathOnLaunch,
      hostPort: hostPort ?? this.hostPort,
      unrealEnginePatcherPath:
          unrealEnginePatcherPath ?? this.unrealEnginePatcherPath,
      authenticationPatcherPath:
          authenticationPatcherPath ?? this.authenticationPatcherPath,
      memoryPatcherPath: memoryPatcherPath ?? this.memoryPatcherPath,
      gameServerInjectType: gameServerInjectType ?? this.gameServerInjectType,
      gameServerFilePath: gameServerFilePath ?? this.gameServerFilePath,
      largePakPatcherFilePath:
          largePakPatcherFilePath ?? this.largePakPatcherFilePath,
      savedBackends: savedBackends ?? this.savedBackends,
      savedBackendsByProfile:
          savedBackendsByProfile ?? this.savedBackendsByProfile,
      versions: versions ?? this.versions,
      selectedVersionId: selectedVersionId ?? this.selectedVersionId,
    );
  }

  static LauncherSettings defaults() {
    return const LauncherSettings(
      username: 'Player',
      profileUseEmailPasswordAuth: false,
      profileAuthEmail: '',
      profileAuthPassword: '',
      profileAuthQuickTipComplete: false,
      profileAvatarPath: '',
      profileSetupComplete: false,
      libraryActionsNudgeComplete: false,
      backendConnectionTipComplete: false,
      darkModeEnabled: true,
      popupBackgroundBlurEnabled: true,
      backgroundImagePath: '',
      backgroundBlur: 15,
      backgroundParticlesOpacity: 1.0,
      startupAnimationEnabled: true,
      backendWorkingDirectory: '',
      backendStartCommand: 'npm run start',
      backendConnectionType: BackendConnectionType.local,
      backendHost: '127.0.0.1',
      backendPort: 3551,
      launchBackendOnSessionStart: true,
      largePakPatcherEnabled: false,
      hostUsername: 'host',
      playCustomLaunchArgs: '',
      hostCustomLaunchArgs: '',
      allowMultipleGameClients: false,
      hostHeadlessEnabled: true,
      hostAutoRestartEnabled: false,
      deleteAftermathOnLaunch: true,
      hostPort: 7777,
      unrealEnginePatcherPath: '',
      authenticationPatcherPath: '',
      memoryPatcherPath: '',
      gameServerInjectType: GameServerInjectType.custom,
      gameServerFilePath: '',
      largePakPatcherFilePath: '',
      savedBackends: <SavedBackend>[],
      savedBackendsByProfile: <String, List<SavedBackend>>{},
      versions: <VersionEntry>[],
      selectedVersionId: '',
    );
  }

  factory LauncherSettings.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    int asInt(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    bool asBool(dynamic value, bool fallback) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lowered = value.toLowerCase();
        if (lowered == 'true' || lowered == '1') return true;
        if (lowered == 'false' || lowered == '0') return false;
      }
      return fallback;
    }

    BackendConnectionType asBackendType(dynamic value) {
      final raw = (value ?? '').toString().toLowerCase().trim();
      if (raw == 'remote') return BackendConnectionType.remote;
      return BackendConnectionType.local;
    }

    Map<String, List<SavedBackend>> parseScopedSavedBackends(dynamic value) {
      final parsed = <String, List<SavedBackend>>{};
      if (value is! Map) return parsed;
      for (final entry in value.entries) {
        final key = profileBackendsKey(entry.key.toString());
        final rawList = entry.value;
        if (rawList is! List) continue;
        final parsedList = <SavedBackend>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            parsedList.add(SavedBackend.fromJson(item));
          } else if (item is Map) {
            parsedList.add(SavedBackend.fromJson(item.cast<String, dynamic>()));
          }
        }
        parsed[key] = parsedList;
      }
      return parsed;
    }

    final resolvedUsername =
        ((json['username'] ?? 'Player').toString().trim().isEmpty)
        ? 'Player'
        : (json['username'] ?? 'Player').toString().trim();

    final parsedVersions = <VersionEntry>[];
    final versionsRaw = json['versions'];
    if (versionsRaw is List) {
      for (final item in versionsRaw) {
        if (item is Map<String, dynamic>) {
          parsedVersions.add(VersionEntry.fromJson(item));
        } else if (item is Map) {
          parsedVersions.add(
            VersionEntry.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }

    final selectedFromFile = (json['selectedVersionId'] ?? '').toString();
    final selected = parsedVersions.any((entry) => entry.id == selectedFromFile)
        ? selectedFromFile
        : (parsedVersions.isNotEmpty ? parsedVersions.first.id : '');

    final parsedSavedBackends = <SavedBackend>[];
    final savedRaw = json['savedBackends'] ?? json['SavedBackends'];
    if (savedRaw is List) {
      for (final item in savedRaw) {
        if (item is Map<String, dynamic>) {
          parsedSavedBackends.add(SavedBackend.fromJson(item));
        } else if (item is Map) {
          parsedSavedBackends.add(
            SavedBackend.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }

    final parsedSavedBackendsByProfile = parseScopedSavedBackends(
      json['savedBackendsByProfile'] ??
          json['SavedBackendsByProfile'] ??
          json['savedBackendsByUser'] ??
          json['SavedBackendsByUser'],
    );
    final profileSavedBackendsKey = profileBackendsKey(resolvedUsername);
    final hasProfileScopedSavedBackends = parsedSavedBackendsByProfile
        .containsKey(profileSavedBackendsKey);
    if (!hasProfileScopedSavedBackends && parsedSavedBackends.isNotEmpty) {
      parsedSavedBackendsByProfile[profileSavedBackendsKey] =
          List<SavedBackend>.from(parsedSavedBackends);
    }
    final resolvedSavedBackends = List<SavedBackend>.from(
      parsedSavedBackendsByProfile[profileSavedBackendsKey] ??
          parsedSavedBackends,
    );

    return LauncherSettings(
      username: resolvedUsername,
      profileUseEmailPasswordAuth: asBool(
        json['profileUseEmailPasswordAuth'] ??
            json['profileEmailPasswordAuth'] ??
            json['ProfileUseEmailPasswordAuth'],
        false,
      ),
      profileAuthEmail:
          (json['profileAuthEmail'] ??
                  json['profileEmail'] ??
                  json['accountEmail'] ??
                  '')
              .toString()
              .trim(),
      profileAuthPassword:
          (json['profileAuthPassword'] ?? json['accountPassword'] ?? '')
              .toString(),
      profileAuthQuickTipComplete: asBool(
        json['profileAuthQuickTipComplete'] ??
            json['ProfileAuthQuickTipComplete'],
        false,
      ),
      profileAvatarPath: (json['profileAvatarPath'] ?? '').toString(),
      profileSetupComplete: asBool(
        json['profileSetupComplete'] ?? json['ProfileSetupComplete'],
        true,
      ),
      libraryActionsNudgeComplete: asBool(
        json['libraryActionsNudgeComplete'],
        true,
      ),
      backendConnectionTipComplete: asBool(
        json['backendConnectionTipComplete'],
        true,
      ),
      darkModeEnabled: asBool(
        json['darkModeEnabled'] ?? json['darkMode'] ?? json['DarkMode'],
        true,
      ),
      popupBackgroundBlurEnabled: asBool(
        json['popupBackgroundBlurEnabled'] ??
            json['popupBackgroundBlur'] ??
            json['PopupBackgroundBlur'],
        true,
      ),
      backgroundImagePath:
          (json['backgroundImagePath'] ?? json['BackgroundImagePath'] ?? '')
              .toString(),
      backgroundBlur: asDouble(
        json['backgroundBlur'] ?? json['BackgroundBlur'],
        15,
      ).clamp(0, 30),
      backgroundParticlesOpacity: asDouble(
        json['backgroundParticlesOpacity'] ??
            json['BackgroundParticlesOpacity'],
        1.0,
      ).clamp(0, 2),
      startupAnimationEnabled: asBool(
        json['startupAnimationEnabled'] ?? json['StartupAnimationEnabled'],
        true,
      ),
      backendWorkingDirectory: (json['backendWorkingDirectory'] ?? '')
          .toString(),
      backendStartCommand: (json['backendStartCommand'] ?? 'npm run start')
          .toString(),
      backendConnectionType: asBackendType(
        json['backendConnectionType'] ??
            json['backendType'] ??
            json['BackendConnectionType'] ??
            json['BackendType'],
      ),
      backendHost: (json['backendHost'] ?? '').toString(),
      backendPort: asInt(json['backendPort'], 3551),
      launchBackendOnSessionStart: asBool(
        json['launchBackendOnSessionStart'] ?? json['launchBackend'],
        true,
      ),
      largePakPatcherEnabled: asBool(
        json['largePakPatcherEnabled'] ?? json['largePakPatcher'],
        false,
      ),
      hostUsername: ((json['hostUsername'] ?? '').toString().trim().isEmpty)
          ? 'host'
          : (json['hostUsername'] ?? '').toString().trim(),
      playCustomLaunchArgs:
          (json['playCustomLaunchArgs'] ?? json['playLaunchArgs'] ?? '')
              .toString(),
      hostCustomLaunchArgs:
          (json['hostCustomLaunchArgs'] ?? json['hostLaunchArgs'] ?? '')
              .toString(),
      allowMultipleGameClients: asBool(
        json['allowMultipleGameClients'] ?? json['multiClientLaunching'],
        false,
      ),
      hostHeadlessEnabled: asBool(
        json['hostHeadlessEnabled'] ?? json['hostHeadless'] ?? true,
        true,
      ),
      hostAutoRestartEnabled: asBool(
        json['hostAutoRestartEnabled'] ?? json['hostAutoRestart'],
        false,
      ),
      deleteAftermathOnLaunch: asBool(
        json['deleteAftermathOnLaunch'] ??
            json['deleteGfeSdkOnHostLaunch'] ??
            json['deleteGfeSdkOnLaunch'],
        true,
      ),
      hostPort: asInt(
        json['hostPort'] ?? json['gameServerPort'],
        7777,
      ).clamp(1, 65535).toInt(),
      unrealEnginePatcherPath:
          (json['unrealEnginePatcherPath'] ??
                  json['UnrealEnginePatcherPath'] ??
                  '')
              .toString(),
      authenticationPatcherPath:
          (json['authenticationPatcherPath'] ??
                  json['AuthenticationPatcherPath'] ??
                  '')
              .toString(),
      memoryPatcherPath:
          (json['memoryPatcherPath'] ?? json['MemoryPatcherPath'] ?? '')
              .toString(),
      gameServerInjectType: GameServerInjectType.custom,
      gameServerFilePath:
          (json['gameServerFilePath'] ?? json['GameServerFilePath'] ?? '')
              .toString(),
      largePakPatcherFilePath:
          (json['largePakPatcherFilePath'] ??
                  json['LargePakPatcherFilePath'] ??
                  '')
              .toString(),
      savedBackends: resolvedSavedBackends,
      savedBackendsByProfile: parsedSavedBackendsByProfile,
      versions: parsedVersions,
      selectedVersionId: selected,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'username': username,
      'profileUseEmailPasswordAuth': profileUseEmailPasswordAuth,
      'profileAuthEmail': profileAuthEmail,
      'profileAuthPassword': profileAuthPassword,
      'profileAuthQuickTipComplete': profileAuthQuickTipComplete,
      'profileAvatarPath': profileAvatarPath,
      'profileSetupComplete': profileSetupComplete,
      'libraryActionsNudgeComplete': libraryActionsNudgeComplete,
      'backendConnectionTipComplete': backendConnectionTipComplete,
      'darkModeEnabled': darkModeEnabled,
      'popupBackgroundBlurEnabled': popupBackgroundBlurEnabled,
      'backgroundImagePath': backgroundImagePath,
      'backgroundBlur': backgroundBlur,
      'backgroundParticlesOpacity': backgroundParticlesOpacity,
      'startupAnimationEnabled': startupAnimationEnabled,
      'backendWorkingDirectory': backendWorkingDirectory,
      'backendStartCommand': backendStartCommand,
      'backendConnectionType': backendConnectionType.name,
      'backendHost': backendHost,
      'backendPort': backendPort,
      'launchBackendOnSessionStart': launchBackendOnSessionStart,
      'largePakPatcherEnabled': largePakPatcherEnabled,
      'hostUsername': hostUsername,
      'playCustomLaunchArgs': playCustomLaunchArgs,
      'hostCustomLaunchArgs': hostCustomLaunchArgs,
      'allowMultipleGameClients': allowMultipleGameClients,
      'hostHeadlessEnabled': hostHeadlessEnabled,
      'hostAutoRestartEnabled': hostAutoRestartEnabled,
      'deleteAftermathOnLaunch': deleteAftermathOnLaunch,
      'hostPort': hostPort,
      'unrealEnginePatcherPath': unrealEnginePatcherPath,
      'authenticationPatcherPath': authenticationPatcherPath,
      'memoryPatcherPath': memoryPatcherPath,
      'gameServerInjectType': gameServerInjectType.name,
      'gameServerFilePath': gameServerFilePath,
      'largePakPatcherFilePath': largePakPatcherFilePath,
      'savedBackends': savedBackends.map((entry) => entry.toJson()).toList(),
      'savedBackendsByProfile': savedBackendsByProfile.map(
        (profileKey, profileSavedBackends) => MapEntry(
          profileKey,
          profileSavedBackends.map((entry) => entry.toJson()).toList(),
        ),
      ),
      'versions': versions.map((entry) => entry.toJson()).toList(),
      'selectedVersionId': selectedVersionId,
    };
  }
}

class SavedBackend {
  const SavedBackend({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;

  factory SavedBackend.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return SavedBackend(
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: asInt(json['port'], 3551).clamp(1, 65535).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'name': name, 'host': host, 'port': port};
  }
}

class VersionEntry {
  const VersionEntry({
    required this.id,
    required this.name,
    required this.gameVersion,
    required this.location,
    required this.executablePath,
    this.splashImagePath = '',
  });

  final String id;
  final String name;
  final String gameVersion;
  final String location;
  final String executablePath;
  final String splashImagePath;

  VersionEntry copyWith({
    String? id,
    String? name,
    String? gameVersion,
    String? location,
    String? executablePath,
    String? splashImagePath,
  }) {
    return VersionEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      gameVersion: gameVersion ?? this.gameVersion,
      location: location ?? this.location,
      executablePath: executablePath ?? this.executablePath,
      splashImagePath: splashImagePath ?? this.splashImagePath,
    );
  }

  factory VersionEntry.fromJson(Map<String, dynamic> json) {
    return VersionEntry(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      gameVersion: (json['gameVersion'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      executablePath: (json['executablePath'] ?? '').toString(),
      splashImagePath: (json['splashImagePath'] ?? json['coverImagePath'] ?? '')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'gameVersion': gameVersion,
      'location': location,
      'executablePath': executablePath,
      'splashImagePath': splashImagePath,
    };
  }
}
