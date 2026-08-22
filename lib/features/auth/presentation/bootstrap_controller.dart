import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class BootstrapState extends Equatable {
  final bool loading;
  final String? error;
  final bool succeeded;

  const BootstrapState._({
    this.loading = false,
    this.error,
    this.succeeded = false,
  });
  const BootstrapState.idle() : this._();
  const BootstrapState.loading() : this._(loading: true);
  const BootstrapState.error(String message) : this._(error: message);
  const BootstrapState.success() : this._(succeeded: true);

  @override
  List<Object?> get props => [loading, error, succeeded];
}

class BootstrapController extends Notifier<BootstrapState> {
  @override
  BootstrapState build() => const BootstrapState.idle();

  Future<void> submit(String email, String password, String displayName) async {
    state = const BootstrapState.loading();
    final result = await ref.read(authRepositoryProvider).bootstrapFirstAdmin(
          email: email,
          password: password,
          displayName: displayName,
        );
    state = result.when(
      ok: (_) => const BootstrapState.success(),
      err: (f) => BootstrapState.error(f.message),
    );
  }
}

final bootstrapControllerProvider =
    NotifierProvider<BootstrapController, BootstrapState>(
        BootstrapController.new);
