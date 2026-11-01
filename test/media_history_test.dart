import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/models/chat_message.dart';
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
