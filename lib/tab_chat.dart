// tab_chat.dart

import 'widgets/confirm_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remixicon/remixicon.dart';
import 'room_chat.dart';
import 'relay_manager.dart';
import 'chat_manager.dart';
import 'call_overlay.dart';
import 'call_manager.dart';
import 'package:flutter/services.dart';
import 'services/app_settings.dart';
import 'services/chatme_toast.dart';
import 'story/story_manager.dart';
import 'story/story_prepare_page.dart';
import 'story/story_strip.dart';
import 'story/story_viewer_page.dart';
import 'package:image_picker/image_picker.dart';
import 'models/contact.dart';
import 'models/chat_message.dart';
import 'models/call_log.dart';
import 'core/theme/chatme_colors.dart';
import 'core/utils/time_utils.dart';
import 'core/utils/duration_utils.dart';
import 'core/utils/debug_logger.dart';
import 'widgets/user_avatar.dart';
import 'widgets/chatme_search_bar.dart';
import 'widgets/chatme_menu.dart';
import 'ui/contacts/contact_profile.dart';
import 'tab_calls.dart';

/// Marks every unread chat read with the same recipe as opening a room: one
/// batched local status write per chat, receipts only for the newest few
/// messages, then the badge and notification are cleared.
Future<void> markAllChatsAsRead(RelayManager relayManager) async {
  final peers = Hive.box<Contact>('contacts')
      .values
      .where((contact) => contact.unreadCount > 0)
      .map((contact) => contact.pubkey)
      .toList();

  for (final peer in peers) {
    try {
      final toAck =
          await ChatManager.instance.markIncomingAsRead(peerPubkey: peer);
      for (final id in toAck) {
        try {
          await relayManager.sendReceipt(id, peer, 'read');
        } catch (e) {
          DebugLogger.log('[Chat] mark-all-read receipt failed | $e',
              type: 'ERROR');
        }
      }
      await ChatManager.instance.clearUnreadCount(peer);
    } catch (e) {
      DebugLogger.log('[Chat] mark-all-read failed | $e', type: 'ERROR');
    }
  }
}

class ChatsScreen extends StatefulWidget {
  final RelayManager relayManager;

  const ChatsScreen({super.key, required this.relayManager});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _chatScrollController = ScrollController();
  String _searchQuery = "";
  bool _isMarkingAllRead = false;
  bool _isPreparingStory = false;
  bool _isPostingStory = false;
  bool _storyStripRevealed = false;
  double? _storyPullStartY;
  double _storyPullDistance = 0;
  bool _storyPullHapticFired = false;

  static const double _storyPullThreshold = 56;

  @override
  void initState() {
    super.initState();
    widget.relayManager.onMessageReceived = () {
      if (mounted) setState(() {});
    };

    widget.relayManager.onMessageDelivered = (eventId) {
      if (mounted) setState(() {});
    };

    StoryManager.instance.revision.addListener(_onStoryRevisionChanged);
  }

  @override
  void dispose() {
    StoryManager.instance.revision.removeListener(_onStoryRevisionChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onStoryRevisionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _hasActiveStories => Hive.isBoxOpen('stories') &&
      StoryManager.instance.activeStories().isNotEmpty;

  bool get _storyStripVisible => _storyStripRevealed || _hasActiveStories;

  bool get _canRevealStoryStrip => !_storyStripVisible && _searchQuery.isEmpty;

  bool get _isChatListAtTop =>
      !_chatScrollController.hasClients || _chatScrollController.offset <= 0;

  void _onPullDownStart(PointerDownEvent event) {
    if (!_canRevealStoryStrip) return;
    _storyPullStartY = event.position.dy;
    _storyPullDistance = 0;
    _storyPullHapticFired = false;
  }

  void _onPullDownMove(PointerMoveEvent event) {
    final startY = _storyPullStartY;
    if (startY == null || !_canRevealStoryStrip) return;
    if (!_isChatListAtTop) {
      _resetPullDown();
      return;
    }

    final dy = event.position.dy - startY;
    if (dy <= 0) return;
    _storyPullDistance = dy;
    if (_storyPullDistance >= _storyPullThreshold && !_storyPullHapticFired) {
      HapticFeedback.mediumImpact();
      _storyPullHapticFired = true;
    }
  }

  void _onPullDownEnd(PointerUpEvent event) => _finishPullDown();

  void _onPullDownCancel(PointerCancelEvent event) => _finishPullDown();

  void _finishPullDown() {
    if (_canRevealStoryStrip && _storyPullDistance >= _storyPullThreshold) {
      setState(() => _storyStripRevealed = true);
    }
    _resetPullDown();
  }

  void _resetPullDown() {
    _storyPullStartY = null;
    _storyPullDistance = 0;
    _storyPullHapticFired = false;
  }

  Future<void> _markAllChatsAsRead() {
    if (!mounted || _isMarkingAllRead) return Future.value();
    _isMarkingAllRead = true;
    return markAllChatsAsRead(widget.relayManager).whenComplete(() {
      if (mounted) _isMarkingAllRead = false;
    });
  }

  /// Calls no longer own a bottom tab, so missed calls need their own quiet
  /// marker. A timestamp in the existing settings box avoids touching the
  /// Hive CallLog model or any live call state.
  static const String _callsHistorySeenKey = 'calls_history_seen_at';

  bool _hasUnseenMissedCalls(Box<CallLog> logs) {
    final seen =
        Hive.box('settings').get(_callsHistorySeenKey, defaultValue: 0) as int;
    return logs.values.any((log) => log.isMissed && log.timestamp > seen);
  }

  Future<void> _openCallsHistory() async {
    await Hive.box('settings')
        .put(_callsHistorySeenKey, DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CallsScreen(relayManager: widget.relayManager),
      ),
    );
    // A call can land while the history page is open. It was visible there, so
    // returning must not light the dot again for something already seen.
    await Hive.box('settings')
        .put(_callsHistorySeenKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() {});
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: ChatmeColors.textSecondary, fontSize: 14),
      );
    }

    final List<TextSpan> spans = [];
    final String lowercaseText = text.toLowerCase();
    final String lowercaseQuery = query.toLowerCase();

    int start = 0;
    int indexOfHighlight;

    while ((indexOfHighlight = lowercaseText.indexOf(lowercaseQuery, start)) !=
        -1) {
      // Text before highlighted segment
      if (indexOfHighlight > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfHighlight)));
      }

      // Highlighted segment (bold)
      spans.add(TextSpan(
        text: text.substring(indexOfHighlight, indexOfHighlight + query.length),
        style: const TextStyle(
          color: ChatmeColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = indexOfHighlight + query.length;
    }

    // Remaining text after last highlight
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: ChatmeColors.textSecondary, fontSize: 14),
        children: spans,
      ),
    );
  }

  Widget _buildStatusIcon(String status, Color color) {
    switch (status) {
      case 'pending':
      case 'sending':
        return Icon(Icons.access_time_rounded,
            size: 13, color: color.withAlpha(120));
      case 'sent':
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
      case 'read':
        return ValueListenableBuilder(
          valueListenable:
              Hive.box('settings').listenable(keys: ['read_receipts_enabled']),
          builder: (context, _, __) {
            if (!AppSettings.instance.readReceiptsEnabled) {
              return Icon(Icons.done, size: 13, color: color.withAlpha(153));
            }
            return const Icon(Icons.done_all,
                size: 13, color: ChatmeColors.accentPrimary);
          },
        );
      case 'error':
        return const Icon(Icons.error_outline,
            size: 13, color: ChatmeColors.statusDanger);
      default:
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: const Text(
            'Chatme',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: ChatmeColors.accentPrimary,
            ),
          ),
          actions: [
            if (_isPostingStory)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: ChatmeColors.accentPrimary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ValueListenableBuilder<Box<CallLog>>(
              valueListenable: Hive.box<CallLog>('call_logs').listenable(),
              builder: (context, logs, _) {
                return ChatmeMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: Theme.of(context).iconTheme.color),
                  entries: [
                    const ChatmeMenuEntry(
                      value: 'mark_all_read',
                      label: 'Mark all as read',
                    ),
                    ChatmeMenuEntry(
                      value: 'calls_history',
                      label: 'Calls History',
                      dot: _hasUnseenMissedCalls(logs),
                    ),
                    const ChatmeMenuEntry(
                      value: 'add_story',
                      label: 'Add story',
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'mark_all_read') _markAllChatsAsRead();
                    if (value == 'calls_history') _openCallsHistory();
                    if (value == 'add_story') _addStory();
                  },
                );
              },
            ),
          ],
          elevation: 0,
        ),
        body: Column(
          children: [
            if (_searchQuery.isEmpty && _storyStripVisible)
              StoryStrip(
                relayManager: widget.relayManager,
                onAddStory: _addStory,
                onOpenAuthor: _openStoryAuthor,
              ),
            ChatmeSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'Search contact or messages',
              onChanged: (val) {
                setState(() => _searchQuery = val.toLowerCase());
              },
              onClear: () => setState(() => _searchQuery = ""),
            ),
            ValueListenableBuilder<CallState>(
              valueListenable: CallManager.instance.callStateNotifier,
              builder: (context, callState, _) {
                if (callState == CallState.idle ||
                    callState == CallState.ending ||
                    callState == CallState.error) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: CallFloatingBar(relay: widget.relayManager),
                );
              },
            ),
            Expanded(
              child: Listener(
                onPointerDown: _onPullDownStart,
                onPointerMove: _onPullDownMove,
                onPointerUp: _onPullDownEnd,
                onPointerCancel: _onPullDownCancel,
                child: ValueListenableBuilder<Box<Contact>>(
                valueListenable: Hive.box<Contact>('contacts').listenable(),
                builder: (context, contactBox, _) {
                  return ValueListenableBuilder(
                    // Registry listenable: one rebuild of the chat list per
                    // flushed batch (the registry is touched once per chat).
                    valueListenable: Hive.box('chats').listenable(),
                    builder: (context, Box chatRegistry, _) {
                      final myPubkey = AppSettings.instance.myPubkey;
                      final contactList = contactBox.values.toList();

                      // 1. Filter saved contacts by name (only during search)
                      List<Contact> filteredSavedContacts = [];
                      if (_searchQuery.isNotEmpty) {
                        filteredSavedContacts = contactList.where((c) {
                          return c.isSaved &&
                              c.name.toLowerCase().contains(_searchQuery);
                        }).toList();
                      }

                      // 2. Chat previews (name or pubkey match)
                      List<Map<String, dynamic>> chatPreviews = [];

                      // 3. Message body matches
                      List<Map<String, dynamic>> messageResults = [];

                      for (var contact in contactList) {
                        final String displayName =
                            AppSettings.getContactDisplayName(contact);

                        bool nameMatches = _searchQuery.isNotEmpty &&
                              (displayName
                                      .toLowerCase()
                                      .contains(_searchQuery) ||
                                contact.pubkey
                                    .toLowerCase()
                                    .contains(_searchQuery));

                        // Only inspect messages when searching message bodies
                        if (_searchQuery.length >= 2) {
                          final chatKey = ChatManager.instance
                              .getChatKey(myPubkey, contact.pubkey);
                          for (var m in ChatManager.instance
                              .messagesForChatSync(chatKey)) {
                            if (m.plaintext
                                .toLowerCase()
                                .contains(_searchQuery)) {
                              messageResults.add({
                                'contact': contact,
                                'message': m,
                              });
                            }
                          }
                        }

                        if ((contact.lastChatTime > 0 ||
                                contact.lastMessage.isNotEmpty) &&
                            (_searchQuery.isEmpty || nameMatches)) {
                          chatPreviews.add({
                            'contact': contact,
                            'lastMsg': null,
                            'time': contact.lastChatTime,
                          });
                        }
                      }

                      // Sort chats by most recent
                      chatPreviews.sort((a, b) =>
                          (b['time'] as int).compareTo(a['time'] as int));

                      if (chatPreviews.isEmpty &&
                          filteredSavedContacts.isEmpty &&
                          messageResults.isEmpty) {
                        return _searchQuery.isEmpty
                            ? _buildEmptyState()
                            : _buildNoResultState();
                      }

                      return ListView(
                          controller: _chatScrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          // Contacts section (search only)
                          if (_searchQuery.isNotEmpty &&
                              filteredSavedContacts.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text("CONTACTS",
                                  style: TextStyle(
                                      color: ChatmeColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 1.2)),
                            ),
                              ...filteredSavedContacts.map((contact) =>
                                  _buildContactItem(contact, null)),
                            const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Divider(height: 1, thickness: 0.1)),
                          ],

                          // Chats section
                          if (chatPreviews.isNotEmpty) ...[
                            if (_searchQuery.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text("CHATS",
                                    style: TextStyle(
                                        color: ChatmeColors.textMuted,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 1.2)),
                              ),
                            ...chatPreviews.map((item) => _buildContactItem(
                                item['contact'] as Contact,
                                item['lastMsg'] as ChatMessage?)),
                            if (_searchQuery.isNotEmpty &&
                                messageResults.isNotEmpty)
                              const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                  child: Divider(height: 1, thickness: 0.1)),
                          ],

                          // Messages section (search only)
                          if (_searchQuery.isNotEmpty &&
                              messageResults.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text("MESSAGES",
                                  style: TextStyle(
                                      color: ChatmeColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 1.2)),
                            ),
                            ...messageResults.map((res) {
                              final contact = res['contact'] as Contact;
                              final msg = res['message'] as ChatMessage;
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                title: Text(
                                  AppSettings.getContactDisplayName(contact),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: ChatmeColors.textMuted),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (msg.senderPubkey == myPubkey)
                                      const Text("You: ",
                                          style: TextStyle(
                                                color:
                                                    ChatmeColors.accentPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                    Expanded(
                                      child: _buildHighlightedText(
                                          msg.plaintext, _searchQuery),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              ChatDetailScreen(
                                                contact: contact,
                                                relayManager:
                                                    widget.relayManager,
                                                initialMessageId: msg.id,
                                              )));
                                },
                              );
                            }),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 70, color: ChatmeColors.textSubtle),
          const SizedBox(height: 16),
          Text(
            'No results for "$_searchQuery"',
            style: const TextStyle(color: ChatmeColors.textMuted, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(Contact contact, ChatMessage? lastMsg) {
    final myPubkey = AppSettings.instance.myPubkey;
    final String displayName = AppSettings.getContactDisplayName(contact);

    final isMe = lastMsg?.senderPubkey == myPubkey;

    final String rawMessageText = lastMsg != null
        ? lastMsg.plaintext
        : (contact.lastMessage.isNotEmpty
            ? contact.lastMessage
            : 'Tap to start chatting');

    final bool isCall = rawMessageText.startsWith('[CALL]:');
    IconData? callIcon;
    Color? callIconColor;
    String callLabel = '';

    if (isCall) {
      final parts = rawMessageText.split(':');
      final direction = parts.length > 1 ? parts[1] : 'outgoing';
      final durationSeconds =
          parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;

      final bool isMissed = direction == 'missed';
      final bool isIncoming = direction == 'incoming';

      if (isMissed) {
        callIcon = Icons.call_missed;
        callIconColor = ChatmeColors.statusDanger;
        callLabel = 'Missed Call';
      } else if (isIncoming) {
        callIcon = Icons.call_received;
        callIconColor = ChatmeColors.textSecondary;
        callLabel = 'Incoming Call';
      } else {
        callIcon = Icons.call_made;
        callIconColor = ChatmeColors.textSecondary;
        callLabel = 'Outgoing Call';
      }

      if (durationSeconds > 0) {
        callLabel =
            '$callLabel (${DurationUtils.formatCallDuration(durationSeconds)})';
      }
    }

    return ListTile(
      leading: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ContactProfilePage(
                contact: contact,
                relayManager: widget.relayManager,
              ),
            ),
          );
        },
        child: UserAvatar(
          pubkey: contact.pubkey,
          name: displayName,
          radius: 26,
          relayManager: widget.relayManager,
        ),
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Theme.of(context).iconTheme.color,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (lastMsg != null && isMe && !isCall) ...[
              _buildStatusIcon(lastMsg.status, ChatmeColors.textSecondary),
              const SizedBox(width: 4),
            ],
            if (isCall && callIcon != null) ...[
              Icon(callIcon, size: 16, color: callIconColor),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                isCall ? callLabel : rawMessageText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: isCall && rawMessageText.contains(':missed:')
                      ? ChatmeColors.statusDanger
                      : ChatmeColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimeUtils.formatTimeHumanized(
                lastMsg?.timestamp ?? contact.lastChatTime),
            style: const TextStyle(fontSize: 11, color: ChatmeColors.textMuted),
          ),
          const SizedBox(height: 4),
          if (contact.unreadCount > 0)
            Badge.count(
              count: contact.unreadCount,
              backgroundColor: ChatmeColors.statusDanger,
              textColor: ChatmeColors.textPrimary,
            )
          else
            const SizedBox(height: 18),
        ],
      ),
      onLongPress: () => _showDeleteDialog(contact),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              contact: contact,
              relayManager: widget.relayManager,
            ),
          ),
        );
      },
    );
  }

  Future<void> _addStory() async {
    if (_isPreparingStory || _isPostingStory) return;
    _isPreparingStory = true;

    StoryPrepareResult? prepared;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMedia();
      if (picked == null || !mounted) return;

      prepared = await Navigator.of(context).push<StoryPrepareResult>(
        MaterialPageRoute(
          builder: (_) => StoryPreparePage(
            mediaPath: picked.path,
            isVideo:
                StoryPreparePage.isVideoMedia(picked.path, picked.mimeType),
          ),
        ),
      );
    } finally {
      if (mounted) _isPreparingStory = false;
    }
    if (prepared == null || !mounted || _isPostingStory) return;

    setState(() => _isPostingStory = true);
    try {
      await StoryManager.instance.createStory(
        relay: widget.relayManager,
        file: prepared.file,
        mimeType: prepared.mimeType,
        width: prepared.width,
        height: prepared.height,
        durationSeconds: prepared.durationSeconds,
        caption: prepared.caption,
      );
      if (!mounted) return;
      ChatmeToast.show('Story posted');
    } catch (e) {
      if (!mounted) return;
      ChatmeToast.show('Story failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isPostingStory = false);
      }
    }
  }

  void _openStoryAuthor(String authorPubkey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerPage(
          relayManager: widget.relayManager,
          initialAuthorPubkey: authorPubkey,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Remix.chat_3_line, size: 80, color: ChatmeColors.textSubtle),
          SizedBox(height: 20),
          Text('No conversations yet',
              style: TextStyle(color: ChatmeColors.textMuted)),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(Contact contact) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear chat history?',
      message:
          'All messages with ${contact.name} will be permanently deleted. This action cannot be undone.',
      confirmLabel: 'Delete all',
    );

    if (confirmed) {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = ChatManager.instance.getChatKey(myPubkey, contact.pubkey);
      await ChatManager.instance.deleteChatHistory(chatKey);
      if (!contact.isSaved) {
        await Hive.box<Contact>('contacts').delete(contact.pubkey);
      }
      HapticFeedback.vibrate();
    }

    _searchFocusNode.unfocus();
  }
}
