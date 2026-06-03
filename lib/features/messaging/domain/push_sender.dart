abstract interface class PushSender {
  /// Best-effort push to all users in [companyId] holding any of [recipientRoles].
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  });
}

/// Default no-op (used in tests and when no relay is configured).
class NoopPushSender implements PushSender {
  const NoopPushSender();
  @override
  Future<void> notify({
    required String companyId,
    required List<String> recipientRoles,
    required String title,
    required String body,
  }) async {}
}
