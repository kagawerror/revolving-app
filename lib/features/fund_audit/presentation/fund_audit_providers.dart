import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/request_providers.dart';
import '../data/firestore_fund_audit_repository.dart';
import '../data/mlkit_ocr_text_service.dart';
import '../domain/denomination.dart';
import '../domain/fund_audit.dart';
import '../domain/fund_audit_math.dart';
import '../domain/fund_audit_pdf.dart';
import '../domain/fund_audit_repository.dart';
import '../domain/ocr_count_parser.dart';
import '../domain/ocr_row_reconstructor.dart';
import '../domain/ocr_text_service.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/share/file_share_service.dart';

final fundAuditRepositoryProvider = Provider<FundAuditRepository>(
    (ref) => FirestoreFundAuditRepository(ref.watch(firestoreProvider)));

final ocrTextServiceProvider = Provider<OcrTextService>((ref) {
  final service = MlkitOcrTextService();
  ref.onDispose(service.dispose);
  return service;
});

/// Editable state of the create-audit form. The [outcome] is recomputed from
/// [counts] on every change so the UI variance is always live.
class FundAuditFormState extends Equatable {
  final String fundId;
  final String fundName;
  final Money effectiveBudget;
  final Map<Denomination, int> counts;
  final Set<Denomination> ocrPrefilled;
  final String? proofImagePath;
  final String proofImageUrl;
  final String note;
  final bool ocrRunning;

  /// True after an OCR run that produced NO usable denomination counts, so the
  /// UI can prompt manual entry. The photo is still kept as proof; the grid stays
  /// fully editable.
  final bool ocrAttemptedNoMatch;
  final bool saving;
  final FundAuditOutcome outcome;

  const FundAuditFormState({
    required this.fundId,
    required this.fundName,
    required this.effectiveBudget,
    required this.counts,
    required this.ocrPrefilled,
    required this.proofImagePath,
    required this.proofImageUrl,
    required this.note,
    required this.ocrRunning,
    required this.ocrAttemptedNoMatch,
    required this.saving,
    required this.outcome,
  });

  FundAuditFormState copyWith({
    String? fundId,
    String? fundName,
    Money? effectiveBudget,
    Map<Denomination, int>? counts,
    Set<Denomination>? ocrPrefilled,
    String? proofImagePath,
    String? proofImageUrl,
    String? note,
    bool? ocrRunning,
    bool? ocrAttemptedNoMatch,
    bool? saving,
    FundAuditOutcome? outcome,
  }) {
    return FundAuditFormState(
      fundId: fundId ?? this.fundId,
      fundName: fundName ?? this.fundName,
      effectiveBudget: effectiveBudget ?? this.effectiveBudget,
      counts: counts ?? this.counts,
      ocrPrefilled: ocrPrefilled ?? this.ocrPrefilled,
      proofImagePath: proofImagePath ?? this.proofImagePath,
      proofImageUrl: proofImageUrl ?? this.proofImageUrl,
      note: note ?? this.note,
      ocrRunning: ocrRunning ?? this.ocrRunning,
      ocrAttemptedNoMatch: ocrAttemptedNoMatch ?? this.ocrAttemptedNoMatch,
      saving: saving ?? this.saving,
      outcome: outcome ?? this.outcome,
    );
  }

  @override
  List<Object?> get props => [
        fundId,
        fundName,
        effectiveBudget,
        counts,
        ocrPrefilled,
        proofImagePath,
        proofImageUrl,
        note,
        ocrRunning,
        ocrAttemptedNoMatch,
        saving,
        outcome,
      ];
}

typedef FundAuditArgs = ({String companyId, String fundId});

class FundAuditController
    extends AutoDisposeFamilyNotifier<FundAuditFormState, FundAuditArgs> {
  List<FundRequest> _outstanding = const [];

  @override
  FundAuditFormState build(FundAuditArgs arg) {
    // Read the fund snapshot ONCE (read, not watch) so a later stream emission
    // never rebuilds this notifier and discards the custodian's typed counts.
    // If it isn't cached yet, [_loadFundMeta] fills it in asynchronously.
    final funds =
        ref.read(companyFundsProvider(arg.companyId)).valueOrNull ?? const [];
    final fund = funds.where((f) => f.id == arg.fundId).firstOrNull;
    final fundName = fund?.name ?? '';
    // Effective budget = originalBudget + adjustmentsCentavos (release-first
    // trunk). This is the audit's "Total Fund". Passed explicitly into
    // [computeFundAudit].
    final effectiveBudget = fund?.effectiveBudget ?? Money.zero;

    // Outstanding released cash + (if missing) fund metadata, fetched once.
    _loadOutstanding(arg);
    if (fund == null) _loadFundMeta(arg);

    const counts = <Denomination, int>{};
    final outcome = computeFundAudit(
      effectiveBudget: effectiveBudget,
      counts: counts,
      outstandingForFund: _outstanding,
    );

    return FundAuditFormState(
      fundId: arg.fundId,
      fundName: fundName,
      effectiveBudget: effectiveBudget,
      counts: counts,
      ocrPrefilled: const {},
      proofImagePath: null,
      proofImageUrl: '',
      note: '',
      ocrRunning: false,
      ocrAttemptedNoMatch: false,
      saving: false,
      outcome: outcome,
    );
  }

  Future<void> _loadOutstanding(FundAuditArgs arg) async {
    final result = await ref
        .read(fundAuditRepositoryProvider)
        .fetchOutstandingForFund(arg.companyId, arg.fundId);
    final list = result.valueOrNull;
    if (list == null) return;
    _outstanding = list;
    // Recompute with the now-known outstanding cash.
    state = state.copyWith(outcome: _recompute(state.counts));
  }

  /// Resolves the fund name + effective budget when not already cached, without
  /// re-running [build]. Preserves any counts already entered.
  Future<void> _loadFundMeta(FundAuditArgs arg) async {
    final funds = await ref.read(companyFundsProvider(arg.companyId).future);
    final fund = funds.where((f) => f.id == arg.fundId).firstOrNull;
    if (fund == null) return;
    state = state.copyWith(
      fundName: fund.name,
      effectiveBudget: fund.effectiveBudget,
    );
    state = state.copyWith(outcome: _recompute(state.counts));
  }

  FundAuditOutcome _recompute(Map<Denomination, int> counts) => computeFundAudit(
        effectiveBudget: state.effectiveBudget,
        counts: counts,
        outstandingForFund: _outstanding,
      );

  /// Captures a photo, runs OCR, and merges parsed counts into the grid. Counts
  /// the OCR provided are marked [FundAuditFormState.ocrPrefilled] so the UI can
  /// flag them as needing review. On OCR failure the grid is left editable.
  Future<void> pickPhotoAndOcr({ImageSource source = ImageSource.camera}) async {
    final picker = ref.read(imagePickerProvider);
    final XFile? file = await picker.pickImage(source: source, maxWidth: 1600);
    if (file == null) return;

    state = state.copyWith(
      proofImagePath: file.path,
      ocrRunning: true,
      ocrAttemptedNoMatch: false,
    );

    final result = await ref.read(ocrTextServiceProvider).recognizeLines(file.path);
    final lines = result.valueOrNull;
    if (lines == null) {
      // OCR failed — keep the photo, leave the grid for manual entry, and flag
      // the no-match state so the UI prompts manual entry.
      state = state.copyWith(ocrRunning: false, ocrAttemptedNoMatch: true);
      return;
    }

    // ML Kit segments bordered sheets column-wise; reconstruct visual rows first
    // so the line-based parser sees `<face> ... <count>` together.
    final rows = reconstructRows(lines);
    final parsed = parseDenominationCounts(rows);
    final merged = {...state.counts, ...parsed};
    state = state.copyWith(
      counts: merged,
      ocrPrefilled: {...state.ocrPrefilled, ...parsed.keys},
      ocrRunning: false,
      ocrAttemptedNoMatch: parsed.isEmpty,
      outcome: _recompute(merged),
    );
  }

  void setCount(Denomination d, int n) {
    final counts = {...state.counts, d: n < 0 ? 0 : n};
    state = state.copyWith(counts: counts, outcome: _recompute(counts));
  }

  void increment(Denomination d) => setCount(d, (state.counts[d] ?? 0) + 1);

  void decrement(Denomination d) => setCount(d, (state.counts[d] ?? 0) - 1);

  void setNote(String s) => state = state.copyWith(note: s);

  /// Builds the [FundAudit] (snapshotting fund/company/custodian names) and
  /// writes it via the repository. Uploads the proof photo first if present.
  Future<Result<String>> save() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) {
      return const Err(AuthFailure('You are signed out.'));
    }
    final company = ref
        .read(companiesProvider)
        .valueOrNull
        ?.where((c) => c.id == arg.companyId)
        .firstOrNull;

    state = state.copyWith(saving: true);
    try {
      var proofUrl = state.proofImageUrl;
      final path = state.proofImagePath;
      if (proofUrl.isEmpty && path != null) {
        final bytes = await _readBytes(path);
        if (bytes != null) {
          final upload =
              await ref.read(cloudinaryUploaderProvider).uploadJpeg(bytes);
          proofUrl = upload.valueOrNull ?? '';
        }
      }

      final outcome = state.outcome;
      final audit = FundAudit(
        id: '',
        companyId: arg.companyId,
        fundId: arg.fundId,
        fundName: state.fundName,
        companyName: company?.name ?? '',
        custodianUid: user.uid,
        custodianName: user.displayName,
        effectiveBudget: outcome.effectiveBudget,
        physicalCash: outcome.physicalCash,
        outstanding: outcome.outstanding,
        varianceCentavos: outcome.varianceCentavos,
        denominations: outcome.denominations,
        proofImageUrl: proofUrl,
        note: state.note,
      );
      return ref.read(fundAuditRepositoryProvider).create(audit);
    } finally {
      state = state.copyWith(saving: false);
    }
  }

  Future<Uint8List?> _readBytes(String path) async {
    try {
      return await XFile(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

final fundAuditControllerProvider = AutoDisposeNotifierProviderFamily<
    FundAuditController, FundAuditFormState, FundAuditArgs>(
  FundAuditController.new,
);

final fundAuditHistoryProvider =
    StreamProvider.autoDispose.family<List<FundAudit>, FundAuditArgs>(
  (ref, arg) => ref
      .watch(fundAuditRepositoryProvider)
      .watchByFund(arg.companyId, arg.fundId),
);

final fundAuditByIdProvider =
    FutureProvider.autoDispose.family<FundAudit, String>((ref, id) async {
  final result = await ref.watch(fundAuditRepositoryProvider).getById(id);
  return result.when(ok: (a) => a, err: (f) => throw f);
});

/// Exposed so the UI can mock the picker in widget tests; defaults to a real
/// [ImagePicker].
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

/// Builds and shares the certificate PDF for a saved audit.
class FundAuditPdfShare {
  final FileShareService _share;
  FundAuditPdfShare(this._share);

  Future<Result<void>> share(FundAudit audit) async {
    try {
      final bytes = await fundAuditCertificatePdf(audit);
      final name =
          'cash-count-${audit.fundName.isEmpty ? audit.fundId : audit.fundName}'
              .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
      return _share.shareBytes(bytes, '$name.pdf', mimeType: 'application/pdf');
    } catch (e) {
      return const Err(UnexpectedFailure('Could not build the certificate.'));
    }
  }
}

final fundAuditPdfShareProvider = Provider<FundAuditPdfShare>(
    (ref) => FundAuditPdfShare(ref.watch(fileShareServiceProvider)));
