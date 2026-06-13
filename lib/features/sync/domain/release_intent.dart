import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';

/// A cash release the incharge performed on-device, captured as a pure intent so
/// it can be queued offline and reconciled against the server later. The
/// [clientReleaseId] makes replay idempotent. Image paths are local files
/// awaiting upload + backfill; they are placeholders here (the outbox/upload
/// phase consumes them).
class ReleaseIntent extends Equatable {
  final String requestId;
  final String fundId;
  final String companyId;
  final Money amount;
  final String clientReleaseId;

  /// Local file paths for the release proof photo and recipient signature,
  /// captured offline and uploaded on sync. Null when not yet captured / not
  /// applicable.
  final String? localProofPath;
  final String? localSignaturePath;

  const ReleaseIntent({
    required this.requestId,
    required this.fundId,
    required this.companyId,
    required this.amount,
    required this.clientReleaseId,
    this.localProofPath,
    this.localSignaturePath,
  });

  @override
  List<Object?> get props => [
        requestId,
        fundId,
        companyId,
        amount,
        clientReleaseId,
        localProofPath,
        localSignaturePath,
      ];
}
