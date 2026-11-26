import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:video_player/video_player.dart';

import '../core/utils/time_utils.dart';
import '../models/contact.dart';
import '../relay_manager.dart';
import '../room_chat.dart';
import '../services/app_settings.dart';
import '../widgets/chatme_menu.dart';
import '../widgets/user_avatar.dart';
import 'story_item.dart';
import 'story_manager.dart';
import 'story_timing.dart';
import 'story_viewers_panel.dart';

/// Opens the author's room chat in place of the story route. Replacing the
/// route means going back lands on the chats page, not back on the story.
void openStoryAuthorChat(
  BuildContext context, {
  required String authorPubkey,
  required String displayName,
  required RelayManager relayManager,
  Widget Function(Contact contact, RelayManager relayManager)? buildChatPage,
}) {
  final contact = Hive.box<Contact>('contacts').get(authorPubkey) ??
      Contact(pubkey: authorPubkey, name: displayName);
  final chatPage = buildChatPage ??
      (contact, relay) => ChatDetailScreen(contact: contact, relayManager: relay);
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => chatPage(contact, relayManager)),
  );
}

class StoryViewerPage extends StatefulWidget {
  final RelayManager relayManager;
  final String initialAuthorPubkey;

  const StoryViewerPage({
    super.key,
    required this.relayManager,
    required this.initialAuthorPubkey,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  late String _authorPubkey;
  int _index = 0;
  int _loadGeneration = 0;
  VideoPlayerController? _video;
  Timer? _imageTimer;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  StoryPlayback? _playback;
  bool _loadingMedia = false;
  String? _mediaPath;
  bool _viewersOpen = false;

  List<StoryItem> get _stories =>
      StoryManager.instance.activeStories(authorPubkey: _authorPubkey);

  @override
  void initState() {
    super.initState();
    _authorPubkey = widget.initialAuthorPubkey;
    _loadCurrent();
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _disposeVideo();
    _progress.dispose();
    super.dispose();
  }

  void _disposeVideo() {
    final controller = _video;
    _video = null;
    controller?.removeListener(_onVideoTick);
    unawaited(controller?.dispose());
  }

  void _stopProgress() {
    _imageTimer?.cancel();
    _imageTimer = null;
    _playback = null;
    _progress.value = 0;
  }

  void _onVideoTick() {
    if (!mounted) return;
    final playback = _playback;
    if (playback == null || playback.isPaused) return;
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;

    final position = controller.value.position;
    _progress.value = StoryTiming.progress(position, duration);
    if (position >= duration - const Duration(milliseconds: 120)) {
      _next();
    }
  }

  void _startImageTicker() {
    _imageTimer?.cancel();
    final playback = _playback;
    if (playback == null || playback.isPaused) return;

    _imageTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted || _playback != playback) {
        timer.cancel();
        return;
      }
      final value = playback.progress;
      _progress.value = value;
      if (playback.isFinished) {
        timer.cancel();
        if (_imageTimer == timer) _imageTimer = null;
        _next();
      }
    });
  }

  /// Holding the media pauses it immediately; releasing resumes from the
  /// same point. Photos use the playback clock; videos pause their player so
  /// the visible frame stays put.
  void _pausePlayback() {
    final playback = _playback;
    if (playback == null || playback.isPaused) return;

    playback.pause();
    _imageTimer?.cancel();
    _imageTimer = null;
    final controller = _video;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      unawaited(() async {
        try {
          await controller.pause();
        } catch (_) {}
      }());
    }
  }

  void _resumePlayback() {
    final playback = _playback;
    if (playback == null || !playback.isPaused) return;

    playback.resume();
    final controller = _video;
    if (controller != null && controller.value.isInitialized) {
      unawaited(() async {
        try {
          await controller.play();
        } catch (_) {}
      }());
    } else {
      _startImageTicker();
    }
  }

  Future<void> _loadCurrent() async {
    final generation = ++_loadGeneration;
    final stories = _stories;
    if (stories.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (_index >= stories.length) _index = stories.length - 1;
    final story = stories[_index];

    _stopProgress();
    _disposeVideo();
    setState(() {
      _loadingMedia = true;
      _mediaPath = story.localPath.isNotEmpty ? story.localPath : null;
    });

    await StoryManager.instance.markViewed(
      story,
      relay: widget.relayManager,
    );
    if (!mounted || generation != _loadGeneration) return;
    final path = await StoryManager.instance.ensureLocalMedia(story);
    if (!mounted || generation != _loadGeneration) return;

    if (path != null && story.isVideo) {
      VideoPlayerController? controller;
      try {
        controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        if (!mounted || generation != _loadGeneration) {
          await controller.dispose();
          return;
        }
        await controller.setLooping(false);
        if (!mounted || generation != _loadGeneration) {
          await controller.dispose();
          return;
        }
        controller.addListener(_onVideoTick);
        _video = controller;
        await controller.play();
        if (!mounted || generation != _loadGeneration) return;
      } catch (_) {
        controller?.removeListener(_onVideoTick);
        if (generation == _loadGeneration) {
          if (_video == controller) _video = null;
          await controller?.dispose();
        }
      }
    }

    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loadingMedia = false;
      _mediaPath = path;
    });

    final duration = StoryTiming.durationFor(
      story,
      videoDuration: _video?.value.duration,
    );
    final playback = StoryPlayback(duration: duration);
    playback.start();
    _playback = playback;
    if (_video == null) _startImageTicker();
  }

  void _next() {
    final stories = _stories;
    if (_index < stories.length - 1) {
      setState(() => _index++);
      _loadCurrent();
    } else {
      _loadGeneration++;
      _stopProgress();
      _disposeVideo();
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _loadCurrent();
    }
  }

  /// Deletes the current story without a snackbar or a dialog. The viewer
  /// simply moves to the next story, or closes when there is none left.
  Future<void> _deleteCurrentStory() async {
    final stories = _stories;
    if (stories.isEmpty) return;
    final story = stories[_index.clamp(0, stories.length - 1)];
    _stopProgress();
    _disposeVideo();
    if (!mounted) return;
    setState(() => _loadingMedia = true);
    await StoryManager.instance.deleteStory(story, relay: widget.relayManager);
    if (!mounted) return;
    _loadCurrent();
  }

  String _displayName(String pubkey) {
    final contact = Hive.box<Contact>('contacts').get(pubkey);
    if (contact == null) return AppSettings.formatDisplayName(pubkey);
    return AppSettings.getContactDisplayName(contact);
  }

  List<StoryViewerEntry> _viewerEntries(StoryItem story) {
    final viewers = story.viewedBy.entries
        .where((e) => e.key != story.authorPubkey)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return viewers
        .map((e) => StoryViewerEntry(pubkey: e.key, name: _displayName(e.key)))
        .toList();
  }

  Widget _buildProgressBars(int count, int current, double progress) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == count - 1 ? 0 : 3),
              child: _ProgressSegment(
                value: i < current ? 1.0 : (i == current ? progress : 0.0),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = _stories;
    if (stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final index = _index.clamp(0, stories.length - 1);
    final story = stories[index];
    final isMine = story.authorPubkey == AppSettings.instance.myPubkey;
    final displayName =
        isMine ? AppSettings.instance.myName : _displayName(story.authorPubkey);
    final headerName = isMine ? 'Your story' : displayName;
    final timeLabel = TimeUtils.formatDayAndTime(
      story.createdAt,
      alwaysUse24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: StoryViewerGestures(
                onHoldStart: _pausePlayback,
                onHoldEnd: _resumePlayback,
                onNext: _next,
                onPrevious: _prev,
                child: _loadingMedia
                    ? const Center(child: CircularProgressIndicator())
                    : _mediaPath == null
                        ? const Center(
                            child: Text(
                              'Story unavailable',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : story.isVideo && _video != null
                            ? FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: _video!.value.size.width,
                                  height: _video!.value.size.height,
                                  child: VideoPlayer(_video!),
                                ),
                              )
                            : Image.file(File(_mediaPath!),
                                fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    automaticallyImplyLeading: false,
                    leading: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    titleSpacing: 0,
                    title: Row(
                      children: [
                        UserAvatar(
                          pubkey: story.authorPubkey,
                          name: displayName,
                          radius: 17,
                          relayManager: widget.relayManager,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (timeLabel.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  timeLabel,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      StoryMoreMenu(
                        canDelete: isMine,
                        onDelete: _deleteCurrentStory,
                        onMessage: () => openStoryAuthorChat(
                          context,
                          authorPubkey: story.authorPubkey,
                          displayName: displayName,
                          relayManager: widget.relayManager,
                        ),
                        onMenuOpened: _pausePlayback,
                        onMenuDismissed: _resumePlayback,
                      ),
                    ],
                  ),
                  Positioned(
                    top: 2,
                    left: 10,
                    right: 10,
                    child: AbsorbPointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (context, value, _) => _buildProgressBars(
                          stories.length,
                          index,
                          value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (story.caption.isNotEmpty && !_viewersOpen)
                    Padding(
                      padding: EdgeInsets.only(bottom: isMine ? 12 : 0),
                      child: Text(
                        story.caption,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (isMine) const SizedBox(height: 48),
                ],
              ),
            ),
            if (isMine)
              Positioned.fill(
                child: StoryViewersPanel(
                  viewCount: story.viewedBy.keys
                      .where((k) => k != story.authorPubkey)
                      .length,
                  viewers: _viewerEntries(story),
                  onDelete: _deleteCurrentStory,
                  onMessageViewer: (pubkey) => openStoryAuthorChat(
                    context,
                    authorPubkey: pubkey,
                    displayName: _displayName(pubkey),
                    relayManager: widget.relayManager,
                  ),
                  onExpandedChanged: (expanded) {
                    setState(() => _viewersOpen = expanded);
                    if (expanded) {
                      _pausePlayback();
                    } else {
                      _resumePlayback();
                    }
                  },
                  avatarBuilder: (pubkey, name) => UserAvatar(
                    pubkey: pubkey,
                    name: name,
                    radius: 16,
                    relayManager: widget.relayManager,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The three-dot button on the story header. My own story offers silent
/// delete; somebody else's story offers a message to its author. Opening the
/// menu holds the story, dismissing it lets the story run again.
class StoryMoreMenu extends StatelessWidget {
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onMessage;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuDismissed;

  const StoryMoreMenu({
    super.key,
    required this.canDelete,
    this.onDelete,
    this.onMessage,
    this.onMenuOpened,
    this.onMenuDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final entries = canDelete
        ? const [
            ChatmeMenuEntry<int>(value: 0, label: 'Delete story'),
          ]
        : const [
            ChatmeMenuEntry<int>(value: 0, label: 'Message'),
          ];
    return ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      entries: entries,
      onOpened: onMenuOpened,
      onCanceled: onMenuDismissed,
      onSelected: (_) {
        onMenuDismissed?.call();
        if (canDelete) {
          onDelete?.call();
        } else {
          onMessage?.call();
        }
      },
    );
  }
}

class _ProgressSegment extends StatelessWidget {
  final double value;

  const _ProgressSegment({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 3,
        color: Colors.white.withAlpha(70),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Story viewer gestures: hold the media to pause and release to resume, tap
/// the left half for the previous story and the right half for the next one,
/// and swipe horizontally for previous/next.
class StoryViewerGestures extends StatefulWidget {
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  const StoryViewerGestures({
    super.key,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  @override
  State<StoryViewerGestures> createState() => _StoryViewerGesturesState();
}

class _StoryViewerGesturesState extends State<StoryViewerGestures> {
  static const _holdDelay = Duration(milliseconds: 500);

  Timer? _holdTimer;
  bool _didHold = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onDown() {
    _didHold = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDelay, () => _didHold = true);
    widget.onHoldStart();
  }

  void _onUp() {
    _holdTimer?.cancel();
    _holdTimer = null;
    widget.onHoldEnd();
  }

  void _onTapUp(TapUpDetails details) {
    if (_didHold) return;
    final width = context.size?.width ?? 0;
    if (details.localPosition.dx < width / 2) {
      widget.onPrevious();
    } else {
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUp(),
      onPointerCancel: (_) => _onUp(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity <= -250) {
            widget.onNext();
          } else if (velocity >= 250) {
            widget.onPrevious();
          }
        },
        child: widget.child,
      ),
    );
  }
}
