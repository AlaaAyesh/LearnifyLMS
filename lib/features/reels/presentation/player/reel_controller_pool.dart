import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const BetterPlayerBufferingConfiguration _reelBufferingConfig =
    BetterPlayerBufferingConfiguration(
  minBufferMs: 2000,
  maxBufferMs: 10000,
  bufferForPlaybackMs: 500,
  bufferForPlaybackAfterRebufferMs: 500,
);

const BetterPlayerCacheConfiguration _reelCacheConfig =
    BetterPlayerCacheConfiguration(
  useCache: true,
  maxCacheSize: 128 * 1024 * 1024,
  maxCacheFileSize: 32 * 1024 * 1024,
  preCacheSize: 6 * 1024 * 1024,
);

class ReelControllerPool {
  static final ReelControllerPool _instance = ReelControllerPool._internal();
  factory ReelControllerPool() => _instance;
  ReelControllerPool._internal();

  static const int maxControllers = 3;

  final List<BetterPlayerController> _controllers = <BetterPlayerController>[];

  BetterPlayerController controllerAt(int slot) {
    assert(slot >= 0 && slot < maxControllers);
    while (_controllers.length < maxControllers) {
      _controllers.add(_createController());
    }
    return _controllers[slot];
  }

  BetterPlayerController _createController() {
    return BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: false,
        autoDispose: false,
        looping: true,
        handleLifecycle: true,
        allowedScreenSleep: false,
        autoDetectFullscreenDeviceOrientation: true,
        aspectRatio: 9 / 16,
        fit: BoxFit.cover,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
          enableFullscreen: false,
          enablePlayPause: false,
          enableMute: false,
          enableOverflowMenu: false,
          enableProgressText: false,
          enableProgressBar: true,
          enableSkips: false,
          enableSubtitles: false,
        ),
      ),
    );
  }

  void releaseSlot(int slot) {
    if (slot < 0 || slot >= _controllers.length) return;
    try {
      _controllers[slot].pause();
    } catch (_) {}
  }

  bool contains(BetterPlayerController controller) {
    return _controllers.contains(controller);
  }

  /// Bunny Stream `/play/{id}` → `{base}/{id}/playlist.m3u8` for HLS.
  static String toBunnyHlsUrl(String bunnyPlayUrl) {
    final url = bunnyPlayUrl.trim();
    if (url.isEmpty) return url;
    if (url.contains('.m3u8')) return url;
    if (!url.contains('/play/')) return url;
    final parts = url.split('/play/');
    if (parts.length != 2 || parts[1].isEmpty) return url;
    final pathPart = parts[1].split('?').first.trim();
    if (pathPart.isEmpty) return url;
    final base = parts[0];
    return '$base/$pathPart/playlist.m3u8';
  }

  static bool _isIosLikeReelsTarget() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Hybrid reels loading (no WebView): **iOS** prefers progressive (`other`);
  /// **Android** (and other non‑iOS) prefers **HLS** from [toBunnyHlsUrl].
  /// Falls back to the alternate strategy if the primary load fails.
  ///
  /// [forceStart]: when true, mutes on iOS then calls [play]. When false (preload),
  /// only binds the source; use [warmUp] to buffer.
  Future<bool> setDataSource(
    BetterPlayerController controller, {
    required String url,
    bool forceStart = true,
  }) async {
    if (url.trim().isEmpty) return false;

    try {
      controller.pause();
    } catch (_) {}

    final trimmed = url.trim();

    Future<void> tryLoad(String loadUrl, BetterPlayerVideoFormat format) async {
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        loadUrl,
        videoFormat: format,
        cacheConfiguration: _reelCacheConfig,
        bufferingConfiguration: _reelBufferingConfig,
      );
      await controller.setupDataSource(dataSource);
    }

    Future<bool> bindPrimary() async {
      if (_isIosLikeReelsTarget()) {
        await tryLoad(trimmed, BetterPlayerVideoFormat.other);
      } else {
        final hlsUrl = toBunnyHlsUrl(trimmed);
        await tryLoad(hlsUrl, BetterPlayerVideoFormat.hls);
      }
      return true;
    }

    Future<bool> bindFallback() async {
      if (_isIosLikeReelsTarget()) {
        final hlsUrl = toBunnyHlsUrl(trimmed);
        await tryLoad(hlsUrl, BetterPlayerVideoFormat.hls);
      } else {
        await tryLoad(trimmed, BetterPlayerVideoFormat.other);
      }
      return true;
    }

    Future<void> maybeForceStart() async {
      if (!forceStart) return;
      if (_isIosLikeReelsTarget()) {
        try {
          await controller.setVolume(0);
        } catch (_) {}
      }
      try {
        await controller.play();
      } catch (_) {}
    }

    try {
      await bindPrimary();
      await maybeForceStart();
      return true;
    } catch (e) {
      debugPrint('Reel primary load failed: $e');
    }

    try {
      await bindFallback();
      await maybeForceStart();
      return true;
    } catch (e) {
      debugPrint('Reel fallback load failed: $e');
    }

    return false;
  }

  Future<void> warmUp(BetterPlayerController controller) async {
    try {
      await controller.setVolume(0);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await controller.pause();
      await controller.seekTo(Duration.zero);
    } catch (_) {}
  }

  void pauseAll() {
    for (final c in _controllers) {
      try {
        c.pause();
      } catch (_) {}
    }
  }

  void disposeAll() {
    final toDispose = List<BetterPlayerController>.from(_controllers);
    _controllers.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in toDispose) {
        try {
          c.dispose(forceDispose: true);
        } catch (_) {}
      }
    });
  }

  void clearPool() {
    _controllers.clear();
  }
}

final reelControllerPool = ReelControllerPool();
