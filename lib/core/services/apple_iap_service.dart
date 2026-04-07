import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class AppleIAPService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  static const Map<int, String> productIdMap = {
    1: 'com.learnifykids.one_month_sub',
    2: 'com.learnifykids.six_month_sub',
    3: 'com.learnifykids.one_year_sub',
  };

  static String? getProductId(int planId) {
    return productIdMap[planId];
  }

  static int? getPlanId(String productId) {
    for (var entry in productIdMap.entries) {
      if (entry.value == productId) {
        return entry.key;
      }
    }
    return null;
  }

  static String getDisplayName(String productId, String originalTitle) {
    if (productId == 'com.learnifykids.one_year_sub') {
      return 'Lifetime Access';
    }
    if (originalTitle.contains('1 Year Subscription') ||
        originalTitle.contains('Year Subscription')) {
      return 'Lifetime Access';
    }
    return originalTitle;
  }

  Future<bool> isAvailable() async {
    try {
      return await _inAppPurchase.isAvailable();
    } catch (e) {
      debugPrint('Apple IAP availability error: $e');
      return false;
    }
  }

  Future<void> initialize({
    required Function(PurchaseDetails) onPurchaseUpdated,
    required Function(String) onError,
  }) async {
    try {
      final bool available = await isAvailable();
      if (!available) {
        throw Exception('متجر App Store غير متاح على هذا الجهاز');
      }

      await _purchaseSubscription?.cancel();

      _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
        (List<PurchaseDetails> purchaseDetailsList) {
          _handlePurchaseUpdates(purchaseDetailsList, onPurchaseUpdated, onError);
        },
        onDone: () {
          debugPrint('Apple IAP purchase stream closed');
        },
        onError: (error) {
          debugPrint('Apple IAP purchase stream error: $error');
          onError('خطأ في نظام الدفع: $error');
        },
      );

      debugPrint('Apple IAP initialized successfully');
    } catch (e) {
      debugPrint('Apple IAP initialization error: $e');
      onError('فشل تهيئة نظام الدفع: $e');
      rethrow;
    }
  }

  void _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
    Function(PurchaseDetails) onPurchaseUpdated,
    Function(String) onError,
  ) {
    for (final purchaseDetails in purchaseDetailsList) {
      debugPrint(
        'Apple IAP update: ${purchaseDetails.status}, Product: ${purchaseDetails.productID}',
      );

      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          debugPrint('Purchase pending: ${purchaseDetails.productID}');
          break;

        case PurchaseStatus.error:
          final errorMsg =
              purchaseDetails.error?.message ?? 'خطأ في عملية الشراء';
          final errorCode = purchaseDetails.error?.code;
          debugPrint('Purchase error: $errorMsg');
          debugPrint('Error code: $errorCode');

          String detailedError = errorMsg;
          if (errorCode != null) {
            detailedError += '\n\nكود الخطأ: $errorCode';
          }

          detailedError += '\n\nتأكد من:';
          detailedError += '\n1. تسجيل الدخول بـ Apple ID على الجهاز';
          detailedError += '\n2. المنتج مفعّل في App Store Connect';
          detailedError += '\n3. إصدار التطبيق مرفوع ويحتوي على In-App Purchase';

          onError(detailedError);
          if (purchaseDetails.pendingCompletePurchase) {
            _inAppPurchase.completePurchase(purchaseDetails);
          }
          break;

        case PurchaseStatus.purchased:
          debugPrint('Purchase completed: ${purchaseDetails.productID}');
          onPurchaseUpdated(purchaseDetails);
          break;

        case PurchaseStatus.restored:
          debugPrint('Purchase restored: ${purchaseDetails.productID}');
          onPurchaseUpdated(purchaseDetails);
          if (purchaseDetails.pendingCompletePurchase) {
            _inAppPurchase.completePurchase(purchaseDetails);
          }
          break;

        case PurchaseStatus.canceled:
          debugPrint('Purchase canceled: ${purchaseDetails.productID}');
          onError('تم إلغاء عملية الشراء');
          if (purchaseDetails.pendingCompletePurchase) {
            _inAppPurchase.completePurchase(purchaseDetails);
          }
          break;
      }
    }
  }

  Future<List<ProductDetails>> getProducts(List<String> productIds) async {
    debugPrint('Apple IAP querying products: $productIds');

    final bool available = await isAvailable();
    if (!available) {
      throw Exception('متجر App Store غير متاح');
    }

    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(productIds.toSet());

    debugPrint('Apple IAP query: ${response.productDetails.length} products');
    debugPrint('Not found IDs: ${response.notFoundIDs}');

    if (response.error != null) {
      throw Exception(
        'خطأ في جلب المنتجات: ${response.error!.message}',
      );
    }

    if (response.productDetails.isEmpty) {
      String errorMessage = 'لم يتم العثور على المنتجات المطلوبة.\n\n';
      errorMessage += 'المعرفات المطلوبة: $productIds\n';
      if (response.notFoundIDs.isNotEmpty) {
        errorMessage += 'المعرفات غير الموجودة: ${response.notFoundIDs}\n';
      }
      errorMessage += '\nتأكد من:';
      errorMessage += '\n1. إنشاء المنتجات في App Store Connect (In-App Purchases)';
      errorMessage += '\n2. ربط المنتجات بإصدار التطبيق قبل الإرسال للمراجعة';
      errorMessage += '\n3. استخدام نفس Bundle ID في Xcode و App Store Connect';
      throw Exception(errorMessage);
    }

    for (var product in response.productDetails) {
      final displayName = getDisplayName(product.id, product.title);
      debugPrint(
        'Product: ${product.id}, Price: ${product.price}, Title: $displayName',
      );
    }

    return response.productDetails;
  }

  Future<void> purchaseProduct(ProductDetails productDetails) async {
    final displayName =
        getDisplayName(productDetails.id, productDetails.title);
    debugPrint('Apple IAP starting purchase: ${productDetails.id}');

    final purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );

    try {
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        throw Exception(
          'فشل بدء عملية الشراء.\n\n'
          'تأكد من:\n'
          '1. تسجيل الدخول بـ Apple ID على الجهاز\n'
          '2. المنتج مفعّل في App Store Connect\n'
          '3. إصدار التطبيق مرفوع ويحتوي على In-App Purchase',
        );
      }

      debugPrint('Apple IAP purchase initiated: ${productDetails.id}');
    } catch (e) {
      debugPrint('Apple IAP purchase error: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في عملية الشراء: $e');
    }
  }

  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.pendingCompletePurchase) {
      debugPrint('Completing purchase: ${purchaseDetails.productID}');
      await _inAppPurchase.completePurchase(purchaseDetails);
      debugPrint('Purchase completed: ${purchaseDetails.productID}');
    }
  }

  Future<void> restorePurchases() async {
    debugPrint('Restoring Apple IAP purchases...');
    try {
      await _inAppPurchase.restorePurchases();
      debugPrint('Apple IAP restore completed');
    } catch (e) {
      debugPrint('Apple IAP restore error: $e');
      throw Exception('فشل استرجاع المشتريات: $e');
    }
  }

  void dispose() {
    debugPrint('Disposing AppleIAPService');
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
  }
}
