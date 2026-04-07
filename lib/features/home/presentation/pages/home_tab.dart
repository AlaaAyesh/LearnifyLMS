import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/custom_background.dart';
import '../../domain/entities/banner.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/category_course_block.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/home_data.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/site_banner_carousel.dart';
import '../widgets/category_item.dart';
import '../widgets/course_grid_card.dart';
import '../widgets/popular_course_card.dart';
import '../widgets/section_header.dart';
import '../../../banners/domain/entities/banner.dart' as banner_entity;
import '../../../banners/domain/usecases/get_site_banners_usecase.dart';
import 'categories_page.dart';
import 'course_details_page.dart';
import 'main_navigation_page.dart';
import 'single_category_page.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<banner_entity.Banner> _siteBanners = [];
  bool _isLoadingBanners = true;
  final GetSiteBannersUseCase _getSiteBannersUseCase = sl<GetSiteBannersUseCase>();

  @override
  void initState() {
    super.initState();
    _loadSiteBanners();
  }

  Future<void> _loadSiteBanners() async {
    setState(() => _isLoadingBanners = true);
    final result = await _getSiteBannersUseCase(perPage: 10, page: 1);
    result.fold(
      (failure) {
        if (mounted) {
          setState(() {
            _isLoadingBanners = false;
            _siteBanners = [];
          });
        }
      },
      (response) {
        if (mounted) {
          setState(() {
            _isLoadingBanners = false;
            _siteBanners = response.banners;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _HomeTabContent(
      siteBanners: _siteBanners,
      isLoadingBanners: _isLoadingBanners,
    );
  }
}

class _HomeTabContent extends StatelessWidget {
  final List<banner_entity.Banner> siteBanners;
  final bool isLoadingBanners;

  const _HomeTabContent({
    required this.siteBanners,
    required this.isLoadingBanners,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Stack(
        children: [
          const CustomBackground(),
          SafeArea(
            child: BlocBuilder<HomeBloc, HomeState>(
              buildWhen: (previous, current) => previous != current,
              builder: (context, state) {
                if (state is HomeLoading) {
                  if (state.cachedData != null) {
                    return _buildContent(context, state.cachedData!);
                  }
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }

                if (state is HomeError) {
                  if (state.cachedData != null) {
                    return _buildContent(context, state.cachedData!);
                  }
                  return _buildErrorState(context, state.message);
                }

                if (state is HomeLoaded) {
                  return _buildContent(context, state.homeData);
                }

                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, HomeData homeData) {
    final categoryEntries = homeData.coursesByCategory.entries.toList(growable: false);
    return RefreshIndicator(
      onRefresh: () async {
        context.read<HomeBloc>().add(RefreshHomeDataEvent());
      },
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: Responsive.spacing(context, 16)),
          ),
          SliverToBoxAdapter(
            child: _HomeBannerSection(
              siteBanners: siteBanners,
              isLoadingBanners: isLoadingBanners,
              homeBanners: homeData.banners,
              onBannerTap: _onBannerTapPlaceholder,
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeCategoriesSection(
              categories: homeData.categories,
              homeData: homeData,
              onCategoryTap: _onCategoryTap,
              onSeeAll: () => _navigateToCategoriesPage(context, homeData),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomePopularCoursesSection(
              popularCourses: homeData.popularCourses,
              onCourseTap: _onCourseTap,
            ),
          ),
          if (homeData.categoryCourseBlocks.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCategoryCourseBlockSection(
                  context,
                  homeData.categoryCourseBlocks[index],
                ),
                childCount: homeData.categoryCourseBlocks.length,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = categoryEntries[index];
                  return _buildCategorySection(
                    context,
                    entry.key,
                    entry.value,
                    homeData,
                  );
                },
                childCount: categoryEntries.length,
              ),
            ),
          SliverToBoxAdapter(
            child: _HomeFreeCoursesSection(
              freeCourses: homeData.freeCourses,
              onCourseTap: _onCourseTap,
              buildCoursesGrid: _buildCoursesGrid,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: Responsive.spacing(context, 100)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCourseBlockSection(BuildContext context, CategoryCourseBlock block) {
    if (block.courses.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'دورات ${block.category.nameAr}',
          onSeeAll: () => _navigateToSingleCategory(context, block.category, block.courses),
        ),
        SizedBox(height: Responsive.spacing(context, 12)),

        _buildCoursesGrid(context, block.courses),
        SizedBox(height: Responsive.spacing(context, 24)),
      ],
    );
  }

  Widget _buildCategorySection(BuildContext context, Category category, List<Course> courses, HomeData homeData) {
    if (courses.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'دورات ${category.nameAr}',
          onSeeAll: () => _navigateToSingleCategory(context, category, courses),
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        _buildCoursesGrid(context, courses),
        SizedBox(height: Responsive.spacing(context, 24)),
      ],
    );
  }

  Widget _buildCoursesGrid(BuildContext context, List<Course> courses) {
    final reversedCourses = courses.reversed.toList();
    return SizedBox(
      height: Responsive.height(context, 130),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: Responsive.padding(context, horizontal: 16),
        itemCount: reversedCourses.length,
        itemBuilder: (context, index) {
          final course = reversedCourses[index];
          return RepaintBoundary(
            child: Padding(
              padding: Responsive.padding(context, left: 20),
              child: CourseGridCard(
                course: course,
                onTap: () => _onCourseTap(context, course),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onCategoryTap(BuildContext context, Category category, HomeData homeData) {
    final courses = homeData.coursesByCategory[category] ?? [];
    _navigateToSingleCategory(context, category, courses);
  }

  void _onCourseTap(BuildContext context, Course course) {
    if (course.soon) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذه الدورة قادمة قريباً'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    
    context.pushWithNav(CourseDetailsPage(course: course));
  }

  void _navigateToCategoriesPage(BuildContext context, HomeData homeData) {
    context.pushWithNav(CategoriesPage(
      categories: homeData.categories,
      coursesByCategory: homeData.coursesByCategory,
    ));
  }

  void _navigateToSingleCategory(BuildContext context, Category category, List<Course> courses) {
    context.pushWithNav(SingleCategoryPage(
      category: category,
    ));
  }

  static void _onBannerTapPlaceholder(HomeBanner banner) {}

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: Responsive.padding(context, all: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: Responsive.iconSize(context, 80),
              color: Colors.red[400],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            Text(
              'حدث خطأ',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 18),
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 8)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 14),
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 24)),
            ElevatedButton.icon(
              onPressed: () {
                context.read<HomeBloc>().add(LoadHomeDataEvent());
              },
              icon: Icon(Icons.refresh, size: Responsive.iconSize(context, 20)),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: Responsive.padding(context, horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.radius(context, 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeBannerSection extends StatelessWidget {
  final List<banner_entity.Banner> siteBanners;
  final bool isLoadingBanners;
  final List<HomeBanner> homeBanners;
  final void Function(HomeBanner)? onBannerTap;

  const _HomeBannerSection({
    required this.siteBanners,
    required this.isLoadingBanners,
    required this.homeBanners,
    required this.onBannerTap,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (!isLoadingBanners && siteBanners.isNotEmpty) {
      children.addAll([
        SiteBannerCarousel(
          banners: siteBanners,
          autoScrollDuration: const Duration(seconds: 20),
        ),
        SizedBox(height: Responsive.spacing(context, 24)),
      ]);
    } else if (homeBanners.isNotEmpty) {
      children.addAll([
        BannerCarousel(
          banners: homeBanners,
          autoScrollDuration: const Duration(seconds: 3),
          onBannerTap: onBannerTap ?? (_) {},
        ),
        SizedBox(height: Responsive.spacing(context, 24)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _HomeCategoriesSection extends StatelessWidget {
  final List<Category> categories;
  final HomeData homeData;
  final void Function(BuildContext, Category, HomeData) onCategoryTap;
  final VoidCallback onSeeAll;

  const _HomeCategoriesSection({
    required this.categories,
    required this.homeData,
    required this.onCategoryTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'التصنيفات', onSeeAll: onSeeAll),
        SizedBox(height: Responsive.spacing(context, 12)),
        SizedBox(
          height: Responsive.height(context, 125),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: Responsive.padding(context, horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return RepaintBoundary(
                child: Padding(
                  padding: Responsive.padding(context, left: 16),
                  child: CategoryItem(
                    category: category,
                    onTap: () => onCategoryTap(context, category, homeData),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: Responsive.spacing(context, 24)),
      ],
    );
  }
}

class _HomePopularCoursesSection extends StatelessWidget {
  final List<Course> popularCourses;
  final void Function(BuildContext, Course) onCourseTap;

  const _HomePopularCoursesSection({
    required this.popularCourses,
    required this.onCourseTap,
  });

  @override
  Widget build(BuildContext context) {
    if (popularCourses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'الأكثر مشاهدة'),
        SizedBox(height: Responsive.spacing(context, 12)),
        Padding(
          padding: Responsive.padding(context, right: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spacing = Responsive.width(context, 16);
              final cardMargin = Responsive.width(context, 8);
              final cardWidth = (constraints.maxWidth - spacing - 2 * cardMargin) / 2;
              return SizedBox(
                height: Responsive.height(context, 150),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: popularCourses
                      .map(
                        (course) => RepaintBoundary(
                          child: Padding(
                            padding: Responsive.padding(context, horizontal: 4),
                            child: PopularCourseCard(
                              course: course,
                              onTap: () => onCourseTap(context, course),
                              width: cardWidth,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ),
        SizedBox(height: Responsive.spacing(context, 24)),
      ],
    );
  }
}

class _HomeFreeCoursesSection extends StatelessWidget {
  final List<Course> freeCourses;
  final void Function(BuildContext, Course) onCourseTap;
  final Widget Function(BuildContext, List<Course>) buildCoursesGrid;

  const _HomeFreeCoursesSection({
    required this.freeCourses,
    required this.onCourseTap,
    required this.buildCoursesGrid,
  });

  @override
  Widget build(BuildContext context) {
    if (freeCourses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'دورات مجانية', onSeeAll: () {}),
        SizedBox(height: Responsive.spacing(context, 12)),
        buildCoursesGrid(context, freeCourses),
        SizedBox(height: Responsive.spacing(context, 24)),
      ],
    );
  }
}

