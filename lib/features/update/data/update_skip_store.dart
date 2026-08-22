import 'package:shared_preferences/shared_preferences.dart';

/// Persists the highest update [versionCode] the user has dismissed ("Later")
/// or that failed to install, so the one-shot launch check won't re-prompt for
/// the same build every time the app opens. A newer manifest (higher
/// versionCode) still prompts — see [decideUpdate].
///
/// The [SharedPreferences] instance is injected so tests can pass an in-memory
/// one (`SharedPreferences.setMockInitialValues`). Mirrors `OutboxStore`'s
/// injected-prefs pattern.
class UpdateSkipStore {
  UpdateSkipStore(this._prefs);

  static const _key = 'update.skippedVersionCode';

  final SharedPreferences _prefs;

  /// The last dismissed/failed versionCode, or 0 if none.
  int skippedVersionCode() => _prefs.getInt(_key) ?? 0;

  /// Remember [versionCode] as skipped. Monotonic: never lowers the stored value
  /// so an older/rolled-back manifest can't un-skip a newer dismissal.
  Future<void> skip(int versionCode) async {
    if (versionCode <= skippedVersionCode()) return;
    await _prefs.setInt(_key, versionCode);
  }
}
