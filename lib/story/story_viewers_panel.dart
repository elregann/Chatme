import 'package:flutter/material.dart';

import '../widgets/chatme_menu.dart';

class StoryViewerEntry {
  final String pubkey;
  final String name;

  const StoryViewerEntry({required this.pubkey, required this.name});
}

class StoryViewersPanel extends StatefulWidget {
  final int viewCount;
  final List<StoryViewerEntry> viewers;
  final VoidCallback onDelete;
  final ValueChanged<String> onMessageViewer;
  final ValueChanged<bool>? onExpandedChanged;
  final Widget Function(String pubkey, String name)? avatarBuilder;

  const StoryViewersPanel({
    super.key,
    required this.viewCount,
    required this.viewers,
    required this.onDelete,
    required this.onMessageViewer,
    this.onExpandedChanged,
    this.avatarBuilder,
  });

  @override
  State<StoryViewersPanel> createState() => _StoryViewersPanelState();
}

class _StoryViewersPanelState extends State<StoryViewersPanel> {
  bool _open = false;

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
    widget.onExpandedChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _buildPill(),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setOpen(false),
            child: const SizedBox.expand(),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildPill() {
    return GestureDetector(
      onTap: () => _setOpen(true),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ChatmeMenu.darkColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${widget.viewCount} views',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return SizedBox(
      width: 320,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: ChatmeMenu.darkColor,
          borderRadius: BorderRadius.circular(ChatmeMenu.radius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Viewed by ${widget.viewCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ChatmeMenuButton<int>(
                    icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                    color: ChatmeMenu.darkColor,
                    textColor: Colors.white,
                    entries: const [
                      ChatmeMenuEntry<int>(value: 0, label: 'Delete story'),
                    ],
                    onSelected: (_) => widget.onDelete(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Flexible(
              child: widget.viewers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No viewers yet',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: widget.viewers.length,
                      itemBuilder: (context, index) {
                        final viewer = widget.viewers[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              widget.avatarBuilder?.call(
                                    viewer.pubkey,
                                    viewer.name,
                                  ) ??
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.white24,
                                    child: Text(
                                      viewer.name.isNotEmpty
                                          ? viewer.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  viewer.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    widget.onMessageViewer(viewer.pubkey),
                                behavior: HitTestBehavior.opaque,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Message',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
