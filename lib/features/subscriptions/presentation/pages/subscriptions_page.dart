import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/apply_button.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/benefit_item.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/payment_button.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/payment_methods_row.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/promo_code_text_field.dart';
import 'package:learnify_lms/features/subscriptions/presentation/pages/widgets/subscription_plan_card.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_background.dart';
import '../../../../core/widgets/premium_subscription_popup.dart';
import '../../../../core/widgets/support_section.dart';
import '../../../authentication/data/datasources/auth_local_datasource.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../domain/entities/subscription_plan.dart';
import '../../domain/entities/subscription.dart';
import '../bloc/subscription_bloc.dart';
import '../bloc/subscription_event.dart';
import '../bloc/subscription_state.dart';
import '../../data/models/payment_model.dart';
import '../../../../core/routing/app_router.dart';

class SubscriptionsPage extends StatelessWidget {
  final bool showBackButton;

  const SubscriptionsPage({
    super.key,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SubscriptionBloc>()..add(const LoadSubscriptionsEvent()),
      child: _SubscriptionsPageContent(showBackButton: showBackButton),
    );
  }
}

class _SubscriptionsPageContent extends StatefulWidget {
  final bool showBackButton;

  const _SubscriptionsPageContent({
    this.showBackButton = true,
  });

  @override
  State<_SubscriptionsPageContent> createState() => _SubscriptionsPageContentState();
}

class _SubscriptionsPageContentState extends State<_SubscriptionsPageContent> with WidgetsBindingObserver {
  final TextEditingController _promoController = TextEditingController();
  bool _shouldShowPaymentAfterLogin = false;
  int? _pendingSelectedIndex;
  String? _pendingPromoCode;
  DateTime? _lastReloadTime;

  static const List<String> _benefits = [
    'الوصول الكامل لجميع الكورسات الحالية والمستقبلية',
    'شهادة إتمام بعد كل كورس',
    'محتوى متجدد باستمرار',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promoController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      final now = DateTime.now();
      if (_lastReloadTime == null ||
          now.difference(_lastReloadTime!).inSeconds > 5) {
        print('App resumed, reloading subscriptions...');
        _lastReloadTime = now;
        context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: CustomAppBar(
      title: 'اختر باقتك الآن',
        showBackButton: widget.showBackButton,
    ),
      body: Stack(
        children: [
          const CustomBackground(),
          BlocConsumer<SubscriptionBloc, SubscriptionState>(
            listener: (context, state) {
              if (state is SubscriptionError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.red,
                  ),
                );
              } else if (state is PromoCodeApplied) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (state is SubscriptionsLoaded && _shouldShowPaymentAfterLogin) {
                final selectedSubscription = state.selectedSubscription;
                if (selectedSubscription != null && mounted) {
                  _shouldShowPaymentAfterLogin = false;
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      _showPaymentBottomSheet(context, selectedSubscription, _pendingPromoCode);
                    }
                  });
                }
              } else if (state is PaymentCompleted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    print('Reloading subscriptions from UI after payment completion...');
                    context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());

                    print('Reloading user data to update subscription status...');
                    try {
                      context.read<AuthBloc>().add(CheckAuthStatusEvent());
                    } catch (e) {
                      print('Error reloading user data: $e');
                    }
                  }
                });
              }
            },
            builder: (context, state) {
              if (state is SubscriptionLoading) {
                return Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (state is SubscriptionsEmpty) {
                return _buildEmptyState(context);
              }

              if (state is SubscriptionsLoaded) {
                return _buildContent(context, state);
              }

              if (state is SubscriptionError) {
                return _buildErrorState(context, state.message);
              }

              return Center(
                child: CircularProgressIndicator(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SubscriptionsLoaded state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: Responsive.padding(context, horizontal: 22, vertical: 16),
              child: Column(
                children: [
              _buildPlansList(context, state),
                  SizedBox(height: Responsive.spacing(context, 16)),
                  _buildBenefitsList(),
                  SizedBox(height: Responsive.spacing(context, 16)),
                  _buildPromoCodeSection(context),
                  SizedBox(height: Responsive.spacing(context, 16)),
              _buildPaymentSection(context, state),
                  SizedBox(height: Responsive.spacing(context, 6)),
                  const SupportSection(),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildPlansList(BuildContext context, SubscriptionsLoaded state) {
    final isSelectedPlan = state.selectedIndex;
    final hasCouponApplied = state.appliedPromoCode != null && 
                             state.appliedPromoCode!.isNotEmpty &&
                             state.discountPercentage != null &&
                             state.discountPercentage! > 0;
    
    return Column(
      children: List.generate(
        state.subscriptions.length,
        (index) {
          final subscription = state.subscriptions[index];
          final maxDuration = state.subscriptions
              .map((s) => s.duration)
              .reduce((a, b) => a > b ? a : b);
          final isRecommended = subscription.duration == maxDuration;

          final shouldShowCouponDiscount = hasCouponApplied && index == isSelectedPlan;

          return Padding(
            padding: Responsive.padding(
              context,
              bottom: index < state.subscriptions.length - 1 ? 12 : 0,
            ),
          child: SubscriptionPlanCard(
              plan: SubscriptionPlan(
                title: _getDurationTitle(subscription.duration),
                originalPrice: subscription.localizedPriceBeforeDiscount,
                discountedPrice: subscription.localizedPrice,
                currency: subscription.getCurrencySymbol(),
                description: _getDurationDescription(subscription.duration),
                isRecommended: isRecommended,
                isActive: subscription.isActive,
              ),
              isSelected: state.selectedIndex == index,
              couponDiscountPercentage: shouldShowCouponDiscount ? state.discountPercentage : null,
              finalPriceAfterCoupon: shouldShowCouponDiscount ? state.finalPriceAfterCoupon : null,
              onTap: () {
                context.read<SubscriptionBloc>().add(
                      SelectSubscriptionEvent(index: index),
                    );
              },
        ),
          );
        },
      ),
    );
  }

  String _getDurationTitle(int duration) {
    if (duration == 1) {
      return 'باقة شهرية';
    } else if (duration == 6) {
      return 'باقة 6 شهور';
    } else if (duration == 12) {
      return 'باقة سنوية';
    } else {
      return 'باقة $duration شهور';
    }
  }

  String _getDurationDescription(int duration) {
    if (duration == 1) {
      return 'الوصول للكورسات و الشورتس لمدة شهر';
    } else if (duration == 12) {
      return 'الوصول للكورسات الشورتس لمدة سنة';
    } else {
      return 'الوصول للكورسات الشورتس لمدة $duration شهور';
    }
  }

  Widget _buildBenefitsList() {
    return Column(
      children: _benefits.map((benefit) => BenefitItem(text: benefit)).toList(),
    );
  }

  Widget _buildPromoCodeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'هل لديك كوبون خصم؟',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.black,
            fontSize: Responsive.fontSize(context, 14),
          ),
          textAlign: TextAlign.right,
        ),
        SizedBox(height: Responsive.spacing(context, 8)),
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: PromoCodeTextField(controller: _promoController),
            ),
            SizedBox(width: Responsive.width(context, 10)),
            ApplyButton(onPressed: _applyPromoCode),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentSection(BuildContext context, SubscriptionsLoaded state) {
    return Padding(
      padding: Responsive.padding(context, all: 16),
      child: Column(
        children: [
          PaymentButton(
            onPressed: () {
              print('Payment button pressed');
              if (mounted) {
                _processPayment(context, state);
              }
            },
          ),
          SizedBox(height: Responsive.spacing(context, 10)),
          const PaymentMethodsRow(),
        ],
      ),
    );
  }

  void _processPayment(BuildContext context, SubscriptionsLoaded state) async {
    final selectedSubscription = state.selectedSubscription;
    
    if (selectedSubscription == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار باقة أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authLocalDataSource = sl<AuthLocalDataSource>();
    final token = await authLocalDataSource.getAccessToken();
    
    final isAuthenticated = token != null && token.isNotEmpty;
    
    if (!isAuthenticated) {
      final goToLogin = await _showLoginRequiredDialog(context);

      if (goToLogin != true) {
        return;
      }

      if (!mounted) return;

      final selectedIndex = state.selectedIndex;
      final promoCode = state.appliedPromoCode;

      setState(() {
        _shouldShowPaymentAfterLogin = true;
        _pendingSelectedIndex = selectedIndex;
        _pendingPromoCode = promoCode;
      });

      final result = await Navigator.of(context, rootNavigator: true).pushNamed(
        AppRouter.login,
        arguments: {
          'returnTo': 'subscriptions',
          'selectedPlanIndex': selectedIndex,
          'promoCode': promoCode,
        },
      );

      if (result == true && mounted) {
        context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _pendingSelectedIndex != null) {
            context.read<SubscriptionBloc>().add(
              SelectSubscriptionEvent(index: _pendingSelectedIndex!),
            );
          }
        });
      } else {
        if (mounted) {
          setState(() {
            _shouldShowPaymentAfterLogin = false;
            _pendingSelectedIndex = null;
            _pendingPromoCode = null;
          });
        }
      }
      return;
    }

    final finalPrice = state.finalPriceAfterCoupon != null
        ? double.tryParse(state.finalPriceAfterCoupon!) ?? double.tryParse(selectedSubscription.localizedPrice) ?? 0.0
        : double.tryParse(selectedSubscription.localizedPrice) ?? 0.0;
    
    if (finalPrice == 0 && state.appliedPromoCode != null && state.appliedPromoCode!.isNotEmpty) {
      final currencyCode =
          selectedSubscription.paymentCurrencyCode ?? CurrencyService.getCurrencyCode();
      context.read<SubscriptionBloc>().add(
        ProcessPaymentEvent(
          service: PaymentService.kashier,
          currency: currencyCode,
          subscriptionId: selectedSubscription.id,
          phone: '',
          couponCode: state.appliedPromoCode,
        ),
      );
    } else {
      _showPaymentBottomSheet(context, selectedSubscription, state.appliedPromoCode);
    }
  }

  Future<bool?> _showLoginRequiredDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: PremiumOvalPopup(
            showCloseButton: true,
            onClose: () => Navigator.of(dialogContext).pop(false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'تسجيل الدخول مطلوب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 18),
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: Responsive.spacing(context, 12)),
                Text(
                  'لا يمكنك إتمام عملية الدفع بدون تسجيل الدخول. الرجاء تسجيل الدخول ثم المتابعة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 15),
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: Responsive.spacing(context, 24)),
                LayoutBuilder(
                  builder: (buttonsContext, constraints) {
                    final isNarrow = constraints.maxWidth < 320;

                    Widget cancelButton = OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: Responsive.spacing(context, 12),
                        ),
                        side: BorderSide(color: AppColors.greyLight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Responsive.radius(context, 28),
                          ),
                        ),
                        minimumSize: Size(
                          double.infinity,
                          Responsive.height(context, 44),
                        ),
                      ),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );

                    Widget loginButton = ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: EdgeInsets.symmetric(
                          vertical: Responsive.spacing(context, 12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Responsive.radius(context, 28),
                          ),
                        ),
                        elevation: 0,
                        minimumSize: Size(
                          double.infinity,
                          Responsive.height(context, 44),
                        ),
                      ),
                      child: const Text(
                        'تسجيل الدخول',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                        ),
                      ),
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: cancelButton,
                          ),
                          SizedBox(height: Responsive.spacing(context, 12)),
                          SizedBox(
                            width: double.infinity,
                            child: loginButton,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cancelButton),
                        SizedBox(width: Responsive.spacing(context, 12)),
                        Expanded(child: loginButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPaymentBottomSheet(
    BuildContext context,
    Subscription selectedSubscription,
    String? promoCode,
  ) {
    final bloc = context.read<SubscriptionBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Responsive.radius(context, 24)),
        ),
      ),
      builder: (ctx) {
        final paymentCurrency =
            selectedSubscription.paymentCurrencyCode ?? CurrencyService.getCurrencyCode();
        final currencySymbol = selectedSubscription.getCurrencySymbol();

        return BlocProvider.value(
          value: bloc,
          child: BlocBuilder<SubscriptionBloc, SubscriptionState>(
            builder: (context, state) {
              String amount;
              double? discountPercentage;
              String? appliedCouponCode = promoCode;
              
              if (state is SubscriptionsLoaded && 
                  state.appliedPromoCode != null && 
                  state.finalPriceAfterCoupon != null &&
                  state.discountPercentage != null &&
                  state.discountPercentage! > 0) {
                amount = state.finalPriceAfterCoupon!;
                discountPercentage = state.discountPercentage;
                appliedCouponCode = state.appliedPromoCode;
              } else {
                amount = selectedSubscription.localizedPrice;
              }

              return BlocListener<SubscriptionBloc, SubscriptionState>(
                listener: (context, state) async {
                  if (state is PaymentProcessing) {} else if (state is PaymentCheckoutReady) {
                    final uri = Uri.parse(state.checkoutUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('لا يمكن فتح رابط الدفع'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  } else if (state is PaymentFailed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else if (state is PaymentCompleted || state is PaymentInitiated) {
                    try {
                      context.read<AuthBloc>().add(CheckAuthStatusEvent());
                    } catch (e) {
                      print('Error reloading user data: $e');
                    }
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: Padding(
                  padding: EdgeInsets.only(
                    left: Responsive.width(ctx, 20),
                    right: Responsive.width(ctx, 20),
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + Responsive.height(ctx, 20),
                    top: Responsive.height(ctx, 16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: Responsive.width(ctx, 50),
                          height: Responsive.height(ctx, 5),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(Responsive.radius(ctx, 12)),
                          ),
                        ),
                      ),
                      SizedBox(height: Responsive.spacing(ctx, 16)),
                      Text(
                        'اختر طريقة الدفع',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(ctx, 16),
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: Responsive.spacing(ctx, 12)),
                      _PaymentOptionTile(
                        title: 'بطاقه ائتمانيه او محفظة',
                        subtitle: 'ادفع عبر بوابة Kashier',
                        icon: Icons.credit_card,
                        onTap: () {
                          bloc.add(
                            ProcessPaymentEvent(
                              service: PaymentService.kashier,
                              currency: paymentCurrency,
                              subscriptionId: selectedSubscription.id,
                              phone: '',
                              couponCode: appliedCouponCode,
                            ),
                          );
                        },
                      ),
                      if (Platform.isAndroid) ...[
                        SizedBox(height: Responsive.spacing(ctx, 12)),
                        _PaymentOptionTile(
                          title: 'Google Play',
                          subtitle: 'ادفع عبر Google Play ',
                          icon: Icons.payment,
                          onTap: () {
                            bloc.add(
                              ProcessPaymentEvent(
                                service: PaymentService.gplay,
                                currency: paymentCurrency,
                                subscriptionId: selectedSubscription.id,
                                phone: '',
                                couponCode: appliedCouponCode,
                              ),
                            );
                          },
                        ),
                      ] else if (Platform.isIOS) ...[
                        SizedBox(height: Responsive.spacing(ctx, 12)),
                        _PaymentOptionTile(
                          title: 'Apple In‑App Purchase',
                          subtitle: 'ادفع عبر Apple IAP',
                          icon: Icons.apple,
                          onTap: () {
                            bloc.add(
                              ProcessPaymentEvent(
                                service: PaymentService.iap,
                                currency: paymentCurrency,
                                subscriptionId: selectedSubscription.id,
                                phone: '',
                                couponCode: appliedCouponCode,
                              ),
                            );
                          },
                        ),
                      ],
                      SizedBox(height: Responsive.spacing(ctx, 12)),
                      SizedBox(height: Responsive.spacing(ctx, 16)),
                      if (discountPercentage != null && discountPercentage > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'السعر قبل الخصم',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: Responsive.fontSize(ctx, 12),
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              '${selectedSubscription.localizedPriceBeforeDiscount} $currencySymbol',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: Responsive.fontSize(ctx, 12),
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.spacing(ctx, 4)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: Responsive.width(ctx, 8),
                                vertical: Responsive.height(ctx, 4),
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(Responsive.radius(ctx, 4)),
                              ),
                              child: Text(
                                'خصم ${discountPercentage.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: Responsive.fontSize(ctx, 12),
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                            Text(
                              '-${((double.tryParse(selectedSubscription.localizedPrice) ?? 0) - (double.tryParse(amount) ?? 0)).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')} $currencySymbol',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: Responsive.fontSize(ctx, 12),
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.spacing(ctx, 8)),
                        Divider(
                          height: Responsive.height(ctx, 1),
                          color: Colors.grey[300],
                        ),
                        SizedBox(height: Responsive.spacing(ctx, 8)),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الإجمالي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(ctx, 14),
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '$amount $currencySymbol',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(ctx, 18),
                              fontWeight: FontWeight.bold,
                              color: discountPercentage != null && discountPercentage > 0
                                  ? const Color(0xFF4CAF50)
                                  : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: Responsive.spacing(ctx, 20)),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: Responsive.iconSize(context, 80),
            color: Colors.grey[400],
          ),
          SizedBox(height: Responsive.spacing(context, 16)),
          Text(
            'لا توجد باقات متاحة حالياً',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 18),
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 8)),
          Text(
            'يرجى المحاولة لاحقاً',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 14),
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 24)),
          ElevatedButton.icon(
            onPressed: () {
              context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
            },
            icon: Icon(Icons.refresh, size: Responsive.iconSize(context, 20)),
            label: const Text('تحديث'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.white,
              padding: Responsive.padding(context, horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Responsive.radius(context, 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
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
              fontSize: Responsive.fontSize(context, 18),
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 8)),
          Padding(
            padding: Responsive.padding(context, horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 14),
                color: Colors.grey[500],
              ),
            ),
          ),
          SizedBox(height: Responsive.spacing(context, 24)),
          ElevatedButton.icon(
            onPressed: () {
              context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
            },
            icon: Icon(Icons.refresh, size: Responsive.iconSize(context, 20)),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.white,
              padding: Responsive.padding(context, horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Responsive.radius(context, 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyPromoCode() {
    final promoCode = _promoController.text.trim();
    if (promoCode.isNotEmpty) {
      context.read<SubscriptionBloc>().add(
            ApplyPromoCodeEvent(promoCode: promoCode),
          );
    }
  }
}

class _PaymentOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Responsive.radius(context, 12)),
      child: Container(
        padding: Responsive.padding(context, vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(Responsive.radius(context, 12)),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: Responsive.width(context, 8),
              offset: Offset(0, Responsive.height(context, 3)),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: Responsive.width(context, 40),
              height: Responsive.width(context, 40),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(Responsive.radius(context, 10)),
              ),
              child: Icon(
                icon,
                color: AppColors.primary,
                size: Responsive.iconSize(context, 24),
              ),
            ),
            SizedBox(width: Responsive.width(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: Responsive.fontSize(context, 14),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: Responsive.spacing(context, 4)),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: Responsive.fontSize(context, 12),
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: Responsive.iconSize(context, 16),
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}


