// room_chat.dart

import 'core/theme/chatme_colors.dart';
import 'core/utils/unseen_message.dart';
import 'dart:async';
import 'dart:math' as math;
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
import 'services/chat_reply.dart';
import 'models/contact.dart';
import 'models/chat_message.dart';
import 'notification_handler.dart';
import 'package:remixicon/remixicon.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/duration_utils.dart';
import 'ui/chat_image_crop_page.dart';
import 'widgets/user_avatar.dart';
import 'ui/contacts/contact_profile.dart';
import 'core/utils/shortcut_helper.dart';
import 'services/link_preview_service.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_highlight.dart';
import 'widgets/chatme_menu.dart';
import 'services/image_prepare.dart';
import 'package:image_picker/image_picker.dart';
import 'services/just_audio_backend.dart';
import 'services/record_backend.dart';
import 'services/voice_recorder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'services/keyboard_height.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji;

const double _composerBarHeight = 52.0;
const double _composerBarRadius = 26.0;
const double _composerBarInset = 6.0;
const double _composerInnerRadius = _composerBarRadius - _composerBarInset;
const double _composerSendSize = 42.0;
const double _listSidePadding = 8.0;

class ChatDetailScreen extends StatefulWidget {
  final Contact contact;
  final RelayManager relayManager;

  /// A picture from the viewer that should become the reply target.
  final ChatMessage? initialReply;

  /// A message to scroll to and highlight once the chat has opened.
  final String? initialMessageId;

  const ChatDetailScreen({
    super.key,
    required this.contact,
    required this.relayManager,
    this.initialReply,
    this.initialMessageId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  ChatScreenHandle? _chatHandle;

  Timer? _previewDebounce;
  String? _composerUrl;
  String? _dismissedUrl;
  LinkPreviewData? _composerPreview;

  // Emoji panel <-> keyboard dock.
  bool _isEmojiPanelOpen = false;
  bool _isEmojiPanelClosing = false;
  double _emojiPanelHeight = 0.0;

  // Whether the panel is mounted. Changing it rebuilds only the dock, so the
  // panel can leave at the end of the keyboard animation without rebuilding
  // the whole chat screen in the middle of a frame.
  final ValueNotifier<bool> _emojiPanelMounted = ValueNotifier<bool>(false);
  Widget? _cachedEmojiPanel;
  bool? _cachedEmojiPanelDark;
  double? _cachedEmojiPanelSafeBottom;
  double _keyboardInsetBottom = 0.0;
  bool _wasLandscape = false;
  int _emojiPanelCloseToken = 0;
  Timer? _emojiPanelCloseTimer;
  Timer? _keyboardSettleTimer;
  late final AnimationController _emojiRevealController;

  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  String? _draggingId;

  int _newMessagesCount = 0;

  bool _isMarkingRead = false;
  bool _markReadAgain = false;
  bool _suppressChatRebuild = false;
  Widget? _lastChatListWidget;

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
    _emojiRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    WidgetsBinding.instance.addObserver(this);
    NotificationHandler.clearNotification(widget.contact.pubkey);
    widget.relayManager.currentlyChattingWith = widget.contact.pubkey;
    NotificationHandler.activeChatPubkey = widget.contact.pubkey;
    widget.relayManager.onMessageReceived = () async {
      if (!mounted) return;

      if (_userIsNearBottom) {
        _markAllAsRead();
      }

      setState(() {});
    };
    widget.relayManager.onIncomingMessageSaved = (peerPubkey) {
      if (!mounted) return;
      if (!shouldCountUnseen(
        peerPubkey: peerPubkey,
        openPubkey: widget.contact.pubkey,
        nearBottom: _userIsNearBottom,
      )) {
        return;
      }
      setState(() => _newMessagesCount++);
    };

    _anchoredController.itemPositions.addListener(_handlePositionsChanged);
    _scrollController.addListener(_handleScrollChanged);
    _messageController.addListener(_onComposerChanged);
    _messageController.addListener(_onTextPresenceChanged);
    _focusNode.addListener(_handleComposerFocusChanged);
    if (widget.initialReply != null) {
      _replyingTo = widget.initialReply;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusComposer();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAllAsRead();
    });
    if (widget.initialMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpAfterRouteOpens());
    }
  }

  Animation<double>? _openAnimation;

  void _jumpAfterRouteOpens() {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _scrollToMessage(widget.initialMessageId);
      return;
    }
    _openAnimation = animation;
    animation.addStatusListener(_onOpenAnimationStatus);
  }

  void _onOpenAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _openAnimation?.removeStatusListener(_onOpenAnimationStatus);
    _openAnimation = null;
    if (mounted) _scrollToMessage(widget.initialMessageId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _chatHandle?.route)) return;
    if (_chatHandle != null) ChatScreenRegistry.unregister(_chatHandle!);
    _chatHandle = ChatScreenHandle(
      pubkey: widget.contact.pubkey,
      route: route,
      onReply: _startReply,
    );
    ChatScreenRegistry.register(_chatHandle!);
  }

  void _startReply(ChatMessage message) {
    if (!canReplyTo(message)) return;
    setState(() => _replyingTo = message);
    _focusComposer();
  }

  void _focusComposer() {
    if (mounted) _focusNode.requestFocus();
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

  double _readKeyboardInset() {
    final view = View.of(context);
    final ratio = view.devicePixelRatio;
    return ratio <= 0 ? 0.0 : view.viewInsets.bottom / ratio;
  }

  Size _readScreenSize() {
    final view = View.of(context);
    final ratio = view.devicePixelRatio;
    return ratio <= 0 ? Size.zero : view.physicalSize / ratio;
  }

  double _emojiHeightForOpening() {
    final size = _readScreenSize();
    final landscape = size.width > size.height;
    Object? stored;
    try {
      stored = Hive.box('settings').get(KeyboardHeight.key(landscape: landscape));
    } catch (_) {}
    return KeyboardHeight.forOpening(
      keyboardNow: _readKeyboardInset(),
      stored: stored,
      screenHeight: size.height,
    );
  }

  void _rememberKeyboardHeight(double height) {
    final size = _readScreenSize();
    final key = KeyboardHeight.key(landscape: size.width > size.height);
    try {
      final box = Hive.box('settings');
      if (KeyboardHeight.shouldSave(box.get(key), height)) box.put(key, height);
    } catch (_) {}
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final size = _readScreenSize();
    final bottom = _readKeyboardInset();
    _keyboardInsetBottom = bottom;

    final landscape = size.width > size.height;
    if (landscape != _wasLandscape) {
      _wasLandscape = landscape;
      if (_isEmojiPanelOpen && !_isEmojiPanelClosing && bottom == 0) {
        setState(() => _emojiPanelHeight = _emojiHeightForOpening());
      }
    }

    // A keyboard height only counts once it stopped moving, so the middle of
    // an animation is never taken for the real height.
    _keyboardSettleTimer?.cancel();
    if (KeyboardHeight.valid(bottom) != null) {
      _keyboardSettleTimer = Timer(const Duration(milliseconds: 120), _onKeyboardSettled);
    }

  }

  void _onKeyboardSettled() {
    if (!mounted) return;
    final height = _keyboardInsetBottom;
    if (KeyboardHeight.valid(height) == null) return;
    _rememberKeyboardHeight(height);
    if (_isEmojiPanelOpen && _isEmojiPanelClosing) _finishEmojiPanelDismiss();
  }

  void _handleComposerFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus && _isEmojiPanelOpen && !_isEmojiPanelClosing) {
      _restoreKeyboardFromEmojiPanel();
    }
  }

  void _toggleEmojiPanel() {
    if (_isEmojiPanelOpen) {
      _restoreKeyboardFromEmojiPanel();
    } else {
      _openEmojiPanel();
    }
  }

  void _openEmojiPanel() {
    final hasKeyboard = _readKeyboardInset() > 0;

    _emojiPanelCloseToken++;
    _emojiPanelCloseTimer?.cancel();

    _emojiPanelMounted.value = true;
    setState(() {
      _isEmojiPanelOpen = true;
      _isEmojiPanelClosing = false;
      _emojiPanelHeight = _emojiHeightForOpening();
    });

    if (hasKeyboard) {
      // The keyboard already fills the dock, so the panel is laid out under it
      // at full height and nothing moves when the keyboard goes away.
      _emojiRevealController.value = 1.0;
    } else {
      _emojiRevealController.value = 0.0;
      _emojiRevealController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isEmojiPanelOpen || _isEmojiPanelClosing) return;
      _focusNode.unfocus();
    });
  }

  void _restoreKeyboardFromEmojiPanel() {
    if (!mounted) return;
    if (!_isEmojiPanelOpen) {
      _focusNode.requestFocus();
      return;
    }

    final token = ++_emojiPanelCloseToken;
    if (!_isEmojiPanelClosing) {
      setState(() => _isEmojiPanelClosing = true);
    }
    _focusNode.requestFocus();

    // Safety net for when no keyboard ever shows up (hardware keyboard).
    _emojiPanelCloseTimer?.cancel();
    _emojiPanelCloseTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || token != _emojiPanelCloseToken) return;
      if (_keyboardInsetBottom > 0) return;
      _finishEmojiPanelDismiss();
    });
  }

  // Called when the keyboard stopped moving (or never came). The panel stays
  // behind the keyboard until then, so nothing is rebuilt during the animation.
  // If the keyboard turned out a little shorter than the panel, the panel
  // shrinks to it first so the composer does not step down.
  void _finishEmojiPanelDismiss() {
    if (!mounted || !_isEmojiPanelOpen) return;
    final token = ++_emojiPanelCloseToken;
    _emojiPanelCloseTimer?.cancel();
    _isEmojiPanelOpen = false;
    _isEmojiPanelClosing = false;

    final target = KeyboardHeight.revealAfterSettle(
      keyboard: _keyboardInsetBottom,
      panel: _emojiPanelHeight,
    );
    if (target >= 1.0) {
      _unmountEmojiPanel();
      return;
    }
    _emojiRevealController
        .animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut)
        .whenComplete(() {
      if (!mounted || token != _emojiPanelCloseToken || _isEmojiPanelOpen) return;
      _unmountEmojiPanel();
    });
  }

  void _unmountEmojiPanel() {
    _emojiRevealController.value = 0.0;
    _emojiPanelMounted.value = false;
    _cachedEmojiPanel = null;
  }

  // Used by the system back gesture: dismiss the panel without bringing the
  // keyboard back.
  void _closeEmojiPanel() {
    if (!mounted || !_isEmojiPanelOpen) return;
    _emojiPanelCloseToken++;
    _emojiPanelCloseTimer?.cancel();
    _focusNode.unfocus();
    setState(() {
      _isEmojiPanelOpen = false;
      _isEmojiPanelClosing = false;
    });
    _unmountEmojiPanel();
  }

  @override
  void dispose() {
    _openAnimation?.removeStatusListener(_onOpenAnimationStatus);
    WidgetsBinding.instance.removeObserver(this);
    if (_chatHandle != null) ChatScreenRegistry.unregister(_chatHandle!);
    _removeReactionOverlay();
    stopVoicePlayer();
    _recordTicker?.cancel();
    cancelVoiceRecording();

    widget.relayManager.currentlyChattingWith = null;
    NotificationHandler.activeChatPubkey = null;
    widget.relayManager.onMessageReceived = null;
    widget.relayManager.onIncomingMessageSaved = null;

    _floatingDateTimer?.cancel();
    _scrollIdleTimer?.cancel();
    _previewDebounce?.cancel();
    _emojiPanelCloseTimer?.cancel();
    _keyboardSettleTimer?.cancel();
    _emojiPanelMounted.dispose();
    _emojiRevealController.dispose();

    _anchoredController.itemPositions.removeListener(_handlePositionsChanged);
    _anchoredController.dispose();
    _scrollController.dispose();

    _dragOffsetNotifier.dispose();
    _focusNode.removeListener(_handleComposerFocusChanged);
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

    try {
      do {
        _markReadAgain = false;

        // Marks the whole history read in one storage batch and returns only
        // the newest few ids that deserve a receipt. Older history must not
        // be acknowledged: each receipt is a NIP-17 wrap on the UI isolate.
        // `_suppressChatRebuild` keeps the open room from rebuilding once per
        // status write; a single rebuild follows below.
        _suppressChatRebuild = true;
        final List<String> toAck;
        try {
          toAck = await ChatManager.instance
              .markIncomingAsRead(peerPubkey: peerPubkey);
        } finally {
          _suppressChatRebuild = false;
        }

        for (final id in toAck) {
          if (!mounted) break;
          try {
            await widget.relayManager.sendReceipt(id, peerPubkey, 'read');
          } catch (e) {
            DebugLogger.log('[Chat] sendReceipt failed | $e', type: 'ERROR');
          }
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

  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb) return;
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null || !mounted) return;

      final imageBytes = await picked.readAsBytes();
      if (!mounted) return;
      final croppedBytes = await ChatImageCropPage.open(context, imageBytes);
      if (croppedBytes == null || !mounted) return;

      final prepared = await prepareImage(croppedBytes);
      if (!mounted) return;

      final replyId = _replyingTo?.id;
      final replyContent = _replyingTo?.plaintext;
      final replySenderPubkey = _replyingTo?.senderPubkey;
      if (mounted) setState(() => _replyingTo = null);

      ChatManager.sendImage(
        image: prepared,
        receiverPubkey: widget.contact.pubkey,
        relayManager: widget.relayManager,
        replyToId: replyId,
        replyToContent: replyContent,
        replyToSenderPubkey: replySenderPubkey,
      ).catchError((Object e) {
        DebugLogger.log('[Image] Send failed | $e', type: 'ERROR');
      });
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _maybeAutoScroll(force: true);
      });
    } on ImagePrepareException catch (e) {
      _showHint(e.message);
    } catch (e) {
      DebugLogger.log('[Image] Pick failed | $e', type: 'ERROR');
      _showHint('Could not open the photo');
    }
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

  Widget _buildRecordingBar(Color accentColor, Color onAccentColor, Color textColor) {
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
                child: Center(
                  child: Icon(Icons.send_rounded, color: onAccentColor, size: 20),
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
        globalId: widget.contact.globalId,
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

    final screenWidth = MediaQuery.sizeOf(context).width;
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
      final chatKey = targetMessage.chatKey;
      final targetId = targetMessage.id;

      final before = ChatManager.instance.getMessageByIdSync(targetId, chatKey);
      if (before == null) return;

      final bool isMessageReady =
          (before.status == 'sent' || before.status == 'read') &&
              !targetId.startsWith('temp_') &&
              !targetId.startsWith('pending_');

      await ChatManager.instance.setMessageReaction(
        chatKey: chatKey,
        messageId: targetId,
        reactorPubkey: AppSettings.instance.myPubkey,
        emoji: emoji,
      );

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

    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
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

  @override
  Widget build(BuildContext context) {
    final contactsBox = Hive.box<Contact>('contacts');
    final currentContact = contactsBox.get(widget.contact.pubkey) ?? widget.contact;
    String displayName = AppSettings.getContactDisplayName(currentContact);

    final chatKey = ChatManager.instance.getChatKey(AppSettings.instance.myPubkey, widget.contact.pubkey);

    const headerColor = ChatmeColors.surfaceBase;
    const headerTextColor = ChatmeColors.textPrimary;
    const accentColor = ChatmeColors.accentPrimary;

    return Scaffold(
      backgroundColor: ChatmeColors.backgroundPrimary,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: headerColor,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
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
                  style: const TextStyle(
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
            icon: const Icon(Icons.phone_outlined, color: headerTextColor),
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
          ChatmeMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: headerTextColor),
            offset: const Offset(0, 40),
            entries: [
              ChatmeMenuEntry(
                value: 'save_rename',
                icon: widget.contact.isSaved ? Icons.edit_outlined : Icons.person_add_alt_1_outlined,
                label: widget.contact.isSaved ? 'Rename' : 'Save Contact',
              ),
            ],
            onSelected: (value) {
              if (value == 'save_rename') _showSaveContactDialog();
            },
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
              // Filtered listenable: only writes to THIS chat rebuild the
              // room. A plain box listenable would rebuild it for every
              // message saved anywhere (e.g. a full restore backlog).
              valueListenable: ChatManager.instance.chatMessagesListenable(chatKey),
              builder: (context, Box<ChatMessage> box, _) {
                if (_suppressChatRebuild && _lastChatListWidget != null) {
                  return _lastChatListWidget!;
                }

                final List<ChatMessage> messages =
                    ChatManager.instance.messagesForChatSync(chatKey);
                messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                _cachedMessages = messages;

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
                        padding: const EdgeInsets.symmetric(horizontal: _listSidePadding, vertical: 8),
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
                                child: MessageHighlight(
                                  highlighted: _highlightedIds.contains(message.id),
                                  color: accentColor.withAlpha(56),
                                  bleed: _listSidePadding,
                                  bottomInset: MessageBubble.bottomGap(message.reactions.isNotEmpty),
                                  child: message.senderPubkey == AppSettings.instance.myPubkey
                                      ? _wrapMyDismissible(message)
                                      : _wrapTheirDismissible(message),
                                ),
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
                          color: ChatmeColors.surfaceOverlay,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 4, offset: const Offset(0, 2))
                          ],
                        ),
                        child: Text(
                          _floatingDate,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ChatmeColors.accentPrimary),
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
                                  color: ChatmeColors.surfaceOverlay,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ChatmeColors.borderSubtle,
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
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: ChatmeColors.textSecondary,
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
          _buildComposerDock(),
        ],
      ),
    );
  }

  Widget _buildDateDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ChatmeColors.surfaceOverlay,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 1)
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: ChatmeColors.accentPrimary
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposerDock() {
    // Built here, once per setState, so the keyboard animation only rebuilds
    // the small builder below and reuses these same widgets.
    final composer = _buildFloatingInputBar();

    return AnimatedBuilder(
      animation: Listenable.merge([_emojiRevealController, _emojiPanelMounted]),
      builder: (context, _) {
        final panelMounted = _emojiPanelMounted.value;
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
        final panelHeight = _emojiPanelHeight;
        final panelSpace = panelMounted ? panelHeight * _emojiRevealController.value : 0.0;

        // One reserved area for both keyboard and emoji panel. Whichever is
        // taller wins, so swapping between them never moves the composer.
        final reserved = math.max(keyboard, math.max(safeBottom, panelSpace));

        return PopScope(
          canPop: !(panelMounted && _isEmojiPanelOpen),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isEmojiPanelOpen) _closeEmojiPanel();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              composer,
              SizedBox(
                height: reserved,
                child: !panelMounted
                    ? null
                    : Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: panelHeight,
                            child: _emojiPanelFor(safeBottom),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // One picker is kept and reused while the keyboard animates, since building
  // it is expensive.
  Widget _emojiPanelFor(double safeBottom) {
    final cached = _cachedEmojiPanel;
    if (cached != null &&
        _cachedEmojiPanelDark == true &&
        _cachedEmojiPanelSafeBottom == safeBottom) {
      return cached;
    }
    _cachedEmojiPanelDark = true;
    _cachedEmojiPanelSafeBottom = safeBottom;
    return _cachedEmojiPanel = RepaintBoundary(child: _buildEmojiPanel(safeBottom));
  }

  Widget _buildEmojiPanel(double safeBottom) {
    const accentColor = ChatmeColors.accentPrimary;
    const panelBg = ChatmeColors.surfaceRaised;
    const iconColor = ChatmeColors.textMuted;
    const dividerColor = ChatmeColors.dividerSubtle;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: panelBg,
        border: Border(top: BorderSide(color: dividerColor, width: 0.5)),
      ),
      child: Column(
        children: [
          Expanded(
            child: emoji.EmojiPicker(
              textEditingController: _messageController,
              config: const emoji.Config(
                height: null,
                emojiViewConfig: emoji.EmojiViewConfig(
                  columns: 8,
                  emojiSizeMax: 28,
                  backgroundColor: panelBg,
                  verticalSpacing: 2,
                  horizontalSpacing: 2,
                  gridPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  noRecents: Text(
                    'No recent emoji',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                  ),
                ),
                categoryViewConfig: emoji.CategoryViewConfig(
                  initCategory: emoji.Category.SMILEYS,
                  backgroundColor: panelBg,
                  iconColor: iconColor,
                  iconColorSelected: accentColor,
                  indicatorColor: accentColor,
                  backspaceColor: accentColor,
                  dividerColor: Colors.transparent,
                ),
                bottomActionBarConfig: emoji.BottomActionBarConfig(
                  backgroundColor: panelBg,
                  buttonColor: Colors.transparent,
                  buttonIconColor: iconColor,
                  showSearchViewButton: false,
                  showBackspaceButton: true,
                ),
              ),
            ),
          ),
          SizedBox(height: safeBottom),
        ],
      ),
    );
  }

  Widget _buildFloatingInputBar() {
    const accentColor = ChatmeColors.accentPrimary;
    const onAccentColor = ChatmeColors.onAccent;
    const inputBgColor = ChatmeColors.surfaceRaised;
    const inputTextColor = ChatmeColors.textPrimary;
    const inputHintColor = ChatmeColors.textSubtle;

    return SafeArea(
      top: false,
      bottom: false,
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
                color: Colors.black.withAlpha(30),
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
                _buildRecordingBar(accentColor, onAccentColor, inputTextColor),
              Offstage(
                offstage: _isRecording,
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: _composerBarHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Material(
                            type: MaterialType.transparency,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkResponse(
                              onTap: _toggleEmojiPanel,
                              containedInkWell: true,
                              highlightShape: BoxShape.circle,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(scale: animation, child: child),
                                  child: Icon(
                                    (_isEmojiPanelOpen && !_isEmojiPanelClosing)
                                        ? Icons.keyboard
                                        : Icons.emoji_emotions_outlined,
                                    key: ValueKey(_isEmojiPanelOpen && !_isEmojiPanelClosing),
                                    color: (_isEmojiPanelOpen && !_isEmojiPanelClosing)
                                        ? accentColor
                                        : ChatmeColors.textSecondary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: _composerBarHeight,
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 5,
                        minLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          color: inputTextColor,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            color: inputHintColor,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  if (!kIsWeb)
                    SizedBox(
                      height: _composerBarHeight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: _hasText ? 0 : 40,
                        child: ClipRect(
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: 40,
                            alignment: Alignment.centerRight,
                            child: IgnorePointer(
                              ignoring: _hasText,
                              child: AnimatedSlide(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                offset: _hasText ? const Offset(1, 0) : Offset.zero,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 150),
                                  opacity: _hasText ? 0 : 1,
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: ChatmeMenuButton<ImageSource>(
                                        requestFocus: false,
                                        offset: const Offset(0, -90),
                                        color: inputBgColor,
                                        textColor: inputTextColor,
                                        icon: const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 24,
                                          color: ChatmeColors.textSecondary,
                                        ),
                                        onSelected: _pickImage,
                                        entries: const [
                                          ChatmeMenuEntry(
                                            value: ImageSource.camera,
                                            icon: Icons.photo_camera_outlined,
                                            label: 'Camera',
                                          ),
                                          ChatmeMenuEntry(
                                            value: ImageSource.gallery,
                                            icon: Icons.photo_library_outlined,
                                            label: 'Gallery',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                            decoration: const BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: _isSending
                                  ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: onAccentColor))
                                  : Icon(
                                      (_hasText || kIsWeb) ? Icons.send_rounded : Icons.mic_rounded,
                                      color: onAccentColor,
                                      size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposerLinkPreview() {
    final data = _composerPreview!;
    const bgColor = ChatmeColors.surfaceOverlay;
    const titleColor = ChatmeColors.accentPrimary;
    const subColor = ChatmeColors.textSecondary;

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
                      style: const TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      data.description ?? data.host,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: subColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: subColor),
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
    const nameColor = ChatmeColors.accentPrimary;
    const bgColor = ChatmeColors.surfaceOverlay;
    const previewTextColor = ChatmeColors.textSecondary;
    const iconThemeColor = ChatmeColors.accentPrimary;

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
          const Icon(Icons.reply, color: iconThemeColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _getReplyName(_replyingTo!.senderPubkey),
                    style: const TextStyle(
                        color: nameColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12
                    )
                ),
                Text(
                    _formatMessagePreview(_replyingTo!.plaintext),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: previewTextColor,
                        fontSize: 12
                    )
                ),
              ],
            ),
          ),
          IconButton(
              icon: const Icon(
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

    if (!shouldReply || !canReplyTo(message)) return;

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

    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;
    final bubbleColor = isMe ? ChatmeColors.bubbleOutgoing : ChatmeColors.bubbleIncoming;
    final textColor = isMe ? ChatmeColors.onAccent : ChatmeColors.textPrimary;

    final previewUrl = AppSettings.instance.linkPreviewsEnabled
        ? LinkPreviewService.extractFirstUrl(message.plaintext)
        : null;
    final hasReply = message.replyToContent != null;

    return MessageBubble(
      message: message,
      isMe: isMe,
      bubbleColor: bubbleColor,
      textColor: textColor,
      footer: _buildBubbleFooter(message, textColor),
      imageFooter: _buildBubbleFooter(message, ChatmeColors.textPrimary, dim: false),
      previewUrl: previewUrl,
      replySenderName: hasReply
          ? _getReplyName(_resolveReplySenderPubkey(message))
          : null,
      replyPreview: hasReply
          ? _formatMessagePreview(message.replyToContent!)
          : null,
      onReplyTap: () => _scrollToMessage(message.replyToId),
      onLongPressStart: (details) =>
          _showReactionPopup(context, details.globalPosition, message),
    );
  }

  Widget _buildBubbleFooter(
    ChatMessage message,
    Color color, {
    bool dim = true,
  }) {
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;
    final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final timeStr = DateFormat(is24Hour ? 'HH:mm' : 'h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(message.timestamp),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            color: dim ? color.withAlpha(153) : color,
            fontSize: 11,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(message.status, color),
        ],
      ],
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
            return const Icon(
              Icons.done_all,
              size: 13,
              color: ChatmeColors.readReceipt,
            );
          },
        );
      case 'error':
        return const Icon(Icons.error_outline, size: 13, color: ChatmeColors.statusDanger);
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
            decoration: const InputDecoration(
              hintText: 'Enter name',
              border: InputBorder.none,
            ),
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
    final isMe = message.senderPubkey == AppSettings.instance.myPubkey;

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

    const normalTextColor = ChatmeColors.textPrimary;
    final textColor = isMissed ? ChatmeColors.statusDanger : (isMe ? ChatmeColors.onAccent : ChatmeColors.textPrimary);
    final iconColor = isMissed ? ChatmeColors.statusDanger : textColor;
    final timeColor = (isMe ? ChatmeColors.onAccent : normalTextColor).withAlpha(153);

    final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final timeStr = DateFormat(is24Hour ? 'HH:mm' : 'h:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final bubbleColor = isMe ? ChatmeColors.bubbleOutgoing : ChatmeColors.bubbleIncoming;

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
          border: !isMe ? Border.all(color: ChatmeColors.borderSubtle, width: 0.5) : null,
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