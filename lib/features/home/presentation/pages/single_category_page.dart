import 'package:flutter/material.dart';
import 'package:learnify_lms/core/theme/app_text_styles.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_background.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/course.dart';
import '../../../courses/presentation/bloc/courses_bloc.dart';
import '../../../courses/presentation/bloc/courses_event.dart';
import '../../../courses/presentation/bloc/courses_state.dart';
import 'course_details_page.dart';
import 'main_navigation_page.dart';

class SingleCategoryPage extends StatefulWidget {
  final Category category;
  final List<Course>? initialCourses;

  const SingleCategoryPage({
    super.key,
    required this.category,
    this.initialCourses,
  });

  @override
  State<SingleCategoryPage> createState() => _SingleCategoryPageState();
}

class _SingleCategoryPageState extends State<SingleCategoryPage> {
  late final CoursesBloc _coursesBloc;
  final ScrollController _scrollController = ScrollController();
  int _visibleItemCount = 20;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _coursesBloc = sl<CoursesBloc>();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coursesBloc.add(
        LoadCoursesEvent(
          categoryId: widget.category.id,
          perPage: 50,
          refresh: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _coursesBloc.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll <= 0) return;

    if (currentScroll >= maxScroll * 0.8) {
      setState(() {
        _visibleItemCount += _pageSize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _coursesBloc,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: CustomAppBar(title: 'دورات ${widget.category.nameAr}'),
        body: Stack(
          children: [
            const CustomBackground(),
            BlocBuilder<CoursesBloc, CoursesState>(
            builder: (context, state) {
              if (state is CoursesLoading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              
              if (state is CoursesError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.message,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          context.read<CoursesBloc>().add(
                            LoadCoursesEvent(
                              categoryId: widget.category.id,
                              perPage: 50,
                              refresh: true,
                            ),
                          );
                        },
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }
              
              final courses = state is CoursesLoaded 
                  ? state.courses 
                  : (state is CoursesEmpty 
                      ? <Course>[] 
                      : (widget.initialCourses ?? <Course>[]));
              
              if (courses.isEmpty) {
                return _buildEmptyState();
              }
              
              return _buildCoursesGrid(context, courses);
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد دورات في هذا التصنيف',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesGrid(BuildContext context, List<Course> courses) {
    final reversedCourses = courses.reversed.toList();
    final itemCount = _visibleItemCount.clamp(0, reversedCourses.length);
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 20,
        mainAxisSpacing: 24,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final course = reversedCourses[index];
        return _CourseGridItem(
          course: course,
          onTap: course.soon ? null : () => _onCourseTap(context, course),
        );
      },
    );
  }

  void _onCourseTap(BuildContext context, Course course) {
    context.pushWithNav(CourseDetailsPage(course: course));
  }
}

class _CourseGridItem extends StatelessWidget {
  final Course course;
  final VoidCallback? onTap;

  const _CourseGridItem({
    required this.course,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isComingSoon = course.soon;

    return GestureDetector(
      onTap: isComingSoon ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.grey.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(),
                  if (isComingSoon)
                    Container(
                      width: Responsive.width(context, 120),
                      height: Responsive.width(context, 120),
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
                          fontSize: Responsive.fontSize(context, 34),
                          fontWeight: FontWeight.bold,
                          color: AppColors.soonText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            course.nameAr,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isComingSoon ? Colors.grey[600] : AppColors.textPrimary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    final thumbnailUrl = course.effectiveThumbnail;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.cover,
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