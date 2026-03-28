import 'dart:io';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../data/models/payment_model.dart';
import '../../data/models/subscription_model.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../../domain/usecases/create_subscription_usecase.dart';
import '../../domain/usecases/get_subscription_by_id_usecase.dart';
import '../../domain/usecases/get_subscriptions_usecase.dart';
import '../../domain/usecases/update_subscription_usecase.dart';
import '../../../../core/services/google_play_billing_service.dart';
import '../../../../core/services/apple_iap_service.dart';
import 'subscription_event.dart';
import 'subscription_state.dart';
import '../../domain/usecases/verify_iap_receipt_usecase.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  final GetSubscriptionsUseCase getSubscriptionsUseCase;
  final GetSubscriptionByIdUseCase getSubscriptionByIdUseCase;
  final CreateSubscriptionUseCase createSubscriptionUseCase;
  final UpdateSubscriptionUseCase updateSubscriptionUseCase;
  final SubscriptionRepository subscriptionRepository;
  final VerifyIapReceiptUseCase verifyIapReceiptUseCase;

  late final GooglePlayBillingService _billingService;
  late final AppleIAPService _appleIapService;
  bool _billingInitialized = false;
  bool _appleIapInitialized = false;
  int? _pendingPurchaseId;
  Timer? _paymentTimeoutTimer;

  SubscriptionBloc({
    required this.getSubscriptionsUseCase,
    required this.getSubscriptionByIdUseCase,
    required this.createSubscriptionUseCase,
    required this.updateSubscriptionUseCase,
    required this.subscriptionRepository,
    required this.verifyIapReceiptUseCase,
  }) : super(SubscriptionInitial()) {
    _billingService = GooglePlayBillingService();
    _appleIapService = AppleIAPService();

    on<LoadSubscriptionsEvent>(_onLoadSubscriptions);
    on<LoadSubscriptionByIdEvent>(_onLoadSubscriptionById);
    on<SelectSubscriptionEvent>(_onSelectSubscription);
    on<ApplyPromoCodeEvent>(_onApplyPromoCode);
    on<CreateSubscriptionEvent>(_onCreateSubscription);
    on<UpdateSubscriptionEvent>(_onUpdateSubscription);
    on<ClearSubscriptionStateEvent>(_onClearState);
    on<ProcessPaymentEvent>(_onProcessPayment);
    on<VerifyIapReceiptEvent>(_onVerifyIapReceipt);
  }

  Future<void> _initializeGooglePlayBilling(
      Emitter<SubscriptionState> emit,
      ) async {
    if (_billingInitialized) return;

    print('Initializing Google Play Billing...');
    try {
      await _billingService.initialize(
        onPurchaseUpdated: (PurchaseDetails purchase) async {
          print('Purchase updated callback triggered');
          await _verifyAndCompletePurchase(purchase, emit);
        },
        onError: (String error) {
          print('Billing error callback: $error');
          emit(PaymentFailed(error));
        },
      );
      _billingInitialized = true;
      print('Google Play Billing initialized successfully');
    } catch (e) {
      print('Failed to initialize billing: $e');
      emit(PaymentFailed('فشل تهيئة نظام الدفع: $e'));
      rethrow;
    }
  }

  Future<void> _initializeAppleIAP(Emitter<SubscriptionState> emit) async {
    if (_appleIapInitialized) return;

    print('Initializing Apple IAP...');
    try {
      await _appleIapService.initialize(
        onPurchaseUpdated: (PurchaseDetails purchase) async {
          print('Apple IAP purchase updated');
          await _verifyAndCompletePurchase(purchase, emit);
        },
        onError: (String error) {
          print('Apple IAP error: $error');
          emit(PaymentFailed(error));
        },
      );
      _appleIapInitialized = true;
      print('Apple IAP initialized successfully');
    } catch (e) {
      print('Failed to initialize Apple IAP: $e');
      emit(PaymentFailed('فشل تهيئة نظام الدفع: $e'));
      rethrow;
    }
  }

  Future<void> _completePurchaseForStore(
    String store,
    PurchaseDetails purchaseDetails,
  ) async {
    if (!purchaseDetails.pendingCompletePurchase) return;
    if (store == 'app_store') {
      await _appleIapService.completePurchase(purchaseDetails);
    } else {
      await _billingService.completePurchase(purchaseDetails);
    }
  }

  Future<void> _verifyAndCompletePurchase(
      PurchaseDetails purchase,
      Emitter<SubscriptionState> emit,
      ) async {
    print('Verifying purchase: ${purchase.productID}');

    if (_pendingPurchaseId == null) {
      print('No pending purchase ID found');
      emit(PaymentFailed('خطأ: لم يتم العثور على معرف الدفع'));
      if (purchase.pendingCompletePurchase) {
        await _completePurchaseForStore(
          Platform.isAndroid ? 'google_play' : 'app_store',
          purchase,
        );
      }
      return;
    }

    try {
      final verificationData = purchase.verificationData;

      print('Verification data: ${verificationData.serverVerificationData}');
      print('Transaction ID: ${purchase.purchaseID}');
      print('Product ID: ${purchase.productID}');
      print('Purchase ID from backend: $_pendingPurchaseId');

      add(VerifyIapReceiptEvent(
        receiptData: verificationData.serverVerificationData,
        transactionId: purchase.purchaseID ?? '',
        purchaseId: _pendingPurchaseId!,
        store: Platform.isAndroid ? 'google_play' : 'app_store',
        purchaseDetails: purchase,
      ));

    } catch (e) {
      print('Verification error: $e');
      emit(PaymentFailed('فشل التحقق من عملية الشراء: $e'));
      if (purchase.pendingCompletePurchase) {
        await _completePurchaseForStore(
          Platform.isAndroid ? 'google_play' : 'app_store',
          purchase,
        );
      }
    }
  }
  Future<void> _onVerifyIapReceipt(
      VerifyIapReceiptEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    print('Verifying IAP receipt with backend...');
    print('Receipt data: ${event.receiptData.substring(0, event.receiptData.length > 50 ? 50 : event.receiptData.length)}...');
    print('Transaction ID: ${event.transactionId}');
    print('Purchase ID: ${event.purchaseId}');
    print('Store: ${event.store}');
    
    emit(IapVerificationLoading());

    final result = await verifyIapReceiptUseCase(
      receiptData: event.receiptData,
      transactionId: event.transactionId,
      purchaseId: event.purchaseId,
      store: event.store,
    );

    result.fold(
      (failure) {
        _paymentTimeoutTimer?.cancel();
        print('Verification failed: ${failure.message}');
        emit(IapVerificationFailure(failure.message));
        if (event.purchaseDetails != null && event.purchaseDetails!.pendingCompletePurchase) {
          _completePurchaseForStore(event.store, event.purchaseDetails!);
        }
        _pendingPurchaseId = null;
      },
      (_) async {
        _paymentTimeoutTimer?.cancel();
        print('Verification successful');
        if (event.purchaseDetails != null && event.purchaseDetails!.pendingCompletePurchase) {
          _completePurchaseForStore(event.store, event.purchaseDetails!);
        }
        emit(IapVerificationSuccess());
        emit(PaymentCompleted(
          purchase: null,
          message: 'تم تفعيل اشتراكك بنجاح',
        ));
        await Future.delayed(const Duration(milliseconds: 500));
        print('Reloading subscriptions after successful payment...');
        await _onLoadSubscriptions(const LoadSubscriptionsEvent(), emit);
        _pendingPurchaseId = null;
      },
    );
  }

  Future<void> _onLoadSubscriptions(
      LoadSubscriptionsEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    emit(SubscriptionLoading());

    final subscriptionsResult = await getSubscriptionsUseCase();
    
    await subscriptionsResult.fold(
      (failure) async {
        emit(SubscriptionError(failure.message));
      },
      (subscriptions) async {
        if (subscriptions.isEmpty) {
          emit(SubscriptionsEmpty());
        } else {
          int? activeSubscriptionId;
          try {
            print('Fetching user transactions to find active subscription...');
            final transactionsResult = await subscriptionRepository.getMyTransactions(
              page: 1,
              perPage: 10,
            );
            
            transactionsResult.fold(
              (failure) {
                print('Failed to fetch transactions: ${failure.message}');
              },
              (transactionsResponse) {
                print('Transactions fetched: ${transactionsResponse.transactions.length} transactions');
                final activeTransaction = transactionsResponse.activeSubscriptionTransaction;
                if (activeTransaction != null) {
                  activeSubscriptionId = activeTransaction.purchasableId;
                  print('Active subscription found! ID: $activeSubscriptionId, Status: ${activeTransaction.status.value}, Type: ${activeTransaction.purchasableType}');
                } else {
                  print('No active subscription transaction found');
                }
              },
            );
          } catch (e) {
            print('Error fetching transactions: $e');
          }

          print('Marking subscriptions as active. Active subscription ID: $activeSubscriptionId');
          final subscriptionsWithActive = subscriptions.map((subscription) {
            final isActive = activeSubscriptionId != null && 
                           subscription.id == activeSubscriptionId;
            if (isActive) {
              print('✓ Subscription ${subscription.id} (${subscription.nameAr}) is marked as ACTIVE');
            }
            return SubscriptionModel(
              id: subscription.id,
              nameAr: subscription.nameAr,
              nameEn: subscription.nameEn,
              price: subscription.price,
              usdPrice: subscription.usdPrice,
              priceBeforeDiscount: subscription.priceBeforeDiscount,
              usdPriceBeforeDiscount: subscription.usdPriceBeforeDiscount,
              localizedPrice: subscription.localizedPrice,
              localizedPriceBeforeDiscount: subscription.localizedPriceBeforeDiscount,
              duration: subscription.duration,
              currency: subscription.currency,
              isActive: isActive,
              createdAt: subscription.createdAt,
              updatedAt: subscription.updatedAt,
            );
          }).toList();

          int recommendedIndex = 0;
          int maxDuration = 0;
          for (int i = 0; i < subscriptionsWithActive.length; i++) {
            if (subscriptionsWithActive[i].duration > maxDuration) {
              maxDuration = subscriptionsWithActive[i].duration;
              recommendedIndex = i;
            }
          }
          emit(SubscriptionsLoaded(
            subscriptions: subscriptionsWithActive,
            selectedIndex: recommendedIndex,
          ));
        }
      },
    );
  }

  Future<void> _onLoadSubscriptionById(
      LoadSubscriptionByIdEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    emit(SubscriptionLoading());

    final result = await getSubscriptionByIdUseCase(id: event.id);

    result.fold(
          (failure) => emit(SubscriptionError(failure.message)),
          (subscription) => emit(SubscriptionDetailsLoaded(subscription: subscription)),
    );
  }

  void _onSelectSubscription(
      SelectSubscriptionEvent event,
      Emitter<SubscriptionState> emit,
      ) {
    final currentState = state;
    if (currentState is SubscriptionsLoaded) {
      final newSelectedSubscription = event.index < currentState.subscriptions.length
          ? currentState.subscriptions[event.index]
          : null;

      if (currentState.appliedPromoCode != null &&
          currentState.appliedPromoCode!.isNotEmpty &&
          currentState.discountPercentage != null &&
          newSelectedSubscription != null) {
        final currentPrice = double.tryParse(newSelectedSubscription.localizedPrice) ?? 0.0;
        final discountPercentage = currentState.discountPercentage!;
        final discountAmount = (currentPrice * discountPercentage / 100);
        final finalPrice = currentPrice - discountAmount;
        final finalPriceString = finalPrice.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

        emit(currentState.copyWith(
          selectedIndex: event.index,
          discountAmount: discountAmount,
          finalPriceAfterCoupon: finalPriceString,
        ));
      } else {
        emit(currentState.copyWith(selectedIndex: event.index));
      }
    }
  }

  Future<void> _onApplyPromoCode(
      ApplyPromoCodeEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    final currentState = state;
    if (currentState is SubscriptionsLoaded) {
      final selectedSubscription = currentState.selectedSubscription;

      if (selectedSubscription == null) {
        emit(SubscriptionError('يرجى اختيار باقة أولاً'));
        return;
      }

      if (event.promoCode.isEmpty) {
        emit(SubscriptionError('يرجى إدخال كود الخصم'));
        return;
      }

      final result = await subscriptionRepository.validateCoupon(
        code: event.promoCode,
        type: 'subscription',
        id: selectedSubscription.id,
      );

      result.fold(
            (failure) {
          emit(SubscriptionError(failure.message));
          if (state is SubscriptionError) {
            emit(currentState);
          }
        },
            (validationResult) {
          print('Coupon validation result: $validationResult');

          Map<String, dynamic> responseData;
          if (validationResult['data'] != null && validationResult['data'] is Map) {
            responseData = validationResult['data'] as Map<String, dynamic>;
          } else {
            responseData = validationResult is Map<String, dynamic>
                ? validationResult
                : <String, dynamic>{};
          }

          final discountPercentage = responseData['discount_percentage'] != null
              ? (responseData['discount_percentage'] is num
              ? responseData['discount_percentage'].toDouble()
              : double.tryParse(responseData['discount_percentage'].toString()) ?? 0.0)
              : (responseData['percentage'] != null
              ? (responseData['percentage'] is num
              ? responseData['percentage'].toDouble()
              : double.tryParse(responseData['percentage'].toString()) ?? 0.0)
              : null);

          final discountAmount = responseData['discount_amount'] != null
              ? (responseData['discount_amount'] is num
              ? responseData['discount_amount'].toDouble()
              : double.tryParse(responseData['discount_amount'].toString()) ?? 0.0)
              : (responseData['discount'] != null
              ? (responseData['discount'] is num
              ? responseData['discount'].toDouble()
              : double.tryParse(responseData['discount'].toString()) ?? 0.0)
              : null);

          final discountType = responseData['discount_type']?.toString().toLowerCase() ??
              responseData['type']?.toString().toLowerCase() ??
              'percentage';

          final currentPrice = double.tryParse(selectedSubscription.localizedPrice) ?? 0.0;
          double finalPrice = currentPrice;
          double? calculatedDiscountPercentage;
          double calculatedDiscountAmount = 0.0;

          if (discountType == 'percentage' && discountPercentage != null && discountPercentage > 0) {
            calculatedDiscountPercentage = discountPercentage;
            calculatedDiscountAmount = (currentPrice * discountPercentage / 100);
            finalPrice = currentPrice - calculatedDiscountAmount;
          } else if (discountType == 'fixed' && discountAmount != null && discountAmount > 0) {
            calculatedDiscountAmount = discountAmount;
            finalPrice = currentPrice - discountAmount;
            if (finalPrice < 0) finalPrice = 0;
            calculatedDiscountPercentage = currentPrice > 0
                ? ((discountAmount / currentPrice) * 100)
                : 0.0;
          } else if (discountPercentage != null && discountPercentage > 0) {
            calculatedDiscountPercentage = discountPercentage;
            calculatedDiscountAmount = (currentPrice * discountPercentage / 100);
            finalPrice = currentPrice - calculatedDiscountAmount;
          } else if (discountAmount != null && discountAmount > 0) {
            calculatedDiscountAmount = discountAmount;
            finalPrice = currentPrice - discountAmount;
            if (finalPrice < 0) finalPrice = 0;
            calculatedDiscountPercentage = currentPrice > 0
                ? ((discountAmount / currentPrice) * 100)
                : 0.0;
          }

          final finalPriceString = finalPrice.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

          final updatedState = currentState.copyWith(
            appliedPromoCode: event.promoCode,
            discountAmount: calculatedDiscountAmount,
            discountPercentage: calculatedDiscountPercentage,
            finalPriceAfterCoupon: finalPriceString,
          );
          emit(updatedState);

          emit(PromoCodeApplied(
            promoCode: event.promoCode,
            discountAmount: calculatedDiscountAmount,
            discountPercentage: calculatedDiscountPercentage,
            message: calculatedDiscountPercentage != null && calculatedDiscountPercentage > 0
                ? 'تم تطبيق كود الخصم بنجاح - خصم ${calculatedDiscountPercentage.toStringAsFixed(0)}%'
                : 'تم تطبيق كود الخصم بنجاح',
          ));

          emit(updatedState);
        },
      );
    }
  }

  Future<void> _onCreateSubscription(
      CreateSubscriptionEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    emit(SubscriptionLoading());

    final result = await createSubscriptionUseCase(request: event.request);

    result.fold(
          (failure) => emit(SubscriptionError(failure.message)),
          (subscription) => emit(SubscriptionCreated(subscription: subscription)),
    );
  }

  Future<void> _onUpdateSubscription(
      UpdateSubscriptionEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    emit(SubscriptionLoading());

    final result = await updateSubscriptionUseCase(
      id: event.id,
      request: event.request,
    );

    result.fold(
          (failure) => emit(SubscriptionError(failure.message)),
          (subscription) => emit(SubscriptionUpdated(subscription: subscription)),
    );
  }

  void _onClearState(
      ClearSubscriptionStateEvent event,
      Emitter<SubscriptionState> emit,
      ) {
    emit(SubscriptionInitial());
  }

  Future<void> _onProcessPayment(
      ProcessPaymentEvent event,
      Emitter<SubscriptionState> emit,
      ) async {
    _paymentTimeoutTimer?.cancel();
    
    emit(PaymentProcessing());

    _paymentTimeoutTimer = Timer(const Duration(seconds: 5), () {
      final currentState = state;
      if (currentState is PaymentProcessing || currentState is PaymentInitiated) {
        add(const LoadSubscriptionsEvent());
      }
    });

    if (event.service == PaymentService.iap && Platform.isIOS) {
      try {
        print('Processing Apple IAP payment...');
        print('Subscription ID: ${event.subscriptionId}');

        if (event.subscriptionId == null) {
          print('Subscription ID is null');
          emit(PaymentFailed('يرجى اختيار باقة أولاً'));
          return;
        }

        print('Step 1: Creating payment record in backend...');
        final request = ProcessPaymentRequest(
          service: event.service,
          currency: event.currency,
          courseId: event.courseId,
          subscriptionId: event.subscriptionId,
          phone: event.phone,
          couponCode: event.couponCode,
        );

        final paymentResult = await subscriptionRepository.processPayment(request: request);

        await paymentResult.fold(
          (failure) {
            _paymentTimeoutTimer?.cancel();
            print('Failed to create payment record: ${failure.message}');
            emit(PaymentFailed('فشل إنشاء سجل الدفع: ${failure.message}'));
          },
          (response) async {
            if (response.purchase == null) {
              print('No purchase ID in response');
              emit(PaymentFailed('فشل: لم يتم الحصول على معرف الدفع من السيرفر'));
              return;
            }

            _pendingPurchaseId = response.purchase!.id;
            print('Payment record created with ID: $_pendingPurchaseId');

            if (!_appleIapInitialized) {
              await _initializeAppleIAP(emit);
            }

            final productId = AppleIAPService.getProductId(event.subscriptionId!);

            if (productId == null) {
              print('Invalid subscription ID: ${event.subscriptionId}');
              emit(PaymentFailed(
                'معرف الباقة غير صحيح.\n'
                'معرف الباقة: ${event.subscriptionId}\n'
                'المعرفات المتاحة: ${AppleIAPService.productIdMap.keys.join(', ')}',
              ));
              return;
            }

            print('Apple product ID for subscription ${event.subscriptionId}: $productId');

            final products = await _appleIapService.getProducts([productId]);

            if (products.isEmpty) {
              print('Product not found in App Store');
              emit(PaymentFailed(
                'الباقة غير متوفرة في المتجر.\n'
                'معرف المنتج: $productId\n'
                'تأكد من:\n'
                '1. إنشاء المنتج في App Store Connect (In-App Purchases)\n'
                '2. ربط المنتج بإصدار التطبيق قبل الإرسال للمراجعة',
              ));
              return;
            }

            final product = products.first;
            final displayName = AppleIAPService.getDisplayName(
              product.id,
              product.title,
            );
            print('Product found: ${product.id}, Price: ${product.price}, Title: $displayName');

            print('Step 2: Initiating Apple IAP purchase...');
            await _appleIapService.purchaseProduct(product);

            _paymentTimeoutTimer?.cancel();
            emit(PaymentInitiated(
              purchase: response.purchase,
              message: 'جارٍ معالجة عملية الشراء عبر App Store...',
            ));
          },
        );
      } catch (e) {
        _paymentTimeoutTimer?.cancel();
        print('Apple IAP payment error: $e');
        emit(PaymentFailed('فشل عملية الشراء: $e'));
        _pendingPurchaseId = null;
      }
      return;
    }

    if (event.service == PaymentService.gplay) {
      try {
        print('Processing Google Play payment...');
        print('Subscription ID: ${event.subscriptionId}');

        if (event.subscriptionId == null) {
          print('Subscription ID is null');
          emit(PaymentFailed('يرجى اختيار باقة أولاً'));
          return;
        }

        print('Step 1: Creating payment record in backend...');
        final request = ProcessPaymentRequest(
          service: event.service,
          currency: event.currency,
          courseId: event.courseId,
          subscriptionId: event.subscriptionId,
          phone: event.phone,
          couponCode: event.couponCode,
        );

        final paymentResult = await subscriptionRepository.processPayment(request: request);
        
        await paymentResult.fold(
          (failure) {
            _paymentTimeoutTimer?.cancel();
            print('Failed to create payment record: ${failure.message}');
            emit(PaymentFailed('فشل إنشاء سجل الدفع: ${failure.message}'));
          },
          (response) async {
            if (response.purchase == null) {
              print('No purchase ID in response');
              emit(PaymentFailed('فشل: لم يتم الحصول على معرف الدفع من السيرفر'));
              return;
            }

            _pendingPurchaseId = response.purchase!.id;
            print('Payment record created with ID: $_pendingPurchaseId');

            if (!_billingInitialized) {
              await _initializeGooglePlayBilling(emit);
            }

            final productId = GooglePlayBillingService.getProductId(event.subscriptionId!);

            if (productId == null) {
              print('Invalid subscription ID: ${event.subscriptionId}');
              emit(PaymentFailed(
                'معرف الباقة غير صحيح.\n'
                'معرف الباقة: ${event.subscriptionId}\n'
                'المعرفات المتاحة: ${GooglePlayBillingService.productIdMap.keys.join(', ')}',
              ));
              return;
            }

            print('Product ID for subscription ${event.subscriptionId}: $productId');

            final products = await _billingService.getProducts([productId]);

            if (products.isEmpty) {
              print('Product not found in Google Play');
              emit(PaymentFailed(
                'الباقة غير متوفرة في المتجر.\n'
                'معرف المنتج: $productId\n'
                'تأكد من:\n'
                '1. إعداد المنتج في Google Play Console\n'
                '2. تفعيل المنتج\n'
                '3. رفع التطبيق على Internal Testing',
              ));
              return;
            }

            final product = products.first;
            final displayName = GooglePlayBillingService.getDisplayName(
              product.id, 
              product.title,
            );
            print('Product found: ${product.id}, Price: ${product.price}, Title: $displayName');

            print('Step 2: Initiating Google Play purchase...');
            await _billingService.purchaseProduct(product);

            _paymentTimeoutTimer?.cancel();
            emit(PaymentInitiated(
              purchase: response.purchase,
              message: 'جارٍ معالجة عملية الشراء عبر Google Play...',
            ));
          },
        );

      } catch (e) {
        _paymentTimeoutTimer?.cancel();
        print('Google Play payment error: $e');
        emit(PaymentFailed('فشل عملية الشراء: $e'));
        _pendingPurchaseId = null;
      }
      return;
    }

    final currentState = state;
    double finalPrice = 0.0;

    if (currentState is SubscriptionsLoaded &&
        currentState.finalPriceAfterCoupon != null) {
      finalPrice = double.tryParse(currentState.finalPriceAfterCoupon!) ?? 0.0;
    } else if (event.subscriptionId != null) {
      if (currentState is SubscriptionsLoaded) {
        final subscription = currentState.subscriptions.firstWhere(
              (s) => s.id == event.subscriptionId,
          orElse: () => currentState.subscriptions.first,
        );
        finalPrice = double.tryParse(subscription.localizedPrice) ?? 0.0;
      }
    }

    final request = ProcessPaymentRequest(
      service: event.service,
      currency: event.currency,
      courseId: event.courseId,
      subscriptionId: event.subscriptionId,
      phone: event.phone,
      couponCode: event.couponCode,
    );

    final result = await subscriptionRepository.processPayment(request: request);

    result.fold(
          (failure) {
            _paymentTimeoutTimer?.cancel();
            emit(PaymentFailed(failure.message));
          },
          (response) {
        _paymentTimeoutTimer?.cancel();
        if (response.isSuccess) {
          if (response.isFreeSubscription ||
              (finalPrice == 0 && response.subscriptionData != null)) {
            print('Free subscription activated: ${response.subscriptionData}');
            emit(PaymentCompleted(
              purchase: null,
              message: response.dataMessage ?? response.message ?? 'تم تفعيل الاشتراك بنجاح',
            ));
            print('Payment completed, reloading subscriptions in 0.5 seconds...');
            Future.delayed(const Duration(milliseconds: 500), () async {
              print('Reloading subscriptions after successful payment...');
              await _onLoadSubscriptions(const LoadSubscriptionsEvent(), emit);
            });
          } else if (response.hasCheckoutUrl) {
            emit(PaymentCheckoutReady(
              checkoutUrl: response.checkoutUrl!,
              message: response.dataMessage ?? 'تم بدء عملية الدفع',
            ));
          } else if (response.purchase != null) {
            if (response.purchase!.status == PaymentStatus.completed) {
              emit(PaymentCompleted(
                purchase: response.purchase!,
                message: response.dataMessage ?? 'تمت عملية الدفع بنجاح',
              ));
              print('Payment completed, reloading subscriptions in 0.5 seconds...');
              Future.delayed(const Duration(milliseconds: 500), () async {
                print('Reloading subscriptions after successful payment...');
                await _onLoadSubscriptions(const LoadSubscriptionsEvent(), emit);
              });
            } else {
              emit(PaymentInitiated(
                purchase: response.purchase!,
                message: response.dataMessage ?? 'تم بدء عملية الدفع',
              ));
            }
          } else {
            if (finalPrice == 0) {
              emit(PaymentCompleted(
                purchase: null,
                message: response.dataMessage ?? response.message ?? 'تم تفعيل الاشتراك بنجاح',
              ));
              print('Payment completed, reloading subscriptions in 0.5 seconds...');
              Future.delayed(const Duration(milliseconds: 500), () async {
                print('Reloading subscriptions after successful payment...');
                await _onLoadSubscriptions(const LoadSubscriptionsEvent(), emit);
              });
            } else {
              emit(PaymentInitiated(
                purchase: null,
                message: response.dataMessage ?? response.message,
              ));
            }
          }
        } else {
          emit(PaymentFailed(response.message));
        }
      },
    );
  }
  @override
  Future<void> close() {
    _paymentTimeoutTimer?.cancel();
    _billingService.dispose();
    _appleIapService.dispose();
    return super.close();
  }
}