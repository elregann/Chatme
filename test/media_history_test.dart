import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/services/gallery_save.dart';
import 'package:chatme/services/media_history.dart';
import 'package:chatme/ui/media/image_viewer.dart';

void main() {
  ChatMessage msg(String id, int ts, {Map<String, String> file = const {}, String path = ''}) =>
      ChatMessage(
        id: id,
        senderPubkey: 'a',
        receiverPubkey: 'b',
        content: 'c',
        plaintext: 'p',
        timestamp: ts,
        chatKey: 'k',
        file: file,
        localPath: path,
      );

  const image = {'type': 'image/jpeg'};
  const voice = {'type': 'audio/mp4'};

  group('imagesNewestFirst', () {
    test('keeps only pictures', () {
      final out = imagesNewestFirst([
        msg('text', 1),
        msg('vn', 2, file: voice),
        msg('img', 3, file: image),
      ]);
      expect(out.map((m) => m.id), ['img']);
    });

    test('puts the newest first', () {
      final out = imagesNewestFirst([
        msg('old', 100, file: image),
        msg('new', 300, file: image),
        msg('mid', 200, file: image),
      ]);
      expect(out.map((m) => m.id), ['new', 'mid', 'old']);
    });

    test('does not change the input list', () {
      final input = [msg('a', 1, file: image), msg('b', 2, file: image)];
      imagesNewestFirst(input);
      expect(input.map((m) => m.id), ['a', 'b']);
    });
  });

  group('viewerSetFor', () {
    final images = [
      msg('c', 300, file: image, path: '/m/c.jpg'),
      msg('b', 200, file: image),
      msg('a', 100, file: image, path: '/m/a.jpg'),
    ];

    test('lists only downloaded pictures and finds the tapped one', () {
      final set = viewerSetFor(images, 'a')!;
      expect(set.paths, ['/m/c.jpg', '/m/a.jpg']);
      expect(set.index, 1);
      expect(set.messages.map((m) => m.id), ['c', 'a']);
    });

    test('first picture starts at zero', () {
      expect(viewerSetFor(images, 'c')!.index, 0);
    });

    test('a picture that is not downloaded gives nothing', () {
      expect(viewerSetFor(images, 'b'), isNull);
    });

    test('an unknown id gives nothing', () {
      expect(viewerSetFor(images, 'zzz'), isNull);
    });
  });

  group('viewerCounter', () {
    test('is one based', () {
      expect(viewerCounter(0, 5), '1 / 5');
      expect(viewerCounter(4, 5), '5 / 5');
    });
  });

  group('ImageViewerPage', () {
    Widget host(ImageViewerPage page) => MaterialApp(home: page);

    testWidgets('starts on the given picture and swipes to the next', (tester) async {
      await tester.pumpWidget(host(const ImageViewerPage(
        paths: ['/x/1.jpg', '/x/2.jpg', '/x/3.jpg'],
        initialIndex: 1,
      )));
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('a single picture shows no counter', (tester) async {
      await tester.pumpWidget(host(const ImageViewerPage.single(path: '/x/1.jpg')));
      await tester.pump();
      expect(find.textContaining(' / '), findsNothing);
    });

    testWidgets('the menu saves the picture on screen to the gallery', (tester) async {
      final saved = <String>[];
      await tester.pumpWidget(host(ImageViewerPage(
        paths: const ['/x/1.jpg', '/x/2.jpg'],
        initialIndex: 1,
        saveToGallery: (path) async => saved.add(path),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Gallery'));
      await tester.pumpAndSettle();

      expect(saved, ['/x/2.jpg']);
      expect(find.text('Saved to the Chatme album'), findsOneWidget);
    });

    testWidgets('a failed save shows its reason', (tester) async {
      await tester.pumpWidget(host(ImageViewerPage(
        paths: const ['/x/1.jpg'],
        saveToGallery: (_) async => throw const GallerySaveException('Allow photo access to save'),
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Gallery'));
      await tester.pumpAndSettle();

      expect(find.text('Allow photo access to save'), findsOneWidget);
    });

    testWidgets('the menu replies to the picture on screen', (tester) async {
      final replies = <ChatMessage>[];
      final images = [
        msg('one', 1, file: image, path: '/x/1.jpg'),
        msg('two', 2, file: image, path: '/x/2.jpg'),
      ];
      await tester.pumpWidget(host(ImageViewerPage(
        paths: images.map((m) => m.localPath).toList(),
        messages: images,
        onReply: replies.add,
      )));
      await tester.pump();

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Save to Gallery'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Reply')).dy,
        greaterThan(tester.getTopLeft(find.text('Save to Gallery')).dy),
      );

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(replies.map((m) => m.id), ['two']);
    });

    testWidgets('a picture that is still sending has no Reply', (tester) async {
      final replies = <ChatMessage>[];
      await tester.pumpWidget(host(ImageViewerPage(
        paths: const ['/x/1.jpg'],
        messages: [msg('temp_1', 1, file: image, path: '/x/1.jpg')],
        onReply: replies.add,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Save to Gallery'), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      expect(replies, isEmpty);
    });

    testWidgets('a viewer without a message has no Reply', (tester) async {
      await tester.pumpWidget(host(ImageViewerPage(
        paths: const ['/x/1.jpg'],
        onReply: (_) {},
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsNothing);
    });

    testWidgets('an out of range start is clamped', (tester) async {
      await tester.pumpWidget(host(const ImageViewerPage(
        paths: ['/x/1.jpg', '/x/2.jpg'],
        initialIndex: 9,
      )));
      await tester.pump();
      expect(find.text('2 / 2'), findsOneWidget);
    });
  });
}
