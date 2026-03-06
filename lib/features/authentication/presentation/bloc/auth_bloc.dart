import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/error/failures.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final RegisterUseCase registerUseCase;
  final AuthRepository authRepository;

  String? _resetPasswordEmail;

  AuthBloc({
    required this.loginUseCase,
    required this.registerUseCase,
    required this.authRepository,
  }) : super(AuthInitial()) {
    on<LoginEvent>(_onLogin);
    on<RegisterEvent>(_onRegister);
    on<SocialLoginEvent>(_onSocialLogin);
    on<CompleteProfileEvent>(_onCompleteProfile);
    on<LogoutEvent>(_onLogout);
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<ForgotPasswordEvent>(_onForgotPassword);
    on<ResetPasswordEvent>(_onResetPassword);
    on<SendEmailOtpEvent>(_onSendEmailOtp);
    on<VerifyEmailOtpEvent>(_onVerifyEmailOtp);
    on<CheckEmailVerificationEvent>(_onCheckEmailVerification);
    on<ChangePasswordEvent>(_onChangePassword);
    on<GoogleSignInEvent>(_onGoogleSignIn);
    on<GoogleCallbackEvent>(_onGoogleCallback);
    on<MobileOAuthLoginEvent>(_onMobileOAuthLogin);
    on<NativeGoogleSignInEvent>(_onNativeGoogleSignIn);
    on<NativeAppleSignInEvent>(_onNativeAppleSignIn);
    on<UpdateProfileEvent>(_onUpdateProfile);
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '695539439418-g40jdtebreloi78lkk4f4t24v1fktu8q.apps.googleusercontent.com',
  );

  Future<void> _onLogin(LoginEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());

    final result = await loginUseCase(
      email: event.email,
      password: event.password,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onRegister(RegisterEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());

    final result = await registerUseCase(
      name: event.name,
      email: event.email,
      password: event.password,
      passwordConfirmation: event.passwordConfirmation,
      role: event.role,
      phone: event.phone,
      specialtyId: event.specialtyId,
      gender: event.gender,
      religion: event.religion,
      birthday: event.birthday,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onSocialLogin(
    SocialLoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    if (event.provider == 'apple') {
      emit(const AuthError('تسجيل الدخول عبر Apple غير متاح حالياً'));
      return;
    }

    emit(const AuthError('مزود تسجيل الدخول غير مدعوم'));
  }

  Future<void> _onCompleteProfile(
    CompleteProfileEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.mobileOAuthLogin(
      provider: event.providerId,
      accessToken: event.accessToken,
      name: event.name,
      phone: event.phone,
      specialtyId: event.specialtyId,
      gender: event.gender,
      religion: event.religion,
      birthday: event.birthday,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());

    final result = await authRepository.logout();

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(AuthUnauthenticated()),
    );
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    final isLoggedInResult = await authRepository.isLoggedIn();

    await isLoggedInResult.fold(
      (failure) async => emit(AuthUnauthenticated()),
      (isLoggedIn) async {
        if (isLoggedIn) {
          final userResult = await authRepository.getCurrentUser();
          userResult.fold(
            (failure) => emit(AuthUnauthenticated()),
            (user) async {
              if (user != null) {
                if (user.isProfileComplete) {
                  emit(AuthAuthenticated(user));
                } else {
                  final localDataSource = sl<AuthLocalDataSource>();
                  final token = await localDataSource.getAccessToken();
                  
                  if (token != null && token.isNotEmpty) {
                    emit(SocialLoginNeedsCompletion(
                      email: user.email,
                      name: user.name,
                      providerId: 'existing_user',
                      accessToken: token,
                      requiresRegistration: false,
                    ));
                  } else {
                    emit(AuthUnauthenticated());
                  }
                }
              } else {
                emit(AuthUnauthenticated());
              }
            },
          );
        } else {
          emit(AuthUnauthenticated());
        }
      },
    );
  }

  Future<void> _onForgotPassword(
    ForgotPasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.forgotPassword(email: event.email);

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) {
        _resetPasswordEmail = event.email;
        emit(ForgotPasswordSuccess(email: event.email));
      },
    );
  }

  Future<void> _onResetPassword(
    ResetPasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.resetPassword(
      email: event.email,
      otp: event.otp,
      password: event.password,
      passwordConfirmation: event.passwordConfirmation,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(PasswordResetSuccess()),
    );
  }

  Future<void> _onSendEmailOtp(
    SendEmailOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.sendEmailOtp();

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(EmailOtpSent()),
    );
  }

  Future<void> _onVerifyEmailOtp(
    VerifyEmailOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.verifyEmailOtp(otp: event.otp);

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(EmailVerified()),
    );
  }

  Future<void> _onCheckEmailVerification(
    CheckEmailVerificationEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.checkEmailVerification();

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (isVerified) => emit(EmailVerificationStatus(isVerified: isVerified)),
    );
  }

  Future<void> _onChangePassword(
    ChangePasswordEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.changePassword(
      currentPassword: event.currentPassword,
      newPassword: event.newPassword,
      passwordConfirmation: event.passwordConfirmation,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (_) => emit(PasswordChanged()),
    );
  }


  Future<void> _onGoogleSignIn(
    GoogleSignInEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.getGoogleAuthUrl();

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (url) => emit(GoogleAuthUrlLoaded(url: url)),
    );
  }

  Future<void> _onGoogleCallback(
    GoogleCallbackEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.handleGoogleCallback(code: event.code);

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onMobileOAuthLogin(
    MobileOAuthLoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.mobileOAuthLogin(
      provider: event.provider,
      accessToken: event.accessToken,
    );

    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onNativeGoogleSignIn(
    NativeGoogleSignInEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      await _googleSignIn.signOut();

      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      if (account == null) {
        emit(const AuthError('تم إلغاء تسجيل الدخول'));
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;
      final String? accessToken = auth.accessToken;

      final String? tokenToSend = idToken ?? accessToken;

      if (tokenToSend == null || tokenToSend.isEmpty) {
        emit(const AuthError('فشل في الحصول على رمز الوصول'));
        return;
      }

      final result = await authRepository.mobileOAuthLogin(
        provider: 'google',
        accessToken: tokenToSend,
      );

      result.fold(
        (failure) {
          if (failure is NotFoundFailure) {
            emit(
              SocialLoginNeedsCompletion(
                email: account.email ?? '',
                name: account.displayName,
                providerId: 'google',
                accessToken: tokenToSend,
                requiresRegistration: true,
              ),
            );
          } else {
            emit(AuthError(failure.message));
          }
        },
        (user) {
          if (!user.isProfileComplete) {
            emit(
              SocialLoginNeedsCompletion(
                email: user.email,
                name: user.name,
                providerId: 'google',
                accessToken: tokenToSend,
                requiresRegistration: false,
              ),
            );
          } else {
            emit(AuthAuthenticated(user));
          }
        },
      );
    } catch (e) {
      final errorMessage = _parseGoogleSignInError(e.toString());
      emit(AuthError(errorMessage));
    }
  }

  String _parseGoogleSignInError(String error) {
    if (error.contains('ApiException: 10')) {
      return 'خطأ في إعدادات التطبيق. يرجى التواصل مع الدعم الفني.';
    } else if (error.contains('ApiException: 7')) {
      return 'خطأ في الاتصال بالإنترنت. يرجى المحاولة مرة أخرى.';
    } else if (error.contains('ApiException: 12501')) {
      return 'تم إلغاء تسجيل الدخول';
    } else if (error.contains('ApiException: 12502')) {
      return 'عملية تسجيل الدخول قيد التنفيذ';
    } else if (error.contains('ApiException: 12500')) {
      return 'فشل تسجيل الدخول. يرجى المحاولة مرة أخرى.';
    } else if (error.contains('sign_in_canceled')) {
      return 'تم إلغاء تسجيل الدخول';
    } else if (error.contains('network_error')) {
      return 'خطأ في الاتصال بالإنترنت';
    }
    return 'خطأ في تسجيل الدخول. يرجى المحاولة مرة أخرى.';
  }

  Future<void> _onNativeAppleSignIn(
    NativeAppleSignInEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        emit(const AuthError('تسجيل الدخول عبر Apple غير متاح على هذا الجهاز'));
        return;
      }

      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final identityToken = credential.identityToken;
      
      if (identityToken == null || identityToken.isEmpty) {
        emit(const AuthError('فشل في الحصول على رمز الوصول'));
        return;
      }

      final String? email = credential.email;
      final String? givenName = credential.givenName;
      final String? familyName = credential.familyName;
      final String? fullName = (givenName != null || familyName != null)
          ? '${givenName ?? ''} ${familyName ?? ''}'.trim()
          : null;

      final result = await authRepository.mobileOAuthLogin(
        provider: 'apple',
        accessToken: identityToken,
      );

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) {
          if (user.isProfileComplete) {
            emit(AuthAuthenticated(user));
          } else {
            emit(SocialLoginNeedsCompletion(
              email: email ?? user.email,
              name: fullName ?? user.name,
              providerId: 'apple',
              accessToken: identityToken,
              requiresRegistration: false,
            ));
          }
        },
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('SignInWithApple error: code=${e.code}, message=${e.message}');
      final errorMessage = _parseAppleSignInError(e);
      emit(AuthError(errorMessage));
    } catch (e, st) {
      debugPrint('Apple sign-in exception: $e');
      debugPrint('Stack trace: $st');
      emit(AuthError('خطأ في تسجيل الدخول. يرجى المحاولة مرة أخرى.'));
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _parseAppleSignInError(SignInWithAppleAuthorizationException e) {
    debugPrint('Apple auth error code: ${e.code}, message: ${e.message}');
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return 'تم إلغاء تسجيل الدخول';
      case AuthorizationErrorCode.failed:
        return 'فشل تسجيل الدخول. يرجى المحاولة مرة أخرى.';
      case AuthorizationErrorCode.invalidResponse:
        return 'استجابة غير صالحة من Apple';
      case AuthorizationErrorCode.notHandled:
        return 'لم يتم التعامل مع الطلب';
      case AuthorizationErrorCode.notInteractive:
        return 'تسجيل الدخول غير تفاعلي';
      case AuthorizationErrorCode.unknown:
      default:
        return 'خطأ غير معروف. يرجى المحاولة مرة أخرى.';
    }
  }

  Future<void> _onUpdateProfile(
    UpdateProfileEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await authRepository.updateProfile(
      name: event.name,
      email: event.email,
      phone: event.phone,
      gender: event.gender,
      religion: event.religion,
      about: event.about,
      birthday: event.birthday,
      specialtyId: event.specialtyId,
      role: event.role,
    );

    result.fold(
      (failure) {
        if (failure is AuthenticationFailure) {
          final message = failure.message;

          if (message.contains('جهاز آخر') ||
              message.contains('another device')) {
            emit(AuthLoggedInFromAnotherDevice(message));
          } else if (message.contains('انتهت صلاحية') ||
              message.contains('expired') ||
              message.contains('unauthenticated')) {
            emit(AuthSessionExpired(message));
          } else {
            emit(AuthError(message));
          }
        } else {
          emit(AuthError(failure.message));
        }
      },
      (user) {
        emit(ProfileUpdated(user));
        emit(AuthAuthenticated(user));
      },
    );
  }
}


