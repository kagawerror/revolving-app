import 'dart:math';

/// Mints a client-side action id used for offline idempotency: the same release
/// (or any queued mutation) carries one stable id from the moment it is created
/// on-device, so a replay after reconnect can be deduped server-side instead of
/// double-applying money.
///
/// We avoid adding the `uuid` package; a microsecond timestamp plus 48 bits of
/// randomness is collision-safe enough for a per-device action log. [random] is
/// injectable so tests can make it deterministic.
String newClientId([Random? random]) {
  final rng = random ?? Random();
  final micros = DateTime.now().microsecondsSinceEpoch;
  final a = rng.nextInt(1 << 24);
  final b = rng.nextInt(1 << 24);
  final rand = ((a << 24) | b).toRadixString(16).padLeft(12, '0');
  return '${micros.toRadixString(16)}-$rand';
}
