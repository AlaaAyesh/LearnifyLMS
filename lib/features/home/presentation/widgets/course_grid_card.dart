import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/course.dart';

class CourseGridCard extends StatelessWidget {
  final Course course;
  final VoidCallback? onTap;

  const CourseGridCard({
    super.key,
    required this.course,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: Responsive.width(context, 85),
            height: Responsive.width(context, 85),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.grey.withOpacity(0.2),
                width: Responsive.width(context, 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.4),
                  blurRadius: Responsive.width(context, 4),
                  offset: Offset(0, Responsive.height(context, 2)),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildThumbnail(context),
                  ),
                  if (course.soon)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        alignment: Alignment.center,
                        child: Text(
                          'قريباً',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: Responsive.fontSize(context, 12),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          SizedBox(height: Responsive.spacing(context, 4)),

          SizedBox(
            width: Responsive.width(context, 90),
            child: Text(
              course.nameAr,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 11),
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final thumbnailUrl = course.effectiveThumbnail;

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final cacheSize =
      (Responsive.width(context, 80) * dpr).round().clamp(160, 480);

      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.cover,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        placeholder: (context, url) => Container(
          color: Colors.grey.shade100,
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Image.asset(
      'assets/images/paint.png',
      fit: BoxFit.cover,
    );
  }
}
