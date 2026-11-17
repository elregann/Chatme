import 'package:chatme/models/chat_message.dart';
import 'package:chatme/widgets/video_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  ChatMessage video({String localPath = '', String status = 'sent'}) =>
      ChatMessage(
        id: 'vid_1',
        senderPubkey: 'me',
        receiverPubkey: 'peer',
        content: '',
        plaintext: 'Video',
        timestamp: 1000,
        status: status,
        chatKey: 'chat_me_peer',
        file: const {'type': 'video/mp4', 'dim': '1080x1920', 'duration': '8'},
        localPath: localPath,
      );

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('a downloaded video draws its poster, not a decoder',
      (tester) async {
    await tester.pumpWidget(host(VideoBubble(
      message: video(localPath: 'C:/videos/clip.mp4'),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async => 'C:/videos/clip.mp4.thumb.jpg',
    )));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, 'C:/videos/clip.mp4.thumb.jpg');
    expect(image.fit, BoxFit.cover);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('a video whose poster cannot be made shows a dark tile',
      (tester) async {
    await tester.pumpWidget(host(VideoBubble(
      message: video(localPath: 'C:/videos/clip.mp4'),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async => null,
    )));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('a video being sent shows only the circle', (tester) async {
    await tester.pumpWidget(host(VideoBubble(
      message: video(localPath: 'C:/videos/clip.mp4', status: 'sending'),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async => null,
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
  });

  testWidgets('a video being sent keeps the poster it already has',
      (tester) async {
    await tester.pumpWidget(host(VideoBubble(
      message: video(localPath: 'C:/videos/clip.mp4', status: 'sending'),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async => 'C:/videos/clip.mp4.thumb.jpg',
    )));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('an undownloaded video asks for no poster', (tester) async {
    var asked = 0;
    await tester.pumpWidget(host(VideoBubble(
      message: video(),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async {
        asked++;
        return null;
      },
    )));
    await tester.pump();

    expect(asked, 0);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a video that finishes downloading gets its poster',
      (tester) async {
    await tester.pumpWidget(host(VideoBubble(
      key: const ValueKey('vid_1'),
      message: video(),
      footer: const SizedBox.shrink(),
    )));
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    await tester.pumpWidget(host(VideoBubble(
      key: const ValueKey('vid_1'),
      message: video(localPath: 'C:/videos/clip.mp4'),
      footer: const SizedBox.shrink(),
      thumbResolver: (_) async => 'C:/videos/clip.mp4.thumb.jpg',
    )));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
  });
}
