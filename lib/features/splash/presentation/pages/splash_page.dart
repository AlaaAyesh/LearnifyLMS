import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/storage/hive_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../authentication/domain/repositories/auth_repository.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/bloc/auth_state.dart';
import '../widgets/animated_logo.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isFirstTime = true;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _initPushNotifications();
    _checkFirstTime();
  }

  Future<void> _initPushNotifications() async {
    if (Firebase.apps.isEmpty) return;

    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('TOKEN: $token');
    } catch (error, stackTrace) {
      debugPrint('Push notifications init skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _initAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();
  }

  Future<void> _refreshLoggedInUserIfSessionExists() async {
    final repo = sl<AuthRepository>();
    final authBloc = context.read<AuthBloc>();
    final isLoggedInResult = await repo.isLoggedIn();
    await isLoggedInResult.fold(
      (_) async {},
      (isLoggedIn) async {
        if (!isLoggedIn || !mounted) return;
        await repo.getCurrentUserFromApi();
        if (!mounted) return;
        authBloc.add(CheckAuthStatusEvent());
      },
    );
  }

  Future<void> _checkFirstTime() async {
    final hiveService = sl<HiveService>();
    final isFirstTime = await hiveService.getData(AppConstants.keyIsFirstTime);
    
    if (!mounted) return;
    
    setState(() {
      _isFirstTime = isFirstTime == null || isFirstTime == true;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    if (_isFirstTime) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      await hiveService.saveData(AppConstants.keyIsFirstTime, false);

      await _refreshLoggedInUserIfSessionExists();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      await _refreshLoggedInUserIfSessionExists();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {},
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Responsive.isTablet(context)
                ? _buildTabletContent(context)
                : _buildPhoneContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneContent(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
              children: [
                SizedBox(height: (screenHeight - topPadding) * 0.15),
                const AnimatedLogo(),
        const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: RichText(
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
            text: const TextSpan(
                      children: [
                        TextSpan(
                          // text: 'مستقبل ابنك يبدأ\n',
                          text: 'TESTTTTTTTTTTTTTTT',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF000000),
                            height: 1.5,
                          ),
                        ),
                        TextSpan(
                          text: 'هنا 👋',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFFFFF),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
      ],
    );
  }

  Widget _buildTabletContent(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AnimatedLogo(),
            const SizedBox(height: 32),
            RichText(
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'مستقبل ابنك يبدأ\n',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF000000),
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: 'هنا 👋',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFFFFF),
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}



