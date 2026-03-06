import 'package:equatable/equatable.dart';
import '../../domain/entities/user.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

class ForgotPasswordSuccess extends AuthState {
  final String email;

  const ForgotPasswordSuccess({required this.email});

  @override
  List<Object?> get props => [email];
}

class PasswordResetSuccess extends AuthState {}

class EmailOtpSent extends AuthState {}

class EmailVerified extends AuthState {}

class EmailVerificationStatus extends AuthState {
  final bool isVerified;

  const EmailVerificationStatus({required this.isVerified});

  @override
  List<Object?> get props => [isVerified];
}

class PasswordChanged extends AuthState {}

class SocialLoginNeedsCompletion extends AuthState {
  final String email;
  final String? name;
  final String providerId;
  final String accessToken;
  final bool requiresRegistration;

  const SocialLoginNeedsCompletion({
    required this.email,
    this.name,
    required this.providerId,
    required this.accessToken,
    required this.requiresRegistration,
  });

  @override
  List<Object?> get props => [email, name, providerId, accessToken, requiresRegistration];
}

class GoogleAuthUrlLoaded extends AuthState {
  final String url;

  const GoogleAuthUrlLoaded({required this.url});

  @override
  List<Object?> get props => [url];
}

class ProfileUpdated extends AuthState {
  final User user;

  const ProfileUpdated(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthSessionExpired extends AuthState {
  final String message;

  const AuthSessionExpired(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthLoggedInFromAnotherDevice extends AuthState {
  final String message;

  const AuthLoggedInFromAnotherDevice(this.message);

  @override
  List<Object?> get props => [message];
}


