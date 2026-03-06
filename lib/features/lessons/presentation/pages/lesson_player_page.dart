import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../res/assets_res.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/bunny_video_player.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../authentication/data/datasources/auth_local_datasource.dart';
import '../../../home/domain/entities/chapter.dart';
import '../../../home/domain/entities/course.dart';
import '../../../home/domain/entities/lesson.dart';
import '../bloc/lesson_bloc.dart';
import '../bloc/lesson_event.dart';
import '../bloc/lesson_state.dart';

const Color _durationTagPurple = Color(0xFFA667E4);

const Color _lessonCardBorder = Color(0xFFBDC1CA);
const Color _lessonCardShadow1 = Color(0x21171a1f);
const Color _lessonCardShadow2 = Color(0x14171a1f);

class LessonPlayerPage extends StatelessWidget {
  final int lessonId;
  final Lesson? lesson;
  final Course? course;
  final Chapter? chapter;
  final Function(double)? onProgressUpdate;

  const LessonPlayerPage({
    super.key,
    required this.lessonId,
    this.lesson,
    this.course,
    this.chapter,
    this.onProgressUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = sl<LessonBloc>();
        if (lessonId > 0) {
          bloc.add(LoadLessonEvent(lessonId: lessonId));
        }
        return bloc;
      },
      child: _LessonPlayerPageContent(
        lessonId: lessonId,
        initialLesson: lesson,
        course: course,
        chapter: chapter,
        onProgressUpdate: onProgressUpdate,
      ),
    );
  }
}

class _LessonPlayerPageContent extends StatefulWidget {
  final int lessonId;
  final Lesson? initialLesson;
  final Course? course;
  final Chapter? chapter;
  final Function(double)? onProgressUpdate;

  const _LessonPlayerPageContent({
    required this.lessonId,
    this.initialLesson,
    this.course,
    this.chapter,
    this.onProgressUpdate,
  });

  @override
  State<_LessonPlayerPageContent> createState() =>
      _LessonPlayerPageContentState();
}

class _LessonPlayerPageContentState extends State<_LessonPlayerPageContent> {
  bool _hasMarkedAsViewed = false;
  WebViewController? _videoController;
  String? _currentVideoUrl;

  DateTime? _videoStartTime;
  Timer? _progressTimer;
  double _currentProgress = 0.0;
  int? _videoDurationSeconds;

  bool? _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _checkAuthentication() async {
    try {
      final authLocalDataSource = sl<AuthLocalDataSource>();
      final token = await authLocalDataSource.getAccessToken();
      setState(() {
        _isAuthenticated = token != null && token.isNotEmpty;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();

    if (widget.lessonId > 0 && !_hasMarkedAsViewed) {
      if (kDebugMode) {
        debugPrint(
          'LessonPlayerPage: Marking lesson ${widget.lessonId} as viewed on dispose (fallback)',
        );
      }
      if (mounted) {
        context
            .read<LessonBloc>()
            .add(MarkLessonViewedEvent(lessonId: widget.lessonId));
      }
      if (widget.onProgressUpdate != null) {
        widget.onProgressUpdate!(1.0);
      }
    }

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  int? _parseDurationToSeconds(String? duration) {
    if (duration == null || duration.isEmpty) return null;
    try {
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final seconds = int.parse(parts[1]);
        return minutes * 60 + seconds;
      } else if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = int.parse(parts[2]);
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  void _startProgressTracking(Lesson lesson) {
    if (widget.lessonId <= 0) {
      if (kDebugMode) {
        debugPrint(
          'LessonPlayerPage: Skipping progress tracking for invalid lesson ID: ${widget.lessonId}',
        );
      }
      return;
    }

    if (_progressTimer != null && _progressTimer!.isActive) {
      if (kDebugMode) {
        debugPrint(
          'LessonPlayerPage: Progress tracking already started for lesson ${widget.lessonId}',
        );
      }
      return;
    }

    _videoDurationSeconds =
        _parseDurationToSeconds(lesson.videoDuration ?? lesson.duration);
    if (_videoDurationSeconds == null || _videoDurationSeconds! <= 0) {
      if (kDebugMode) {
        debugPrint(
          'LessonPlayerPage: Cannot start progress tracking - invalid duration for lesson ${widget.lessonId}',
        );
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'LessonPlayerPage: Starting progress tracking for lesson ${widget.lessonId} (duration: $_videoDurationSeconds seconds)',
      );
    }

    _videoStartTime = DateTime.now();
    _currentProgress = 0.0;
    _hasMarkedAsViewed = false;

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_videoStartTime == null || _videoDurationSeconds == null) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_videoStartTime!).inSeconds;
      final newProgress = (elapsed / _videoDurationSeconds!).clamp(0.0, 1.0);

      if (!mounted) {
        timer.cancel();
        return;
      }

      _currentProgress = newProgress;

      if (widget.onProgressUpdate != null) {
        widget.onProgressUpdate!(newProgress);
        if (kDebugMode) {
          debugPrint(
            'LessonPlayerPage: Progress update - lesson ${widget.lessonId}, progress: ${(newProgress * 100).toStringAsFixed(1)}%',
          );
        }
      }
    });
  }

  void _onVideoLoaded() {
    if (widget.lessonId > 0 && !_hasMarkedAsViewed) {
      _hasMarkedAsViewed = true;
      if (kDebugMode) {
        debugPrint(
          'LessonPlayerPage: Marking lesson ${widget.lessonId} as viewed (video loaded)',
        );
      }
      if (mounted) {
        context
            .read<LessonBloc>()
            .add(MarkLessonViewedEvent(lessonId: widget.lessonId));
        if (widget.onProgressUpdate != null) {
          widget.onProgressUpdate!(1.0);
        }
      }
    }
  }

  WebViewController _getVideoController(String videoUrl) {
    if (_videoController != null && _currentVideoUrl == videoUrl) {
      return _videoController!;
    }

    _currentVideoUrl = videoUrl;

    String embedUrl = videoUrl.replaceFirst('/play/', '/embed/');
    if (!embedUrl.contains('?')) {
      embedUrl = '$embedUrl?autoplay=true&responsive=true&aspectRatio=16:9';
    } else {
      embedUrl = '$embedUrl&autoplay=true&responsive=true&aspectRatio=16:9';
    }

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { 
      width: 100%; 
      height: 100%; 
      background: #000;
      overflow: hidden;
      margin: 0;
      padding: 0;
    }
    .video-wrapper {
      position: relative;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }
    iframe {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      border: 0;
      min-width: 100%;
      min-height: 100%;
    }
  </style>
</head>
<body>
  <div class="video-wrapper">
  <iframe 
    src="$embedUrl"
      allow="accelerometer;gyroscope;autoplay;encrypted-media;picture-in-picture;fullscreen"
    allowfullscreen="true">
  </iframe>
  </div>
</body>
</html>
''';

    _videoController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString(html);

    return _videoController!;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lessonId <= 0 && widget.initialLesson?.bunnyUrl != null) {
      return _buildPlayerPage(widget.initialLesson!);
    }

    return BlocConsumer<LessonBloc, LessonState>(
      listener: (context, state) {
        if (state is LessonError) {}
        if (state is LessonLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startProgressTracking(state.lesson);
          });
        }
      },
      builder: (context, state) {
        if (state is LessonLoading) return _buildLoadingScreen();
        if (state is LessonLoaded) return _buildPlayerPage(state.lesson);
        if (state is LessonError) {
          if (_isAuthenticated == null) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                setState(() {});
              }
            });
            return _buildLoadingScreen();
          }

          if (_canUseInitialLessonForFreeCourse(state.message)) {
            return _buildPlayerPage(widget.initialLesson!);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, 'accessDenied');
          });
          return _buildLoadingScreen();
        }
        return _buildLoadingScreen();
      },
    );
  }

  bool _canUseInitialLessonForFreeCourse(String errorMessage) {
    final isAccessDenied =
        errorMessage.toLowerCase().contains('access denied') ||
            errorMessage.toLowerCase().contains('permission') ||
            errorMessage.toLowerCase().contains('unauthorized') ||
            errorMessage.toLowerCase().contains('ليس لديك صلاحية');

    if (!isAccessDenied) return false;

    if (widget.course == null) return false;
    final isFreeCourse = widget.course!.price == null ||
        widget.course!.price!.isEmpty ||
        widget.course!.price == '0' ||
        widget.course!.price == '0.00';

    if (!isFreeCourse) return false;

    if (widget.initialLesson == null ||
        (widget.initialLesson!.bunnyUrl == null ||
            widget.initialLesson!.bunnyUrl!.isEmpty)) {
      return false;
    }

    return _isAuthenticated == true;
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: 'جاري التحميل',
        onBack: () => Navigator.pop(context, _currentProgress),
      ),
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Widget _buildPlayerPage(Lesson lesson) {
    final videoUrl = lesson.bunnyUrl;

    if (videoUrl == null || videoUrl.isEmpty) {
      return _buildNoVideoScreen(lesson);
    }

    if (_videoStartTime == null && widget.lessonId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startProgressTracking(lesson);
      });
    }

    final String appBarTitle = widget.course?.nameAr ?? lesson.nameAr;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: appBarTitle,
        onBack: () => _onBackPressed(lesson),
      ),
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: BunnyVideoPlayer(
                videoUrl: videoUrl,
                onVideoLoaded: () {
                  _onVideoLoaded();
                  if (widget.lessonId > 0) {
                    _startProgressTracking(lesson);
                  }
                },
              ),
            ),
            Padding(
              padding:
                  Responsive.padding(context, horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: Responsive.width(context, 40),
                    height: Responsive.width(context, 40),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _buildCourseOrLogoImage(lesson),
                    ),
                  ),
                  SizedBox(width: Responsive.width(context, 12)),
                  Expanded(
                    child: Text(
                      widget.course?.nameAr ?? lesson.nameAr,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: Responsive.fontSize(context, 14),
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.course != null && widget.course!.chapters.isNotEmpty
                  ? _buildChaptersLessonsList(lesson)
                  : _buildFallbackContent(lesson),
            ),
          ],
        ),
      ),
    );
  }

  void _onBackPressed(Lesson lesson) {
    if (widget.lessonId > 0 &&
        _videoStartTime != null &&
        _videoDurationSeconds != null &&
        _videoDurationSeconds! > 0) {
      final elapsed = DateTime.now().difference(_videoStartTime!).inSeconds;
      final finalProgress = (elapsed / _videoDurationSeconds!).clamp(0.0, 1.0);
      if (!_hasMarkedAsViewed) {
        _hasMarkedAsViewed = true;
        if (mounted)
          context
              .read<LessonBloc>()
              .add(MarkLessonViewedEvent(lessonId: widget.lessonId));
      }
      if (widget.onProgressUpdate != null)
        widget.onProgressUpdate!(finalProgress);
      if (mounted) Navigator.pop(context, finalProgress);
    } else {
      Navigator.pop(context, _currentProgress);
    }
  }

  Widget _buildCourseOrLogoImage(Lesson lesson) {
    final courseImageUrl = widget.course?.effectiveThumbnail;

    if (courseImageUrl != null && courseImageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: courseImageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Image.asset(
          AssetsRes.APP_LOGO,
          fit: BoxFit.cover,
        ),
        errorWidget: (_, __, ___) => Image.asset(
          AssetsRes.APP_LOGO,
          fit: BoxFit.cover,
        ),
      );
    }

    return Image.asset(
      AssetsRes.APP_LOGO,
      fit: BoxFit.cover,
    );
  }

  String _formatDurationToHms(String? duration) {
    if (duration == null || duration.isEmpty) return '00:00:00';
    final parts = duration.trim().split(':');
    int totalSeconds = 0;
    if (parts.length == 2) {
      totalSeconds =
          (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length >= 3) {
      totalSeconds = (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatCourseTotalDuration() {
    if (widget.course == null) return '00:00:00';
    int totalSeconds = 0;
    for (final chapter in widget.course!.chapters) {
      for (final l in chapter.lessons) {
        final d = l.videoDuration ?? l.duration;
        if (d != null && d.isNotEmpty) {
          final parts = d.split(':');
          if (parts.length == 2) {
            totalSeconds += (int.tryParse(parts[0]) ?? 0) * 60 +
                (int.tryParse(parts[1]) ?? 0);
          } else if (parts.length == 3) {
            totalSeconds += (int.tryParse(parts[0]) ?? 0) * 3600 +
                (int.tryParse(parts[1]) ?? 0) * 60 +
                (int.tryParse(parts[2]) ?? 0);
          }
        }
      }
    }
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildFallbackContent(Lesson lesson) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLessonInfoCard(lesson),
          if (lesson.description != null && lesson.description!.isNotEmpty)
            _buildDescriptionSection(lesson),
          SizedBox(height: Responsive.spacing(context, 24)),
        ],
      ),
    );
  }

  Widget _buildDurationChip() {
    return Container(
      height: Responsive.height(context, 36),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.width(context, 9),
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _durationTagPurple,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatCourseTotalDuration(),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: Responsive.fontSize(context, 14),
              height: 22 / 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          SizedBox(width: Responsive.width(context, 3)),
          Icon(
            Icons.schedule,
            size: Responsive.iconSize(context, 20),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersLessonsList(Lesson currentLesson) {
    final hasAccess = widget.course!.hasAccess;

    return ListView.builder(
      padding: Responsive.padding(context, bottom: 24),
      itemCount: widget.course!.chapters.length,
      itemBuilder: (context, chapterIndex) {
        final chapter = widget.course!.chapters[chapterIndex];
        final isFirstChapter = chapterIndex == 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: Responsive.padding(context,
                  left: 16, right: 16, top: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      chapter.nameAr,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: Responsive.fontSize(context, 16),
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isFirstChapter) _buildDurationChip(),
                ],
              ),
            ),
            // نعرض الدروس من الأقدم إلى الأحدث في شاشة المشغّل
            ...chapter.lessons.map((lesson) {
              final isCurrent = lesson.id == currentLesson.id;
              final isViewed = lesson.viewed;
              final isLocked =
                  !hasAccess && lesson.id != currentLesson.id && lesson.id != 0;

              return _buildLessonRow(
                lesson: lesson,
                isCurrent: isCurrent,
                isViewed: isViewed,
                isLocked: isLocked,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildLessonRow({
    required Lesson lesson,
    required bool isCurrent,
    required bool isViewed,
    required bool isLocked,
  }) {
    final bgColor = isCurrent ? const Color(0xFFFFF2D9) : Colors.white;

    return Container(
      margin: EdgeInsets.only(
        left: Responsive.width(context, 10),
        right: Responsive.width(context, 10),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _lessonCardBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 4),
            blurRadius: 7,
            color: _lessonCardShadow1,
          ),
          BoxShadow(
            offset: Offset(0, 0),
            blurRadius: 2,
            color: _lessonCardShadow2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLocked
              ? null
              : isCurrent
                  ? null
                  : () {
                      Chapter? targetChapter;
                      if (widget.course != null) {
                        try {
                          targetChapter = widget.course!.chapters.firstWhere(
                            (c) => c.lessons.any((l) => l.id == lesson.id),
                          );
                        } catch (_) {}
                      }
                      Navigator.of(context, rootNavigator: true)
                          .pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => LessonPlayerPage(
                            lessonId: lesson.id,
                            lesson: lesson,
                            course: widget.course,
                            chapter: targetChapter,
                            onProgressUpdate: widget.onProgressUpdate,
                          ),
                        ),
                      );
                    },
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: Responsive.height(context, 74)),
            child: Padding(
              padding: Responsive.padding(context,
                  left: 16, right: 16, vertical: 12),
              child: Row(
                children: [
                  Center(
                    child: isLocked
                        ? Container(
                            width: Responsive.width(context, 40),
                            height: Responsive.width(context, 40),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_outline,
                              color: Colors.grey[600],
                              size: Responsive.iconSize(context, 26),
                            ),
                          )
                        : isViewed
                            ? Icon(
                                Icons.check_circle_outline,
                                color: AppColors.primary,
                                size: Responsive.iconSize(context, 35),
                              )
                            : isCurrent
                                ? Container(
                                    width: Responsive.width(context, 40),
                                    height: Responsive.width(context, 40),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              AppColors.primary.withOpacity(0.35),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.play_arrow_outlined,
                                        color: Colors.white,
                                        size: Responsive.iconSize(context, 35),
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.play_arrow_outlined,
                                    color: AppColors.primary,
                                    size: Responsive.iconSize(context, 35),
                                  ),
                  ),
                  SizedBox(width: Responsive.width(context, 12)),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.nameAr,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: Responsive.fontSize(context, 14),
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lesson.videoDuration != null ||
                            lesson.duration != null) ...[
                          SizedBox(height: Responsive.height(context, 2)),
                          Text(
                            _formatDurationToHms(
                                lesson.videoDuration ?? lesson.duration),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(context, 12),
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLessonInfoCard(Lesson lesson) {
    return Container(
      padding: Responsive.padding(context, all: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lesson.nameAr,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: Responsive.fontSize(context, 18),
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 8)),
          Row(
            children: [
              if (lesson.videoDuration != null) ...[
                Container(
                  height: Responsive.height(context, 36),
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.width(context, 9),
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _durationTagPurple,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatDurationToHms(lesson.videoDuration),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(context, 14),
                          height: 22 / 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: Responsive.width(context, 3)),
                      Icon(
                        Icons.schedule,
                        size: Responsive.iconSize(context, 20),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: Responsive.width(context, 8)),
              ],
              if (lesson.viewed) ...[
                Container(
                  padding:
                      Responsive.padding(context, horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(Responsive.radius(context, 4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: Responsive.iconSize(context, 14),
                          color: AppColors.success),
                      SizedBox(width: Responsive.width(context, 4)),
                      Text(
                        'تمت المشاهدة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(context, 12),
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(Lesson lesson) {
    return Padding(
      padding: Responsive.padding(context, all: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: AppColors.primary,
                  size: Responsive.iconSize(context, 20)),
              SizedBox(width: Responsive.width(context, 8)),
              Text(
                'وصف الدرس',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: Responsive.fontSize(context, 16),
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.spacing(context, 8)),
          Container(
            padding: Responsive.padding(context, all: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius:
                  BorderRadius.circular(Responsive.radius(context, 8)),
            ),
            child: Text(
              lesson.description!,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 14),
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoVideoScreen(Lesson lesson) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: lesson.nameAr,
        onBack: () => Navigator.pop(context, _currentProgress),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined,
                size: Responsive.iconSize(context, 80),
                color: Colors.grey[400]),
            SizedBox(height: Responsive.spacing(context, 16)),
            Text(
              'الفيديو غير متاح حالياً',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 18),
                color: AppColors.textSecondary,
              ),
            ),
            if (lesson.videoStatus != null) ...[
              SizedBox(height: Responsive.spacing(context, 8)),
              Text(
                'الحالة: ${lesson.videoStatus}',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 14),
                    color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
