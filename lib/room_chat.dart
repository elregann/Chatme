// room_chat.dart

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:anchored_list/anchored_list.dart';
import 'call_manager.dart';
import 'call_overlay.dart';
import 'relay_manager.dart';
import 'chat_manager.dart';
import 'services/app_settings.dart';
import 'models/contact.dart';
import 'models/chat_message.dart';
import 'notification_handler.dart';
import 'package:remixicon/remixicon.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/duration_utils.dart';
import 'widgets/user_avatar.dart';
import 'ui/contacts/contact_profile.dart';
import 'core/utils/shortcut_helper.dart';
import 'services/link_preview_service.dart';
import 'widgets/link_preview_card.dart';
import 'widgets/voice_note_bubble.dart';
import 'services/just_audio_backend.dart';
import 'services/record_backend.dart';
import 'services/voice_recorder.dart';
import 'package:cached_network_image/cached_network_image.dart';

const double _composerBarHeight = 52.0;
const double _composerBarRadius = 26.0;
const double _composerBarInset = 6.0;
const double _composerInnerRadius = _composerBarRadius - _composerBarInset;
const double _composerSendSize = 42.0;

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
  final FocusNode _focusNode = FocusNode();

  final AnchoredListController _anchoredController = AnchoredListController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> _cachedMessages = [];
  int _previousMessageCount = -1;

  bool _isSending = false;
  bool _hasText = false;
  bool _isRecording = false;
  Timer? _recordTicker;
  bool _showScrollButton = false;
  bool _userIsNearBottom = true;
  bool _isUserScrolling = false;
  bool _isCompensatingScroll = false;

  ChatMessage? _replyingTo;
  final Set<String> _highlightedIds = {};

  Timer? _previewDebounce;
  String? _composerUrl;
  String? _dismissedUrl;
  LinkPreviewData? _composerPreview;

  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  String? _draggingId;

  int _newMessagesCount = 0;

  bool _isMarkingRead = false;
  bool _markReadAgain = false;
  bool _suppressChatRebuild = false;
  Widget? _lastChatListWidget;

  bool _isShortText(String text, BuildContext context) {
    const double timeWidth = 55;
    final maxWidth = MediaQuery.of(context).size.width * 0.90 - 80 - timeWidth;
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
    NotificationHandler.activeChatPubkey = widget.contact.pubkey;
    widget.relayManager.onMessageReceived = () async {
      if (!mounted) return;

      if (_userIsNearBottom) {
        _markAllAsRead();
      } else {
        setState(() => _newMessagesCount++);
      }

      setState(() {});
    };

    _anchoredController.itemPositions.addListener(_handlePositionsChanged);
    _scrollController.addListener(_handleScrollChanged);
    _messageController.addListener(_onComposerChanged);
    _messageController.addListener(_onTextPresenceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAllAsRead();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationHandler.clearNotification(widget.contact.pubkey);
    }
    if (_isRecording &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      _cancelRecording();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeReactionOverlay();
    stopVoicePlayer();
    _recordTicker?.cancel();
    cancelVoiceRecording();

    widget.relayManager.currentlyChattingWith = null;
    NotificationHandler.activeChatPubkey = null;
    widget.relayManager.onMessageReceived = null;

    _floatingDateTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _previewDebounce?.cancel();

    _anchoredController.itemPositions.removeListener(_handlePositionsChanged);
    _anchoredController.dispose();
    _scrollController.dispose();

    _dragOffsetNotifier.dispose();
    _focusNode.dispose();
    _messageController.removeListener(_onComposerChanged);
    _messageController.removeListener(_onTextPresenceChanged);
    _messageController.dispose();

    super.dispose();
  }

  void _handlePositionsChanged() {
    if (_isCompensatingScroll) return;

    final positions = _anchoredController.itemPositions.value;
    if (positions.isEmpty) return;

    _isUserScrolling = true;

    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(const Duration(milliseconds: 120), () {
      _isUserScrolling = false;
    });
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) return;

    final double viewportHeight = _scrollController.position.viewportDimension;
    if (viewportHeight <= 0) return;

    final bool nearBottom = _scrollController.position.pixels <= 100;
    final bool showButton = !nearBottom && _scrollController.position.pixels > (viewportHeight * 0.2);

    if (nearBottom != _userIsNearBottom || showButton != _showScrollButton) {
      final bool wasAwayFromBottom = !_userIsNearBottom;
      setState(() {
        _userIsNearBottom = nearBottom;
        _showScrollButton = showButton;
      });
      if (nearBottom && wasAwayFromBottom) {
        setState(() => _newMessagesCount = 0);
        _markAllAsRead();
      }
    }
  }

  void _updateFloatingDate() {
    if (_cachedMessages.isEmpty) return;

    final positions = _anchoredController.itemPositions.value;
    if (positions.isEmpty) return;

    int maxIndex = 0;
    int minIndex = _cachedMessages.length;
    for (final p in positions) {
      if (p.index > maxIndex) maxIndex = p.index;
      if (p.index < minIndex) minIndex = p.index;
    }
    if (maxIndex >= _cachedMessages.length) return;

    if (minIndex == 0) {
      _floatingDateTimer?.cancel();
      if (_showFloatingDate) _hideFloatingDate();
      return;
    }

    final label = _getDateLabel(_cachedMessages[maxIndex].timestamp);

    if (label != _floatingDate || !_showFloatingDate) {
      setState(() {
        _floatingDate = label;
        _showFloatingDate = true;
      });
    }

    _floatingDateTimer?.cancel();
    _floatingDateTimer = Timer(
      const Duration(milliseconds: 1500),
      _hideFloatingDate,
    );
  }

  void _hideFloatingDate() {
    if (!mounted || !_showFloatingDate) return;
    setState(() => _showFloatingDate = false);
  }

  void _maybeAutoScroll({bool force = false}) {
    if (!_anchoredController.isAttached) return;
    if (_isUserScrolling && !force) return;

    if (force || _userIsNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_anchoredController.isAttached) return;
        _scrollToBottom(force: force);
      });
    }
  }

  void _scrollToMessage(String? messageId) {
    if (messageId == null) return;
    if (!_anchoredController.isAttached) return;
    if (_cachedMessages.isEmpty) return;

    final index = _cachedMessages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    _anchoredController.animateToIndex(
      index,
      alignment: 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    setState(() => _highlightedIds.add(messageId));
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlightedIds.remove(messageId));
    });
  }

  void _scrollToBottom({bool force = false}) {
    if (!_anchoredController.isAttached) return;
    setState(() => _newMessagesCount = 0);
    _markAllAsRead();
    _anchoredController.animateToIndex(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _markAllAsRead() async {
    if (!mounted) return;
    if (_isMarkingRead) {
      _markReadAgain = true;
      return;
    }
    _isMarkingRead = true;
    final peerPubkey = widget.contact.pubkey;
    final myPubkey = AppSettings.instance.myPubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, peerPubkey);

    try {
      do {
        _markReadAgain = false;

        final messages = await ChatManager.instance.getMessages(peerPubkey);
        final unread = messages
            .where((m) => m.senderPubkey == peerPubkey && m.status != 'read')
            .toList();
        if (unread.isEmpty) continue;

        final sentIds = <String>[];
        for (final m in unread) {
          if (!mounted) break;
          try {
            await widget.relayManager.sendReceipt(m.id, peerPubkey, 'read');
            sentIds.add(m.id);
          } catch (e) {
            DebugLogger.log('[Chat] sendReceipt failed | $e', type: 'ERROR');
          }
        }
        if (sentIds.isEmpty) continue;

        _suppressChatRebuild = true;
        try {
          for (final id in sentIds) {
            try {
              // Pass chatKey directly to avoid a full scan of all chat boxes.
              await ChatManager.instance.updateMessageStatus(id, 'read', chatKey: chatKey);
            } catch (e) {
              DebugLogger.log('[Chat] updateMessageStatus failed | $e', type: 'ERROR');
            }
          }
        } finally {
          _suppressChatRebuild = false;
        }

        await ChatManager.instance.clearUnreadCount(peerPubkey);
        if (mounted) setState(() {});
      } while (_markReadAgain && mounted);
    } catch (e) {
      DebugLogger.log('[Chat] markAllAsRead failed | $e', type: 'ERROR');
    } finally {
      _isMarkingRead = false;
      _suppressChatRebuild = false;
    }
  }

  void _onComposerChanged() {
    if (!AppSettings.instance.linkPreviewsEnabled) {
      if (_composerPreview != null) setState(() => _composerPreview = null);
      return;
    }

    final url = LinkPreviewService.extractFirstUrl(_messageController.text);
    if (url == _composerUrl) return;

    _composerUrl = url;
    _previewDebounce?.cancel();

    if (url == null) {
      _dismissedUrl = null;
      if (_composerPreview != null) setState(() => _composerPreview = null);
      return;
    }

    if (_composerPreview != null && _composerPreview!.url != url) {
      setState(() => _composerPreview = null);
    }
    if (url == _dismissedUrl) return;

    _previewDebounce = Timer(const Duration(milliseconds: 600), () async {
      final data = await LinkPreviewService.instance.fetch(url);
      if (!mounted || _composerUrl != url || url == _dismissedUrl) return;
      setState(() => _composerPreview = data);
    });
  }

  void _onTextPresenceChanged() {
    final has = _messageController.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  bool get _callBusy {
    final s = CallManager.instance.callStateNotifier.value;
    return s != CallState.idle && s != CallState.ending && s != CallState.error;
  }

  void _showHint(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _startRecording() async {
    if (kIsWeb || _isRecording) return;
    if (_callBusy) {
      _showHint('Finish the call before recording');
      return;
    }
    stopVoicePlayer();
    final result = await voiceRecorder.start();
    if (!mounted) {
      await voiceRecorder.cancel();
      return;
    }
    switch (result) {
      case StartResult.started:
        setState(() => _isRecording = true);
        _recordTicker?.cancel();
        _recordTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (mounted) setState(() {});
        });
      case StartResult.noPermission:
        _showHint('Allow microphone access to record voice notes');
      case StartResult.failed:
        _showHint('Could not start recording');
      case StartResult.alreadyRecording:
        break;
    }
  }

  void _endRecordingUi() {
    _recordTicker?.cancel();
    _recordTicker = null;
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _cancelRecording() async {
    _endRecordingUi();
    await voiceRecorder.cancel();
  }

  Future<void> _sendRecording() async {
    if (!_isRecording) return;
    _endRecordingUi();
    final voice = await voiceRecorder.finish();
    if (voice == null) {
      _showHint('Recording was too short');
      return;
    }

    final replyId = _replyingTo?.id;
    final replyContent = _replyingTo?.plaintext;
    final replySenderPubkey = _replyingTo?.senderPubkey;
    if (mounted) setState(() => _replyingTo = null);

    ChatManager.sendVoiceNote(
      recordedPath: voice.path,
      seconds: voice.seconds,
      receiverPubkey: widget.contact.pubkey,
      relayManager: widget.relayManager,
      replyToId: replyId,
      replyToContent: replyContent,
      replyToSenderPubkey: replySenderPubkey,
    ).catchError((Object e) {
      DebugLogger.log('[Voice] Send failed | $e', type: 'ERROR');
    });
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _maybeAutoScroll(force: true);
    });
  }

  Widget _buildRecordingBar(Color accentColor, Color textColor) {
    final elapsed = voiceRecorder.elapsed;
    final blinkOn = (elapsed.inMilliseconds ~/ 500).isEven;
    return SizedBox(
      height: _composerBarHeight,
      child: Row(
        children: [
          const SizedBox(width: 20),
          AnimatedOpacity(
            opacity: blinkOn ? 1 : 0.25,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            DurationUtils.formatClock(elapsed.inSeconds),
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
          Expanded(
            child: Center(
              child: TextButton(
                onPressed: _cancelRecording,
                child: Text(
                  'CANCEL',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 6),
            child: GestureDetector(
              onTap: _sendRecording,
              child: Container(
                height: _composerSendSize,
                width: _composerSendSize,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                child: const Center(
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _dismissComposerPreview() {
    _dismissedUrl = _composerUrl;
    setState(() => _composerPreview = null);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final contactsBox = Hive.box<Contact>('contacts');
    if (!contactsBox.containsKey(widget.contact.pubkey)) {
      final newContact = Contact(
        pubkey: widget.contact.pubkey,
        name: widget.contact.name,
        isSaved: false,
        lastChatTime: DateTime.now().millisecondsSinceEpoch,
        lastMessage: text,
        unreadCount: 0,
      );
      await contactsBox.put(widget.contact.pubkey, newContact);
      DebugLogger.log('[Chat] Temporary contact registered: ${widget.contact.name}', type: 'DATABASE');
    }

    final replyId = _replyingTo?.id;
    final replyContent = _replyingTo?.plaintext;
    final replySenderPubkey = _replyingTo?.senderPubkey;

    _messageController.clear();
    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    final myPubkey = AppSettings.instance.myPubkey;
    final receiver = widget.contact.pubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, receiver);
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final messageTs = DateTime.now().millisecondsSinceEpoch;

    final tempMessage = ChatMessage(
      id: tempId,
      senderPubkey: myPubkey,
      receiverPubkey: receiver,
      content: '',
      plaintext: text,
      timestamp: messageTs,
      status: 'sending',
      chatKey: chatKey,
      replyToId: replyId,
      replyToContent: replyContent,
      replyToSenderPubkey: replySenderPubkey,
    );

    try {
      await ChatManager.instance.saveMessage(tempMessage);
      _maybeAutoScroll(force: true);

      final event = await widget.relayManager.sendMessage(
        receiverPubkey: receiver,
        plaintext: text,
        replyToId: replyId,
        replyToContent: replyContent,
        messageTimestampMs: messageTs,
      );

      await ChatManager.instance.updateMessageIdAndStatus(
        tempId,
        event['rumorId'].toString(),
        'sending',
        chatKey,
        newContent: (event['giftWrap'] as Map<String, dynamic>)['content'].toString(),
        newGiftWrapId: event['giftWrapId'].toString(),
      );

      _maybeAutoScroll(force: true);
    } catch (e) {
      final offlineId = 'pending_${DateTime.now().millisecondsSinceEpoch}';

      final pendingMessage = tempMessage.copyWith(
        id: offlineId,
        content: '',
        plaintext: text,
        status: 'pending',
      );

      await ChatManager.instance.saveMessage(pendingMessage);
      await ChatManager.instance.deleteMessage(tempId, chatKey);

      DebugLogger.log('[Chat] Message queued for offline delivery', type: 'INFO');
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

    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final shadowColor = isDark ? Colors.black.withAlpha(100) : Colors.black.withAlpha(30);

    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._quickReactions.map((emoji) => _buildEmojiButton(emoji)),
                Container(
                  width: 1,
                  height: 30,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                _buildMoreButton(iconColor),
                Container(
                  width: 1,
                  height: 30,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                GestureDetector(
                  onTap: () {
                    if (_messageForReaction != null) {
                      Clipboard.setData(ClipboardData(text: _messageForReaction!.plaintext));
                      HapticFeedback.mediumImpact();
                      _removeReactionOverlay();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.all(2),
                    child: Icon(Icons.copy_rounded, size: 20, color: iconColor),
                  ),
                ),
              ],
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

  Future<void> _handleReaction(String emoji) async {
    final targetMessage = _messageForReaction;
    _messageForReaction = null;
    if (targetMessage == null) return;

    HapticFeedback.lightImpact();

    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = targetMessage.chatKey;
      final targetId = targetMessage.id;
      final box = Hive.box('chats');

      ChatMessage? findTarget() {
        final dynamic r = box.get(chatKey);
        if (r is! List) return null;
        for (final m in r.cast<ChatMessage>()) {
          if (m.id == targetId) return m;
        }
        return null;
      }

      final before = findTarget();
      if (before == null) return;

      final bool isMessageReady =
          (before.status == 'sent' || before.status == 'read') &&
              !targetId.startsWith('temp_') &&
              !targetId.startsWith('pending_');

      final dynamic rawBefore = box.get(chatKey);
      if (rawBefore is! List) return;
      final listBefore = rawBefore.cast<ChatMessage>().toList();
      final idxBefore = listBefore.indexWhere((m) => m.id == targetId);
      if (idxBefore == -1) return;
      listBefore[idxBefore] = listBefore[idxBefore].copyWith(
        reactions: {...listBefore[idxBefore].reactions, myPubkey: emoji},
        pendingReactions: {...listBefore[idxBefore].pendingReactions, myPubkey: emoji},
      );
      await box.put(chatKey, listBefore);

      if (isMessageReady) {
        try {
          await widget.relayManager.sendReaction(
            messageId: targetId,
            receiverPubkey: widget.contact.pubkey,
            targetAuthorPubkey: targetMessage.senderPubkey,
            emoji: emoji,
          );
        } catch (e) {
          DebugLogger.log('[Reaction] sendReaction failed | $e', type: 'ERROR');
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      DebugLogger.log('[Reaction] Handle failed | $e', type: 'ERROR');
    }
  }

  void _showAllReactionsDialog() {
    FocusScope.of(context).unfocus();

    final backupMessage = _messageForReaction;
    _removeReactionOverlay();
    _messageForReaction = backupMessage;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    const accentColor = Color(0xFF2196F3);

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogHeight = screenHeight * 0.7;
    final crossAxisCount = screenWidth < 360 ? 5 : 6;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: screenWidth * 0.9,
            constraints: BoxConstraints(maxHeight: dialogHeight),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Reaction',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose an emoji to react',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentColor.withAlpha(30), width: 0.5),
                      ),
                      child: Icon(
                        Icons.emoji_emotions_outlined,
                        size: 18,
                        color: accentColor.withAlpha(200),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 0.5, thickness: 0.5, color: borderColor),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: _allReactions.length,
                    itemBuilder: (context, index) {
                      final emoji = _allReactions[index];
                      return GestureDetector(
                        onTap: () {
                          _handleReaction(emoji);
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: borderColor,
                              width: 0.5,
                            ),
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                emoji,
                                style: TextStyle(
                                  fontSize: screenWidth < 360 ? 20 : 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 0.5, thickness: 0.5, color: borderColor),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          child: Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 13,
                                color: textSecondary,
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
    final contactsBox = Hive.box<Contact>('contacts');
    final c = contactsBox.get(senderPubkey);
    if (c != null) return AppSettings.getContactDisplayName(c);
    return AppSettings.formatDisplayName(senderPubkey);
  }

  String _resolveReplySenderPubkey(ChatMessage message) {
    final replyId = message.replyToId;
    if (replyId != null) {
      final i = _cachedMessages.indexWhere((m) => m.id == replyId);
      if (i != -1) return _cachedMessages[i].senderPubkey;
    }
    return message.replyToSenderPubkey ?? message.senderPubkey;
  }

  bool _canReplyTo(ChatMessage m) =>
      !m.id.startsWith('temp_') && !m.id.startsWith('pending_');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final contactsBox = Hive.box<Contact>('contacts');
    final currentContact = contactsBox.get(widget.contact.pubkey) ?? widget.contact;
    String displayName = AppSettings.getContactDisplayName(currentContact);

    final chatKey = ChatManager.instance.getChatKey(AppSettings.instance.myPubkey, widget.contact.pubkey);

    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final headerColor = isNostrCyber
        ? const Color(0xFF1B1425)
        : (isDark ? const Color(0xFF121212) : Colors.white);

    final headerTextColor = isNostrCyber ? Colors.white : (isDark ? Colors.white : Colors.black);

    final accentColor = isNostrCyber ? const Color(0xFF7B2CBF) : (isDark ? const Color(0xFF2196F3) : const Color(0xFF2196F3));
    final dividerBg = isDark ? const Color(0xFF182229) : const Color(0xFFFFFFFF).withAlpha(230);

    return Scaffold(
      backgroundColor: isNostrCyber
          ? const Color(0xFF130F1A)
          : (isDark ? const Color(0xFF121212) : const Color(0xFFE5DDD5)),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: headerColor,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: headerTextColor,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ContactProfilePage(
                  contact: widget.contact,
                  relayManager: widget.relayManager,
                ),
              ),
            );
          },
          child: Row(
            children: [
              UserAvatar(
                pubkey: widget.contact.pubkey,
                name: displayName,
                radius: 20,
                relayManager: widget.relayManager,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: headerTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.phone_outlined, color: headerTextColor),
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
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: headerTextColor),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            elevation: 0,
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
                width: 0.5,
              ),
            ),
            onSelected: (value) {
              if (value == 'save_rename') _showSaveContactDialog();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'save_rename',
                height: 40,
                child: Text(
                  widget.contact.isSaved ? 'Rename' : 'Save Contact',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<CallState>(
            valueListenable: CallManager.instance.callStateNotifier,
            builder: (context, callState, _) {
              if (callState == CallState.idle ||
                  callState == CallState.ending ||
                  callState == CallState.error) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: CallFloatingBar(relay: widget.relayManager),
              );
            },
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Hive.box('chats').listenable(),
              builder: (context, Box box, _) {
                if (_suppressChatRebuild && _lastChatListWidget != null) {
                  return _lastChatListWidget!;
                }

                final dynamic rawData = box.get(chatKey);
                if (rawData is List) {
                  final List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
                  messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                  _cachedMessages = messages;
                } else {
                  _cachedMessages = [];
                }

                final int newCount = _cachedMessages.length;
                if (_previousMessageCount >= 0 && newCount > _previousMessageCount) {
                  final int delta = newCount - _previousMessageCount;
                  if (!_userIsNearBottom) {
                    if (_anchoredController.isAttached) {
                      _isCompensatingScroll = true;
                      _anchoredController.itemsInsertedAbove(delta);

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _isCompensatingScroll = false;
                          _handlePositionsChanged();
                        }
                      });
                    }
                  }
                }
                _previousMessageCount = newCount;

                if (_cachedMessages.isEmpty) {
                  return _lastChatListWidget = _buildEmptyState();
                }

                return _lastChatListWidget = Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification ||
                            notification is ScrollStartNotification) {
                          _updateFloatingDate();
                        }
                        return false;
                      },
                      child: AnchoredList.builder(
                        controller: _anchoredController,
                        scrollController: _scrollController,
                        itemCount: _cachedMessages.length,
                        reverse: true,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemBuilder: (context, index) {
                          final message = _cachedMessages[index];
                          double topPadding = 1;

                          if (index < _cachedMessages.length - 1) {
                            final nextMessage = _cachedMessages[index + 1];
                            if (message.senderPubkey != nextMessage.senderPubkey) {
                              topPadding = 8;
                            }
                          }

                          bool showDateDivider = false;
                          if (index == _cachedMessages.length - 1) {
                            showDateDivider = true;
                          } else {
                            final nextMessage = _cachedMessages[index + 1];
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
                                child: message.senderPubkey == AppSettings.instance.myPubkey
                                    ? _wrapMyDismissible(message)
                                    : _wrapTheirDismissible(message),
                              ),
                            ],
                          );
                        },
                      ),
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
                        bottom: 20,
                        right: 16,
                        child: GestureDetector(
                          onTap: () => _scrollToBottom(),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
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
                                  Icons.keyboard_arrow_down_rounded,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  size: 24,
                                ),
                              ),
                              if (_newMessagesCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(
                                      minWidth: 20,
                                      minHeight: 20,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        _newMessagesCount > 99 ? '99+' : '$_newMessagesCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final accentColor = isNostrCyber
        ? const Color(0xFFD4BBFC)
        : (isDark ? const Color(0xFF2196F3) : const Color(0xFF2196F3));

    final dividerBg = isNostrCyber
        ? const Color(0xFF1B1425)
        : (isDark ? const Color(0xFF182229) : const Color(0xFFFFFFFF).withAlpha(230));

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
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final accentColor = isNostrCyber ? const Color(0xFF7B2CBF) : const Color(0xFF2196F3);
    final inputBgColor = isNostrCyber
        ? const Color(0xFF1B1425)
        : (isDark ? const Color(0xFF2C2C2C) : Colors.white);
    final inputTextColor = isNostrCyber ? Colors.white : (isDark ? Colors.white : Colors.black);
    final inputHintColor = isNostrCyber ? Colors.white54 : (isDark ? Colors.white38 : Colors.black38);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            12, // Left
            kIsWeb ? 20 : 6, // Top
            12, // Right
            kIsWeb ? 20 : 6 // Bottom
        ),
        child: Container(
          constraints: BoxConstraints(
            minHeight: _composerBarHeight,
            maxHeight: (_replyingTo != null ? 230 : 180) +
                (_composerPreview != null ? 72 : 0),
          ),
          decoration: BoxDecoration(
            color: inputBgColor,
            borderRadius: BorderRadius.circular(_composerBarRadius),
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
              if (_composerPreview != null) _buildComposerLinkPreview(),
              if (_isRecording)
                _buildRecordingBar(accentColor, inputTextColor)
              else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _composerBarHeight,
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 5,
                        minLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: inputTextColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: inputHintColor,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _composerBarHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2, right: 6),
                      child: Center(
                        child: GestureDetector(
                          onTap: _isSending ? null : ((_hasText || kIsWeb) ? _sendMessage : _startRecording),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: _composerSendSize,
                            width: _composerSendSize,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: _isSending
                                  ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                                  : Icon(
                                      (_hasText || kIsWeb) ? Icons.send_rounded : Icons.mic_rounded,
                                      color: Colors.white,
                                      size: 20),
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

  Widget _buildComposerLinkPreview() {
    final data = _composerPreview!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final bgColor = isNostrCyber
        ? const Color(0xFF251C33)
        : (isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15));
    final titleColor = isNostrCyber
        ? const Color(0xFFD4BBFC)
        : const Color(0xFF2196F3);
    final subColor = isNostrCyber
        ? Colors.white70
        : (isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153));

    return Container(
      margin: const EdgeInsets.fromLTRB(
        _composerBarInset,
        _composerBarInset,
        _composerBarInset,
        0,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_composerInnerRadius),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            if (data.imageUrl != null)
              CachedNetworkImage(
                imageUrl: data.imageUrl!,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(width: 64, height: 64),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title ?? data.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      data.description ?? data.host,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: subColor),
              onPressed: _dismissComposerPreview,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.only(right: 8),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessagePreview(String text) {
    if (text.startsWith('[CALL]:')) {
      final parts = text.split(':');
      final direction = parts.length > 1 ? parts[1] : 'outgoing';
      final durationSeconds = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;

      final bool isMissed = direction == 'missed';
      final bool isIncoming = direction == 'incoming';

      String label = isMissed
          ? 'Missed Call'
          : (isIncoming ? 'Incoming Call' : 'Outgoing Call');

      if (durationSeconds > 0) {
        label = '$label (${DurationUtils.formatCallDuration(durationSeconds)})';
      }
      return label;
    }
    return text;
  }

  Widget _buildReplyPreviewInside() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final nameColor = isNostrCyber
        ? const Color(0xFFD4BBFC)
        : (isDark ? const Color(0xFF2196F3) : const Color(0xFF2196F3));

    final bgColor = isNostrCyber
        ? const Color(0xFF251C33)
        : (isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15));

    final previewTextColor = isNostrCyber
        ? Colors.white70
        : (isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153));

    final iconThemeColor = isNostrCyber
        ? const Color(0xFFD4BBFC)
        : (isDark ? Colors.white70 : Colors.black87);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        _composerBarInset,
        _composerBarInset,
        _composerBarInset,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_composerInnerRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, color: iconThemeColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _getReplyName(_replyingTo!.senderPubkey),
                    style: TextStyle(
                        color: nameColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12
                    )
                ),
                Text(
                    _formatMessagePreview(_replyingTo!.plaintext),
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

  Widget _wrapMyDismissible(ChatMessage message) =>
      _wrapDismissible(message, Alignment.centerRight);

  Widget _wrapTheirDismissible(ChatMessage message) =>
      _wrapDismissible(message, Alignment.centerLeft);

  Widget _wrapDismissible(ChatMessage message, Alignment alignment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragUpdate: (d) => _onSwipeUpdate(message, d),
      onHorizontalDragEnd: (_) => _onSwipeEnd(message),
      onHorizontalDragCancel: _resetSwipe,
      child: ValueListenableBuilder<double>(
        valueListenable: _dragOffsetNotifier,
        child: Align(
          alignment: alignment,
          child: _buildMessageBubble(message),
        ),
        builder: (context, offset, bubble) {
          final isDragging = _draggingId == message.id;
          final dx = isDragging ? offset : 0.0;

          return Transform.translate(
            offset: Offset(dx, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                bubble!,
                if (isDragging)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: -32,
                    child: Opacity(
                      opacity: ((-dx) / 40).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: ((-dx) / 50).clamp(0.0, 1.0),
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.only(bottom: 2),
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
              ],
            ),
          );
        },
      ),
    );
  }

  void _onSwipeUpdate(ChatMessage message, DragUpdateDetails details) {
    if (_draggingId != null && _draggingId != message.id) return;

    final current = _dragOffsetNotifier.value;
    if (details.delta.dx >= 0 && current >= 0) return;

    _draggingId = message.id;
    final resistance = current < -30 ? 0.3 : 0.6;
    _dragOffsetNotifier.value =
        (current + details.delta.dx * resistance).clamp(-70.0, 0.0).toDouble();
  }

  void _onSwipeEnd(ChatMessage message) {
    final shouldReply =
        _draggingId == message.id && _dragOffsetNotifier.value <= -45;
    _resetSwipe();

    if (!shouldReply || !_canReplyTo(message)) return;

    HapticFeedback.mediumImpact();
    setState(() => _replyingTo = message);
    _focusNode.requestFocus();
  }

  void _resetSwipe() {
    _draggingId = null;
    _dragOffsetNotifier.value = 0.0;
  }

  Widget _buildMessageBubble(ChatMessage message) {
    if (message.plaintext.startsWith('[CALL]:')) {
      return _buildCallMessageBubble(message);
    }

    final theme = Theme.of(context);
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;
    final isDark = theme.brightness == Brightness.dark;
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final is24Hour = MediaQuery.of(context).alwaysUse24HourFormat;
    final timeStr = DateFormat(is24Hour ? 'HH:mm' : 'h:mm a').format(
        DateTime.fromMillisecondsSinceEpoch(message.timestamp)
    );

    final bubbleColor = isNostrCyber
        ? (isMe ? const Color(0xFF7B2CBF) : const Color(0xFF251C33))
        : (isMe
        ? (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE3F2FD))
        : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF)));

    final textColor = isNostrCyber
        ? Colors.white
        : (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000));

    final hasReactions = message.reactions.isNotEmpty;
    final isHighlighted = _highlightedIds.contains(message.id);
    final previewUrl = AppSettings.instance.linkPreviewsEnabled
        ? LinkPreviewService.extractFirstUrl(message.plaintext)
        : null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: hasReactions ? 25 : 2),
        child: Container(
          decoration: BoxDecoration(
            color: isHighlighted ? Colors.blue.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: GestureDetector(
            onLongPressStart: (details) => _showReactionPopup(context, details.globalPosition, message),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.90),
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

                        if (previewUrl != null)
                          LinkPreviewCard(
                            key: ValueKey('${message.id}_$previewUrl'),
                            url: previewUrl,
                            textColor: textColor,
                            backgroundColor: isNostrCyber
                                ? Colors.white.withAlpha(20)
                                : (isDark
                                ? Colors.black.withAlpha(40)
                                : Colors.black.withAlpha(15)),
                          ),

                        const SizedBox(height: 4),

                        message.isVoiceNote
                            ? VoiceNoteBubble(
                          key: ValueKey('vn_${message.id}'),
                          message: message,
                          textColor: textColor,
                          footer: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(timeStr, style: TextStyle(color: textColor.withAlpha(153), fontSize: 11)),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                _buildStatusIcon(message.status, textColor),
                              ],
                            ],
                          ),
                        )
                            : (_isShortText(message.plaintext, context))
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
      ),
    );
  }

  Widget _buildReplyInBubble(ChatMessage message, bool isMe) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final String senderName = _getReplyName(_resolveReplySenderPubkey(message));

    final nameColor = isNostrCyber ? const Color(0xFFD0BCFF) : const Color(0xFF2196F3);
    final bgColor = isNostrCyber ? Colors.white.withAlpha(20) : (isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(15));
    final contentColor = isNostrCyber ? Colors.white70 : (isDark ? Colors.white.withAlpha(153) : Colors.black.withAlpha(153));

    return GestureDetector(
      onTap: () => _scrollToMessage(message.replyToId),
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(10),
              bottom: Radius.circular(10)
          ),
          border: Border(
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
              style: TextStyle(
                color: nameColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              _formatMessagePreview(message.replyToContent ?? ""),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: contentColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        return ValueListenableBuilder(
          valueListenable: Hive.box('settings').listenable(keys: ['read_receipts_enabled']),
          builder: (context, _, __) {
            if (!AppSettings.instance.readReceiptsEnabled) {
              return Icon(Icons.done, size: 13, color: color.withAlpha(153));
            }
            return const Icon(Icons.done_all, size: 13, color: Color(0xFF34B7F1));
          },
        );
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
                  const Icon(Remix.chat_3_line, size: 48),
                  const SizedBox(height: 16),
                  Text('No messages yet with ${widget.contact.name}')
                ]
            )
        )
    );
  }

  Future<void> _showSaveContactDialog() async {
    final contactsBox = Hive.box<Contact>('contacts');
    final targetContact = contactsBox.get(widget.contact.pubkey) ?? widget.contact;
    final nameController = TextEditingController(text: targetContact.isSaved ? targetContact.name : "");
    await showDialog(
      context: context,
      builder: (dialogContext) {
        void save() {
          final name = nameController.text.trim();
          if (name.isEmpty) return;
          targetContact.name = name;
          targetContact.isSaved = true;
          Hive.box<Contact>('contacts').put(targetContact.pubkey, targetContact).then((_) async {
            await ShortcutHelper.pushConversationShortcut(
              id: targetContact.pubkey,
              name: targetContact.displayName,
              avatarBytes: null,
            );

            HapticFeedback.lightImpact();
            if (dialogContext.mounted) {
              setState(() {});
              Navigator.pop(dialogContext);
            }
          });
        }

        return AlertDialog(
          title: Text(targetContact.isSaved ? 'Rename contact' : 'Save contact'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => save(),
            decoration: const InputDecoration(hintText: 'Enter name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(onPressed: save, child: const Text('Save')),
          ],
        );
      },
    );
  }

  Widget _buildCallMessageBubble(ChatMessage message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;
    final bool isNostrCyber = AppSettings.instance.roomChatTheme == 'nostr_cyber';

    final parts = message.plaintext.split(':');
    final direction = parts.length > 1 ? parts[1] : 'outgoing';
    final durationSeconds = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;

    final bool isMissed = direction == 'missed';
    final bool isIncoming = direction == 'incoming';

    IconData callIcon;
    String label;

    if (isMissed) {
      callIcon = Icons.call_missed;
      label = 'Missed Call';
    } else if (isIncoming) {
      callIcon = Icons.call_received;
      label = 'Incoming Call';
    } else {
      callIcon = Icons.call_made;
      label = 'Outgoing Call';
    }

    final durationLabel = DurationUtils.formatCallDuration(durationSeconds);

    final normalTextColor = isNostrCyber ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final textColor = isMissed
        ? Colors.red
        : normalTextColor;
    final iconColor = isMissed ? Colors.red : textColor;
    final timeColor = normalTextColor.withAlpha(153);

    final is24Hour = MediaQuery.of(context).alwaysUse24HourFormat;
    final timeStr = DateFormat(is24Hour ? 'HH:mm' : 'h:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final bubbleColor = isNostrCyber
        ? (isMe ? const Color(0xFF7B2CBF) : const Color(0xFF251C33))
        : (isMe
        ? (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE3F2FD))
        : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF)));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMe ? 60 : 12,
          right: isMe ? 12 : 60,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isDark
              ? Border.all(color: Colors.white10, width: 0.5)
              : null,
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(callIcon, color: iconColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      durationLabel,
                      style: TextStyle(fontSize: 13, color: timeColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 11, color: timeColor),
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