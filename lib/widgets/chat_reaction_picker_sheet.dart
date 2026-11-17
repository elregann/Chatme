// chat_reaction_picker_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/chat_reactions.dart';
import '../core/theme/chatme_colors.dart';

/// Shows the Chatme emoji reaction picker as a modal bottom sheet.
///
/// Returns the chosen emoji string, or `null` if the user dismissed the sheet.
Future<String?> showChatReactionPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: ChatmeColors.scrimStrong,
    elevation: 0,
    builder: (context) => const ChatReactionPickerSheet(),
  );
}

class ChatReactionPickerSheet extends StatefulWidget {
  const ChatReactionPickerSheet({super.key});

  @override
  State<ChatReactionPickerSheet> createState() => _ChatReactionPickerSheetState();
}

class _ChatReactionPickerSheetState extends State<ChatReactionPickerSheet> {
  int _selectedCategoryIndex = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onCategorySelected(int index) {
    if (_selectedCategoryIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedCategoryIndex = index);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final screenWidth = media.size.width;
    final bottomInset = media.padding.bottom;

    final sheetHeight = (screenHeight * 0.56).clamp(360.0, 560.0);
    final crossAxisCount = screenWidth < 360 ? 5 : (screenWidth > 600 ? 8 : 6);

    final currentCategory = ChatReactions.categories[_selectedCategoryIndex];

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: ChatmeColors.surfaceBase,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: ChatmeColors.borderSubtle,
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: ChatmeColors.textMuted.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header: Title + Badge + Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: ChatmeColors.accentPrimary.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ChatmeColors.accentPrimary.withAlpha(45),
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.emoji_emotions_rounded,
                    size: 18,
                    color: ChatmeColors.accentPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Reactions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ChatmeColors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap an emoji to react',
                        style: TextStyle(
                          fontSize: 12,
                          color: ChatmeColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ChatmeColors.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ChatmeColors.borderSubtle,
                        width: 0.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: ChatmeColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Categories horizontal list
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: ChatReactions.categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = ChatReactions.categories[index];
                final isSelected = _selectedCategoryIndex == index;

                return GestureDetector(
                  onTap: () => _onCategorySelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ChatmeColors.accentPrimary
                          : ChatmeColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? ChatmeColors.accentPrimary
                            : ChatmeColors.borderSubtle,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat.icon,
                          size: 15,
                          color: isSelected
                              ? ChatmeColors.onAccent
                              : ChatmeColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          cat.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? ChatmeColors.onAccent
                                : ChatmeColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 0.5, thickness: 0.5, color: ChatmeColors.dividerSubtle),

          // Emoji Grid
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: currentCategory.emojis.length,
              itemBuilder: (context, index) {
                final emoji = currentCategory.emojis[index];
                return _EmojiTile(
                  emoji: emoji,
                  onSelected: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context, emoji);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiTile extends StatefulWidget {
  final String emoji;
  final VoidCallback onSelected;

  const _EmojiTile({
    required this.emoji,
    required this.onSelected,
  });

  @override
  State<_EmojiTile> createState() => _EmojiTileState();
}

class _EmojiTileState extends State<_EmojiTile> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse().then((_) => widget.onSelected());
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: ChatmeColors.surfaceRaised.withAlpha(140),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ChatmeColors.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 26),
            ),
          ),
        ),
      ),
    );
  }
}
