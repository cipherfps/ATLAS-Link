import 'dart:convert';
import 'dart:io';

import 'package:atlas_link_flutter/resilient_json_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory testDirectory;
  late File settingsFile;
  late ResilientJsonStore store;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'atlas-settings-store-',
    );
    settingsFile = File(
      '${testDirectory.path}${Platform.pathSeparator}settings.json',
    );
    store = ResilientJsonStore(settingsFile);
  });

  tearDown(() async {
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('retains the previous valid settings as a backup', () async {
    await store.writeObject({
      'versions': ['first'],
    });
    await store.writeObject({
      'versions': ['second'],
    });

    expect(jsonDecode(await settingsFile.readAsString()), {
      'versions': ['second'],
    });
    expect(jsonDecode(await store.backupFile.readAsString()), {
      'versions': ['first'],
    });
  });

  test('recovers an empty primary from the last valid backup', () async {
    await store.writeObject({
      'versions': ['safe'],
    });
    await store.writeObject({
      'versions': ['latest'],
    });
    await settingsFile.writeAsString('', flush: true);

    final result = await ResilientJsonStore(settingsFile).load();

    expect(result.status, ResilientJsonLoadStatus.recovered);
    expect(result.data, {
      'versions': ['safe'],
    });
    expect(jsonDecode(await settingsFile.readAsString()), {
      'versions': ['safe'],
    });
  });

  test('recovers the newest completed temporary write', () async {
    await store.writeObject({
      'versions': ['safe'],
    });
    await settingsFile.writeAsString('', flush: true);
    await store.tempFile.writeAsString(
      jsonEncode({
        'versions': ['newest'],
      }),
      flush: true,
    );

    final result = await ResilientJsonStore(settingsFile).load();

    expect(result.status, ResilientJsonLoadStatus.recovered);
    expect(result.data, {
      'versions': ['newest'],
    });
  });

  test('serializes concurrent writes and leaves valid JSON', () async {
    await Future.wait([
      store.writeObject({'sequence': 1}),
      store.writeObject({'sequence': 2}),
      store.writeObject({'sequence': 3}),
    ]);

    expect(jsonDecode(await settingsFile.readAsString()), {'sequence': 3});
    expect(jsonDecode(await store.backupFile.readAsString()), {'sequence': 2});
  });

  test('quarantines an invalid primary when no backup exists', () async {
    await settingsFile.writeAsString('', flush: true);

    final result = await store.load();

    expect(result.status, ResilientJsonLoadStatus.invalid);
    expect(result.data, isNull);
    expect(await settingsFile.exists(), isFalse);
    expect(result.quarantinedPath, isNotNull);
    expect(await File(result.quarantinedPath!).exists(), isTrue);
  });
}
