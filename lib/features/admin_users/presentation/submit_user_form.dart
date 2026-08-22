import '../../auth/domain/app_user.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/fund.dart';
import '../domain/admin_password_repository.dart';
import '../domain/password_reset_rules.dart';
import '../domain/user_admin_repository.dart';
import '../domain/user_assignment.dart';
import 'user_form_dialog.dart';

/// Orchestrates an admin user-form submission (create or edit), returning `null`
/// on success or a user-safe error message on failure (the dialog stays open and
/// surfaces the message). Pure of Flutter/Firebase: the repositories are injected
/// so this is the unit-test seam for the create/edit + partial-failure contract.
///
/// EDIT ordering is deliberate and load-bearing: the profile update
/// ([UserAdminRepository.updateAssignment]) runs FIRST; only if it succeeds and a
/// new password was entered does the password set
/// ([AdminPasswordRepository.setUserPassword]) run SECOND, against a separate
/// system (the admin-relay Worker, not Firestore). If the profile saves but the
/// password set fails, the profile STAYS saved and the password error is
/// surfaced — never silently swallowed and never rolled back. An empty
/// [UserFormSubmission.newPassword] means "leave the password unchanged" and the
/// password repository is not called at all.
///
/// Passwords are transient: they are handed straight to the repositories and are
/// never logged or persisted here.
Future<String?> submitUserForm({
  required UserFormSubmission submission,
  required AppUser? existing,
  required List<Company> companies,
  required UserAdminRepository userAdminRepository,
  required AdminPasswordRepository adminPasswordRepository,
  List<Fund> funds = const [],
}) async {
  final s = submission;
  final isCreate = existing == null;
  // fundId -> owning companyId, for validating an incharge's fund assignment
  // against the real fund set (a fund must exist and live in a company the
  // incharge belongs to).
  final fundCompanyById = {for (final f in funds) f.id: f.companyId};

  // Pure validation first; surface its message inline (dialog stays open).
  // Email is immutable on edit, so only validate it on the create path.
  // Passwords are CREATE-only (null on edit, which skips that branch).
  final invalid = validateUserAssignment(
    displayName: s.displayName,
    email: s.email,
    role: s.role,
    companyId: s.companyId,
    companyIds: s.companyIds,
    existingCompanyIds: {for (final c in companies) c.id},
    assignedFundIds: s.fundIds,
    fundCompanyById: fundCompanyById,
    password: isCreate ? s.password : null,
    confirmPassword: isCreate ? s.confirmPassword : null,
    validateEmail: isCreate,
  );
  if (invalid != null) return invalid.message;

  if (isCreate) {
    // The app provisions the real Firebase Auth sign-in (on a secondary app, so
    // this admin's session is untouched) then writes the profile. The password
    // is handed to the repo and never persisted/logged here.
    final res = await userAdminRepository.createUserWithAccount(
      email: s.email,
      password: s.password,
      displayName: s.displayName,
      role: s.role,
      companyId: s.companyId,
      companyIds: s.companyIds,
      assignedFundIds: s.fundIds,
    );
    return res.failureOrNull?.message; // null == success
  }

  final res = await userAdminRepository.updateAssignment(
    uid: existing.uid,
    role: s.role,
    companyId: s.companyId,
    companyIds: s.companyIds,
    displayName: s.displayName,
    assignedFundIds: s.fundIds,
  );
  if (res.failureOrNull != null) return res.failureOrNull!.message;

  // Optional password reset runs AFTER the profile save, against a separate
  // system (the admin-relay Worker, not Firestore). Ordering is deliberate:
  // profile first, password second. If the profile saved but the password call
  // fails, the profile STAYS saved and we surface the password error inline so
  // the admin can retry the reset alone — we do not roll back the profile. Empty
  // newPassword == leave unchanged.
  if (s.newPassword.isNotEmpty) {
    final v = validateNewPassword(s.newPassword, s.newConfirmPassword);
    if (v != null) return v.message;
    final pwRes = await adminPasswordRepository.setUserPassword(
      uid: existing.uid,
      newPassword: s.newPassword,
    );
    return pwRes.failureOrNull?.message; // null == success
  }
  return null; // profile saved, no reset requested
}
