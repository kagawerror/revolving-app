import 'package:equatable/equatable.dart';

import 'app_version_info.dart';

enum UpdateStatus { upToDate, updateAvailable }

/// Result of comparing the installed build against the hosted manifest.
class UpdateDecision extends Equatable {
  const UpdateDecision(this.status, [this.latest]);

  final UpdateStatus status;
  final AppVersionInfo? latest;

  bool get hasUpdate => status == UpdateStatus.updateAvailable;

  @override
  List<Object?> get props => [status, latest];
}

/// Pure comparison seam (mirrors `computeRelease`). A null [latest] — a failed
/// or skipped check — is treated as up to date so the app never nags on error.
UpdateDecision decideUpdate({
  required int currentVersionCode,
  required AppVersionInfo? latest,
}) {
  if (latest == null) return const UpdateDecision(UpdateStatus.upToDate);
  if (latest.versionCode > currentVersionCode) {
    return UpdateDecision(UpdateStatus.updateAvailable, latest);
  }
  return UpdateDecision(UpdateStatus.upToDate, latest);
}
