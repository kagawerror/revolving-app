import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_secrets.dart';
import '../data/update_repository.dart';
import '../domain/update_decision.dart';

/// Shared HTTP client for the update check. Closed when the provider scope is
/// disposed. Overridable in tests.
final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Null when no manifest URL is configured (update checks disabled).
final updateRepositoryProvider = Provider<UpdateRepository?>((ref) {
  if (!AppSecrets.hasUpdates) return null;
  return HttpUpdateRepository(
    client: ref.watch(updateHttpClientProvider),
    manifestUrl: AppSecrets.updateManifestUrl,
  );
});

/// The running build's versionCode (pubspec `+N`). Overridable in tests.
final currentVersionCodeProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
});

/// Whether self-hosted updates apply to this platform. Android only; iOS/web
/// are no-ops (Apple forbids sideload-update). Overridable in tests.
final isUpdateSupportedPlatformProvider = Provider<bool>((ref) {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false; // web: dart:io Platform throws.
  }
});

/// One-shot launch check. Fails safe to [UpdateStatus.upToDate] on unsupported
/// platforms, missing config, or any repository error.
final updateCheckProvider = FutureProvider<UpdateDecision>((ref) async {
  if (!ref.watch(isUpdateSupportedPlatformProvider)) {
    return const UpdateDecision(UpdateStatus.upToDate);
  }
  final repo = ref.watch(updateRepositoryProvider);
  if (repo == null) return const UpdateDecision(UpdateStatus.upToDate);

  final current = await ref.watch(currentVersionCodeProvider.future);
  final result = await repo.fetchLatest();
  return result.when(
    ok: (latest) =>
        decideUpdate(currentVersionCode: current, latest: latest),
    err: (_) => const UpdateDecision(UpdateStatus.upToDate),
  );
});
