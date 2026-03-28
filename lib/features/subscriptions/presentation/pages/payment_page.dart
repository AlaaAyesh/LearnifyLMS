import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:learnify_lms/core/theme/app_text_styles.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_background.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/payment_model.dart';
import '../../domain/entities/subscription.dart';
import '../bloc/subscription_bloc.dart';
import '../bloc/subscription_event.dart';
import '../bloc/subscription_state.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import 'payment_checkout_webview_page.dart';
import 'widgets/payment_methods_row.dart';
import 'widgets/payment_success_dialog.dart';

class PaymentPage extends StatelessWidget {
  final Subscription subscription;
  final String? promoCode;
  final double? discountPercentage;
  final String? finalPriceAfterCoupon;

  const PaymentPage({
    super.key,
    required this.subscription,
    this.promoCode,
    this.discountPercentage,
    this.finalPriceAfterCoupon,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SubscriptionBloc>(),
      child: _PaymentPageContent(
        subscription: subscription,
        promoCode: promoCode,
        discountPercentage: discountPercentage,
        finalPriceAfterCoupon: finalPriceAfterCoupon,
      ),
    );
  }
}

class _PaymentPageContent extends StatefulWidget {
  final Subscription subscription;
  final String? promoCode;
  final double? discountPercentage;
  final String? finalPriceAfterCoupon;

  const _PaymentPageContent({
    required this.subscription,
    this.promoCode,
    this.discountPercentage,
    this.finalPriceAfterCoupon,
  });

  @override
  State<_PaymentPageContent> createState() => _PaymentPageContentState();
}

class _PaymentPageContentState extends State<_PaymentPageContent> {
  final TextEditingController _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  
  String get _currencySymbol => widget.subscription.getCurrencySymbol();

  String get _paymentCurrencyCode =>
      widget.subscription.paymentCurrencyCode ?? CurrencyService.getCurrencyCode();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: const CustomAppBar(title: 'إتمام الدفع'),
      body: BlocListener<SubscriptionBloc, SubscriptionState>(
        listener: (context, state) {
          if (state is PaymentProcessing) {
            setState(() => _isLoading = true);
          } else if (state is PaymentCheckoutReady) {
            setState(() => _isLoading = false);
            _openCheckoutUrl(state.checkoutUrl);
          } else if (state is PaymentInitiated || state is PaymentCompleted) {
            setState(() => _isLoading = false);
            _showPaymentSuccessDialog();
          } else if (state is PaymentFailed) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is SubscriptionLoading ||
              state is SubscriptionsLoaded ||
              state is SubscriptionError ||
              state is SubscriptionInitial) {
            if (_isLoading) {
              setState(() => _isLoading = false);
            }
          }
        },
        child: Stack(
          children: [
            const CustomBackground(),
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOrderSummary(),
                    SizedBox(height: 24),

                    _buildPhoneInput(),
                    SizedBox(height: 24),

                    _buildPaymentMethods(),
                    SizedBox(height: 32),

                    _buildPayButton(),
                    SizedBox(height: 16),

                    _buildSecurityNote(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final hasCouponDiscount = widget.discountPercentage != null && 
                              widget.discountPercentage! > 0 && 
                              widget.finalPriceAfterCoupon != null;
    final locPrice = widget.subscription.localizedPrice;
    final locBefore = widget.subscription.localizedPriceBeforeDiscount;
    final displayPrice = hasCouponDiscount 
        ? widget.finalPriceAfterCoupon! 
        : locPrice;
    final originalPrice = locPrice;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ملخص الطلب',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Divider(height: 24),
          _buildSummaryRow(
            'الباقة',
            _getDurationTitle(widget.subscription.duration),
          ),
          SizedBox(height: 12),
          if (locBefore != locPrice && locBefore.isNotEmpty)
            _buildSummaryRow(
              'السعر الأصلي للباقة',
              '$locBefore $_currencySymbol',
              isStrikethrough: true,
            ),
          if (locBefore != locPrice && locBefore.isNotEmpty)
            SizedBox(height: 12),
          _buildSummaryRow(
            'سعر الباقة',
            '$originalPrice $_currencySymbol',
          ),
          SizedBox(height: 12),
          if (widget.promoCode != null && widget.promoCode!.isNotEmpty) ...[
            _buildSummaryRow(
              'كود الخصم',
              widget.promoCode!,
              valueColor: AppColors.success,
            ),
            SizedBox(height: 8),
          ],
          if (hasCouponDiscount) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الخصم',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: AppColors.textSecondary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'خصم ${widget.discountPercentage!.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF4CAF50),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '-${(double.tryParse(originalPrice) ?? 0) - (double.tryParse(displayPrice) ?? 0)} $_currencySymbol',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            _buildSummaryRow(
              'السعر قبل الخصم',
              '$originalPrice $_currencySymbol',
              isStrikethrough: true,
            ),
            SizedBox(height: 12),
          ],
          const Divider(height: 24),
          _buildSummaryRow(
            'المجموع',
            '$displayPrice $_currencySymbol',
            isBold: true,
            valueColor: hasCouponDiscount ? const Color(0xFF4CAF50) : AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isStrikethrough = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
            decoration: isStrikethrough ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'رقم الهاتف للدفع',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: '+201XXXXXXXXX',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontFamily: 'Cairo',
              ),
              prefixIcon: const Icon(Icons.phone_android, color: AppColors.primary),
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'يرجى إدخال رقم الهاتف';
              }
              return null;
            },
          ),
          SizedBox(height: 8),
          Text(
            'سيتم استخدام هذا الرقم لإتمام عملية الدفع',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'طرق الدفع المتاحة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          const PaymentMethodsRow(),
        ],
      ),
    );
  }

  Widget _buildPayButton() {
    final hasCouponDiscount = widget.discountPercentage != null && 
                              widget.discountPercentage! > 0 && 
                              widget.finalPriceAfterCoupon != null;
    final displayPrice = hasCouponDiscount 
        ? widget.finalPriceAfterCoupon! 
        : widget.subscription.localizedPrice;

    final isTablet = Responsive.isTablet(context);
    final double fontSize =
        isTablet ? Responsive.fontSize(context, 18) : Responsive.fontSize(context, 20);
    final double verticalPadding = isTablet ? 14 : 16;
    final double borderRadius = isTablet ? 22 : 12;

    return ElevatedButton(
      onPressed: _isLoading ? null : _processPayment,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        elevation: 2,
      ),
      child: _isLoading
          ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              'ادفع $displayPrice $_currencySymbol',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
    );
  }

  Widget _buildSecurityNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock, size: 16, color: Colors.grey[500]),
        SizedBox(width: 8),
        Text(
          'جميع المعاملات مشفرة وآمنة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  void _processPayment() {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();

    final paymentService = Platform.isAndroid
        ? PaymentService.gplay
        : (Platform.isIOS ? PaymentService.iap : PaymentService.kashier);

    context.read<SubscriptionBloc>().add(
          ProcessPaymentEvent(
            service: paymentService,
            currency: _paymentCurrencyCode,
            subscriptionId: widget.subscription.id,
            phone: phone,
            couponCode: widget.promoCode,
          ),
        );
  }

  Future<void> _openCheckoutUrl(String checkoutUrl) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentCheckoutWebViewPage(
          checkoutUrl: checkoutUrl,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _isLoading = false);

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        print('Reloading subscriptions and transactions after successful payment...');
        context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());

        print('Reloading user data to update subscription status...');
        try {
          context.read<AuthBloc>().add(CheckAuthStatusEvent());
        } catch (e) {
          print('Error reloading user data: $e');
        }
      }

      _showPaymentSuccessDialog();
    } else if (result == false && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت عملية الدفع. يرجى المحاولة مرة أخرى'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showPaymentSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PaymentSuccessDialog(
        onContinue: () {
          Navigator.pop(ctx);

          if (mounted) {
            context.read<SubscriptionBloc>().add(const LoadSubscriptionsEvent());
            try {
              context.read<AuthBloc>().add(CheckAuthStatusEvent());
            } catch (e) {
              print('Error reloading user data: $e');
            }
          }
          
          Navigator.pop(context);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم تفعيل الاشتراك بنجاح! يمكنك الآن مشاهدة جميع الدروس'),
                backgroundColor: AppColors.success,
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }
}




