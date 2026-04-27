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
        autoPlay: true,
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

  void releaseSlot(int slot) {
    if (slot < 0 || slot >= _controllers.length) return;
    try {
      _controllers[slot].pause();
    } catch (_) {}
  }

  bool contains(BetterPlayerController controller) {
    return _controllers.contains(controller);
  }

  static Future<void> _applyIosReelAutoplayMute(BetterPlayerController controller) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await controller.setVolume(0);
    } catch (_) {}
  }

  Future<bool> setDataSource(
    BetterPlayerController controller, {
    required String url,
    bool tryHlsFirst = true,
  }) async {
    if (url.trim().isEmpty) return false;

    try {
      controller.pause();
    } catch (_) {}

    final trimmed = url.trim();
    final hlsUrl = toBunnyHlsUrl(trimmed);

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

    if (tryHlsFirst) {
      try {
        await tryLoad(hlsUrl, BetterPlayerVideoFormat.hls);
        await _applyIosReelAutoplayMute(controller);
        return true;
      } catch (e) {
        debugPrint('Reel HLS failed: $e');
      }
    }

    if (hlsUrl != trimmed) {
      try {
        await tryLoad(trimmed, BetterPlayerVideoFormat.other);
        await _applyIosReelAutoplayMute(controller);
        return true;
      } catch (e) {
        debugPrint('Reel original URL (progressive) failed: $e');
      }
    }

    if (hlsUrl == trimmed) {
      try {
        await tryLoad(trimmed, BetterPlayerVideoFormat.other);
        await _applyIosReelAutoplayMute(controller);
        return true;
      } catch (e) {
        debugPrint('Reel same-URL other format failed: $e');
      }
    } else {
      try {
        await tryLoad(hlsUrl, BetterPlayerVideoFormat.other);
        await _applyIosReelAutoplayMute(controller);
        return true;
      } catch (e) {
        debugPrint('Reel HLS URL as progressive failed: $e');
      }
    }

    return false;
  }

  static bool isDirectStreamUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.contains('.m3u8') || u.contains('.mp4');
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

    // Disposing BetterPlayerController triggers VideoPlayerController notifications.
    // On iOS this can cause "widget tree locked" assertions if done during finalizeTree.
    // Dispose after the current frame to avoid tearing down while the framework is locked.
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

