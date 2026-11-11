import 'dart:io';

import 'package:chatme/core/utils/sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_sync_gate_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() {
    SyncGate.resetForTest();
  });

  test('start opens the gate and widens the window', () {
    expect(SyncGate.isActive, isFalse);
    expect(SyncGate.useFreshWindow, isFalse);

    SyncGate.start('restore');

    expect(SyncGate.isActive, isTrue);
    expect(SyncGate.useFreshWindow, isTrue);
    // Persisted so an app kill mid-sync can resume quietly.
    final box = Hive.box('settings');
    expect(box.get('initial_sync_started_at'), isNotNull);
    expect(box.get('initial_sync_fresh_window'), isTrue);
  });

  test('finish closes the gate and clears the persisted state', () {
    SyncGate.start('restore');
    SyncGate.finish('all relays sent EOSE');

    expect(SyncGate.isActive, isFalse);
    expect(SyncGate.useFreshWindow, isFalse);
    final box = Hive.box('settings');
    expect(box.get('initial_sync_started_at', defaultValue: 0), 0);
    expect(box.get('initial_sync_fresh_window', defaultValue: false), false);
  });

  test('finish is safe when the gate was never started', () {
    SyncGate.finish('nothing to do');
    expect(SyncGate.isActive, isFalse);
  });

  test('resumeIfPending picks up a recently interrupted sync', () {
    SyncGate.start('restore');

    // Simulate the app being killed: in-memory state is gone but the
    // persisted flag survives.
    SyncGate.resetForTest(keepPersisted: true);
    expect(SyncGate.isActive, isFalse);

    SyncGate.resumeIfPending();

    expect(SyncGate.isActive, isTrue);
    expect(SyncGate.useFreshWindow, isTrue);
  });

  test('resumeIfPending ignores a stale gate from long ago', () {
    final box = Hive.box('settings');
    // A gate older than the 10-minute resume window is dropped silently.
    box.put('initial_sync_started_at',
        DateTime.now().millisecondsSinceEpoch - 11 * 60 * 1000);
    box.put('initial_sync_fresh_window', true);

    SyncGate.resumeIfPending();

    expect(SyncGate.isActive, isFalse);
    expect(SyncGate.useFreshWindow, isFalse);
    expect(box.get('initial_sync_started_at', defaultValue: 0), 0);
  });

  test('resumeIfPending does nothing without a persisted gate', () {
    SyncGate.resumeIfPending();
    expect(SyncGate.isActive, isFalse);
  });
}
