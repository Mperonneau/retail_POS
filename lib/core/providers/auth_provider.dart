import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthStatus { unauthenticated, authenticated }

enum ActiveModule { restaurant, hotel, retail }

class AuthState {
  final AuthStatus status;
  final String? userName;
  final String? businessName;
  final ActiveModule module;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.userName,
    this.businessName,
    this.module = ActiveModule.retail,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userName,
    String? businessName,
    ActiveModule? module,
  }) =>
      AuthState(
        status: status ?? this.status,
        userName: userName ?? this.userName,
        businessName: businessName ?? this.businessName,
        module: module ?? this.module,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  void login({
    required String userName,
    required String businessName,
    required ActiveModule module,
  }) {
    state = AuthState(
      status: AuthStatus.authenticated,
      userName: userName,
      businessName: businessName,
      module: module,
    );
  }

  void logout() => state = const AuthState();

  void setModule(ActiveModule module) => state = state.copyWith(module: module);
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
