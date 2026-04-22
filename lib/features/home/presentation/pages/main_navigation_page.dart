import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:learnify_lms/core/theme/app_text_styles.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_state.dart';
import '../../../authentication/presentation/pages/register/complete_profile_page.dart';
import '../../../menu/presentation/pages/menu_page.dart';
import '../../../shorts/presentation/pages/shorts_page.dart';
import '../../../subscriptions/presentation/pages/subscriptions_page.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import 'home_tab.dart';

class TabIndexNotifier extends ValueNotifier<int> {
  TabIndexNotifier(super.value);
}

class TabIndexProvider extends InheritedNotifier<TabIndexNotifier> {
  const TabIndexProvider({
    super.key,
    required TabIndexNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static TabIndexNotifier? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TabIndexProvider>()?.notifier;
  }
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => MainNavigationPageState();
}

class MainNavigationPageState extends State<MainNavigationPage> {
  static const int _maxTabHistory = 4;
  static const int _homeTabIndex = 0;

  int _selectedIndex = 0;
  final List<int> _tabHistory = [];
  late final TabIndexNotifier _tabIndexNotifier;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  bool _showBottomNav = true;
  bool _fiamTriggeredOnce = false;

  int get currentTabIndex => _selectedIndex;

  @override
  void initState() {
    super.initState();
    _tabIndexNotifier = TabIndexNotifier(_selectedIndex);
    _triggerInAppMessageOnHomeOpen();
  }

  void _triggerInAppMessageOnHomeOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_fiamTriggeredOnce || !mounted) return;
      _fiamTriggeredOnce = true;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      if (Firebase.apps.isEmpty) return;

      try {
        await FirebaseAnalytics.instance.logEvent(name: 'home_open');
        await FirebaseInAppMessaging.instance.triggerEvent('home_open');
        debugPrint('FIAM trigger sent: home_open');
      } catch (error, stackTrace) {
        debugPrint('FIAM trigger skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  void setShowBottomNav(bool show) {
    if (_showBottomNav != show) {
      setState(() => _showBottomNav = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is SocialLoginNeedsCompletion) {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => CompleteProfilePage(
                email: state.email,
                name: state.name,
                providerId: state.providerId,
                accessToken: state.accessToken,
                requiresRegistration: state.requiresRegistration,
              ),
            ),
          );
        }
      },
      child: TabIndexProvider(
        notifier: _tabIndexNotifier,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            final rootNav = Navigator.of(context, rootNavigator: true);
            if (rootNav.canPop()) {
              rootNav.pop();
              return;
            }
            final currentNavigator = _navigatorKeys[_selectedIndex].currentState;
            if (currentNavigator != null && currentNavigator.canPop()) {
              currentNavigator.pop();
              return;
            }
            if (_tabHistory.isNotEmpty) {
              final prevTab = _tabHistory.removeLast();
              setState(() {
                _selectedIndex = prevTab;
                _tabIndexNotifier.value = prevTab;
              });
              return;
            }
            if (_selectedIndex != _homeTabIndex) {
              setState(() {
                _selectedIndex = _homeTabIndex;
                _tabIndexNotifier.value = _homeTabIndex;
              });
              return;
            }
            SystemNavigator.pop();
          },
          child: Scaffold(
            body: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildNavigator(
                  0,
                  BlocProvider(
                    create: (_) => sl<HomeBloc>()..add(LoadHomeDataEvent()),
                    child: const HomeTab(),
                  ),
                ),
                _buildNavigator(1, const ShortsPage()),
                _buildNavigator(2, const SubscriptionsPage(showBackButton: false)),
                _buildNavigator(3, const MenuPage()),
              ],
            ),
            bottomNavigationBar: _showBottomNav 
                ? _buildBottomNavigationBar()
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => child,
          settings: settings,
        );
      },
    );
  }

  Widget _buildBottomNavigationBar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home, 'الرئيسية'),
              _buildNavItem(1, Icons.play_circle_outline, Icons.play_circle, 'شورتس'),
              _buildNavItem(2, Icons.diamond_outlined, Icons.diamond, 'الاشتراك'),
              _buildNavItem(3, Icons.person_outline, Icons.person, 'ملفي'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        if (_selectedIndex == index) {
          _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
        } else {
          setState(() {
            if (index != _homeTabIndex) {
              _tabHistory.add(_selectedIndex);
              if (_tabHistory.length > _maxTabHistory) {
                _tabHistory.removeAt(0);
              }
            } else {
              _tabHistory.clear();
            }
            _selectedIndex = index;
            _tabIndexNotifier.value = index;
          });
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void pushPage(Widget page) {
    _navigatorKeys[_selectedIndex].currentState?.push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void switchToTab(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      if (index != _homeTabIndex) {
        _tabHistory.add(_selectedIndex);
        if (_tabHistory.length > _maxTabHistory) {
          _tabHistory.removeAt(0);
        }
      } else {
        _tabHistory.clear();
      }
      _selectedIndex = index;
      _tabIndexNotifier.value = index;
    });
  }
}

extension MainNavigationContext on BuildContext {
  MainNavigationPageState? get mainNavigation {
    return findAncestorStateOfType<MainNavigationPageState>();
  }
  
  void pushWithNav(Widget page) {
    mainNavigation?.pushPage(page);
  }
}




