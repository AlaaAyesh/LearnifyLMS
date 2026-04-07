import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import '../../../../core/events/global_event_bus.dart';
import '../../../../core/events/subscription_updated_event.dart';
import '../../data/models/reel_category_model.dart';
import '../../domain/entities/reel.dart';
import '../../domain/usecases/get_reels_feed_usecase.dart';
import '../../domain/usecases/record_reel_view_usecase.dart';
import '../../domain/usecases/toggle_reel_like_usecase.dart';
import '../../domain/usecases/get_reel_categories_usecase.dart';
import '../../domain/usecases/get_user_reels_usecase.dart';
import '../../domain/usecases/get_user_liked_reels_usecase.dart';
import 'reels_event.dart';
import 'reels_state.dart';

class ReelsBloc extends Bloc<ReelsEvent, ReelsState> {
  final GetReelsFeedUseCase getReelsFeedUseCase;
  final RecordReelViewUseCase recordReelViewUseCase;
  final ToggleReelLikeUseCase toggleReelLikeUseCase;
  final GetReelCategoriesUseCase getReelCategoriesUseCase;
  final GetUserReelsUseCase getUserReelsUseCase;
  final GetUserLikedReelsUseCase getUserLikedReelsUseCase;
  final GlobalEventBus globalEventBus;

  int _perPage = 10;
  int? _currentCategoryId;
  int _loadRequestId = 0;
  final Set<int> _viewedReelIds = {};
  List<ReelCategoryModel> _categories = [];

  int? _currentUserId;
  int _userReelsPage = 1;
  int _userLikedReelsPage = 1;
  StreamSubscription<SubscriptionUpdatedEvent>? _subscriptionUpdatedListener;

  ReelsBloc({
    required this.getReelsFeedUseCase,
    required this.recordReelViewUseCase,
    required this.toggleReelLikeUseCase,
    required this.getReelCategoriesUseCase,
    required this.getUserReelsUseCase,
    required this.getUserLikedReelsUseCase,
    required this.globalEventBus,
  }) : super(const ReelsInitial()) {
    on<LoadReelsFeedEvent>(_onLoadReelsFeed);
    on<LoadMoreReelsEvent>(_onLoadMoreReels);
    on<LoadNextCategoryReelsEvent>(_onLoadNextCategoryReels);
    on<RefreshReelsFeedEvent>(_onRefreshReelsFeed);
    on<ToggleReelLikeEvent>(_onToggleReelLike);
    on<MarkReelViewedEvent>(_onMarkReelViewed);
    on<LoadReelCategoriesEvent>(_onLoadReelCategories);
    on<SeedSingleReelEvent>(_onSeedSingleReel);
    on<SeedReelsListEvent>(_onSeedReelsList);
    on<LoadUserReelsEvent>(_onLoadUserReels);
    on<LoadMoreUserReelsEvent>(_onLoadMoreUserReels);
    on<LoadUserLikedReelsEvent>(_onLoadUserLikedReels);
    on<LoadMoreUserLikedReelsEvent>(_onLoadMoreUserLikedReels);

    _subscriptionUpdatedListener = globalEventBus
        .on<SubscriptionUpdatedEvent>()
        .listen((_) {
      debugPrint('🔥 SubscriptionUpdatedEvent received in ReelsBloc');
      add(LoadReelsFeedEvent(perPage: _perPage, categoryId: _currentCategoryId));
    });
  }

  List<Reel> _filterReelsByCategory(List<Reel> reels, int? categoryId) {
    if (categoryId == null) return reels;
    return reels
        .where((reel) => reel.categories.any((category) => category.id == categoryId))
        .toList();
  }

  void _onSeedReelsList(
    SeedReelsListEvent event,
    Emitter<ReelsState> emit,
  ) {
    _currentCategoryId = null;

    final reels = event.reels;
    if (reels.isEmpty) {
      emit(const ReelsEmpty());
      return;
    }

    final likedReels = <int, bool>{};
    for (final reel in reels) {
      likedReels[reel.id] = reel.liked;
      if (reel.viewed) {
        _viewedReelIds.add(reel.id);
      }
    }

    emit(ReelsLoaded(
      reels: reels,
      nextCursor: null,
      nextPageUrl: null,
      hasMore: false,
      isLoadingMore: false,
      likedReels: likedReels,
      categories: _categories,
    ));
  }

  void _onSeedSingleReel(
    SeedSingleReelEvent event,
    Emitter<ReelsState> emit,
  ) {
    _currentCategoryId = null;

    final reel = event.reel;

    final likedReels = <int, bool>{reel.id: reel.liked};
    final viewCounts = <int, int>{};
    final likeCounts = <int, int>{};

    if (reel.viewed) {
      _viewedReelIds.add(reel.id);
    }

    emit(ReelsLoaded(
      reels: [reel],
      nextCursor: null,
      nextPageUrl: null,
      hasMore: false,
      isLoadingMore: false,
      likedReels: likedReels,
      viewCounts: viewCounts,
      likeCounts: likeCounts,
      categories: _categories,
    ));
  }

  Future<void> _onLoadReelsFeed(
    LoadReelsFeedEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final requestedCategoryId = event.categoryId;
    final currentState = state;

    if (currentState is ReelsLoading && _currentCategoryId == requestedCategoryId) {
      return;
    }

    final requestId = ++_loadRequestId;
    _perPage = event.perPage;
    final previousCategoryId = _currentCategoryId;
    _currentCategoryId = requestedCategoryId;

    final isCategoryChange = previousCategoryId != event.categoryId;
    final isInitialLoad = currentState is! ReelsLoaded || currentState.reels.isEmpty;

    if (isInitialLoad || isCategoryChange) {
      emit(const ReelsLoading());
    }

    final result = await getReelsFeedUseCase(
      perPage: _perPage,
      categoryId: _currentCategoryId,
    );

    result.fold(
      (failure) {
        emit(ReelsError(failure.message));
      },
      (response) {
        if (requestId != _loadRequestId || _currentCategoryId != requestedCategoryId) {
          return;
        }

        final filteredReels = _filterReelsByCategory(response.reels, _currentCategoryId);

        if (filteredReels.isEmpty) {
          emit(const ReelsEmpty());
        } else {
          final likedReels = <int, bool>{};
          for (final reel in filteredReels) {
            likedReels[reel.id] = reel.liked;
            if (reel.viewed) {
              _viewedReelIds.add(reel.id);
            }
          }

          emit(ReelsLoaded(
            reels: filteredReels,
            nextCursor: response.meta.nextCursor,
            nextPageUrl: response.meta.nextPageUrl,
            hasMore: response.meta.hasMore,
            likedReels: likedReels,
            categories: _categories,
          ));
        }
      },
    );
  }

  Future<void> _onLoadNextCategoryReels(
    LoadNextCategoryReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ReelsLoaded) return;

    final loadingState = currentState.copyWith(
      reels: <Reel>[],
      nextCursor: null,
      nextPageUrl: null,
      hasMore: false,
      isLoadingMore: true,
    );
    emit(loadingState);

    _currentCategoryId = event.categoryId;

    final result = await getReelsFeedUseCase(
      perPage: _perPage,
      categoryId: _currentCategoryId,
    );

    result.fold(
      (failure) => emit(loadingState.copyWith(isLoadingMore: false)),
      (response) {
        final filteredReels = _filterReelsByCategory(response.reels, _currentCategoryId);

        if (filteredReels.isEmpty) {
          emit(loadingState.copyWith(
            hasMore: false,
            isLoadingMore: false,
            nextCursor: null,
            nextPageUrl: null,
          ));
          return;
        }

        final newLikedReels = Map<int, bool>.from(loadingState.likedReels);
        for (final reel in filteredReels) {
          newLikedReels[reel.id] = reel.liked;
          if (reel.viewed) {
            _viewedReelIds.add(reel.id);
          }
        }

        emit(loadingState.copyWith(
          reels: filteredReels,
          nextCursor: response.meta.nextCursor,
          nextPageUrl: response.meta.nextPageUrl,
          hasMore: response.meta.hasMore,
          isLoadingMore: false,
          likedReels: newLikedReels,
        ));
      },
    );
  }

  Future<void> _onLoadMoreReels(
    LoadMoreReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ReelsLoaded) return;
    if (currentState.isLoadingMore || !currentState.hasMore) return;

    emit(currentState.copyWith(isLoadingMore: true));

    final result = await getReelsFeedUseCase(
      perPage: _perPage,
      cursor: currentState.nextCursor,
      nextPageUrl: currentState.nextPageUrl,
      categoryId: _currentCategoryId,
    );

    result.fold(
      (failure) {
        emit(currentState.copyWith(isLoadingMore: false));
      },
      (response) {
        final filteredReels = _filterReelsByCategory(response.reels, _currentCategoryId);
        final newLikedReels = Map<int, bool>.from(currentState.likedReels);
        for (final reel in filteredReels) {
          newLikedReels[reel.id] = reel.liked;
          if (reel.viewed) {
            _viewedReelIds.add(reel.id);
          }
        }

        emit(currentState.copyWith(
          reels: [...currentState.reels, ...filteredReels],
          nextCursor: response.meta.nextCursor,
          nextPageUrl: response.meta.nextPageUrl,
          hasMore: response.meta.hasMore,
          isLoadingMore: false,
          likedReels: newLikedReels,
        ));
      },
    );
  }

  Future<void> _onRefreshReelsFeed(
    RefreshReelsFeedEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final result = await getReelsFeedUseCase(
      perPage: _perPage,
      categoryId: _currentCategoryId,
    );

    result.fold(
      (failure) => emit(ReelsError(failure.message)),
      (response) {
        if (response.reels.isEmpty) {
          emit(const ReelsEmpty());
        } else {
          final likedReels = <int, bool>{};
          for (final reel in response.reels) {
            likedReels[reel.id] = reel.liked;
            if (reel.viewed) {
              _viewedReelIds.add(reel.id);
            }
          }

          emit(ReelsLoaded(
            reels: response.reels,
            nextCursor: response.meta.nextCursor,
            nextPageUrl: response.meta.nextPageUrl,
            hasMore: response.meta.hasMore,
            likedReels: likedReels,
            categories: _categories,
          ));
        }
      },
    );
  }

  Future<void> _onToggleReelLike(
    ToggleReelLikeEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ReelsLoaded) {
      debugPrint('ReelsBloc: Cannot toggle like - state is not ReelsLoaded');
      return;
    }

    final isCurrentlyLiked = currentState.likedReels[event.reelId] ?? false;
    debugPrint('ReelsBloc: Toggling like for reel ${event.reelId}, currently liked: $isCurrentlyLiked');

    final reelIndex = currentState.reels.indexWhere((r) => r.id == event.reelId);
    if (reelIndex == -1) {
      debugPrint('ReelsBloc: Reel ${event.reelId} not found in state');
      return;
    }
    final reel = currentState.reels[reelIndex];
    final currentLikeCount = currentState.getLikeCount(reel);

    final newLikedReels = Map<int, bool>.from(currentState.likedReels);
    newLikedReels[event.reelId] = !isCurrentlyLiked;

    final newLikeCounts = Map<int, int>.from(currentState.likeCounts);
    if (isCurrentlyLiked) {
      newLikeCounts[event.reelId] = (currentLikeCount - 1).clamp(0, double.maxFinite.toInt());
    } else {
      newLikeCounts[event.reelId] = currentLikeCount + 1;
    }
    
    emit(currentState.copyWith(
      likedReels: newLikedReels,
      likeCounts: newLikeCounts,
    ));

    debugPrint('ReelsBloc: Calling API to ${isCurrentlyLiked ? "unlike" : "like"} reel ${event.reelId}');
    final result = await toggleReelLikeUseCase(
      reelId: event.reelId,
      isCurrentlyLiked: isCurrentlyLiked,
    );

    result.fold(
      (failure) {
        debugPrint('ReelsBloc: Like API failed - ${failure.message}');
        if (state is ReelsLoaded) {
          final revertedLikedReels = Map<int, bool>.from((state as ReelsLoaded).likedReels);
          revertedLikedReels[event.reelId] = isCurrentlyLiked;
          
          final revertedLikeCounts = Map<int, int>.from((state as ReelsLoaded).likeCounts);
          revertedLikeCounts[event.reelId] = currentLikeCount;
          
          emit((state as ReelsLoaded).copyWith(
            likedReels: revertedLikedReels,
            likeCounts: revertedLikeCounts,
          ));
        }
      },
      (newLikedStatus) {
        debugPrint('ReelsBloc: Like API success - new status: $newLikedStatus');
      },
    );
  }

  Future<void> _onMarkReelViewed(
    MarkReelViewedEvent event,
    Emitter<ReelsState> emit,
  ) async {
    if (_viewedReelIds.contains(event.reelId)) {
      debugPrint('ReelsBloc: Reel ${event.reelId} already viewed, skipping');
      return;
    }

    final currentState = state;
    if (currentState is! ReelsLoaded) {
      debugPrint('ReelsBloc: Cannot mark viewed - state is not ReelsLoaded');
      return;
    }

    debugPrint('ReelsBloc: Marking reel ${event.reelId} as viewed');

    _viewedReelIds.add(event.reelId);

    final reelIndex = currentState.reels.indexWhere((r) => r.id == event.reelId);
    if (reelIndex == -1) {
      debugPrint('ReelsBloc: Reel ${event.reelId} not found in state for view tracking');
      return;
    }
    final reel = currentState.reels[reelIndex];
    final currentViewCount = currentState.getViewCount(reel);

    final newViewCounts = Map<int, int>.from(currentState.viewCounts);
    newViewCounts[event.reelId] = currentViewCount + 1;
    
    emit(currentState.copyWith(viewCounts: newViewCounts));

    debugPrint('ReelsBloc: Calling API to record view for reel ${event.reelId}');
    final result = await recordReelViewUseCase(event.reelId);
    
    result.fold(
      (failure) {
        debugPrint('ReelsBloc: View API failed - ${failure.message}');
      },
      (_) {
        debugPrint('ReelsBloc: View API success for reel ${event.reelId}');
      },
    );
  }

  Future<void> _onLoadReelCategories(
    LoadReelCategoriesEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final result = await getReelCategoriesUseCase();

    result.fold(
      (failure) {
        debugPrint('ReelsBloc: Failed to load categories - ${failure.message}');
      },
      (categories) {
        _categories = categories;
        emit(ReelsWithCategories(categories: categories));
      },
    );
  }

  Future<void> _onLoadUserReels(
    LoadUserReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    emit(const ReelsLoading());
    _currentUserId = event.userId;
    _userReelsPage = event.page;

    final result = await getUserReelsUseCase(
      userId: event.userId,
      perPage: event.perPage,
      page: event.page,
    );

    result.fold(
      (failure) => emit(ReelsError(failure.message)),
      (response) {
        if (response.reels.isEmpty) {
          emit(const ReelsEmpty());
        } else {
          final likedReels = <int, bool>{};
          for (final reel in response.reels) {
            likedReels[reel.id] = reel.liked;
            if (reel.viewed) {
              _viewedReelIds.add(reel.id);
            }
          }

          emit(ReelsLoaded(
            reels: response.reels,
            nextPageUrl: response.meta.nextPageUrl,
            hasMore: response.meta.hasMore,
            likedReels: likedReels,
            categories: _categories,
          ));
        }
      },
    );
  }

  Future<void> _onLoadMoreUserReels(
    LoadMoreUserReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ReelsLoaded || _currentUserId == null) {
      return;
    }

    if (!currentState.hasMore || currentState.isLoadingMore) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));
    _userReelsPage++;

    final result = await getUserReelsUseCase(
      userId: _currentUserId!,
      perPage: _perPage,
      page: _userReelsPage,
    );

    result.fold(
      (failure) {
        emit(currentState.copyWith(isLoadingMore: false));
        emit(ReelsError(failure.message));
      },
      (response) {
        final updatedReels = [...currentState.reels, ...response.reels];
        final updatedLikedReels = Map<int, bool>.from(currentState.likedReels);
        
        for (final reel in response.reels) {
          updatedLikedReels[reel.id] = reel.liked;
          if (reel.viewed) {
            _viewedReelIds.add(reel.id);
          }
        }

        emit(ReelsLoaded(
          reels: updatedReels,
          nextPageUrl: response.meta.nextPageUrl,
          hasMore: response.meta.hasMore,
          likedReels: updatedLikedReels,
          categories: _categories,
        ));
      },
    );
  }

  Future<void> _onLoadUserLikedReels(
    LoadUserLikedReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    emit(const ReelsLoading());
    _currentUserId = event.userId;
    _userLikedReelsPage = event.page;

    final result = await getUserLikedReelsUseCase(
      userId: event.userId,
      perPage: event.perPage,
      page: event.page,
    );

    result.fold(
      (failure) => emit(ReelsError(failure.message)),
      (response) {
        if (response.reels.isEmpty) {
          emit(const ReelsEmpty());
        } else {
          final likedReels = <int, bool>{};
          for (final reel in response.reels) {
            likedReels[reel.id] = true;
            if (reel.viewed) {
              _viewedReelIds.add(reel.id);
            }
          }

          emit(ReelsLoaded(
            reels: response.reels,
            nextPageUrl: response.meta.nextPageUrl,
            hasMore: response.meta.hasMore,
            likedReels: likedReels,
            categories: _categories,
          ));
        }
      },
    );
  }

  Future<void> _onLoadMoreUserLikedReels(
    LoadMoreUserLikedReelsEvent event,
    Emitter<ReelsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ReelsLoaded || _currentUserId == null) {
      return;
    }

    if (!currentState.hasMore || currentState.isLoadingMore) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));
    _userLikedReelsPage++;

    final result = await getUserLikedReelsUseCase(
      userId: _currentUserId!,
      perPage: _perPage,
      page: _userLikedReelsPage,
    );

    result.fold(
      (failure) {
        emit(currentState.copyWith(isLoadingMore: false));
        emit(ReelsError(failure.message));
      },
      (response) {
        final updatedReels = [...currentState.reels, ...response.reels];
        final updatedLikedReels = Map<int, bool>.from(currentState.likedReels);
        
        for (final reel in response.reels) {
          updatedLikedReels[reel.id] = true;
          if (reel.viewed) {
            _viewedReelIds.add(reel.id);
          }
        }

        emit(ReelsLoaded(
          reels: updatedReels,
          nextPageUrl: response.meta.nextPageUrl,
          hasMore: response.meta.hasMore,
          likedReels: updatedLikedReels,
          categories: _categories,
        ));
      },
    );
  }

  @override
  Future<void> close() async {
    await _subscriptionUpdatedListener?.cancel();
    return super.close();
  }
}


