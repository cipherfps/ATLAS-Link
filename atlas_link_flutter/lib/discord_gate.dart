import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Client side of the "Connect with Discord" flow.
///
/// We can't ship a client secret in the launcher, so the OAuth dance happens in
/// the ATLAS Network Gate (a Cloudflare Worker). This class only:
///   1. opens a one-shot loopback HTTP listener on `127.0.0.1:<random port>`,
///   2. opens the user's browser at `<gateUrl>/login?port=…&state=…`,
///   3. waits for the Worker to redirect the browser back to that loopback with
///      the minted single-use Tailscale key (or an error reason),
///   4. shows a tidy "return to ATLAS" page and hands the key back.
///
/// Nothing here listens on the network beyond loopback, and the only value that
/// ever crosses it is a key that works once and expires in minutes.
class DiscordGate {
  DiscordGate({this.logger});

  final void Function(String message)? logger;

  /// Data URI of the ATLAS logo, embedded into the served pages so it renders
  /// with no external request (ad blockers / offline can't strip it).
  String? _logoDataUri;

  /// Run the login. [openUrl] is injected so this stays Flutter-free/testable;
  /// the launcher passes its own URL opener.
  Future<DiscordGateResult> login({
    required String gateUrl,
    required Future<void> Function(Uri uri) openUrl,
    Duration timeout = const Duration(minutes: 3),
    String? logoDataUri,
  }) async {
    _logoDataUri = logoDataUri;
    final base = gateUrl.trim();
    if (base.isEmpty || !base.startsWith('http')) {
      return const DiscordGateResult.error('config');
    }

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      _log('loopback bind failed: $e');
      return const DiscordGateResult.error('loopback');
    }

    final state = _randomToken();
    final completer = Completer<DiscordGateResult>();

    final sub = server.listen((request) async {
      // Browsers probe /favicon.ico etc.; only the root callback matters.
      if (request.uri.path != '/') {
        await _respond(request, 404, 'Not found');
        return;
      }
      final qp = request.uri.queryParameters;
      // Reject anything that didn't originate from the state we just issued —
      // stops a random local page from posting a forged key to us.
      if (qp['state'] != state) {
        await _respond(request, 400, 'This page is no longer valid.');
        return;
      }

      final status = qp['status'];
      if (status == 'ok' && (qp['key'] ?? '').isNotEmpty) {
        await _respond(
          request,
          200,
          "You're connected to the ATLAS Network. You can close this tab and "
          'return to ATLAS.',
        );
        if (!completer.isCompleted) {
          completer.complete(DiscordGateResult.success(qp['key']!));
        }
      } else {
        final reason = qp['reason'] ?? 'unknown';
        await _respond(
          request,
          200,
          'Could not connect: ${_friendly(reason)} You can close this tab.',
        );
        if (!completer.isCompleted) {
          completer.complete(DiscordGateResult.error(reason));
        }
      }
    });

    final loginUri = Uri.parse('$base/login').replace(
      queryParameters: {'port': '${server.port}', 'state': state},
    );

    try {
      await openUrl(loginUri);
    } catch (e) {
      _log('failed to open browser: $e');
      if (!completer.isCompleted) {
        completer.complete(const DiscordGateResult.error('browser'));
      }
    }

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(const DiscordGateResult.error('timeout'));
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
      await server.close(force: true);
    }
  }

  Future<void> _respond(HttpRequest request, int status, String message) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.html;
    request.response.write(_pageHtml(message, _logoDataUri));
    await request.response.close();
  }

  void _log(String message) => logger?.call(message);
}

/// Outcome of a Discord login attempt.
class DiscordGateResult {
  const DiscordGateResult.success(this.authKey) : error = null;
  const DiscordGateResult.error(this.error) : authKey = null;

  /// Minted single-use Tailscale key on success.
  final String? authKey;

  /// Machine-readable failure reason on error (mirrors the Worker's reasons).
  final String? error;

  bool get ok => authKey != null;
}

String _randomToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Map a Worker/gate error reason to a short, user-facing sentence.
String _friendly(String reason) {
  switch (reason) {
    case 'not_member':
      return 'you need to join the ATLAS Discord first.';
    case 'missing_role':
      return "you don't have the required role yet.";
    case 'account_too_new':
      return 'your Discord account is too new.';
    case 'rate_limited':
      return 'you already connected recently, try again later.';
    case 'discord_denied':
      return 'the Discord login was cancelled.';
    case 'timeout':
      return 'the login timed out.';
    default:
      return 'please try again.';
  }
}

String _pageHtml(String message, [String? logoDataUri]) {
  final logo = (logoDataUri != null && logoDataUri.isNotEmpty)
      ? '<img class="logo" alt="ATLAS" src="$logoDataUri">'
      : '';
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>ATLAS</title><style>'
      'body{margin:0;background:#0b1220;color:#e6edf6;'
      'font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;'
      'display:flex;min-height:100vh;align-items:center;justify-content:center}'
      '.card{max-width:420px;padding:32px;text-align:center}'
      '.logo{width:88px;height:88px;object-fit:contain;margin:0 auto 16px;display:block}'
      'h1{font-size:20px;margin:0 0 10px}p{opacity:.75;margin:0}'
      '</style></head><body><div class="card">'
      '$logo'
      '<h1>ATLAS</h1>'
      '<p>$message</p></div></body></html>';
}
