import '../../features/auth/domain/app_user.dart';

/// Human-readable label for a [UserRole] (capitalised single word in v1).
/// Shared so the profile screen, profile menu, and admin user maintenance all
/// render the same wording for the same role.
String userRoleLabel(UserRole role) {
  final name = role.name;
  return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
}
