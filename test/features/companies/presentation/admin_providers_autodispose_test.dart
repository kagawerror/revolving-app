import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/domain/fund_repository.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';

/// A repository whose [watchByCompany] hands back a single-subscription stream
/// and records when that subscription is cancelled. A cancellation is our proxy
/// for "the Firestore listener was torn down" — the real bug is that, without
/// `autoDispose`, this never happened after sign-out and the orphaned listener
/// kept hitting Firestore with a now-null auth token (PERMISSION_DENIED).
class _LeakSpyFundRepo implements FundRepository {
  bool cancelled = false;
  late final StreamController<List<Fund>> controller =
      StreamController<List<Fund>>(onCancel: () => cancelled = true);

  @override
  Stream<List<Fund>> watchByCompany(String companyId) => controller.stream;

  @override
  Stream<List<Fund>> watchAll() => controller.stream;

  @override
  Stream<Fund?> watchById(String fundId) => const Stream.empty();
  @override
  Future<Result<void>> create(Fund fund) async => const Ok(null);
  @override
  Future<Result<void>> updateDetails({
    required String fundId,
    required String name,
    required int lowBalanceThresholdPct,
  }) async => const Ok(null);
  @override
  Future<Result<void>> adjustBudget({
    required String fundId,
    required Money newBudget,
    required String actorUid,
    required String note,
  }) async => const Ok(null);
  @override
  Future<Result<void>> adjustBalance({
    required String fundId,
    required int signedDeltaCentavos,
    required String reason,
    required String actorUid,
    required UserRole actorRole,
  }) async => const Ok(null);
}

void main() {
  test(
      'companyFundsProvider tears down its Firestore stream once unwatched '
      '(no orphaned listener survives sign-out)', () async {
    final repo = _LeakSpyFundRepo();
    final container = ProviderContainer(
      overrides: [fundRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    // A screen mounts and watches the company's funds: the listener attaches.
    final sub = container.listen(companyFundsProvider('OBKe4e2Q4YYvwCkYyRVX'),
        (_, _) {});
    // Firestore's snapshots() stream emits an initial snapshot immediately;
    // mimic that. It also matters mechanically: a StreamProvider only cancels
    // its source once BOTH internal broadcast listeners detach, and the one
    // backing `.future` won't detach until the stream has yielded a value. A
    // never-emitting fake would leave the source subscribed and mask the fix.
    repo.controller.add(const <Fund>[]);
    await pumpEventQueue();
    expect(repo.controller.hasListener, isTrue,
        reason: 'stream should be subscribed while the provider is watched');

    // Sign-out: the redirect to /login unmounts the screen, so nothing watches
    // the provider anymore. With autoDispose it must dispose and cancel; the
    // scheduled disposal plus the async StreamSubscription.cancel() need the
    // event queue drained, not just a single microtask.
    sub.close();
    await pumpEventQueue();

    expect(repo.cancelled, isTrue,
        reason: 'an unwatched companyFundsProvider must cancel its stream — '
            'otherwise the listener outlives the session and floods '
            'PERMISSION_DENIED after sign-out');
  });
}
