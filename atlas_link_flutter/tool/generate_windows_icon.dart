import 'dart:io';

import 'package:image/image.dart';

/// Generates a multi-size Windows ICO from the app logo.
///
/// Why: Flutter's Windows runner and our installer use `app_icon.ico`. Having
/// multiple embedded sizes (16..256) avoids blurry downscaling in common shell
/// views (taskbar/file explorer/start menu).
void main(List<String> args) {
  final srcPath = args.isNotEmpty ? args[0] : 'assets/images/atlas_logo.png';
  final outPath =
      args.length > 1 ? args[1] : 'windows/runner/resources/app_icon.ico';

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Source icon not found: $srcPath');
    exit(2);
  }

  final srcBytes = srcFile.readAsBytesSync();
  final src = decodeImage(srcBytes);
  if (src == null) {
    stderr.writeln('Failed to decode image: $srcPath');
    exit(3);
  }

  // Match the historical icon bundle sizes used by this repo.
  const sizes = <int>[16, 24, 32, 48, 64, 128, 256];

  final images = <Image>[];
  for (final size in sizes) {
    images.add(
      copyResize(
        src,
        width: size,
        height: size,
        interpolation: Interpolation.cubic,
      ),
    );
  }

  final icoBytes = IcoEncoder().encodeImages(images);

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(icoBytes);

  stdout.writeln('Wrote ${outFile.path} (${icoBytes.length} bytes).');
}

