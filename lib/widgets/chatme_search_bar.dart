// chatme_search_bar.dart

import 'package:flutter/material.dart';

import '../core/theme/chatme_colors.dart';

/// The one search bar used on the Chats and Contacts tabs. Icons are plain
/// Row children and the field is centered by the Row, so the text position
/// does not depend on the font metrics of the device.
class ChatmeSearchBar extends StatelessWidget {
  const ChatmeSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  static const double height = 48;
  static const double _sideWidth = 48;

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  void _clear() {
    controller.clear();
    onClear();
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: focusNode.requestFocus,
        child: Container(
          key: const Key('chatme-search-bar'),
          height: height,
          decoration: BoxDecoration(
            color: ChatmeColors.surfaceMenu,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: _sideWidth,
                child: Icon(
                  Icons.search_rounded,
                  color: ChatmeColors.textMuted,
                  size: 20,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: ChatmeColors.textMuted,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  if (controller.text.isEmpty) {
                    return const SizedBox(width: 12);
                  }
                  return IconButton(
                    key: const Key('chatme-search-clear'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: _sideWidth,
                      height: _sideWidth,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _clear,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
