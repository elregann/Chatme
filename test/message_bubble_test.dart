import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/core/utils/emoji_utils.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatMessage message(
    String text, {
    String status = 'sent',
    String? replyToContent,
  }) {
    return ChatMessage(
      id: 'message-1',
      senderPubkey: 'me',
      receiverPubkey: 'you',
      content: '',
      plaintext: text,
      timestamp: DateTime(2026, 1, 2, 15, 4).millisecondsSinceEpoch,
      status: status,
      chatKey: 'chat',
      replyToContent: replyToContent,
    );
  }

  Widget footer(Color color) {
    return Text(
      '15:04',
      style: TextStyle(color: color, fontSize: 11),
    );
  }

  Widget bubble(
    String text, {
    String? replyToContent,
    String? replyPreview,
    bool isMe = true,
  }) {
    return MessageBubble(
      message: message(text, replyToContent: replyToContent),
      isMe: isMe,
      bubbleColor: isMe ? ChatmeColors.bubbleOutgoing : ChatmeColors.bubbleIncoming,
      textColor: isMe ? ChatmeColors.onAccent : ChatmeColors.textPrimary,
      footer: footer(ChatmeColors.textMuted),
      imageFooter: footer(ChatmeColors.textPrimary),
      replySenderName: replyToContent == null ? null : 'You',
      replyPreview: replyPreview,
    );
  }

  Widget app(Widget child, {double width = 360}) {
    // Like the message list, keep the bubble scrollable so a tall message is
    // not squeezed into the test screen height.
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('a text message keeps its bubble', (tester) async {
    await tester.pumpWidget(app(bubble('Hello captain')));

    expect(find.byKey(const Key('message_bubble_surface')), findsOneWidget);
    expect(find.byKey(const Key('emoji_message')), findsNothing);
  });

  testWidgets('an emoji-only message has no bubble but keeps a footer',
      (tester) async {
    await tester.pumpWidget(app(bubble('😀😀')));

    expect(find.byKey(const Key('message_bubble_surface')), findsNothing);
    expect(find.byKey(const Key('emoji_message')), findsOneWidget);
    expect(find.byKey(const Key('emoji_footer')), findsOneWidget);

    final emoji = tester.widget<Text>(find.byKey(const Key('emoji_message')));
    expect(emoji.style?.fontSize, emojiLargeFontSize);
  });

  testWidgets('four or more emoji use the smaller jumbo size', (tester) async {
    await tester.pumpWidget(app(bubble('😀😀😀😀')));

    final emoji = tester.widget<Text>(find.byKey(const Key('emoji_message')));
    expect(emoji.style?.fontSize, emojiSmallFontSize);
  });

  testWidgets('the emoji footer pill follows the bubble colour',
      (tester) async {
    await tester.pumpWidget(app(bubble('😀')));

    final pill =
        tester.widget<Container>(find.byKey(const Key('emoji_footer')));
    final decoration = pill.decoration! as BoxDecoration;
    expect(decoration.color, ChatmeColors.bubbleOutgoing);
  });

  testWidgets('an emoji-only reply keeps a normal bubble and plain footer',
      (tester) async {
    await tester.pumpWidget(
      app(
        bubble(
          '😀',
          replyToContent: 'quoted message',
          replyPreview: 'quoted message',
        ),
      ),
    );

    expect(find.byKey(const Key('message_bubble_surface')), findsOneWidget);
    expect(find.byKey(const Key('reply_card')), findsOneWidget);
    expect(find.byKey(const Key('emoji_message')), findsOneWidget);
    // A reply uses the plain footer, not the emoji pill.
    expect(find.byKey(const Key('emoji_footer')), findsNothing);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('quoted message'), findsOneWidget);
    expect(find.text('15:04'), findsOneWidget);
  });

  testWidgets('an emoji-only reply starts smaller and keeps shrinking',
      (tester) async {
    Future<double?> sizeFor(String text) async {
      await tester.pumpWidget(
        app(
          bubble(
            text,
            replyToContent: 'quoted message',
            replyPreview: 'quoted message',
          ),
        ),
      );
      final emoji = tester.widget<Text>(find.byKey(const Key('emoji_message')));
      return emoji.style?.fontSize;
    }

    // The biggest tier is skipped: one to three emoji start at the size a
    // stand-alone run of four emoji uses, then shrink as the run grows.
    expect(await sizeFor('😀'), emojiReplyFirstFontSize);
    expect(await sizeFor('😀😀😀'), emojiReplyFirstFontSize);
    expect(await sizeFor('😀' * 4), emojiReplySecondFontSize);
    expect(await sizeFor('😀' * 7), emojiReplyThirdFontSize);
    expect(await sizeFor('😀' * 10), emojiReplyMinFontSize);
  });

  testWidgets('a long emoji-only reply fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        bubble(
          '😀' * 40,
          replyToContent: 'quoted message',
          replyPreview: 'quoted message',
        ),
        width: 320,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('message_bubble_surface')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('message_bubble_surface'))).width,
      lessThanOrEqualTo(320),
    );
  });

  testWidgets('a short reply puts the time at the right edge of a wide bubble',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const quoted = 'This quoted message is long enough to make the reply '
        'bubble use the full width of a narrow screen.';

    await tester.pumpWidget(
      app(
        bubble('iyaa', replyToContent: quoted, replyPreview: quoted),
        width: 320,
      ),
    );

    expect(tester.takeException(), isNull);

    final item = tester.getRect(
      find.byKey(const Key('message_bubble_surface')),
    );
    final time = tester.getRect(find.text('15:04'));

    // isMe: 12px outer margin + 10px bubble padding on the right.
    expect(time.right, moreOrLessEquals(item.right - 22, epsilon: 0.5));
    // The short text stays on the left instead of following the time.
    expect(tester.getRect(find.text('iyaa')).left, lessThan(100));
  });

  testWidgets('a long message stretches its short reply card to the bubble',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const quoted = 'halo';
    const long = 'This is a long message that has to wrap over several lines '
        'without being cut off or pushed outside the bubble. ';

    await tester.pumpWidget(
      app(
        bubble(long * 3, replyToContent: quoted, replyPreview: quoted),
        width: 320,
      ),
    );

    expect(tester.takeException(), isNull);

    final item = tester.getRect(
      find.byKey(const Key('message_bubble_surface')),
    );
    final card = tester.getRect(find.byKey(const Key('reply_card')));

    // The card spans the bubble content: item width minus 50/12 margins and
    // 10px padding on both sides.
    expect(card.width, moreOrLessEquals(item.width - 82, epsilon: 0.5));
  });

  testWidgets('a long message does not overflow a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const text = 'This is a long message that has to wrap over several lines '
        'without pushing the timestamp outside the bubble or the screen. ';

    await tester.pumpWidget(
      app(bubble(text * 4), width: 320),
    );

    expect(tester.takeException(), isNull);

    // 320px screen: bubble max width is min(320 * 0.9, 320 - 62) = 258, so the
    // text area is at most 238px and must wrap instead of running off screen.
    final textSize = tester.getSize(find.text(text * 4));
    expect(textSize.width, lessThanOrEqualTo(238));

    // The bubble plus its side margins still fits inside the screen.
    final itemSize = tester.getSize(
      find.byKey(const Key('message_bubble_surface')),
    );
    expect(itemSize.width, lessThanOrEqualTo(320));
  });

  testWidgets('an emoji-only reply keeps the emoji on the left side inside the bubble for sender',
      (tester) async {
    const quoted = 'Quoted message text';

    await tester.pumpWidget(
      app(
        bubble('😀', replyToContent: quoted, replyPreview: quoted, isMe: true),
        width: 360,
      ),
    );

    expect(tester.takeException(), isNull);
    final bubbleRect = tester.getRect(find.byKey(const Key('message_bubble_surface')));
    final emojiRect = tester.getRect(find.byKey(const Key('emoji_message')));

    // Emoji should stay on the left side of the bubble surface, not pushed to the far right edge.
    expect(emojiRect.left - bubbleRect.left, lessThan(100));
  });

  testWidgets('an emoji-only message aligns the footer pill to the right for recipient',
      (tester) async {
    await tester.pumpWidget(
      app(bubble('😀', isMe: false), width: 360),
    );

    expect(tester.takeException(), isNull);
    final emojiRect = tester.getRect(find.byKey(const Key('emoji_message')));
    final pillRect = tester.getRect(find.byKey(const Key('emoji_footer')));

    // Footer pill right edge should match or exceed emoji right edge.
    expect(pillRect.right, greaterThanOrEqualTo(emojiRect.right - 1.0));
  });

  group('reply card colors', () {
    BoxDecoration cardDecoration(WidgetTester tester) {
      final card = tester.widget<Container>(find.byKey(const Key('reply_card')));
      return card.decoration! as BoxDecoration;
    }

    testWidgets('uses outgoing reply colors on my bubble', (tester) async {
      await tester.pumpWidget(app(bubble(
        'Hello',
        replyToContent: 'Earlier',
        replyPreview: 'Earlier',
        isMe: true,
      )));

      final border = cardDecoration(tester).border! as Border;
      expect(border.left.color, ChatmeColors.accentPrimary);
      expect(cardDecoration(tester).color, ChatmeColors.accentDeep.withAlpha(90));
    });

    testWidgets('uses incoming reply colors on their bubble', (tester) async {
      await tester.pumpWidget(app(bubble(
        'Hello',
        replyToContent: 'Earlier',
        replyPreview: 'Earlier',
        isMe: false,
      )));

      final border = cardDecoration(tester).border! as Border;
      expect(border.left.color, ChatmeColors.accentStrong);
      expect(cardDecoration(tester).color, ChatmeColors.surfaceOverlay);
    });
  });
}
