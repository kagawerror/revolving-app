import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class LoginState extends Equatable {
  final bool loading;
  final String? error;
  final bool succeeded;

  const LoginState._({this.loading = false, this.error, this.succeeded = false});
  const LoginState.idle() : this._();
  const LoginState.loading() : this._(loading: true);
  const LoginState.error(String message) : this._(error: message);
  const LoginState.success() : this._(succeeded: true);

  @override
  List<Object?> get props => [loading, error, succeeded];
}

class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState.idle();

  Future<void> submit(String email, String password) async {
    state = const LoginState.loading();
    final result = await ref.read(authRepositoryProvider).signIn(
          email: email,
          password: password,
        );
    state = result.when(
      ok: (_) => const LoginState.success(),
      err: (f) => LoginState.error(f.message),
    );
  }
}

final loginControllerProvider =
    NotifierProvider<LoginController, LoginState>(LoginController.new);
