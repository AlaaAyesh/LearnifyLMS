enum PaymentService {
  gplay,
  iap,
  stripe,
  wallet,
  kashier,
}

extension PaymentServiceExtension on PaymentService {
  String get value {
    switch (this) {
      case PaymentService.gplay:
        return 'gplay';
      case PaymentService.iap:
        return 'iap';
      case PaymentService.stripe:
        return 'stripe';
      case PaymentService.wallet:
        return 'wallet';
      case PaymentService.kashier:
        return 'kashier';
    }
  }

  static PaymentService fromString(String value) {
    switch (value.toLowerCase()) {
      case 'gplay':
        return PaymentService.gplay;
      case 'iap':
        return PaymentService.iap;
      case 'stripe':
        return PaymentService.stripe;
      case 'wallet':
        return PaymentService.wallet;
      case 'kashier':
        return PaymentService.kashier;
      default:
        return PaymentService.iap;
    }
  }
}

enum PaymentStatus {
  pending,
  completed,
  failed,
}

extension PaymentStatusExtension on PaymentStatus {
  String get value {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.completed:
        return 'completed';
      case PaymentStatus.failed:
        return 'failed';
    }
  }

  static PaymentStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'completed':
      case 'success':
      return PaymentStatus.completed;
      case 'failed':
        return PaymentStatus.failed;
      default:
        return PaymentStatus.pending;
    }
  }
}

class ProcessPaymentRequest {
  final PaymentService service;
  final String currency;
  final int? courseId;
  final int? subscriptionId;
  final String phone;
  final String? couponCode;

  ProcessPaymentRequest({
    required this.service,
    required this.currency,
    this.courseId,
    this.subscriptionId,
    required this.phone,
    this.couponCode,
  }) : assert(courseId != null || subscriptionId != null,
            'Either courseId or subscriptionId must be provided');

  Map<String, dynamic> toFormData() {
    final data = <String, dynamic>{
      'service': service.value,
      'currency': currency,
      'phone': phone,
    };

    if (courseId != null) {
      data['course_id'] = courseId;
    }

    if (subscriptionId != null) {
      data['subscription_id'] = subscriptionId;
    }

    if (couponCode != null && couponCode!.isNotEmpty) {
      data['coupon_code'] = couponCode;
    }

    return data;
  }
}

class PurchaseModel {
  final int id;
  final int userId;
  final String purchasableType;
  final int purchasableId;
  final PaymentStatus status;
  final double amount;
  final String currency;
  final PaymentService paymentService;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseModel({
    required this.id,
    required this.userId,
    required this.purchasableType,
    required this.purchasableId,
    required this.status,
    required this.amount,
    required this.currency,
    required this.paymentService,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseModel.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) {
      throw ArgumentError('Cannot create PurchaseModel from empty JSON');
    }
    
    return PurchaseModel(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      purchasableType: json['purchasable_type'] as String? ?? '',
      purchasableId: json['purchasable_id'] as int? ?? 0,
      status: PaymentStatusExtension.fromString(json['status'] as String? ?? 'pending'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      paymentService: PaymentServiceExtension.fromString(json['payment_service'] as String? ?? 'iap'),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'purchasable_type': purchasableType,
      'purchasable_id': purchasableId,
      'status': status.value,
      'amount': amount,
      'currency': currency,
      'payment_service': paymentService.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isCoursePurchase => purchasableType.contains('Course');

  bool get isSubscriptionPurchase => purchasableType.contains('Subscription');
}

class PaymentResponseModel {
  final String status;
  final String message;
  final String? dataMessage;
  final PurchaseModel? purchase;
  final String? checkoutUrl;
  final Map<String, dynamic>? subscriptionData;

  PaymentResponseModel({
    required this.status,
    required this.message,
    this.dataMessage,
    this.purchase,
    this.checkoutUrl,
    this.subscriptionData,
  });

  factory PaymentResponseModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;

    PurchaseModel? purchaseModel;
    if (data?['purchase'] != null && data!['purchase'] is Map) {
      try {
        purchaseModel = PurchaseModel.fromJson(data['purchase'] as Map<String, dynamic>);
      } catch (e) {
        print('Error parsing purchase: $e');
      }
    }

    Map<String, dynamic>? subscriptionData;
    if (data?['subscription'] != null && data!['subscription'] is Map) {
      subscriptionData = data['subscription'] as Map<String, dynamic>;
    } else if (data != null && data.containsKey('id') && !data.containsKey('checkout_url') && purchaseModel == null) {
      subscriptionData = data;
    }
    
    return PaymentResponseModel(
      status: json['status'] as String? ?? 'success',
      message: json['message'] as String? ?? '',
      dataMessage: data?['message'] as String?,
      purchase: purchaseModel,
      checkoutUrl: data?['checkout_url']?.toString(),
      subscriptionData: subscriptionData,
    );
  }

  bool get isSuccess => status == 'success';

  bool get hasCheckoutUrl => checkoutUrl != null && checkoutUrl!.isNotEmpty;

  bool get isFreeSubscription => subscriptionData != null && !hasCheckoutUrl && purchase == null;
}

class TransactionModel {
  final int id;
  final int userId;
  final String purchasableType;
  final String? purchasableName;
  final int purchasableId;
  final String amount;
  final String currency;
  final String? transactionId;
  final PaymentService paymentService;
  final PaymentStatus status;
  final String? receiptPath;
  final String? receiptUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.purchasableType,
    this.purchasableName,
    required this.purchasableId,
    required this.amount,
    required this.currency,
    this.transactionId,
    required this.paymentService,
    required this.status,
    this.receiptPath,
    this.receiptUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      purchasableType: json['purchasable_type'] as String? ?? '',
      purchasableName: json['purchasable_name'] as String?,
      purchasableId: json['purchasable_id'] as int? ?? 0,
      amount: json['amount']?.toString() ?? '0',
      currency: json['currency'] as String? ?? 'EGP',
      transactionId: json['transaction_id'] as String?,
      paymentService: PaymentServiceExtension.fromString(json['payment_service'] as String? ?? 'kashier'),
      status: PaymentStatusExtension.fromString(json['status'] as String? ?? 'pending'),
      receiptPath: json['receipt_path'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  bool get isSubscriptionTransaction => purchasableType.contains('Subscription');

  bool get isSuccessfulSubscription => isSubscriptionTransaction && status == PaymentStatus.completed;
}

class TransactionsResponseModel {
  final List<TransactionModel> transactions;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;
  final String? nextPageUrl;
  final String? prevPageUrl;

  TransactionsResponseModel({
    required this.transactions,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
    this.nextPageUrl,
    this.prevPageUrl,
  });

  factory TransactionsResponseModel.fromJson(Map<String, dynamic> json) {
    dynamic rawData = json['data'];
    Map<String, dynamic> meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? {};

    if (rawData is Map) {
      meta = (rawData['meta'] as Map?)?.cast<String, dynamic>() ?? meta;
      rawData = rawData['data'];
    }

    if (rawData == null && json['transactions'] is List) {
      rawData = json['transactions'];
    }

    final List<dynamic> data = rawData is List ? rawData : <dynamic>[];

    return TransactionsResponseModel(
      transactions: data
          .map((item) => TransactionModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: meta['total'] as int? ?? 0,
      perPage: meta['per_page'] as int? ?? 10,
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      nextPageUrl: meta['next_page_url'] as String?,
      prevPageUrl: meta['prev_page_url'] as String?,
    );
  }

  TransactionModel? get activeSubscriptionTransaction {
    final subscriptionTransactions = transactions
        .where((t) => t.isSuccessfulSubscription)
        .toList();
    
    if (subscriptionTransactions.isEmpty) return null;

    subscriptionTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return subscriptionTransactions.first;
  }
}



