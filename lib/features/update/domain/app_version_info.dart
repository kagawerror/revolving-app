import 'package:equatable/equatable.dart';

/// Parsed contents of the hosted `version.json` update manifest.
///
/// [versionCode] is the authoritative integer used for comparison (mirrors the
/// Android `versionCode` / pubspec `+N` build number). [notes] is optional and,
/// when present, is shown in the update dialog.
class AppVersionInfo extends Equatable {
  const AppVersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? notes;

  /// Defensive parse: any missing or wrong-typed required field yields null so
  /// a malformed manifest fails safe instead of crashing the launch check.
  static AppVersionInfo? fromMap(Map<String, dynamic> map) {
    final code = map['versionCode'];
    final name = map['versionName'];
    final url = map['apkUrl'];
    if (code is! int || name is! String || url is! String || url.isEmpty) {
      return null;
    }
    final rawNotes = map['notes'];
    final notes = (rawNotes is String && rawNotes.isNotEmpty) ? rawNotes : null;
    return AppVersionInfo(
      versionCode: code,
      versionName: name,
      apkUrl: url,
      notes: notes,
    );
  }

  @override
  List<Object?> get props => [versionCode, versionName, apkUrl, notes];
}
