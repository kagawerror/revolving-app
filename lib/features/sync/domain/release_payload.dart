import '../../../core/money/money.dart';
import 'release_intent.dart';

/// Canonical (de)serialization between a [ReleaseIntent] and an
/// [OutboxEntry.payload] map. Phase 4 controllers build the payload when they
/// enqueue a release; Phase 3's `pendingReleaseIntentsProvider` and Phase 5's
/// sync engine decode it back. Keeping it here makes it a pure, testable seam
/// (no Firebase, money stays integer centavos).
///
/// PRIVACY: this map is persisted in the outbox. It carries an amount and local
/// file paths — callers must never log it.
class ReleasePayload {
  static const String kRequestId = 'requestId';
  static const String kFundId = 'fundId';
  static const String kCompanyId = 'companyId';
  static const String kAmountCentavos = 'amountCentavos';
  static const String kClientReleaseId = 'clientReleaseId';
  static const String kLocalProofPath = 'localProofPath';
  static const String kLocalSignaturePath = 'localSignaturePath';

  /// Serializes a [ReleaseIntent] to a payload map. Money is stored as
  /// integer centavos — never a double.
  static Map<String, dynamic> encode(ReleaseIntent intent) => {
        kRequestId: intent.requestId,
        kFundId: intent.fundId,
        kCompanyId: intent.companyId,
        kAmountCentavos: intent.amount.centavos,
        kClientReleaseId: intent.clientReleaseId,
        if (intent.localProofPath != null) kLocalProofPath: intent.localProofPath,
        if (intent.localSignaturePath != null)
          kLocalSignaturePath: intent.localSignaturePath,
      };

  /// Rebuilds a [ReleaseIntent] from a payload map. Returns null when the
  /// payload is missing the required release fields (so a non-release or
  /// malformed entry is skipped rather than throwing).
  static ReleaseIntent? decode(Map<String, dynamic> payload) {
    final requestId = payload[kRequestId];
    final fundId = payload[kFundId];
    final companyId = payload[kCompanyId];
    final amount = payload[kAmountCentavos];
    final clientReleaseId = payload[kClientReleaseId];
    if (requestId is! String ||
        fundId is! String ||
        companyId is! String ||
        amount is! int ||
        clientReleaseId is! String) {
      return null;
    }
    return ReleaseIntent(
      requestId: requestId,
      fundId: fundId,
      companyId: companyId,
      amount: Money.fromCentavos(amount),
      clientReleaseId: clientReleaseId,
      localProofPath: payload[kLocalProofPath] as String?,
      localSignaturePath: payload[kLocalSignaturePath] as String?,
    );
  }
}
