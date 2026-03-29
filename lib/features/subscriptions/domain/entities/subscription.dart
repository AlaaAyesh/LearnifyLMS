import 'package:equatable/equatable.dart';

class Subscription extends Equatable {
  final int id;
  final String nameAr;
  final String nameEn;
  final String price;
  final String usdPrice;
  final String priceBeforeDiscount;
  final String usdPriceBeforeDiscount;
  /// From API `localized_price` (display amount for the user’s region).
  final String localizedPrice;
  /// From API `localized_price_before_discount`.
  final String localizedPriceBeforeDiscount;
  final int duration;
  final String? currency;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  const Subscription({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.price,
    required this.usdPrice,
    required this.priceBeforeDiscount,
    required this.usdPriceBeforeDiscount,
    required this.localizedPrice,
    required this.localizedPriceBeforeDiscount,
    required this.duration,
    this.currency,
    this.isActive = false,
    this.createdAt,
    this.updatedAt,
  });

  String getName({bool isEnglish = false}) => isEnglish ? nameEn : nameAr;

  bool get hasDiscount {
    final currentPrice = double.tryParse(localizedPrice) ?? 0;
    final originalPrice = double.tryParse(localizedPriceBeforeDiscount) ?? 0;
    return originalPrice > currentPrice;
  }

  int get discountPercentage {
    final currentPrice = double.tryParse(localizedPrice) ?? 0;
    final originalPrice = double.tryParse(localizedPriceBeforeDiscount) ?? 0;
    if (originalPrice <= 0) return 0;
    return (((originalPrice - currentPrice) / originalPrice) * 100).round();
  }

  String getCurrencySymbol() {
    if (currency == null || currency!.isEmpty) {
      return 'جم';
    }
    switch (currency!.toUpperCase()) {
      case 'EGP':
        return 'جم';
      case 'USD':
        return '\$';
      default:
        return 'جم';
    }
  }

  /// Uppercase ISO code from server; use with API `payments/process`.
  String? get paymentCurrencyCode {
    final c = currency?.trim();
    if (c == null || c.isEmpty) return null;
    return c.toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        nameAr,
        nameEn,
        price,
        usdPrice,
        priceBeforeDiscount,
        usdPriceBeforeDiscount,
        localizedPrice,
        localizedPriceBeforeDiscount,
        duration,
        currency,
        isActive,
        createdAt,
        updatedAt,
      ];
}




