// chat_reaction_popup.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/chat_reactions.dart';
import '../core/theme/chatme_colors.dart';
import '../models/chat_message.dart';

/// Interactive long-press popup for a chat bubble featuring a floating
/// quick-reaction bar and a Chatme contextual action menu.
class ChatReactionPopup extends StatefulWidget {
  final ChatMessage message;
  final Offset tapPosition;
  final bool isMe;
  final bool canReply;
  final ValueChanged<String> onReaction;
  final VoidCallback onMoreReactions;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  const ChatReactionPopup({
    super.key,
    required this.message,
    required this.tapPosition,
    required this.isMe,
    required this.canReply,
    required this.onReaction,
    required this.onMoreReactions,
    required this.onReply,
    required this.onCopy,
    required this.onDelete,
    required this.onDismiss,
  });

  @override
  State<ChatReactionPopup> createState() => _ChatReactionPopupState();
}

class _ChatReactionPopupState extends State<ChatReactionPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutQuad,
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _close([VoidCallback? afterClose]) async {
    if (_isClosing) return;
    _isClosing = true;
    await _animController.reverse();
    if (mounted) {
      widget.onDismiss();
      afterClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final topPadding = media.padding.top;
    final bottomPadding = media.padding.bottom;

    final hasText = widget.message.plaintext.isNotEmpty &&
        !widget.message.plaintext.startsWith('[CALL]:');

    // Approximate size of menu to avoid overflow
    const menuWidth = 286.0;
    const reactionBarHeight = 52.0;
    final actionMenuHeight = (widget.canReply ? 46.0 : 0.0) +
        (hasText ? 46.0 : 0.0) +
        46.0; // Delete is always available
    final totalContentHeight = reactionBarHeight + 8.0 + actionMenuHeight;

    // Smart vertical positioning: place below tap if tap is too high up
    final placeBelow = widget.tapPosition.dy < (topPadding + 140.0);
    double top;
    if (placeBelow) {
      top = (widget.tapPosition.dy + 12.0)
          .clamp(topPadding + 10.0, screenSize.height - totalContentHeight - bottomPadding - 10.0);
    } else {
      top = (widget.tapPosition.dy - totalContentHeight - 14.0)
          .clamp(topPadding + 10.0, screenSize.height - totalContentHeight - bottomPadding - 10.0);
    }

    // Smart horizontal positioning: align with bubble flow while staying in screen bounds
    double left;
    if (widget.isMe) {
      left = screenSize.width - menuWidth - 16.0;
    } else {
      left = 16.0;
    }
    left = left.clamp(12.0, screenSize.width - menuWidth - 12.0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Ambient blurred / tinted scrim
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _close(),
              behavior: HitTestBehavior.opaque,
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, _) => Container(
                  color: ChatmeColors.scrim.withAlpha((130 * _fadeAnimation.value).toInt()),
                ),
              ),
            ),
          ),

          // Floating popover
          Positioned(
            top: top,
            left: left,
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    alignment: placeBelow
                        ? (widget.isMe ? Alignment.topRight : Alignment.topLeft)
                        : (widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft),
                    child: child,
                  ),
                );
              },
              child: SizedBox(
                width: menuWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: placeBelow
                      ? [
                          _buildReactionBar(context),
                          const SizedBox(height: 8),
                          _buildActionMenu(context, hasText),
                        ]
                      : [
                          _buildActionMenu(context, hasText),
                          const SizedBox(height: 8),
                          _buildReactionBar(context),
                        ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionBar(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: ChatmeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: ChatmeColors.accentPrimary.withAlpha(45),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final emoji in ChatReactions.defaultQuickReactions)
            _QuickEmojiButton(
              emoji: emoji,
              onTap: () {
                _close(() => widget.onReaction(emoji));
              },
            ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: ChatmeColors.dividerSubtle,
          ),
          GestureDetector(
            onTap: () {
              _close(widget.onMoreReactions);
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ChatmeColors.accentPrimary.withAlpha(28),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ChatmeColors.accentPrimary.withAlpha(50),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: ChatmeColors.accentPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionMenu(BuildContext context, bool hasText) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: ChatmeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ChatmeColors.borderSubtle,
          width: 0.6,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canReply)
              _ActionRow(
                icon: Icons.reply_rounded,
                label: 'Reply',
                onTap: () => _close(widget.onReply),
              ),
            if (widget.canReply)
              const Divider(height: 0.5, thickness: 0.5, color: ChatmeColors.dividerSubtle),
            if (hasText) ...[
              _ActionRow(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () => _close(widget.onCopy),
              ),
              const Divider(height: 0.5, thickness: 0.5, color: ChatmeColors.dividerSubtle),
            ],
            _ActionRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: ChatmeColors.statusDanger,
              onTap: () => _close(widget.onDelete),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickEmojiButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _QuickEmojiButton({
    required this.emoji,
    required this.onTap,
  });

  @override
  State<_QuickEmojiButton> createState() => _QuickEmojiButtonState();
}

class _QuickEmojiButtonState extends State<_QuickEmojiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _bounceController.forward(),
      onTapUp: (_) => _bounceController.reverse().then((_) => widget.onTap()),
      onTapCancel: () => _bounceController.reverse(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: ScaleTransition(
            scale: _bounceAnimation,
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? ChatmeColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 19, color: itemColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: itemColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
