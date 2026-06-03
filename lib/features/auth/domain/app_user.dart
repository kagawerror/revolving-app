import 'package:equatable/equatable.dart';

enum UserRole {
  admin,
  ceo,
  manager,
  superior,
  incharge,
  employee;

  static UserRole fromName(String? name) => UserRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => UserRole.employee,
      );

  /// Any superior-level role may acknowledge a request (single-approver model).
  bool get canApprove =>
      this == UserRole.superior || this == UserRole.manager || this == UserRole.ceo;

  /// Only the incharge custodian creates/releases requests and replenishes.
  bool get canManageFund => this == UserRole.incharge;

  bool get isAdmin => this == UserRole.admin;
}

class AppUser extends Equatable {
  final String uid;
  final String companyId;
  final UserRole role;
  final String displayName;
  final String email;

  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.displayName,
    required this.email,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) => AppUser(
        uid: uid,
        companyId: (map['companyId'] ?? '') as String,
        role: UserRole.fromName(map['role'] as String?),
        displayName: (map['displayName'] ?? '') as String,
        email: (map['email'] ?? '') as String,
      );

  @override
  List<Object?> get props => [uid, companyId, role, displayName, email];
}
