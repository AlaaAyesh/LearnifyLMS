import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/domain/entities/course.dart';

class CourseCircleItem extends StatelessWidget {
  final Course course;
  final VoidCallback? onTap;

  const CourseCircleItem({
    super.key,
    required this.course,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isComingSoon = course.soon;
    final bool isTablet = Responsive.isTablet(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;

        final double baseSize = isTablet ? 100 : 120;
        double circleSize = Responsive.width(context, baseSize);

        final double maxCircleSize = math.max(0, maxHeight - Responsive.height(context, 60));
        circleSize = math.min(circleSize, maxCircleSize);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: isComingSoon ? null : onTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: Responsive.padding(context, all: 16),
                      child: ClipOval(
                        child: _buildThumbnail(context),
                      ),
                    ),
                  ),

                  if (isComingSoon)
                    Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.65),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'قريبآ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          shadows: [
                            Shadow(
                              offset: const Offset(3, 3),
                              blurRadius: 0,
                              color: Colors.black.withOpacity(0.6),
                            ),
                          ],
                          fontSize: Responsive.fontSize(context, 40),
                          fontWeight: FontWeight.bold,
                          color: AppColors.soonText,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 8)),

            Flexible(
              child: Text(
                course.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: Responsive.fontSize(context, 14),
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final thumbnailUrl = course.effectiveThumbnail;

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => const SizedBox.shrink(),
        errorWidget: (context, url, error) => _defaultImage(),
      );
    }

    return _defaultImage();
  }

  Widget _defaultImage() {
    return Image.asset(
      'assets/images/paint.png',
      fit: BoxFit.contain,
    );
  }

}

