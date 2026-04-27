import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/reel.dart';
import '../player/reel_constants.dart';
import '../player/reel_controller_pool.dart';

class ReelPlayerWidget extends StatefulWidget {
  final Reel reel;
  final bool isLiked;
  final int viewCount;
  final int likeCount;
  final bool isActive;
  final BetterPlayerController? controller;
  final bool enablePreload;
  final bool shouldPreload;
  final String? nextBunnyUrl;

  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onRedirect;
  final VoidCallback? onSubscribeClick;
  final VoidCallback onViewed;
  final VoidCallback? onLogoTap;

  const ReelPlayerWidget({
    super.key,
    required this.reel,
    required this.isLiked,
    required this.viewCount,
    required this.likeCount,
    required this.isActive,
    this.controller,
    this.enablePreload = true,
    this.shouldPreload = false,
    this.nextBunnyUrl,
    required this.onLike,
    required this.onShare,
    required this.onRedirect,
    this.onSubscribeClick,
    required this.onViewed,
    this.onLogoTap,
  });

  @override
  State<ReelPlayerWidget> createState() => _ReelPlayerWidgetState();
}

class _ReelPlayerWidgetState extends State<ReelPlayerWidget>
    with WidgetsBindingObserver {
  BetterPlayerController? _controller;
  bool _isLoading = true;
  bool _nativeStarted = false;
  bool _isUserPaused = false;
  bool _isVisibleEnough = false;
  bool _showLikeHeart = false;
  bool _wasPlayingBeforeBackground = false;

  Timer? _viewTimer;
  bool _hasRecordedView = false;
  static const _viewDuration = Duration(seconds: 3);

  Timer? _loadingTimeoutTimer;
  static const _loadingTimeout = Duration(seconds: 10);

  DateTime? _lastTapTime;
  static const _doubleTapDuration = Duration(milliseconds: 300);

  bool _descriptionExpanded = false;

  late final ValueNotifier<int> _progressSecondsNotifier;
  Timer? _progressTimer;
  int? _playerDurationSeconds;
  int? _dragSeekTarget;

  void _setStateSafely(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
      return;
    }
    setState(fn);
  }

  void _onBetterPlayerEvent(BetterPlayerEvent event) {
    if (event.betterPlayerEventType != BetterPlayerEventType.progress) return;
    final params = event.parameters;
    if (params == null) return;
    final progress = params['progress'] as Duration?;
    final duration = params['duration'] as Duration?;
    if (progress == null || duration == null || duration.inSeconds <= 0) return;
    if (!mounted) return;
    if (!_nativeStarted) {
      _nativeStarted = true;
      _cancelLoadingTimeout();
      if (_isLoading) {
        _setStateSafely(() => _isLoading = false);
      }
    }
    final seconds = progress.inSeconds;
    final durationSeconds = duration.inSeconds;
    final next = seconds.clamp(0, durationSeconds);
    if (_progressSecondsNotifier.value != next) {
      _progressSecondsNotifier.value = next;
    }
    if (durationSeconds > 0 && _playerDurationSeconds != durationSeconds) {
      _setStateSafely(() {
        _playerDurationSeconds = durationSeconds;
      });
    }
  }

  bool get _shouldPlayNow => widget.isActive && _isVisibleEnough && !_isUserPaused;

  bool _descriptionExceeds70Percent(BuildContext context, String text, TextStyle style) {
    if (text.isEmpty) return false;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth * _descriptionMaxWidthFactor;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.size.height > screenHeight * 0.7;
  }

  int get _durationSeconds {
    final fromPlayer = _playerDurationSeconds;
    final fromModel = widget.reel.durationSeconds;
    final effective = fromPlayer ?? fromModel;
    return effective > 0 ? effective : ReelConstants.defaultDurationSeconds;
  }

  @override
  void initState() {
    super.initState();
    _progressSecondsNotifier = ValueNotifier<int>(0);
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller;
    final shouldInit = widget.reel.bunnyUrl.isNotEmpty &&
        (widget.isActive || widget.shouldPreload);
    if (_controller != null) {
      _setupCurrent();
    } else if (shouldInit) {
      _setStateSafely(() => _isLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _wasPlayingBeforeBackground = _shouldPlayNow;
      _pauseVideo();
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforeBackground && _shouldPlayNow) {
        _playVideo();
      }
    }
  }

  @override
  void didUpdateWidget(ReelPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeEventsListener(_onBetterPlayerEvent);
      _controller = widget.controller;
      _isUserPaused = false;
      _nativeStarted = false;
      _hasRecordedView = false;
      _cancelLoadingTimeout();
      if (_controller != null) {
        _setupCurrent();
      } else if (widget.reel.bunnyUrl.isNotEmpty && widget.isActive) {
        _setStateSafely(() => _isLoading = false);
      }
    }
    if (oldWidget.reel.id != widget.reel.id ||
        oldWidget.reel.bunnyUrl != widget.reel.bunnyUrl) {
      _descriptionExpanded = false;
      _isUserPaused = false;
      _nativeStarted = false;
      _hasRecordedView = false;
      _progressSecondsNotifier.value = 0;
      _progressTimer?.cancel();
      _cancelLoadingTimeout();
      _controller?.removeEventsListener(_onBetterPlayerEvent);
      if (_controller != null) {
        _setupCurrent();
      } else if (widget.reel.bunnyUrl.isNotEmpty && (widget.isActive || widget.shouldPreload)) {
        _setStateSafely(() => _isLoading = false);
      }
    }

    final shouldInit = widget.reel.bunnyUrl.isNotEmpty &&
        (widget.isActive || widget.shouldPreload);
    if (shouldInit && _controller == null) {
      _setStateSafely(() => _isLoading = false);
    }

    if (!widget.isActive) {
      _pauseVideo();
      _cancelViewTimer();
      _progressTimer?.cancel();
    } else {
      _syncPlaybackState();
    }
    _startOrStopProgressTimer();

    if (widget.enablePreload && widget.nextBunnyUrl != oldWidget.nextBunnyUrl) {
      _preloadNext();
    }
  }

  void _startOrStopProgressTimer() {
    _progressTimer?.cancel();
    if (!_shouldPlayNow || _controller == null) {
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelViewTimer();
    _progressTimer?.cancel();
    _cancelLoadingTimeout();
    _controller?.removeEventsListener(_onBetterPlayerEvent);
    _progressSecondsNotifier.dispose();
    // Don't dispose the BetterPlayerController here.
    // It may be shared (pooled) and BetterPlayer widget might already be unmounting.
    // Controller lifecycle is managed by ReelControllerPool.
    super.dispose();
  }

  void _cancelLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  void _startLoadingTimeout() {
    _cancelLoadingTimeout();
    _loadingTimeoutTimer = Timer(_loadingTimeout, () {
      if (!mounted) return;
      if (_isLoading && widget.isActive) {
        debugPrint('ReelPlayerWidget: loading timeout');
        _setStateSafely(() => _isLoading = false);
      }
    });
  }

  Future<void> _setupCurrent() async {
    if (_controller == null) return;
    if (widget.reel.bunnyUrl.isEmpty) return;

    final currentController = _controller;
    if (currentController == null || !reelControllerPool.contains(currentController)) {
      return;
    }

    debugPrint('Reel VIDEO URL: ${widget.reel.bunnyUrl}');

    _nativeStarted = false;
    _setStateSafely(() => _isLoading = true);
    _startLoadingTimeout();
    currentController.removeEventsListener(_onBetterPlayerEvent);
    currentController.addEventsListener(_onBetterPlayerEvent);
    try {
      final ok = await reelControllerPool.setDataSource(
        currentController,
        url: widget.reel.bunnyUrl,
      );
      if (!ok) {
        _setStateSafely(() => _isLoading = false);
        return;
      }
    } catch (e) {
      debugPrint('ReelPlayerWidget: setDataSource skipped after dispose: $e');
      return;
    }

    if (!mounted || _controller != currentController || !reelControllerPool.contains(currentController)) {
      return;
    }
    // Keep loading until first real progress event arrives from native player.
    // If it never arrives, the timeout handler will switch to fallback.
    if (widget.enablePreload) {
      unawaited(_preloadNext());
    }
    _syncPlaybackState();
  }

  Future<void> _preloadNext() async {
    final nextUrl = widget.nextBunnyUrl;
    if (nextUrl == null || nextUrl.isEmpty) return;
    final nextController = reelControllerPool.controllerAt(2);

    await reelControllerPool.setDataSource(
      nextController,
      url: nextUrl,
      forceStart: false,
    );
    await reelControllerPool.warmUp(nextController);
  }

  void _startViewTimer() {
    if (_hasRecordedView) return;
    _cancelViewTimer();

    _viewTimer = Timer(_viewDuration, () {
      if (mounted && _shouldPlayNow && !_hasRecordedView) {
        _hasRecordedView = true;
        widget.onViewed();
      }
    });
  }

  void _cancelViewTimer() {
    _viewTimer?.cancel();
    _viewTimer = null;
  }

  void _playVideo() {
    if (!_shouldPlayNow) return;
    if (_controller != null) {
      try {
        if (reelControllerPool.contains(_controller!)) {
          _controller!.play();
        }
      } catch (e) {
        debugPrint('ReelPlayerWidget: play skipped after dispose: $e');
      }
      _startViewTimer();
    }
    _startOrStopProgressTimer();
  }

  void _pauseVideo() {
    if (_controller != null) {
      try {
        _controller!.pause();
      } catch (_) {}
    }
    _progressTimer?.cancel();
  }

  void _togglePlayPause() {
    final wasPaused = _isUserPaused;
    _isUserPaused = !_isUserPaused;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        _controller != null &&
        wasPaused &&
        !_isUserPaused) {
      unawaited(_controller!.setVolume(1.0));
    }
    _syncPlaybackState();
  }

  void _syncPlaybackState() {
    if (!mounted) return;
    if (_shouldPlayNow) {
      _playVideo();
    } else {
      _pauseVideo();
      _cancelViewTimer();
    }
    _setStateSafely(() {});
  }

  void _handleTap() {
    final now = DateTime.now();

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < _doubleTapDuration) {
      _lastTapTime = null;
      widget.onLike();
      _showLikeAnimation();
    } else {
      _lastTapTime = now;
      _togglePlayPause();
    }
  }

  void _onProgressBarTap(double tapPosition, double totalWidth) {
    if (_durationSeconds <= 0) return;
    if (totalWidth <= 0) return;
    
    final progress = (1.0 - (tapPosition / totalWidth)).clamp(0.0, 1.0);
    final targetSeconds = (progress * _durationSeconds).round().clamp(0, _durationSeconds);
    
    _seekToSeconds(targetSeconds);
  }

  void _onProgressBarDragUpdate(double dragPosition, double totalWidth) {
    if (_durationSeconds <= 0) return;
    if (totalWidth <= 0) return;

    final progress = (1.0 - (dragPosition / totalWidth)).clamp(0.0, 1.0);
    final targetSeconds =
        (progress * _durationSeconds).round().clamp(0, _durationSeconds);

    _progressSecondsNotifier.value = targetSeconds;
    _dragSeekTarget = targetSeconds;
  }

  void _seekToSeconds(int targetSeconds) {
    _progressSecondsNotifier.value = targetSeconds;

    if (_controller != null) {
      _seekAndResume(targetSeconds);
    }
  }

  Future<void> _seekAndResume(int targetSeconds) async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      if (!reelControllerPool.contains(controller)) return;
      await controller.seekTo(Duration(seconds: targetSeconds));
      if (!mounted) return;
      if (_shouldPlayNow) {
        await controller.play();
      }
    } catch (e) {
      if (mounted) debugPrint('ReelPlayerWidget: Seek error: $e');
    }
  }

  void _showLikeAnimation() {
    _setStateSafely(() => _showLikeHeart = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _setStateSafely(() => _showLikeHeart = false);
      }
    });
  }

  static const _descriptionMaxWidthFactor = 0.55;
  static const _screenHeightThreshold = 0.7;

  Widget _buildDescription(BuildContext context, {double? maxWidth}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final effectiveMaxWidth = maxWidth ?? (screenWidth * _descriptionMaxWidthFactor);
    final description = widget.reel.description.isNotEmpty
        ? widget.reel.description
        : 'تعلم كيفية نطق الحروف';
    final style = TextStyle(
      color: Colors.white.withOpacity(0.7),
      fontSize: Responsive.fontSize(context, 13),
    );
    final shouldTruncate = _descriptionExceeds70Percent(context, description, style) && !_descriptionExpanded;
    final constraints = BoxConstraints(maxWidth: effectiveMaxWidth);

    if (!shouldTruncate) {
      return ConstrainedBox(
        constraints: constraints,
        child: Text(
          description,
          style: style,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          softWrap: true,
          overflow: TextOverflow.clip,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _setStateSafely(() => _descriptionExpanded = true),
      child: ConstrainedBox(
        constraints: constraints,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          textDirection: TextDirection.rtl,
          children: [
            Flexible(
              child: Text(
                description,
                style: style,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            SizedBox(width: Responsive.width(context, 4)),
            Text(
              '... المزيد',
              style: style.copyWith(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final showPausedOverlay = _isUserPaused || (!_shouldPlayNow && widget.isActive);

    return VisibilityDetector(
      key: ValueKey('reel_visibility_${widget.reel.id}'),
      onVisibilityChanged: (info) {
        final nowVisible = info.visibleFraction > 0.6;
        if (nowVisible == _isVisibleEnough) return;
        _isVisibleEnough = nowVisible;
        _syncPlaybackState();
      },
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && widget.reel.bunnyUrl.isNotEmpty)
              BetterPlayer(controller: _controller!)
            else
              _buildThumbnail(context),

            if (showPausedOverlay)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: Responsive.padding(context, all: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: Responsive.iconSize(context, 50),
                    ),
                  ),
                ),
              ),

          if (_showLikeHeart)
            IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: Responsive.iconSize(context, 100),
                ),
              ),
            ),

          if (_isLoading && widget.reel.bunnyUrl.isNotEmpty && widget.isActive)
            IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFFFFC107),
                  strokeWidth: Responsive.width(context, 2),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: Responsive.height(context, 250),
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF1A1A1A),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: Responsive.height(context, 2)),
                  ValueListenableBuilder<int>(
                    valueListenable: _progressSecondsNotifier,
                    builder: (context, seconds, _) {
                      final progress = _durationSeconds > 0
                          ? (seconds / _durationSeconds).clamp(0.0, 1.0)
                          : 0.0;
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final barWidth = constraints.maxWidth;
                          return GestureDetector(
                            onTap: () {},
                            onTapDown: (details) {
                              final RenderBox? box = context.findRenderObject() as RenderBox?;
                              if (box != null && box.hasSize) {
                                final localPos = box.globalToLocal(details.globalPosition);
                                final tapX = localPos.dx.clamp(0.0, barWidth);
                                _onProgressBarTap(tapX, barWidth);
                              }
                            },
                            onHorizontalDragStart: (details) {
                              final RenderBox? box =
                                  context.findRenderObject() as RenderBox?;
                              if (box != null && box.hasSize) {
                                final localPos =
                                    box.globalToLocal(details.globalPosition);
                                final dragX = localPos.dx.clamp(0.0, barWidth);
                                _onProgressBarDragUpdate(dragX, barWidth);
                              }
                            },
                            onHorizontalDragUpdate: (details) {
                              final RenderBox? box =
                                  context.findRenderObject() as RenderBox?;
                              if (box != null && box.hasSize) {
                                final localPos =
                                    box.globalToLocal(details.globalPosition);
                                final dragX = localPos.dx.clamp(0.0, barWidth);
                                _onProgressBarDragUpdate(dragX, barWidth);
                              }
                            },
                            onHorizontalDragEnd: (_) {
                              final target = _dragSeekTarget;
                              if (target != null) {
                                _seekToSeconds(target);
                                _dragSeekTarget = null;
                              }
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              height: Responsive.height(context, 20),
                              padding: EdgeInsets.symmetric(
                                vertical: Responsive.height(context, 8.5),
                              ),
                              child: Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  Container(
                                    width: barWidth * progress,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFC107),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (_isUserPaused && _durationSeconds > 0) ...[
                    SizedBox(height: Responsive.height(context, 6)),
                    ValueListenableBuilder<int>(
                      valueListenable: _progressSecondsNotifier,
                      builder: (context, seconds, _) {
                        return Padding(
                          padding: EdgeInsets.only(
                            top: Responsive.height(context, 6),
                            left: Responsive.width(context, 16),
                            right: Responsive.width(context, 16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(seconds),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: Responsive.fontSize(context, 12),
                                ),
                              ),
                              Text(
                                '${_formatDuration((_durationSeconds - seconds).clamp(0, _durationSeconds))} متبقي',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: Responsive.fontSize(context, 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          Positioned(
            left: Responsive.width(context, 16),
            right: Responsive.width(context, 16),
            bottom: bottomPadding + Responsive.height(context, 40),
            child: IgnorePointer(
              ignoring: false,
              child: Builder(
                builder: (context) {
                  final isTablet = Responsive.isTablet(context);

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: widget.onLogoTap,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildAvatar(context),
                                SizedBox(width: Responsive.width(context, 8)),
                                Flexible(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.reel.owner.name.isNotEmpty
                                            ? widget.reel.owner.name
                                            : 'ليرنفاي',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize:
                                              Responsive.fontSize(context, 16),
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(
                                          height: Responsive.spacing(context, 6)),
                                      _buildDescription(context),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        SizedBox(height: Responsive.spacing(context, 14)),
                        GestureDetector(
                          onTap: () {
                            debugPrint('ReelPlayerWidget: Subscribe button tapped');
                            if (widget.onSubscribeClick != null) {
                              debugPrint('ReelPlayerWidget: Calling onSubscribeClick');
                              widget.onSubscribeClick!();
                            } else {
                              debugPrint('ReelPlayerWidget: onSubscribeClick is null, calling onRedirect');
                              widget.onRedirect();
                            }
                          },
                          child: Container(
                            padding: Responsive.padding(context,
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(
                                  Responsive.radius(context, 16)),
                            ),
                            child: Text(
                              'اشترك من هنا',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: Responsive.fontSize(context, 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: widget.onLike,
                          child: Icon(
                            Icons.favorite,
                            color: widget.isLiked ? Colors.red : Colors.white,
                            size: Responsive.iconSize(context, 38),
                          ),
                        ),
                        SizedBox(height: Responsive.spacing(context, 4)),
                        IgnorePointer(
                          child: Text(
                            _formatCount(widget.likeCount),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: Responsive.fontSize(context, 13),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(height: Responsive.spacing(context, isTablet?5:20)),
                        GestureDetector(
                          onTap: widget.onShare,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(3.14159),
                            child: Icon(
                              Icons.reply,
                              color: Colors.white,
                              size: Responsive.iconSize(context, 32),
                            ),
                          ),
                        ),
                        SizedBox(height: Responsive.spacing(context, 4)),
                        IgnorePointer(
                          child: Text(
                            'مشاركة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: Responsive.fontSize(context, 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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

  Widget _buildThumbnail(BuildContext context) {
    if (widget.reel.thumbnailUrl.isEmpty) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white24,
            size: Responsive.iconSize(context, 80),
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheW = (size.width * dpr).round().clamp(540, 1080);
    final cacheH = (size.height * dpr).round().clamp(960, 1920);
    return CachedNetworkImage(
      imageUrl: widget.reel.thumbnailUrl,
      fit: BoxFit.cover,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      placeholder: (context, url) => Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: CircularProgressIndicator(
            color: const Color(0xFFFFC107),
            strokeWidth: Responsive.width(context, 2),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white24,
            size: Responsive.iconSize(context, 80),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    final isTabletPortrait =
        isPortrait && media.size.shortestSide >= 600;
    final isTablet = Responsive.isTablet(context);

    final size = isTablet
        ? (isTabletPortrait
        ? Responsive.width(context, 36)
        : Responsive.width(context, 24))
        : Responsive.width(context, 36);

    Widget defaultAvatar() {
      return ClipOval(
        child: Container(
          width: size,
          height: size,
          color: Colors.white,
          child: Image.asset(
            'assets/images/app_logo.png',
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (widget.reel.owner.avatarUrl.isEmpty) {
      return defaultAvatar();
    }

    final cacheSize = (size * MediaQuery.of(context).devicePixelRatio).round().clamp(72, 256);
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: CachedNetworkImage(
          imageUrl: widget.reel.owner.avatarUrl,
          fit: BoxFit.cover,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          placeholder: (context, url) => defaultAvatar(),
          errorWidget: (context, url, error) => defaultAvatar(),
        ),
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
