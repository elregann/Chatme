import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatme/services/image_prepare.dart';
import 'package:chatme/story/story_prepare_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _routeHost({
  required WidgetBuilder builder,
  void Function(Object? result)? onResult,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<Object?>(
            MaterialPageRoute(builder: builder),
          );
          onResult?.call(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  group('StoryPreparePage.isVideoMedia', () {
    test('prefers the picker mime and falls back to the extension', () {
      expect(StoryPreparePage.isVideoMedia('/picked/a.mp4', null), isTrue);
      expect(
          StoryPreparePage.isVideoMedia('/picked/a.jpg', 'video/quicktime'),
          isTrue);
      expect(StoryPreparePage.isVideoMedia('/picked/a.jpg', 'image/jpeg'),
          isFalse);
    });
  });

  group('StoryPrepareResult', () {
    test('prepared image keeps the jpeg mime and prepared size', () {
      final result = StoryPrepareResult.fromPreparedImage(
        prepared: PreparedImage(Uint8List.fromList([1, 2]), 12, 8),
        file: File('${Directory.systemTemp.path}/story.jpg'),
      );

      expect(result.mimeType, 'image/jpeg');
      expect(result.width, 12);
      expect(result.height, 8);
      expect(result.durationSeconds, isNull);
      expect(result.trimStartMs, isNull);
    });

    test('video keeps its duration, size and mime from the path', () {
      final result = StoryPrepareResult.fromVideo(
        path: '/cache/story.mp4',
        duration: const Duration(milliseconds: 61500),
        videoSize: const Size(640, 360),
      );

      expect(result.mimeType, 'video/mp4');
      expect(result.durationSeconds, 61);
      expect(result.width, 640);
      expect(result.height, 360);
      expect(result.trimStartMs, isNull);
    });

    test('video result carries the selected trim range and cut duration', () {
      final result = StoryPrepareResult.fromVideo(
        path: '/cache/story-cut.mov',
        duration: const Duration(seconds: 45),
        videoSize: const Size(1280, 720),
        trimStartMs: 5000,
        trimEndMs: 50000,
      );

      expect(result.mimeType, 'video/quicktime');
      expect(result.durationSeconds, 45);
      expect(result.trimStartMs, 5000);
      expect(result.trimEndMs, 50000);
    });
  });

  group('StoryPreparePage', () {
    Widget photoPage({
      Future<PreparedImage> Function(
        Uint8List bytes, {
        int maxSide,
        int quality,
      })? preparer,
      Future<File> Function(Uint8List bytes)? writer,
    }) {
      return StoryPreparePage(
        mediaPath: '/picked/photo.jpg',
        isVideo: false,
        imageLoader: (_) async => Uint8List.fromList([1, 2, 3]),
        imagePreviewBuilder: (_) => const SizedBox.expand(),
        imagePreparer: preparer,
        preparedFileWriter: writer,
      );
    }

    Widget videoPage() {
      return StoryPreparePage(
        mediaPath: '/picked/clip.mp4',
        isVideo: true,
        videoPreviewBuilder: (_) => const SizedBox.expand(),
        trimStripBuilder: (_) => const SizedBox(height: 56),
        knownDuration: const Duration(seconds: 12),
      );
    }

    testWidgets('photo mode shows only back, crop and the round next button',
        (tester) async {
      await tester.pumpWidget(_routeHost(builder: (_) => photoPage()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('New Story'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_rounded), findsOneWidget);
      expect(find.byIcon(Icons.crop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.byIcon(Icons.volume_off_rounded), findsNothing);
      expect(find.byIcon(Icons.text_fields_rounded), findsNothing);
    });

    testWidgets(
        'video mode shows only back, trim strip and the round next button',
        (tester) async {
      await tester.pumpWidget(_routeHost(builder: (_) => videoPage()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('New Story'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_rounded), findsOneWidget);
      expect(find.byTooltip('Trim video'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.byIcon(Icons.crop_rounded), findsNothing);
      expect(find.byIcon(Icons.volume_off_rounded), findsNothing);
    });

    testWidgets('a second tap on next cannot prepare the photo twice',
        (tester) async {
      final gate = Completer<PreparedImage>();
      var prepareCalls = 0;
      StoryPrepareResult? returned;

      await tester.pumpWidget(_routeHost(
        builder: (_) => photoPage(
          preparer: (bytes, {int maxSide = 1600, int quality = 85}) {
            prepareCalls++;
            return gate.future;
          },
          writer: (_) async => File('${Directory.systemTemp.path}/story_prepare_test.jpg'),
        ),
        onResult: (result) => returned = result as StoryPrepareResult?,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final next = find.byIcon(Icons.chevron_right_rounded);
      await tester.tap(next);
      await tester.pump();
      // The busy scrim deliberately covers the button after the first tap.
      await tester.tap(next, warnIfMissed: false);
      await tester.pump();

      expect(prepareCalls, 1);

      gate.complete(PreparedImage(Uint8List.fromList([4, 5]), 3, 2));
      await tester.pumpAndSettle();

      final result = returned;
      expect(result, isNotNull);
      expect(result!.mimeType, 'image/jpeg');
      expect(result.file.path, endsWith('story_prepare_test.jpg'));
    });

    testWidgets('video mode returns the original path when nothing was cut',
        (tester) async {
      StoryPrepareResult? returned;

      await tester.pumpWidget(_routeHost(
        builder: (_) => videoPage(),
        onResult: (result) => returned = result as StoryPrepareResult?,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      final result = returned;
      expect(result, isNotNull);
      expect(result!.file.path, '/picked/clip.mp4');
      expect(result.durationSeconds, 12);
      expect(result.trimStartMs, isNull);
    });
  });
}
