import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _backendId = String.fromEnvironment('ATLAS_BACKEND_ID');

class _BackendDefinition {
  const _BackendDefinition({
    required this.label,
    required this.directory,
    required this.entrypoint,
    required this.extraEnvironment,
  });

  final String label;
  final String directory;
  final String entrypoint;
  final Map<String, String> extraEnvironment;
}

Future<void> main(List<String> args) async {
  final definition = switch (_backendId) {
    'lawinserver' => const _BackendDefinition(
      label: 'LawinServer',
      directory: 'lawinserver',
      entrypoint: 'index.js',
      extraEnvironment: {},
    ),
    'neonite_v2' => const _BackendDefinition(
      label: 'NeoniteV2',
      directory: 'neonite_v2',
      entrypoint: 'app.js',
      extraEnvironment: {'ATLAS_LINK_EMBEDDED_BACKEND': '1'},
    ),
    _ => throw StateError(
      'Unknown ATLAS_BACKEND_ID "$_backendId". Build the wrapper with -DATLAS_BACKEND_ID.',
    ),
  };

  final launcherPid = args.isEmpty ? null : int.tryParse(args.first);
  final exeDir = File(Platform.resolvedExecutable).parent;
  final backendRoot = exeDir.parent;
  final backendDir = args.length >= 2 && args[1].trim().isNotEmpty
      ? Directory(args[1])
      : Directory(_joinPath([backendRoot.path, definition.directory]));
  final nodeExe = File(_joinPath([backendDir.parent.path, 'node', 'node.exe']));
  final app = File(_joinPath([backendDir.path, definition.entrypoint]));

  if (!Platform.isWindows) {
    stderr.writeln('${definition.label} wrapper is only supported on Windows.');
    exitCode = 1;
    return;
  }
  if (!nodeExe.existsSync()) {
    stderr.writeln('Bundled Node runtime was not found at ${nodeExe.path}.');
    exitCode = 1;
    return;
  }
  if (!app.existsSync()) {
    stderr.writeln(
      '${definition.label} entrypoint was not found at ${app.path}.',
    );
    exitCode = 1;
    return;
  }

  Process? child;
  var shuttingDown = false;

  Future<void> shutdown([int code = 0]) async {
    if (shuttingDown) return;
    shuttingDown = true;
    final process = child;
    if (process != null) {
      await _terminateProcessTree(process.pid);
    }
    exit(code);
  }

  child = await Process.start(
    nodeExe.path,
    <String>[app.path],
    workingDirectory: backendDir.path,
    environment: <String, String>{
      ...Platform.environment,
      ...definition.extraEnvironment,
      'FORCE_COLOR': '1',
      'TERM': 'xterm-256color',
    },
    includeParentEnvironment: false,
  );

  unawaited(_pipeBytes(child.stdout, stdout));
  unawaited(_pipeBytes(child.stderr, stderr));

  Timer? launcherWatchTimer;
  if (launcherPid != null && launcherPid > 0) {
    launcherWatchTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!_processExists(launcherPid)) {
        unawaited(shutdown());
      }
    });
  }

  final code = await child.exitCode;
  launcherWatchTimer?.cancel();
  if (!shuttingDown) {
    exit(code);
  }
}

Future<void> _pipeBytes(Stream<List<int>> input, IOSink output) async {
  try {
    await for (final chunk in input) {
      try {
        output.add(chunk);
      } catch (_) {
        // The launcher may close its pipe while the backend is exiting.
      }
    }
  } catch (_) {
    // Ignore backend pipe shutdown noise.
  }
}

bool _processExists(int pid) {
  if (pid <= 0) return false;
  try {
    final result = Process.runSync(
      'tasklist',
      <String>['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final output = '${result.stdout}\n${result.stderr}';
    return output.contains('"$pid"') || output.contains(',$pid,');
  } catch (_) {
    return true;
  }
}

Future<void> _terminateProcessTree(int pid) async {
  if (pid <= 0) return;
  try {
    await Process.run('taskkill', <String>['/F', '/T', '/PID', pid.toString()]);
  } catch (_) {
    // Ignore process shutdown failures.
  }
}

String _joinPath(List<String> parts) => parts.join(Platform.pathSeparator);
