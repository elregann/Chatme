// message_bubble.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/utils/emoji_utils.dart';
import '../models/chat_message.dart';
import 'image_bubble.dart';
import 'link_preview_card.dart';
import 'voice_note_bubble.dart';

/// One chat message bubble.
///
/// The widget only decides how a message looks. The chat screen supplies the
/// theme colours, the pre-formatted footer (time and ticks), and the callbacks;
/// it keeps the message and relay logic.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDark;
  final bool isNostrCyber;
  final Color bubbleColor;
  final Color textColor;

  /// Time and delivery ticks for text, voice notes, and emoji-only messages.
  final Widget footer;

  /// The white footer drawn on top of a picture.
  final Widget imageFooter;

  /// Link preview to show above the message, when previews are enabled.
  final String? previewUrl;

  /// Name shown in the quoted reply, if there is a reply.
  final String? replySenderName;

  /// Already formatted reply text, if there is a reply.
  final String? replyPreview;

  final bool highlighted;
  final VoidCallback? onReplyTap;
  final void Function(LongPressStartDetails details)? onLongPressStart;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.isNostrCyber,
    required this.bubbleColor,
    required this.textColor,
    required this.footer,
    required this.imageFooter,
    this.previewUrl,
    this.replySenderName,
    this.replyPreview,
    this.highlighted = false,
    this.onReplyTap,
    this.onLongPressStart,
  });

  static const double _maxWidthFactor = 0.90;
  static const double _sideMargin = 50;
  static const double _outerMargin = 12;
  static const double _horizontalPadding = 10;

  /// Rough width of the time and ticks, so a short message leaves room for them
  /// on the right instead of putting them on their own line.
  static const double _footerReserve = 64;

  /// Space between a short message and its time.
  static const double _textGap = 8;

  @override
  Widget build(BuildContext context) {
    final hasReactions = message.reactions.isNotEmpty;
    final emojiCount = (!message.isImage && !message.isVoiceNote)
        ? emojiOnlyCount(message.plaintext)
        : null;
    final hasReply = replyPreview != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
        const margins = _sideMargin + _outerMargin;
        final maxBubbleWidth = math.min(
          available * _maxWidthFactor,
          math.max(0.0, available - margins),
        );
        final maxContentWidth = math.max(
          0.0,
          maxBubbleWidth - _horizontalPadding * 2,
        );

        if (emojiCount != null && !hasReply) {
          return _buildEmojiOnly(
            context,
            hasReactions,
            maxBubbleWidth,
            emojiCount,
          );
        }
        return _buildBubble(
          context,
          hasReactions,
          maxBubbleWidth,
          maxContentWidth,
          emojiCount,
        );
      },
    );
  }

  Widget _buildBubble(
    BuildContext context,
    bool hasReactions,
    double maxBubbleWidth,
    double maxContentWidth,
    int? emojiCount,
  ) {
    final hasReply = replyPreview != null;
    final hasPreview = previewUrl != null;

    return Padding(
      padding: EdgeInsets.only(bottom: hasReactions ? 25 : 2),
      child: Container(
        decoration: _highlightDecoration,
        child: GestureDetector(
          onLongPressStart: onLongPressStart,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: const Key('message_bubble_surface'),
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                margin: EdgeInsetsDirectional.only(
                  start: isMe ? _sideMargin : _outerMargin,
                  end: isMe ? _outerMargin : _sideMargin,
                ),
                padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  0,
                  _horizontalPadding,
                  6,
                ),
                decoration: _bubbleDecoration,
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasReply) _buildReply(context),
                      if (hasPreview)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxContentWidth,
                          ),
                          child: LinkPreviewCard(
                            key: ValueKey('${message.id}_$previewUrl'),
                            url: previewUrl!,
                            textColor: textColor,
                            backgroundColor: isNostrCyber
                                ? Colors.white.withAlpha(20)
                                : (isDark
                                    ? Colors.black.withAlpha(40)
                                    : Colors.black.withAlpha(15)),
                          ),
                        ),
                      const SizedBox(height: 4),
                      _buildContent(context, maxContentWidth, emojiCount),
                    ],
                  ),
                ),
              ),
              if (hasReactions)
                Positioned(
                  bottom: -21,
                  right: isMe ? 20 : null,
                  left: isMe ? null : 20,
                  child: _buildReactions(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiOnly(
    BuildContext context,
    bool hasReactions,
    double maxBubbleWidth,
    int emojiCount,
  ) {
    final hasReply = replyPreview != null;
    final textScaler = MediaQuery.textScalerOf(context).clamp(
      maxScaleFactor: 1.3,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: hasReactions ? 25 : 2),
      child: Container(
        decoration: _highlightDecoration,
        child: GestureDetector(
          onLongPressStart: onLongPressStart,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: isMe ? _sideMargin : _outerMargin,
                  end: isMe ? _outerMargin : _sideMargin,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (hasReply) _buildReply(context),
                      if (hasReply) const SizedBox(height: 4),
                      Text(
                        message.plaintext,
                        key: const Key('emoji_message'),
                        textAlign: TextAlign.left,
                        textScaler: textScaler,
                        style: TextStyle(
                          color: textColor,
                          fontSize: emojiFontSizeForCount(emojiCount),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        key: const Key('emoji_footer'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                            width: 0.5,
                          ),
                        ),
                        child: footer,
                      ),
                    ],
                  ),
                ),
              ),
              if (hasReactions)
                Positioned(
                  bottom: -21,
                  right: isMe ? 20 : null,
                  left: isMe ? null : 20,
                  child: _buildReactions(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    double maxContentWidth,
    int? emojiCount,
  ) {
    if (message.isImage) {
      // Keep the picture at its own size; a wide reply must not stretch it.
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImageBubble(
          key: ValueKey('img_${message.id}'),
          message: message,
          footer: imageFooter,
          maxWidth: maxContentWidth,
        ),
      );
    }

    if (message.isVoiceNote) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: VoiceNoteBubble(
          key: ValueKey('vn_${message.id}'),
          message: message,
          textColor: textColor,
          footer: footer,
        ),
      );
    }

    if (emojiCount != null) {
      // An emoji-only reply keeps a normal bubble so the quoted message and a
      // plain footer stay visible, but the emoji start at the smaller size.
      return _buildEmojiReplyContent(context, emojiCount);
    }

    final textStyle = DefaultTextStyle.of(context).style.merge(
          TextStyle(color: textColor, fontSize: 16),
        );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final textMax = maxContentWidth - _textGap - _footerReserve * textScale;

    if (_fitsOnOneLine(context, textStyle, textMax)) {
      // A short message keeps the bubble narrow. When a reply or a link preview
      // makes the bubble wider, the time moves to the far right edge.
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: Text(message.plaintext, style: textStyle)),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: _textGap),
            child: footer,
          ),
        ],
      );
    }

    // A long message uses the full bubble width and puts the time below it, at
    // the right edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message.plaintext, style: textStyle),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: footer,
        ),
      ],
    );
  }

  Widget _buildEmojiReplyContent(BuildContext context, int emojiCount) {
    final textScaler = MediaQuery.textScalerOf(context).clamp(
      maxScaleFactor: 1.3,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            message.plaintext,
            key: const Key('emoji_message'),
            textAlign: TextAlign.left,
            textScaler: textScaler,
            style: TextStyle(
              color: textColor,
              fontSize: emojiReplyFontSizeForCount(emojiCount),
              height: 1.2,
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: footer,
        ),
      ],
    );
  }

  /// Whether the message fits on one line, leaving room for the time.
  bool _fitsOnOneLine(
    BuildContext context,
    TextStyle style,
    double maxWidth,
  ) {
    if (maxWidth <= 0) return false;

    final painter = TextPainter(
      text: TextSpan(text: message.plaintext, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  Widget _buildReply(BuildContext context) {
    final nameColor =
        isNostrCyber ? const Color(0xFFD0BCFF) : const Color(0xFF2196F3);
    final backgroundColor = isNostrCyber
        ? Colors.white.withAlpha(20)
        : (isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15));
    final contentColor = isNostrCyber
        ? Colors.white70
        : (isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153));

    return GestureDetector(
      onTap: onReplyTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: const Key('reply_card'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(10),
            bottom: Radius.circular(10),
          ),
          border: Border(
            left: BorderSide(color: nameColor, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              replySenderName ?? '',
              style: TextStyle(
                color: nameColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              replyPreview ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: contentColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202C33) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: message.reactions.values
            .map(
              (emoji) => Text(
                emoji,
                style: const TextStyle(fontSize: 13),
              ),
            )
            .toList(),
      ),
    );
  }

  BoxDecoration get _highlightDecoration => BoxDecoration(
        color: highlighted ? Colors.blue.withAlpha(40) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      );

  BoxDecoration get _bubbleDecoration => BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        border: isDark && !isMe
            ? Border.all(color: Colors.white10, width: 0.5)
            : null,
      );
}
