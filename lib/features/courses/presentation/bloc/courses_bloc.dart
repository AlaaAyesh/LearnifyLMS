import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../../core/events/global_event_bus.dart';
import '../../../../core/events/subscription_updated_event.dart';
import '../../domain/usecases/get_course_by_id_usecase.dart';
import '../../domain/usecases/get_courses_usecase.dart';
import '../../domain/usecases/get_my_courses_usecase.dart';
import 'courses_event.dart';
import 'courses_state.dart';

class CoursesBloc extends Bloc<CoursesEvent, CoursesState> {
  final GetCoursesUseCase getCoursesUseCase;
  final GetCourseByIdUseCase getCourseByIdUseCase;
  final GetMyCoursesUseCase getMyCoursesUseCase;
  final GlobalEventBus globalEventBus;

  int? _currentCategoryId;
  int? _currentSpecialtyId;
  int _currentPage = 1;
  static const int _perPage = 10;

  final Debouncer _filterDebouncer = Debouncer(delay: const Duration(milliseconds: 300));
  StreamSubscription<SubscriptionUpdatedEvent>? _subscriptionUpdatedListener;

  CoursesBloc({
    required this.getCoursesUseCase,
    required this.getCourseByIdUseCase,
    required this.getMyCoursesUseCase,
    required this.globalEventBus,
  }) : super(CoursesInitial()) {
    on<LoadCoursesEvent>(_onLoadCourses);
    on<LoadMoreCoursesEvent>(_onLoadMoreCourses);
    on<LoadCourseByIdEvent>(_onLoadCourseById);
    on<LoadMyCoursesEvent>(_onLoadMyCourses);
    on<FilterByCategoryEvent>(_onFilterByCategory);
    on<FilterBySpecialtyEvent>(_onFilterBySpecialty);
    on<ClearFiltersEvent>(_onClearFilters);
    on<ClearCoursesStateEvent>(_onClearState);

    _subscriptionUpdatedListener = globalEventBus
        .on<SubscriptionUpdatedEvent>()
        .listen((_) {
      _currentPage = 1;
      debugPrint('🔥 SubscriptionUpdatedEvent received in CoursesBloc');
      add(const LoadCoursesEvent(page: 1, refresh: true));
    });
  }

  Future<void> _onLoadCourses(
    LoadCoursesEvent event,
    Emitter<CoursesState> emit,
  ) async {
    if (event.refresh) {
      _currentPage = 1;
    }

    if (event.categoryId != null) _currentCategoryId = event.categoryId;
    if (event.specialtyId != null) _currentSpecialtyId = event.specialtyId;

    emit(CoursesLoading());

    final result = await getCoursesUseCase(
      page: event.page ?? _currentPage,
      perPage: event.perPage ?? _perPage,
      categoryId: _currentCategoryId,
      specialtyId: _currentSpecialtyId,
    );

    result.fold(
      (failure) => emit(CoursesError(failure.message)),
      (courses) {
        if (courses.isEmpty) {
          emit(CoursesEmpty());
        } else {
          emit(CoursesLoaded(
            courses: courses,
            categoryId: _currentCategoryId,
            specialtyId: _currentSpecialtyId,
            currentPage: _currentPage,
            hasMorePages: courses.length >= _perPage,
          ));
        }
      },
    );
  }

  Future<void> _onLoadMoreCourses(
    LoadMoreCoursesEvent event,
    Emitter<CoursesState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CoursesLoaded || 
        currentState.isLoadingMore || 
        !currentState.hasMorePages) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));

    final nextPage = currentState.currentPage + 1;
    final result = await getCoursesUseCase(
      page: nextPage,
      perPage: _perPage,
      categoryId: _currentCategoryId,
      specialtyId: _currentSpecialtyId,
    );

    result.fold(
      (failure) => emit(currentState.copyWith(isLoadingMore: false)),
      (newCourses) {
        _currentPage = nextPage;
        emit(currentState.copyWith(
          courses: [...currentState.courses, ...newCourses],
          currentPage: nextPage,
          hasMorePages: newCourses.length >= _perPage,
          isLoadingMore: false,
        ));
      },
    );
  }

  Future<void> _onLoadCourseById(
    LoadCourseByIdEvent event,
    Emitter<CoursesState> emit,
  ) async {
    emit(CoursesLoading());

    final result = await getCourseByIdUseCase(id: event.id);

    result.fold(
      (failure) => emit(CoursesError(failure.message)),
      (course) => emit(CourseDetailsLoaded(course: course)),
    );
  }

  Future<void> _onLoadMyCourses(
    LoadMyCoursesEvent event,
    Emitter<CoursesState> emit,
  ) async {
    emit(CoursesLoading());

    final result = await getMyCoursesUseCase();

    result.fold(
      (failure) => emit(CoursesError(failure.message)),
      (courses) {
        if (courses.isEmpty) {
          emit(CoursesEmpty());
        } else {
          emit(const CoursesLoaded(
            courses: [],
            hasMorePages: false,
            currentPage: 1,
          ).copyWith(courses: courses));
        }
      },
    );
  }

  Future<void> _onFilterByCategory(
    FilterByCategoryEvent event,
    Emitter<CoursesState> emit,
  ) async {
    _currentCategoryId = event.categoryId;
    _currentPage = 1;

    _filterDebouncer.call(() {
      add(const LoadCoursesEvent(refresh: true));
    });
  }

  Future<void> _onFilterBySpecialty(
    FilterBySpecialtyEvent event,
    Emitter<CoursesState> emit,
  ) async {
    _currentSpecialtyId = event.specialtyId;
    _currentPage = 1;

    _filterDebouncer.call(() {
      add(const LoadCoursesEvent(refresh: true));
    });
  }
  
  @override
  Future<void> close() {
    _subscriptionUpdatedListener?.cancel();
    _filterDebouncer.dispose();
    return super.close();
  }

  Future<void> _onClearFilters(
    ClearFiltersEvent event,
    Emitter<CoursesState> emit,
  ) async {
    _currentCategoryId = null;
    _currentSpecialtyId = null;
    _currentPage = 1;
    add(const LoadCoursesEvent(refresh: true));
  }

  void _onClearState(
    ClearCoursesStateEvent event,
    Emitter<CoursesState> emit,
  ) {
    _currentCategoryId = null;
    _currentSpecialtyId = null;
    _currentPage = 1;
    emit(CoursesInitial());
  }
}




