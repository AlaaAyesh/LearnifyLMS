import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../authentication/data/datasources/auth_local_datasource.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_background.dart';
import '../../../authentication/domain/entities/user.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/bloc/auth_state.dart';
import '../../../authentication/presentation/widgets/PasswordField.dart';
import '../../../authentication/presentation/widgets/name_field.dart';
import '../../../authentication/presentation/widgets/phone_field.dart';
import '../../../authentication/presentation/widgets/birthday_field.dart';
import '../../../authentication/presentation/widgets/primary_button.dart';
import '../../../../core/routing/app_router.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AuthBloc>().add(CheckAuthStatusEvent());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _ProfilePageContent();
  }
}

class _ProfilePageContent extends StatefulWidget {
  const _ProfilePageContent();

  @override
  State<_ProfilePageContent> createState() => _ProfilePageContentState();
}

class _ProfilePageContentState extends State<_ProfilePageContent> {
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _isAuthenticated = true;
      _isCheckingAuth = false;
    } else {
      _checkAuthentication();
    }
  }

  Future<void> _checkAuthentication() async {
    final authLocalDataSource = sl<AuthLocalDataSource>();
    final token = await authLocalDataSource.getAccessToken();
    setState(() {
      _isAuthenticated = token != null && token.isNotEmpty;
      _isCheckingAuth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: const CustomAppBar(title: 'الحساب'),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (!_isAuthenticated) {
      return _UnauthenticatedProfilePage();
    }

    return const _AuthenticatedProfilePage();
  }
}

class _UnauthenticatedProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: const CustomAppBar(title: 'الحساب'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_off_outlined,
                  size: 80,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 32),

              Text(
                'تسجيل الدخول مطلوب',
                style: AppTextStyles.displayMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),

              Text(
                'للوصول إلى ملفك الشخصي والمحتوى الكامل، يرجى تسجيل الدخول أو إنشاء حساب جديد',
                style: AppTextStyles.bodyLarge,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(51),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushNamed(
                        AppRouter.login,
                        arguments: {'returnTo': 'profile'},
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(38),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushNamed(
                        AppRouter.register,
                        arguments: {'returnTo': 'profile'},
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppColors.primary),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      'إنشاء حساب جديد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthenticatedProfilePage extends StatefulWidget {
  const _AuthenticatedProfilePage();

  @override
  State<_AuthenticatedProfilePage> createState() =>
      _AuthenticatedProfilePageState();
}

class _AuthenticatedProfilePageState extends State<_AuthenticatedProfilePage> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final dayController = TextEditingController();
  final monthController = TextEditingController();
  final yearController = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  String? countryCode = '+20';
  User? currentUser;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    dayController.dispose();
    monthController.dispose();
    yearController.dispose();
    super.dispose();
  }

  void _populateUserData(User user) {
    currentUser = user;
    nameController.text = user.name;
    emailController.text = user.email;

    if (user.phone != null && user.phone!.isNotEmpty) {
      final parsed = _parsePhoneNumber(user.phone!);
      countryCode = parsed['countryCode'];
      phoneController.text = parsed['localNumber'] ?? '';
    }

    if (user.birthday != null && user.birthday!.isNotEmpty) {
      final birthdayParts = _parseBirthday(user.birthday!);
      dayController.text = birthdayParts['day'] ?? '';
      monthController.text = birthdayParts['month'] ?? '';
      yearController.text = birthdayParts['year'] ?? '';
    }
  }

  Map<String, String> _parseBirthday(String birthday) {
    try {
      final parts = birthday.split('-');
      if (parts.length == 3) {
        return {
          'year': parts[0],
          'month': parts[1],
          'day': parts[2],
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfilePage: Error parsing birthday: $e');
      }
    }
    return {'day': '', 'month': '', 'year': ''};
  }

  String? _getBirthdayString() {
    final day = dayController.text.trim();
    final month = monthController.text.trim();
    final year = yearController.text.trim();

    if (day.isEmpty || month.isEmpty || year.isEmpty) {
      return null;
    }

    final dayInt = int.tryParse(day);
    final monthInt = int.tryParse(month);
    final yearInt = int.tryParse(year);

    if (dayInt == null || monthInt == null || yearInt == null) {
      return null;
    }

    return '$year-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}';
  }

  Map<String, String?> _parsePhoneNumber(String fullPhone) {
    const countryCodes = [
      '+966',
      '+971',
      '+965',
      '+974',
      '+973',
      '+968',
      '+962',
      '+961',
      '+964',
      '+963',
      '+212',
      '+216',
      '+213',
      '+218',
      '+249',
      '+967',
      '+20',
    ];

    for (final code in countryCodes) {
      if (fullPhone.startsWith(code)) {
        return {
          'countryCode': code,
          'localNumber': fullPhone.substring(code.length),
        };
      }
    }

    return {
      'countryCode': '+20',
      'localNumber': fullPhone.replaceFirst('+', ''),
    };
  }

  String _normalizePhoneNumber(String localNumber, String countryCode) {
    localNumber = localNumber.trim();

    if (localNumber.startsWith('+')) {
      return localNumber;
    }

    if (localNumber.startsWith('0')) {
      localNumber = localNumber.substring(1);
    }

    return '$countryCode$localNumber';
  }

  void onSave() {
    if (formKey.currentState!.validate()) {
      String? normalizedPhone;
      if (phoneController.text.isNotEmpty) {
        normalizedPhone = _normalizePhoneNumber(
          phoneController.text,
          countryCode ?? '+20',
        );
      }

      final birthday = _getBirthdayString();

      context.read<AuthBloc>().add(
            UpdateProfileEvent(
              name: nameController.text.isNotEmpty ? nameController.text : null,
              phone: normalizedPhone,
              birthday: birthday,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: const CustomAppBar(title: 'الحساب'),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _populateUserData(state.user);
          } else if (state is AuthUnauthenticated) {
            Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
              AppRouter.splash,
              (route) => false,
            );
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
              ),
            );
          } else if (state is ProfileUpdated) {
            _populateUserData(state.user);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم حفظ التعديلات بنجاح'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is AuthLoading) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state is AuthAuthenticated) {
            return _buildProfileContent(state.user);
          }

          return Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        },
      ),
    );
  }

  Widget _buildProfileContent(User user) {
    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    final isTabletPortrait = isPortrait && media.size.shortestSide >= 600;
    if (currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _populateUserData(user);
        setState(() {});
      });
    }

    return Stack(
      children: [
        const CustomBackground(),
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: formKey,
            child: Column(
              children: [
                SizedBox(height: 24),

                _buildProfileAvatar(user),
                SizedBox(height: 16),

                Text(
                  user.name,
                  style: AppTextStyles.displayMedium,
                ),
                SizedBox(height: 4),
                Text(
                  user.email,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: isTabletPortrait
                        ? Responsive.spacing(context, 13)
                        : Responsive.spacing(context, 18),
                  ),
                ),
                SizedBox(height: 8),

                _buildSubscriptionBadge(user),
                SizedBox(height: 32),

                NameField(controller: nameController),
                SizedBox(height: 16),

                PhoneField(
                  controller: phoneController,
                  countryCode: countryCode,
                  onCountryChanged: (v) => setState(() => countryCode = v),
                ),
                SizedBox(height: 16),

                BirthdayField(
                  dayController: dayController,
                  monthController: monthController,
                  yearController: yearController,
                  validator: (value) {
                    return null;
                  },
                ),
                SizedBox(height: 16),

                _buildSectionTitle('تغيير كلمة المرور'),
                SizedBox(height: 16),

                PasswordField(
                  controller: passwordController,
                  obscure: obscurePassword,
                  hintText: 'كلمة المرور الجديدة',
                  validator: (v) => null,
                  onToggleVisibility: () =>
                      setState(() => obscurePassword = !obscurePassword),
                ),
                SizedBox(height: 16),

                PasswordField(
                  controller: confirmPasswordController,
                  obscure: obscureConfirmPassword,
                  hintText: 'تأكيد كلمة المرور',
                  validator: (v) {
                    if (passwordController.text.isNotEmpty &&
                        v != passwordController.text) {
                      return 'كلمة المرور غير متطابقة';
                    }
                    return null;
                  },
                  onToggleVisibility: () => setState(
                      () => obscureConfirmPassword = !obscureConfirmPassword),
                ),
                SizedBox(height: 32),

                PrimaryButton(
                  text: 'حفظ التعديلات',
                  onPressed: onSave,
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar(User user) {
    return CircleAvatar(
      radius: 50,
      backgroundColor: AppColors.primary.withAlpha(26),
      backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
          ? CachedNetworkImageProvider(user.avatarUrl!)
          : null,
      child: user.avatarUrl == null || user.avatarUrl!.isEmpty
          ? Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }

  Widget _buildSubscriptionBadge(User user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: user.isSubscribed
            ? AppColors.success.withAlpha(26)
            : AppColors.warning.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            user.isSubscribed ? Icons.verified : Icons.info_outline,
            size: 16,
            color: user.isSubscribed ? AppColors.success : AppColors.warning,
          ),
          SizedBox(width: 8),
          Text(
            user.isSubscribed ? 'مشترك' : 'غير مشترك',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: user.isSubscribed ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    final isTabletPortrait = isPortrait && media.size.shortestSide >= 600;
    final isTablet = Responsive.isTablet(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: isTablet
              ? (isTabletPortrait
                  ? Responsive.spacing(context, 13)
                  : Responsive.spacing(context, 22))
              : Responsive.spacing(context, 16),
        ),
      ),
    );
  }
}
