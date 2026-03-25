// room_chat.dart

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'call_manager.dart';
import 'relay_manager.dart';
import 'chat_manager.dart';
import 'core/crypto/nip04.dart';
import 'services/app_settings.dart';
import 'models/contact.dart';
import 'models/chat_message.dart';
import 'notification_handler.dart';
import 'package:remixicon/remixicon.dart';

class ChatDetailScreen extends StatefulWidget {
  final Contact contact;
  final RelayManager relayManager;

  const ChatDetailScreen({
    super.key,
    required this.contact,
    required this.relayManager,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isSending = false;
  bool _showScrollButton = false;
  bool _userIsNearBottom = true;
  bool _isUserScrolling = false;

  ChatMessage? _replyingTo;

  double _dragOffset = 0.0;
  String? _draggingId;

  int _newMessagesCount = 0;

  bool _isShortText(String text, BuildContext context) {
    const double timeWidth = 55;
    final maxWidth = MediaQuery.of(context).size.width * 0.70 - 80 - timeWidth;
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return !textPainter.didExceedMaxLines;
  }

  String _floatingDate = "";
  bool _showFloatingDate = false;

  Timer? _floatingDateTimer;
  Timer? _scrollIdleTimer;

  OverlayEntry? _reactionOverlayEntry;
  ChatMessage? _messageForReaction;
  final List<String> _quickReactions = ['👍', '❤️', '😂'];
  final List<String> _allReactions = [
    '👍', '❤️', '😂', '😮', '😢', '😡',
    '👏', '🎉', '🔥', '⭐', '❤️‍🔥', '🥹',
    '🥳', '🫠', '🙏', '💯', '✨', '💬',
    '👀', '🤔', '😎', '✅', '❌', '🚀',
    '🥰', '🤝', '🙌', '💪', '🫡', '🌹',
    '🤪', '🙈', '👻', '🍻', '🌈', '💤'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationHandler.clearNotification(widget.contact.pubkey);
    widget.relayManager.currentlyChattingWith = widget.contact.pubkey;
    widget.relayManager.onMessageReceived = () async {
      if (!mounted) return;

      _markAllAsRead();

      if (!_userIsNearBottom) {
        setState(() => _newMessagesCount++);
      }

      _maybeAutoScroll();
      setState(() {});
    };

    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAllAsRead();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationHandler.clearNotification(widget.contact.pubkey);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeReactionOverlay();

    widget.relayManager.currentlyChattingWith = null;
    widget.relayManager.onMessageReceived = null;

    _floatingDateTimer?.cancel();
    _scrollIdleTimer?.cancel();

    _scrollController.dispose();
    _focusNode.dispose();
    _messageController.dispose();

    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    _isUserScrolling = true;

    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(const Duration(milliseconds: 120), () {
      _isUserScrolling = false;
    });

    final offset = _scrollController.offset;

    final nearBottom = offset < 120;

    final showButton = offset > 600;

    if (nearBottom != _userIsNearBottom || showButton != _showScrollButton) {
      setState(() {
        _userIsNearBottom = nearBottom;
        _showScrollButton = showButton;
      });
    }

    if (offset > 200) {
      _updateFloatingDate();
    } else if (_showFloatingDate) {
      _hideFloatingDate();
    }
  }

  void _updateFloatingDate() {
    if (!_scrollController.hasClients) return;

    _floatingDateTimer?.cancel();

    final box = Hive.box('chats');
    final chatKey = ChatManager.instance.getChatKey(
      AppSettings.instance.myPubkey,
      widget.contact.pubkey,
    );

    final raw = box.get(chatKey);
    if (raw is! List || raw.isEmpty) return;

    final messages = raw.cast<ChatMessage>().toList();
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final double scrollOffset = _scrollController.offset;
    final double viewportHeight = _scrollController.position.viewportDimension;

    final double targetPoint = scrollOffset + (viewportHeight * 0.2);

    int index = (targetPoint / ( _scrollController.position.maxScrollExtent / messages.length )).floor();
    index = index.clamp(0, messages.length - 1);

    final label = _getDateLabel(messages[index].timestamp);

    if (label != _floatingDate) {
      setState(() {
        _floatingDate = label;
        _showFloatingDate = true;
      });
    }

    _floatingDateTimer = Timer(const Duration(milliseconds: 1200), _hideFloatingDate);
  }

  void _hideFloatingDate() {
    if (!mounted || !_showFloatingDate) return;
    setState(() => _showFloatingDate = false);
  }

  void _maybeAutoScroll({bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (_isUserScrolling && !force) return;

    if (force || _userIsNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollToBottom(force: force);
      });
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    setState(() => _newMessagesCount = 0); // Reset badge
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  // =============================
  // MESSAGE STATE
  // =============================

  Future<void> _markAllAsRead() async {
    if (!mounted) return;

    final peerPubkey = widget.contact.pubkey;

    final messages = await ChatManager.instance.getMessages(peerPubkey);

    bool updated = false;

    for (final m in messages) {
      if (m.senderPubkey == peerPubkey && m.status != 'read') {
        await widget.relayManager.sendReceipt(
          m.id,
          peerPubkey,
          'read',
        );
        await ChatManager.instance.updateMessageStatus(m.id, 'read');
        updated = true;
      }
    }

    if (updated && mounted) {
      await ChatManager.instance.clearUnreadCount(peerPubkey);
      setState(() {});
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final replyId = _replyingTo?.id;
    final replyContent = _replyingTo?.plaintext;

    _messageController.clear();
    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    final myPubkey = AppSettings.instance.myPubkey;
    final receiver = widget.contact.pubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, receiver);
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final tempMessage = ChatMessage(
      id: tempId,
      senderPubkey: myPubkey,
      receiverPubkey: receiver,
      content: '',
      plaintext: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'sending',
      chatKey: chatKey,
      replyToId: replyId,
      replyToContent: replyContent,
    );

    try {
      await ChatManager.instance.saveMessage(tempMessage);
      _maybeAutoScroll(force: true);

      final event = await widget.relayManager.sendMessage(
        receiverPubkey: receiver,
        plaintext: text,
        replyToId: replyId,
        replyToContent: replyContent,
      );

      await ChatManager.instance.updateMessageIdAndStatus(
          tempId,
          event['id'].toString(),
          'sending',
          chatKey
      );

      _maybeAutoScroll(force: true);
    } catch (e) {
      final offlineId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final myPrivkey = AppSettings.instance.myPrivkey;

      final encrypted = Nip04.encrypt(text, myPrivkey, receiver);

      final pendingMessage = tempMessage.copyWith(
        id: offlineId,
        content: encrypted,
        status: 'pending',
      );

      await ChatManager.instance.saveMessage(pendingMessage);
      await ChatManager.instance.deleteMessage(tempId, chatKey);

      debugPrint('Messages are saved to the pending queue because they are offline.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showReactionPopup(BuildContext context, Offset tapPosition, ChatMessage message) {
    _messageForReaction = message;
    _removeReactionOverlay();

    final screenWidth = MediaQuery.of(context).size.width;
    double centerX = (screenWidth / 2) - 120;

    _reactionOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeReactionOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: tapPosition.dy - 80,
              left: centerX,
              child: _buildReactionPopupContent(),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_reactionOverlayEntry!);
  }

  Widget _buildReactionPopupContent() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 46,
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 80 : 20),
                    blurRadius: 10,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._quickReactions.map((emoji) => _buildEmojiButton(emoji)),
                  _buildMoreButton(iconColor),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (_messageForReaction != null) {
                Clipboard.setData(ClipboardData(text: _messageForReaction!.plaintext));
                HapticFeedback.mediumImpact();
                _removeReactionOverlay();
              }
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 80 : 20),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(Icons.copy_rounded, size: 20, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return GestureDetector(
      onTap: () {
        _handleReaction(emoji);
        _removeReactionOverlay();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Widget _buildMoreButton(Color iconColor) {
    return GestureDetector(
      onTap: _showAllReactionsDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.add, color: iconColor.withAlpha(150), size: 24),
      ),
    );
  }

  void _handleReaction(String emoji) async {
    if (_messageForReaction == null) return;

    final targetMessage = _messageForReaction!;
    HapticFeedback.lightImpact();

    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = targetMessage.chatKey;
      final targetId = targetMessage.id;

      final box = Hive.box('chats');
      final dynamic raw = box.get(chatKey);

      if (raw is List) {
        final messages = raw.cast<ChatMessage>().toList();
        final index = messages.indexWhere((m) => m.id == targetId);

        if (index != -1) {
          final updatedMessage = messages[index].copyWith(
            reactions: {
              ...messages[index].reactions,
              myPubkey: emoji,
            },
          );

          messages[index] = updatedMessage;
          await box.put(chatKey, messages);

          if (mounted) setState(() {});
        }
      }

      await widget.relayManager.sendReaction(
        messageId: targetId,
        receiverPubkey: widget.contact.pubkey,
        emoji: emoji,
      );

      _messageForReaction = null;

    } catch (e) {
      debugPrint('❌ Error in _handleReaction: $e');
      _messageForReaction = null;
    }
  }

  void _showAllReactionsDialog() {
    FocusScope.of(context).unfocus();

    final backupMessage = _messageForReaction;
    _removeReactionOverlay();
    _messageForReaction = backupMessage;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 100 : 30),
                  blurRadius: 20,
                ),
              ],
            ),
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: _allReactions.length,
              itemBuilder: (context, index) {
                final emoji = _allReactions[index];
                return GestureDetector(
                  onTap: () {
                    _handleReaction(emoji);
                    Navigator.pop(context);
                  },
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _removeReactionOverlay() {
    if (_reactionOverlayEntry != null) {
      _reactionOverlayEntry!.remove();
      _reactionOverlayEntry = null;
    }
  }

  String _getDateLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final check = DateTime(date.year, date.month, date.day);

    if (check == today) return "Today";
    if (check == yesterday) return "Yesterday";
    if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date);
    }
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _getReplyName(String senderPubkey) {
    if (senderPubkey == AppSettings.instance.myPubkey) return "You";
    return widget.contact.isSaved
        ? widget.contact.name
        : "User ${senderPubkey.substring(0, 8)}";
  }

  Color _getAvatarColor(String pubkey) =>
      Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);

  String _getInitials(String name) =>
      name.isEmpty ? "?" : name.substring(0, 1).toUpperCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    String displayName = widget.contact.isSaved ? widget.contact.name : "User ${widget.contact.pubkey.substring(0, 8)}";
    final chatKey = ChatManager.instance.getChatKey(AppSettings.instance.myPubkey, widget.contact.pubkey);

    // Warna Header & Divider
    final headerColor = isDark ? const Color(0xFF121212) : Colors.white;
    final accentColor = isDark ? const Color(0xFF1976D2) : const Color(0xFF1976D2);
    final dividerBg = isDark ? const Color(0xFF182229) : const Color(0xFFFFFFFF).withAlpha(230);

    return Scaffold(
      backgroundColor: isDark
          // Background Roomchat
          ? const Color(0xFF121212)
          : const Color(0xFFE5DDD5),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: headerColor,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.contact.pubkey));
            HapticFeedback.lightImpact();
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _getAvatarColor(widget.contact.pubkey),
                child: Text(_getInitials(displayName),
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('${widget.contact.pubkey.substring(0, 16)}...',
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.phone_outlined, color: isDark ? Colors.white : Colors.black),
            onPressed: () {
              final String pubkey = widget.contact.pubkey;
              final int colorValue = int.tryParse(pubkey.substring(0, 8), radix: 16) ?? 0xFF000000;
              final Color warnaKontak = Color(colorValue | 0xFF000000);
              final currentContext = context;

              Future.delayed(Duration.zero, () {
                if (currentContext.mounted) {
                  CallManager.instance.startCallFlow(
                    context: currentContext,
                    peerName: displayName,
                    peerPubkey: pubkey,
                    relay: widget.relayManager,
                    peerColor: warnaKontak,
                  );
                }
              });
            },
          ),
          IconButton(
              icon: Icon(widget.contact.isSaved ? Remix.edit_2_fill : Remix.user_add_fill, color: isDark ? Colors.white : Colors.black),
              onPressed: _showSaveContactDialog
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Hive.box('chats').listenable(),
              builder: (context, Box box, _) {
                final dynamic rawData = box.get(chatKey);
                List<ChatMessage> messages = rawData is List ? rawData.cast<ChatMessage>().toList() : [];
                if (messages.isEmpty) return _buildEmptyState();

                messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        double topPadding = 1;

                        if (index < messages.length - 1) {
                          final nextMessage = messages[index + 1];
                          if (message.senderPubkey != nextMessage.senderPubkey) {
                            topPadding = 8;
                          }
                        }

                        bool showDateDivider = false;
                        if (index == messages.length - 1) {
                          showDateDivider = true;
                        } else {
                          final nextMessage = messages[index + 1];
                          final date = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
                          final prevDate = DateTime.fromMillisecondsSinceEpoch(nextMessage.timestamp);
                          if (date.day != prevDate.day || date.month != prevDate.month || date.year != prevDate.year) {
                            showDateDivider = true;
                          }
                        }

                        return Column(
                          children: [
                            if (showDateDivider) _buildDateDivider(_getDateLabel(message.timestamp)),
                            Padding(
                              padding: EdgeInsets.only(top: topPadding),
                              child: _wrapWithDismissible(message),
                            ),
                          ],
                        );
                      },
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _showFloatingDate ? 1.0 : 0.0,
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: dividerBg,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 4, offset: const Offset(0, 2))
                          ],
                        ),
                        child: Text(
                          _floatingDate,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
                        ),
                      ),
                    ),
                    if (_showScrollButton)
                      Positioned(
                        bottom: 20, // Sedikit lebih tinggi agar tidak menumpuk
                        right: 16, // Jarak ideal dari pinggir kanan
                        child: GestureDetector(
                          onTap: () => _scrollToBottom(),
                          child: Container(
                            width: 38, // Ukuran lingkaran kecil yang pas
                            height: 38,
                            decoration: BoxDecoration(
                              // Mengikuti tema minimalis Abu-abu/Hitam
                              color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black12,
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(20),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded, // Icon "v" halus
                              color: isDark ? Colors.white70 : Colors.black87,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildFloatingInputBar(),
        ],
      ),
    );
  }

  Widget _buildDateDivider(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF1976D2) : const Color(0xFF1976D2);
    final dividerBg = isDark ? const Color(0xFF182229) : const Color(0xFFFFFFFF).withAlpha(230);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: dividerBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 1)
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: accentColor
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingInputBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const double actionButtonSize = 38.0;
    const double containerHeight = 38.0;
    const accentColor = Color(0xFF1976D2);
    final inputBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            10,
            kIsWeb ? 20 : 6,
            10,
            kIsWeb ? 20 : 6
        ),
        child: Container(
          constraints: BoxConstraints(
            minHeight: 38,
            maxHeight: _replyingTo != null ? 230 : 180,
          ),
          decoration: BoxDecoration(
            color: inputBgColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 30 : 15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo != null) _buildReplyPreviewInside(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 5,
                        minLines: 1,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: kIsWeb ? 10 : 8,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  // Tombol Send
                  Container(
                    height: containerHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.only(right: 4, left: 10),
                    child: GestureDetector(
                      onTap: _isSending ? null : _sendMessage,
                      child: Transform.translate(
                        offset: const Offset(0, -4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: actionButtonSize,
                          width: actionButtonSize,
                          decoration: const BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: _isSending
                                ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreviewInside() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Nama tetap Biru sesuai permintaan
    final nameColor = isDark ? const Color(0xFF1976D2) : const Color(0xFF1976D2);

    // Background Kotak
    final bgColor = isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15);

    final previewTextColor = isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153);

    final iconThemeColor = isDark ? Colors.white70 : Colors.black87;

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(18), // Kiri kanan atas bagian reply dalam
            bottom: Radius.circular(8)
        ),
      ),
      child: Row(
        children: [
          // Ikon Reply warna tema flat
          Icon(Icons.reply, color: iconThemeColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _getReplyName(_replyingTo!.senderPubkey),
                    style: TextStyle(
                        color: nameColor, // Tetap Biru
                        fontWeight: FontWeight.bold,
                        fontSize: 12
                    )
                ),
                Text(
                    _replyingTo!.plaintext,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: previewTextColor,
                        fontSize: 12
                    )
                ),
              ],
            ),
          ),
          IconButton(
              icon: Icon(
                  Icons.close,
                  size: 20,
                  color: iconThemeColor
              ),
              onPressed: () => setState(() => _replyingTo = null),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero
          ),
        ],
      ),
    );
  }

  Widget _wrapWithDismissible(ChatMessage message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0 || _dragOffset > 0) {
          setState(() {
            _draggingId = message.id;
            double resistance = 0.6;
            if (_dragOffset > 30) resistance = 0.3;
            _dragOffset += details.delta.dx * resistance;
            if (_dragOffset > 70) _dragOffset = 70;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset >= 45) {
          HapticFeedback.mediumImpact();
          setState(() => _replyingTo = message);
          _focusNode.requestFocus();
        }
        setState(() {
          _dragOffset = 0;
          _draggingId = null;
        });
      },
      child: Container(
        color: Colors.transparent,
        transform: Matrix4.translationValues(
            _draggingId == message.id ? _dragOffset : 0, 0, 0
        ),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (_draggingId == message.id)
              SizedBox(
                width: (_dragOffset * 0.6).clamp(0.0, 46.0),
                child: Opacity(
                  opacity: (_dragOffset / 40).clamp(0.0, 1.0),
                  child: Center(
                    child: Transform.scale(
                      scale: (_dragOffset / 50).clamp(0.0, 1.0),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black12,
                            width: 0.5,
                          ),
                        ),
                        child: Icon(
                          Icons.reply_rounded,
                          color: isDark ? Colors.white70 : Colors.black87,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: _buildMessageBubble(message),
            ),
          ],
        ),
      ),
    );
  }

  //Mengatur jarak Bubble Pesan dan ketika ada reaksi pada pesan (FIX)
  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;
    final isDark = theme.brightness == Brightness.dark;

    // LOGIKA JAM
    final is24Hour = MediaQuery.of(context).alwaysUse24HourFormat;
    final timeStr = DateFormat(is24Hour ? 'HH:mm' : 'h:mm a').format(
        DateTime.fromMillisecondsSinceEpoch(message.timestamp)
    );

    // Tema Bubble
    final bubbleColor = isMe
        ? (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE3F2FD))
        : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF));

    // Teks: Terang (Hitam), Gelap (Putih)
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    final hasReactions = message.reactions.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: hasReactions ? 25 : 2),
        child: GestureDetector(
          onLongPressStart: (details) => _showReactionPopup(context, details.globalPosition, message),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
                margin: EdgeInsets.only(
                  left: isMe ? 50 : 12,
                  right: isMe ? 12 : 50,
                ),
                decoration: BoxDecoration(
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
                ),
                padding: const EdgeInsets.only(left: 10, right: 10, top: 0, bottom: 6),

                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message.replyToContent != null)
                        _buildReplyInBubble(message, isMe),

                      const SizedBox(height: 4),

                      (_isShortText(message.plaintext, context))
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              message.plaintext,
                              style: TextStyle(color: textColor, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(timeStr, style: TextStyle(color: textColor.withAlpha(153), fontSize: 11)),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                _buildStatusIcon(message.status, textColor),
                              ],
                            ],
                          ),
                        ],
                      )

                          : Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              message.plaintext,
                              style: TextStyle(color: textColor, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(timeStr, style: TextStyle(color: textColor.withAlpha(153), fontSize: 11)),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                _buildStatusIcon(message.status, textColor),
                              ],
                            ],
                          ),
                        ],
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
                  child: _buildReactionsDisplay(message, isMe, textColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyInBubble(ChatMessage message, bool isMe) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String senderName = isMe
        ? (widget.contact.isSaved ? widget.contact.name : "User ${widget.contact.pubkey.substring(0, 8)}")
        : "You";

    const nameColor = Color(0xFF1976D2);
    final bgColor = isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15);
    final contentColor = isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153);

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(10),
            bottom: Radius.circular(10)
        ),
        border: const Border(
          left: BorderSide(
              color: nameColor,
              width: 4
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: const TextStyle(
              color: nameColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            message.replyToContent ?? "",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: contentColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // display reactions
  Widget _buildReactionsDisplay(ChatMessage message, bool isMe, Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: message.reactions.entries.map((e) {
          return Text(
            e.value,
            style: const TextStyle(fontSize: 13),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusIcon(String status, Color color) {
    switch (status) {
      case 'pending':
      case 'sending':
        return Icon(Icons.access_time_rounded, size: 13, color: color.withAlpha(120));
      case 'sent':
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
      case 'read':
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF34B7F1));
      case 'error':
        return const Icon(Icons.error_outline, size: 13, color: Colors.redAccent);
      default:
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
    }
  }

  Widget _buildEmptyState() {
    return Center(
        child: Opacity(
            opacity: 0.5,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 48),
                  const SizedBox(height: 16),
                  Text('No messages yet with ${widget.contact.name}')
                ]
            )
        )
    );
  }

  Future<void> _showSaveContactDialog() async {
    final nameController = TextEditingController(text: widget.contact.isSaved ? widget.contact.name : "");
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.contact.isSaved ? 'Rename contact' : 'Save contact',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Give a name to this identity.',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withAlpha(30), width: 0.5),
                    ),
                    child: Icon(
                      widget.contact.isSaved ? Remix.edit_2_fill : Remix.user_add_fill,
                      size: 18,
                      color: Colors.blue.withAlpha(200),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Divider(height: 0.5, thickness: 0.5, color: borderColor),

              const SizedBox(height: 16),

              // Input
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter name',
                    hintStyle: TextStyle(fontSize: 14, color: textSecondary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(fontSize: 13, color: textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final currentContext = context;
                        if (nameController.text.trim().isNotEmpty) {
                          widget.contact.name = nameController.text.trim();
                          widget.contact.isSaved = true;
                          Hive.box<Contact>('contacts').put(widget.contact.pubkey, widget.contact).then((_) {
                            HapticFeedback.lightImpact();
                            if (currentContext.mounted) {
                              setState(() {});
                              Navigator.pop(currentContext);
                            }
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withAlpha(40), width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.withAlpha(200),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}