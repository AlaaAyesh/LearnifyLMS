class ApiConstants {
  static const String baseUrl = 'https://api.learnifynow.com/api/';

  static const String login = 'auth/login';
  static const String register = 'auth/register';
  static const String logout = 'auth/logout';
  static const String forgotPassword = 'auth/forgot-password';
  static const String resetPassword = 'auth/reset-password';
  static const String changePassword = 'auth/change-password';
  static const String saveFirebaseToken = 'auth/save-firebase-token';

  static const String googleAuth = 'auth/google';
  static const String googleCallback = 'auth/google/callback';
  static const String mobileOAuthLogin = 'auth/mobile/login';

  static const String sendEmailOtp = 'auth/email/send-otp';
  static const String verifyEmailOtp = 'auth/email/verify-otp';
  static const String checkEmailVerification = 'auth/check-email-verification';

  static const String profile = 'user/profile';
  static const String updateProfile = 'auth/update-profile';

  static const String courses = 'courses';
  static const String courseDetails = 'courses/';
  static const String enrollCourse = 'courses/{id}/enroll';
  static const String myCourses = 'myCourses';

  static const String lessons = 'lessons';
  static const String chapters = 'chapters';

  static const String generateCertificate = 'certificates/request';
  static const String ownedCertificates = 'owned-certificates';

  static const String homeApi = 'homeAPI';

  static const String subscriptions = 'subscriptions';
  static const String validateCoupon = 'coupons/validate';

  static const String processPayment = 'payments/process';
  static const String myTransactions = 'myTransactions';
  static const String validateIapReceipt = 'iap/validate-receipt';

  static const String reelsFeed = 'reels/feed';
  static const String recordReelView = 'reels/{id}/views';
  static const String likeReel = 'reels/{id}/like';
  static const String reelCategoriesWithReels = 'reel-categories/with-reels';
  static const String userReels = 'users/{userId}/reels';
  static const String userLikedReels = 'users/{userId}/reels/liked';

  static const String siteBanners = 'site-banners';
  static const String recordBannerClick = 'site-banners/{id}/click';
}


