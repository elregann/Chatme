import 'dart:async';
import 'dart:io';

import 'package:chatme/services/image_prepare.dart';
import 'package:chatme/story/story_prepare_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      expect(result.caption, isEmpty);
    });

    test('prepared image carries a trimmed caption', () {
      final result = StoryPrepareResult.fromPreparedImage(
        prepared: PreparedImage(Uint8List.fromList([1, 2]), 12, 8),
        file: File('${Directory.systemTemp.path}/story.jpg'),
        caption: '  first light  ',
      );

      expect(result.caption, 'first light');
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
      expect(result.caption, isEmpty);
    });

    test('video carries a trimmed caption', () {
      final result = StoryPrepareResult.fromVideo(
        path: '/cache/story.mp4',
        duration: const Duration(seconds: 12),
        caption: '  sunset  ',
      );

      expect(result.caption, 'sunset');
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
        'caption capsule matches the room chat layout and keeps the caret ready',
        (tester) async {
      await tester.pumpWidget(_routeHost(builder: (_) => photoPage()));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, 'Add a caption...');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(field.minLines, 1);
      expect(field.maxLines, 3);
      expect(field.decoration?.contentPadding,
          const EdgeInsets.symmetric(horizontal: 6, vertical: 8));
      expect(field.maxLength, 200);
      expect(field.maxLengthEnforcement, MaxLengthEnforcement.enforced);
      expect(field.focusNode, isNotNull);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller?.selection.isValid, isTrue);
      expect(field.onTap, isNotNull);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      final capsule = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints ==
                const BoxConstraints(minHeight: 48, maxHeight: 180),
      );
      expect(capsule, findsOneWidget);
      expect(tester.getSize(capsule).height, 48);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints == const BoxConstraints(minHeight: 48),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding == const EdgeInsets.symmetric(horizontal: 8),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == 8 &&
              widget.height == null,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding == const EdgeInsets.fromLTRB(12, 6, 12, 6),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('video mode shows only back, trim strip and the round next button',
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

    testWidgets('typed caption is returned with the prepared photo',
        (tester) async {
      StoryPrepareResult? returned;

      await tester.pumpWidget(_routeHost(
        builder: (_) => photoPage(
          preparer: (bytes, {int maxSide = 1600, int quality = 85}) async =>
              PreparedImage(bytes, 4, 3),
          writer: (_) async =>
              File('${Directory.systemTemp.path}/story_caption_test.jpg'),
        ),
        onResult: (result) => returned = result as StoryPrepareResult?,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  morning  ');
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.caption, 'morning');
    });

    testWidgets('typed caption is returned with the prepared video',
        (tester) async {
      StoryPrepareResult? returned;

      await tester.pumpWidget(_routeHost(
        builder: (_) => videoPage(),
        onResult: (result) => returned = result as StoryPrepareResult?,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  evening  ');
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.caption, 'evening');
    });
  });
}
