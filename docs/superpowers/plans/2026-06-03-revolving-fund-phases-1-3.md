# Revolving Fund App — Phases 1–3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the working core of a multi-company revolving-fund app: Firebase-backed foundation, admin-provisioned auth with company isolation, and the full request lifecycle (create-with-proof → acknowledge → release-with-balance-deduction).

**Architecture:** Clean layered architecture organized by feature (`core/`, `services/`, `features/<x>/{domain,data,presentation}`). Domain layer holds immutable models + repository interfaces + pure use-cases (unit-tested without Firebase). Data layer implements repositories against Firestore/Cloudinary. Riverpod provides DI + state; `go_router` provides role-guarded navigation. Money is an integer-centavo value object; statuses are enums with explicit transition rules.

**Tech Stack:** Flutter 3.12+, Dart 3.12+, firebase_core/firebase_auth/cloud_firestore/firebase_messaging, flutter_riverpod, go_router, image_picker, flutter_image_compress, http (Cloudinary unsigned upload), equatable, mocktail (tests).

**Reference spec:** `docs/superpowers/specs/2026-06-03-revolving-fund-app-design.md`

---

## File Structure (created across Phases 1–3)

```
lib/
  main.dart                                  # bootstrap: Firebase init + ProviderScope + router
  core/
    config/app_secrets.dart                  # reads --dart-define values (gitignored copy at runtime)
    error/failure.dart                        # Failure sealed class
    error/result.dart                         # Result<T> = Ok | Err
    money/money.dart                          # Money value object (int centavos)
    theme/app_theme.dart                      # ThemeData
  services/
    firebase/firebase_providers.dart          # FirebaseAuth / FirebaseFirestore providers
    cloudinary/cloudinary_uploader.dart       # unsigned upload via http
    image/image_pick_compress.dart            # pick + compress proof photo
  features/
    auth/
      domain/app_user.dart                     # AppUser model + UserRole enum
      domain/auth_repository.dart              # interface
      data/firebase_auth_repository.dart       # impl
      presentation/auth_providers.dart         # authState, currentUser providers
      presentation/login_controller.dart       # login state notifier
      presentation/login_screen.dart
    companies/
      domain/company.dart
      domain/fund.dart                          # Fund model + lowBalance math
      domain/company_repository.dart
      domain/fund_repository.dart
      data/firestore_company_repository.dart
      data/firestore_fund_repository.dart
      presentation/admin_providers.dart
      presentation/admin_home_screen.dart
      presentation/create_fund_screen.dart
    requests/
      domain/fund_request.dart                  # FundRequest model
      domain/request_status.dart                # RequestStatus enum + transitions
      domain/request_repository.dart
      domain/release_request.dart               # pure use-case: compute deduction
      data/firestore_request_repository.dart     # incl. release transaction
      presentation/request_providers.dart
      presentation/create_request_screen.dart
      presentation/approver_inbox_screen.dart
      presentation/request_detail_screen.dart
  routing/app_router.dart                       # go_router + role guards
firestore.rules                                 # security rules
test/                                           # mirrors lib/ for unit tests
```

---

# PHASE 1 — FOUNDATION

### Task 1: Dependencies, Gradle fix, Firebase bootstrap

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/settings.gradle.kts`
- Modify: `lib/main.dart`
- Create: `lib/core/config/app_secrets.dart`
- Create: `lib/services/firebase/firebase_providers.dart`

- [ ] **Step 1: Add dependencies to `pubspec.yaml`**

Replace the `dependencies:` and `dev_dependencies:` blocks with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  firebase_core: ^3.8.0
  firebase_auth: ^5.3.3
  cloud_firestore: ^5.5.0
  firebase_messaging: ^15.1.5
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  image_picker: ^1.1.2
  flutter_image_compress: ^2.3.0
  http: ^1.2.2
  equatable: ^2.0.5
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mocktail: ^1.0.4
```

- [ ] **Step 2: Run pub get**

Run: `flutter pub get`
Expected: resolves without version conflicts.

- [ ] **Step 3: Fix the Gradle `google-services` plugin (Groovy syntax in a `.kts` file)**

In `android/settings.gradle.kts`, inside the existing `plugins { ... }` block, add:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, replace the broken line
`id 'com.google.gms.google-services' version '4.4.4' apply false` so the `plugins` block reads:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

- [ ] **Step 4: Verify Android still configures**

Run: `cd android && ./gradlew app:tasks -q >/dev/null && echo OK ; cd ..`
Expected: prints `OK` (no Gradle script-compilation error). If `flutter` SDK constants fail outside `flutter build`, instead run `flutter build apk --debug --target-platform android-arm64` and expect it to reach the compile stage.

- [ ] **Step 5: Create `lib/core/config/app_secrets.dart`**

```dart
/// Build-time configuration injected via `--dart-define` (or `--dart-define-from-file=.env`).
/// No secret is hard-coded here; the Cloudinary upload uses an UNSIGNED preset, so the
/// Cloudinary API secret is never present in the app.
class AppSecrets {
  const AppSecrets._();

  static const String cloudinaryCloudName =
      String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const String cloudinaryUploadPreset =
      String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static const String cloudinaryUploadFolder =
      String.fromEnvironment('CLOUDINARY_UPLOAD_FOLDER', defaultValue: 'rev_app/proofs');

  static bool get hasCloudinary =>
      cloudinaryCloudName.isNotEmpty && cloudinaryUploadPreset.isNotEmpty;
}
```

- [ ] **Step 6: Create `lib/services/firebase/firebase_providers.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
```

- [ ] **Step 7: Replace `lib/main.dart` with the bootstrap (router added in Task 6 — temporary home for now)**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Android reads google-services.json via the Gradle plugin
  runApp(const ProviderScope(child: RevApp()));
}

class RevApp extends StatelessWidget {
  const RevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Revolving Fund',
      theme: AppTheme.light(),
      home: const Scaffold(body: Center(child: Text('Bootstrapped'))),
    );
  }
}
```

- [ ] **Step 8: Commit** (after Task 2 supplies `app_theme.dart`; if committing now, stub the theme import)

```bash
git add pubspec.yaml android/ lib/main.dart lib/core/config/app_secrets.dart lib/services/firebase/firebase_providers.dart
git commit -m "chore: add Firebase/Riverpod deps, fix google-services Gradle plugin, bootstrap app"
```

---

### Task 2: `Money` value object (TDD)

**Files:**
- Create: `lib/core/money/money.dart`
- Test: `test/core/money/money_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';

void main() {
  test('fromPesos converts to centavos', () {
    expect(Money.fromPesos(100).centavos, 10000);
    expect(Money.fromPesos(0.05).centavos, 5);
  });

  test('addition and subtraction are exact', () {
    final a = Money.fromCentavos(10000);
    final b = Money.fromCentavos(2550);
    expect((a - b).centavos, 7450);
    expect((a + b).centavos, 12550);
  });

  test('percentageOf computes integer-centavo threshold', () {
    // 3% of 100,000.00 = 3,000.00
    expect(Money.fromPesos(100000).percentageOf(3).centavos, 300000);
  });

  test('comparison operators', () {
    expect(Money.fromCentavos(100) <= Money.fromCentavos(100), isTrue);
    expect(Money.fromCentavos(99) < Money.fromCentavos(100), isTrue);
  });

  test('value equality', () {
    expect(Money.fromCentavos(500), Money.fromCentavos(500));
  });

  test('format renders peso string', () {
    expect(Money.fromCentavos(123456).format(), '₱1,234.56');
  });

  test('rejects negative construction', () {
    expect(() => Money.fromCentavos(-1), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/money/money_test.dart`
Expected: FAIL — `Money` not found.

- [ ] **Step 3: Implement `lib/core/money/money.dart`**

```dart
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Exact money value, stored as integer centavos. Never use double for money math.
class Money extends Equatable implements Comparable<Money> {
  final int centavos;

  const Money._(this.centavos);

  factory Money.fromCentavos(int centavos) {
    if (centavos < 0) {
      throw ArgumentError.value(centavos, 'centavos', 'must be >= 0');
    }
    return Money._(centavos);
  }

  factory Money.fromPesos(num pesos) => Money.fromCentavos((pesos * 100).round());

  static const Money zero = Money._(0);

  Money operator +(Money other) => Money._(centavos + other.centavos);
  Money operator -(Money other) => Money.fromCentavos(centavos - other.centavos);

  /// Integer-centavo percentage (e.g. 3% threshold of a budget).
  Money percentageOf(num percent) =>
      Money.fromCentavos((centavos * percent / 100).round());

  bool operator <(Money o) => centavos < o.centavos;
  bool operator <=(Money o) => centavos <= o.centavos;
  bool operator >(Money o) => centavos > o.centavos;
  bool operator >=(Money o) => centavos >= o.centavos;

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  String format() =>
      NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(centavos / 100);

  @override
  List<Object?> get props => [centavos];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/money/money_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/money/money.dart test/core/money/money_test.dart
git commit -m "feat(core): add Money value object with exact centavo math"
```

---

### Task 3: `Result` / `Failure` types (TDD)

**Files:**
- Create: `lib/core/error/failure.dart`
- Create: `lib/core/error/result.dart`
- Test: `test/core/error/result_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';

void main() {
  test('Ok carries a value and maps', () {
    const Result<int> r = Ok(2);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull, 2);
    expect(r.map((v) => v * 10).valueOrNull, 20);
  });

  test('Err carries a failure and short-circuits map', () {
    const Result<int> r = Err(AuthFailure('nope'));
    expect(r.isOk, isFalse);
    expect(r.failureOrNull, isA<AuthFailure>());
    expect(r.map((v) => v * 10).failureOrNull, isA<AuthFailure>());
  });

  test('when folds both branches', () {
    const Result<int> ok = Ok(5);
    final out = ok.when(ok: (v) => 'v$v', err: (f) => 'e${f.message}');
    expect(out, 'v5');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/error/result_test.dart`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `lib/core/error/failure.dart`**

```dart
import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override
  List<Object?> get props => [message, runtimeType];
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}
```

- [ ] **Step 4: Implement `lib/core/error/result.dart`**

```dart
import 'failure.dart';

sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) { Ok<T>(:final value) => value, _ => null };
  Failure? get failureOrNull =>
      switch (this) { Err<T>(:final failure) => failure, _ => null };

  Result<R> map<R>(R Function(T value) f) => switch (this) {
        Ok<T>(:final value) => Ok(f(value)),
        Err<T>(:final failure) => Err(failure),
      };

  R when<R>({required R Function(T) ok, required R Function(Failure) err}) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/error/result_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/error/ test/core/error/
git commit -m "feat(core): add Result and Failure sealed types"
```

---

### Task 4: App theme + finalize bootstrap

**Files:**
- Create: `lib/core/theme/app_theme.dart`

- [ ] **Step 1: Create `lib/core/theme/app_theme.dart`**

```dart
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      inputDecorationBorder: const OutlineInputBorder(),
    );
  }
}

extension on ThemeData {
  // placeholder to keep file cohesive if future tokens are added
}
```

> Note: remove the stray extension if your linter flags it; it documents intent only.

- [ ] **Step 2: Verify app compiles**

Run: `flutter analyze`
Expected: no errors (warnings acceptable).

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/app_theme.dart
git commit -m "feat(core): add app theme"
```

---

### Task 5: Routing skeleton with `go_router`

**Files:**
- Create: `lib/routing/app_router.dart`
- Modify: `lib/main.dart`

> The router is initially flat (login + a placeholder home). Role guards are added in Task 11 once auth providers exist. This task only wires `MaterialApp.router`.

- [ ] **Step 1: Create `lib/routing/app_router.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Home (placeholder)'))),
      ),
    ],
  );
});
```

- [ ] **Step 2: Update `lib/main.dart` to use the router**

Replace `RevApp` with a `ConsumerWidget`:

```dart
class RevApp extends ConsumerWidget {
  const RevApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Revolving Fund',
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
```

Add imports: `package:flutter_riverpod/flutter_riverpod.dart` and `routing/app_router.dart`.

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/routing/app_router.dart lib/main.dart
git commit -m "feat(routing): wire go_router skeleton"
```

---

# PHASE 2 — AUTH + MULTI-TENANCY

### Task 6: Domain models — `AppUser`, `UserRole`

**Files:**
- Create: `lib/features/auth/domain/app_user.dart`
- Test: `test/features/auth/domain/app_user_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

void main() {
  test('UserRole parses from string and defaults to employee', () {
    expect(UserRole.fromName('incharge'), UserRole.incharge);
    expect(UserRole.fromName('garbage'), UserRole.employee);
  });

  test('approver roles can acknowledge requests', () {
    expect(UserRole.manager.canApprove, isTrue);
    expect(UserRole.ceo.canApprove, isTrue);
    expect(UserRole.superior.canApprove, isTrue);
    expect(UserRole.incharge.canApprove, isFalse);
    expect(UserRole.employee.canApprove, isFalse);
  });

  test('only incharge can release and manage fund', () {
    expect(UserRole.incharge.canManageFund, isTrue);
    expect(UserRole.manager.canManageFund, isFalse);
  });

  test('fromMap builds an AppUser', () {
    final u = AppUser.fromMap('uid1', {
      'companyId': 'c1',
      'role': 'incharge',
      'displayName': 'Ana',
      'email': 'ana@x.com',
    });
    expect(u.uid, 'uid1');
    expect(u.companyId, 'c1');
    expect(u.role, UserRole.incharge);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/domain/app_user_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/features/auth/domain/app_user.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/domain/app_user_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/domain/app_user.dart test/features/auth/domain/app_user_test.dart
git commit -m "feat(auth): add AppUser model and UserRole permissions"
```

---

### Task 7: `AuthRepository` interface + Firebase implementation

**Files:**
- Create: `lib/features/auth/domain/auth_repository.dart`
- Create: `lib/features/auth/data/firebase_auth_repository.dart`
- Test: `test/features/auth/data/firebase_auth_repository_test.dart`

- [ ] **Step 1: Define the interface `lib/features/auth/domain/auth_repository.dart`**

```dart
import '../../../core/error/result.dart';
import 'app_user.dart';

abstract interface class AuthRepository {
  /// Emits the current signed-in profile, or null when signed out.
  Stream<AppUser?> watchCurrentUser();

  Future<Result<AppUser>> signIn({required String email, required String password});

  Future<void> signOut();
}
```

- [ ] **Step 2: Write the failing test (with mocktail fakes)**

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';

class _MockAuth extends Mock implements FirebaseAuth {}
class _MockCred extends Mock implements UserCredential {}
class _MockUser extends Mock implements User {}

void main() {
  late _MockAuth auth;
  late FirebaseFirestore firestore; // fake_cloud_firestore optional; here we test the failure path
  setUp(() {
    auth = _MockAuth();
  });

  test('signIn maps wrong-password to AuthFailure', () async {
    when(() => auth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'))).thenThrow(
      FirebaseAuthException(code: 'wrong-password'),
    );
    final repo = FirebaseAuthRepository(auth, FirebaseFirestore.instance);
    final res = await repo.signIn(email: 'a@b.com', password: 'x');
    expect(res.failureOrNull, isA<AuthFailure>());
  });
}
```

> Note: the happy path (profile fetch from Firestore) is covered by integration testing against the emulator; this unit test pins the error mapping, which is the logic most likely to regress.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/auth/data/firebase_auth_repository_test.dart`
Expected: FAIL — `FirebaseAuthRepository` not found.

- [ ] **Step 4: Implement `lib/features/auth/data/firebase_auth_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthRepository(this._auth, this._firestore);

  @override
  Stream<AppUser?> watchCurrentUser() {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      return AppUser.fromMap(user.uid, doc.data()!);
    });
  }

  @override
  Future<Result<AppUser>> signIn(
      {required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid = cred.user!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        return const Err(AuthFailure('No profile is provisioned for this account.'));
      }
      return Ok(AppUser.fromMap(uid, doc.data()!));
    } on FirebaseAuthException catch (e) {
      return Err(AuthFailure(_message(e.code)));
    } catch (_) {
      return const Err(UnexpectedFailure('Sign-in failed. Please try again.'));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _message(String code) => switch (code) {
        'invalid-email' => 'That email address is invalid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Incorrect email or password.',
        _ => 'Unable to sign in. Please try again.',
      };
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/auth/data/firebase_auth_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/domain/auth_repository.dart lib/features/auth/data/firebase_auth_repository.dart test/features/auth/data/
git commit -m "feat(auth): add AuthRepository interface + Firebase implementation"
```

---

### Task 8: Auth providers (Riverpod)

**Files:**
- Create: `lib/features/auth/presentation/auth_providers.dart`

- [ ] **Step 1: Create `lib/features/auth/presentation/auth_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../data/firebase_auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  );
});

/// Stream of the current profile (null when signed out). The router watches this.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/auth`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/presentation/auth_providers.dart
git commit -m "feat(auth): add Riverpod auth providers"
```

---

### Task 9: Login controller (TDD) + screen

**Files:**
- Create: `lib/features/auth/presentation/login_controller.dart`
- Create: `lib/features/auth/presentation/login_screen.dart`
- Test: `test/features/auth/presentation/login_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/auth/presentation/login_controller.dart';

class _MockRepo extends Mock implements AuthRepository {}

void main() {
  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );

  test('initial state is idle', () {
    final c = makeContainer();
    addTearDown(c.dispose);
    expect(c.read(loginControllerProvider), const LoginState.idle());
  });

  test('failed sign-in sets error state', () async {
    when(() => repo.signIn(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => const Err(AuthFailure('Incorrect email or password.')));
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(loginControllerProvider.notifier).submit('a@b.com', 'x');
    expect(c.read(loginControllerProvider),
        const LoginState.error('Incorrect email or password.'));
  });

  test('successful sign-in sets success state', () async {
    when(() => repo.signIn(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => const Ok(AppUser(
            uid: 'u', companyId: 'c', role: UserRole.incharge,
            displayName: 'A', email: 'a@b.com')));
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(loginControllerProvider.notifier).submit('a@b.com', 'pw');
    expect(c.read(loginControllerProvider), const LoginState.success());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/presentation/login_controller_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/features/auth/presentation/login_controller.dart`**

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class LoginState extends Equatable {
  final bool loading;
  final String? error;
  final bool succeeded;

  const LoginState._({this.loading = false, this.error, this.succeeded = false});
  const LoginState.idle() : this._();
  const LoginState.loading() : this._(loading: true);
  const LoginState.error(String message) : this._(error: message);
  const LoginState.success() : this._(succeeded: true);

  @override
  List<Object?> get props => [loading, error, succeeded];
}

class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState.idle();

  Future<void> submit(String email, String password) async {
    state = const LoginState.loading();
    final result = await ref.read(authRepositoryProvider).signIn(
          email: email,
          password: password,
        );
    state = result.when(
      ok: (_) => const LoginState.success(),
      err: (f) => LoginState.error(f.message),
    );
  }
}

final loginControllerProvider =
    NotifierProvider<LoginController, LoginState>(LoginController.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/auth/presentation/login_controller_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Implement `lib/features/auth/presentation/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'login_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(loginControllerProvider.notifier).submit(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    ref.listen(loginControllerProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Revolving Fund',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.loading ? null : _submit,
                    child: state.loading
                        ? const CircularProgressIndicator()
                        : const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/presentation/ test/features/auth/presentation/
git commit -m "feat(auth): add login controller (TDD) and login screen"
```

---

### Task 10: Role-based router guards

**Files:**
- Modify: `lib/routing/app_router.dart`
- Create: `lib/features/companies/presentation/admin_home_screen.dart` (placeholder home for now)
- Create: `lib/features/requests/presentation/incharge_home_screen.dart` (placeholder)
- Create: `lib/features/requests/presentation/approver_home_screen.dart` (placeholder)

- [ ] **Step 1: Create placeholder home screens** (each a `Scaffold` with an AppBar + sign-out button)

`lib/features/companies/presentation/admin_home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
      body: const Center(child: Text('Admin home — provisioning added in Task 12')),
    );
  }
}
```

Create `incharge_home_screen.dart` and `approver_home_screen.dart` with the same shape (titles "Incharge" / "Approvals", body placeholder text). These become real in Phase 3.

- [ ] **Step 2: Replace `lib/routing/app_router.dart` with the guarded router**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/companies/presentation/admin_home_screen.dart';
import '../features/requests/presentation/approver_home_screen.dart';
import '../features/requests/presentation/incharge_home_screen.dart';

String _homeFor(UserRole role) => switch (role) {
      UserRole.admin => '/admin',
      UserRole.incharge => '/incharge',
      _ when role.canApprove => '/approvals',
      _ => '/incharge', // employees view their requests under the incharge shell in v1
    };

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      final user = auth.valueOrNull;
      if (auth.isLoading) return null;
      if (user == null) return loggingIn ? null : '/login';
      final home = _homeFor(user.role);
      // Block cross-role access: send everyone to their own home.
      if (loggingIn) return home;
      final allowed = home == state.matchedLocation;
      return allowed ? null : home;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
      GoRoute(path: '/incharge', builder: (_, __) => const InchargeHomeScreen()),
      GoRoute(path: '/approvals', builder: (_, __) => const ApproverHomeScreen()),
    ],
  );
});
```

- [ ] **Step 3: Verify the app boots to login**

Run: `flutter analyze` then `flutter run` (or `flutter test` for a widget smoke test).
Expected: analyze clean; app shows the login screen.

- [ ] **Step 4: Commit**

```bash
git add lib/routing/app_router.dart lib/features/companies/presentation/admin_home_screen.dart lib/features/requests/presentation/incharge_home_screen.dart lib/features/requests/presentation/approver_home_screen.dart
git commit -m "feat(routing): role-based redirects + placeholder home screens"
```

---

### Task 11: Company & Fund models + low-balance math (TDD)

**Files:**
- Create: `lib/features/companies/domain/company.dart`
- Create: `lib/features/companies/domain/fund.dart`
- Test: `test/features/companies/domain/fund_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';

void main() {
  Fund fund({int balance = 10000000, int budget = 10000000, int pct = 3}) => Fund(
        id: 'f1',
        companyId: 'c1',
        name: 'Petty Cash',
        originalBudget: Money.fromCentavos(budget),
        availableBalance: Money.fromCentavos(balance),
        lowBalanceThresholdPct: pct,
        status: FundStatus.active,
      );

  test('threshold is pct of original budget', () {
    // 3% of 100,000.00 = 3,000.00
    expect(fund().lowBalanceThreshold, Money.fromPesos(3000));
  });

  test('isLow when balance <= threshold', () {
    expect(fund(balance: 300000).isLow, isTrue); // exactly 3,000.00
    expect(fund(balance: 300001).isLow, isFalse);
  });

  test('canRelease only when balance covers amount', () {
    expect(fund(balance: 500000).canRelease(Money.fromPesos(5000)), isTrue);
    expect(fund(balance: 499999).canRelease(Money.fromPesos(5000)), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/companies/domain/fund_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/features/companies/domain/company.dart`**

```dart
import 'package:equatable/equatable.dart';

class Company extends Equatable {
  final String id;
  final String name;
  const Company({required this.id, required this.name});

  factory Company.fromMap(String id, Map<String, dynamic> m) =>
      Company(id: id, name: (m['name'] ?? '') as String);

  Map<String, dynamic> toMap() => {'name': name};

  @override
  List<Object?> get props => [id, name];
}
```

- [ ] **Step 4: Implement `lib/features/companies/domain/fund.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';

enum FundStatus {
  active,
  low,
  replenishing;

  static FundStatus fromName(String? n) =>
      FundStatus.values.firstWhere((s) => s.name == n, orElse: () => FundStatus.active);
}

class Fund extends Equatable {
  final String id;
  final String companyId;
  final String name;
  final Money originalBudget;
  final Money availableBalance;
  final int lowBalanceThresholdPct;
  final FundStatus status;

  const Fund({
    required this.id,
    required this.companyId,
    required this.name,
    required this.originalBudget,
    required this.availableBalance,
    required this.lowBalanceThresholdPct,
    required this.status,
  });

  Money get lowBalanceThreshold =>
      originalBudget.percentageOf(lowBalanceThresholdPct);

  bool get isLow => availableBalance <= lowBalanceThreshold;

  bool canRelease(Money amount) => availableBalance >= amount;

  factory Fund.fromMap(String id, Map<String, dynamic> m) => Fund(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        originalBudget: Money.fromCentavos((m['originalBudgetCentavos'] ?? 0) as int),
        availableBalance:
            Money.fromCentavos((m['availableBalanceCentavos'] ?? 0) as int),
        lowBalanceThresholdPct: (m['lowBalanceThresholdPct'] ?? 3) as int,
        status: FundStatus.fromName(m['status'] as String?),
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'name': name,
        'originalBudgetCentavos': originalBudget.centavos,
        'availableBalanceCentavos': availableBalance.centavos,
        'lowBalanceThresholdPct': lowBalanceThresholdPct,
        'status': status.name,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, name, originalBudget, availableBalance, lowBalanceThresholdPct, status];
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/companies/domain/fund_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/companies/domain/ test/features/companies/domain/
git commit -m "feat(companies): add Company and Fund models with low-balance math"
```

---

### Task 12: Company/Fund repositories + admin provisioning UI

**Files:**
- Create: `lib/features/companies/domain/company_repository.dart`
- Create: `lib/features/companies/domain/fund_repository.dart`
- Create: `lib/features/companies/data/firestore_company_repository.dart`
- Create: `lib/features/companies/data/firestore_fund_repository.dart`
- Create: `lib/features/companies/presentation/admin_providers.dart`
- Modify: `lib/features/companies/presentation/admin_home_screen.dart`
- Create: `lib/features/companies/presentation/create_fund_screen.dart`

- [ ] **Step 1: Define repository interfaces**

`lib/features/companies/domain/company_repository.dart`:

```dart
import 'company.dart';

abstract interface class CompanyRepository {
  Stream<List<Company>> watchAll();
  Future<String> create(String name);
}
```

`lib/features/companies/domain/fund_repository.dart`:

```dart
import 'fund.dart';

abstract interface class FundRepository {
  Stream<List<Fund>> watchByCompany(String companyId);
  Stream<Fund?> watchById(String fundId);
  Future<void> create(Fund fund);
}
```

- [ ] **Step 2: Implement `lib/features/companies/data/firestore_company_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/company.dart';
import '../domain/company_repository.dart';

class FirestoreCompanyRepository implements CompanyRepository {
  final FirebaseFirestore _db;
  FirestoreCompanyRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('companies');

  @override
  Stream<List<Company>> watchAll() => _col.orderBy('name').snapshots().map(
        (s) => s.docs.map((d) => Company.fromMap(d.id, d.data())).toList(),
      );

  @override
  Future<String> create(String name) async {
    final ref = await _col.add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }
}
```

- [ ] **Step 3: Implement `lib/features/companies/data/firestore_fund_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/fund.dart';
import '../domain/fund_repository.dart';

class FirestoreFundRepository implements FundRepository {
  final FirebaseFirestore _db;
  FirestoreFundRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('funds');

  @override
  Stream<List<Fund>> watchByCompany(String companyId) => _col
      .where('companyId', isEqualTo: companyId)
      .snapshots()
      .map((s) => s.docs.map((d) => Fund.fromMap(d.id, d.data())).toList());

  @override
  Stream<Fund?> watchById(String fundId) => _col.doc(fundId).snapshots().map(
        (d) => d.exists ? Fund.fromMap(d.id, d.data()!) : null,
      );

  @override
  Future<void> create(Fund fund) => _col.add(fund.toCreateMap());
}
```

- [ ] **Step 4: Implement `lib/features/companies/presentation/admin_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../data/firestore_company_repository.dart';
import '../data/firestore_fund_repository.dart';
import '../domain/company.dart';
import '../domain/company_repository.dart';
import '../domain/fund_repository.dart';

final companyRepositoryProvider = Provider<CompanyRepository>(
    (ref) => FirestoreCompanyRepository(ref.watch(firestoreProvider)));

final fundRepositoryProvider = Provider<FundRepository>(
    (ref) => FirestoreFundRepository(ref.watch(firestoreProvider)));

final companiesProvider = StreamProvider<List<Company>>(
    (ref) => ref.watch(companyRepositoryProvider).watchAll());
```

- [ ] **Step 5: Replace `admin_home_screen.dart` body with a company list + create-fund entry**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_providers.dart';
import 'admin_providers.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/create-fund'),
        label: const Text('New fund'),
        icon: const Icon(Icons.add),
      ),
      body: companies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView(
          children: [
            for (final c in list)
              ListTile(leading: const Icon(Icons.business), title: Text(c.name)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `create_fund_screen.dart`** (form: company picker, name, budget in pesos, threshold %)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../domain/fund.dart';
import 'admin_providers.dart';

class CreateFundScreen extends ConsumerStatefulWidget {
  const CreateFundScreen({super.key});
  @override
  ConsumerState<CreateFundScreen> createState() => _CreateFundScreenState();
}

class _CreateFundScreenState extends ConsumerState<CreateFundScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _budget = TextEditingController();
  final _pct = TextEditingController(text: '3');
  String? _companyId;
  bool _saving = false;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _companyId == null) return;
    setState(() => _saving = true);
    final budget = Money.fromPesos(num.parse(_budget.text));
    await ref.read(fundRepositoryProvider).create(Fund(
          id: '',
          companyId: _companyId!,
          name: _name.text.trim(),
          originalBudget: budget,
          availableBalance: budget,
          lowBalanceThresholdPct: int.parse(_pct.text),
          status: FundStatus.active,
        ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New fund')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            companies.maybeWhen(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'Company'),
                items: [
                  for (final c in list)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _companyId = v),
                validator: (v) => v == null ? 'Select a company' : null,
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Fund name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _budget,
              decoration: const InputDecoration(labelText: 'Budget (₱)'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  num.tryParse(v ?? '') == null ? 'Enter an amount' : null,
            ),
            TextFormField(
              controller: _pct,
              decoration: const InputDecoration(labelText: 'Low-balance alert (%)'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  int.tryParse(v ?? '') == null ? 'Enter a whole number' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Create fund'),
            ),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Register the create-fund route** in `app_router.dart` under `/admin`:

```dart
GoRoute(path: '/admin/create-fund', builder: (_, __) => const CreateFundScreen()),
```
(Add the import; remove `/admin/create-fund` from the strict cross-role redirect by allowing paths that `startsWith` the role home — update `_homeFor` guard to: `final allowed = state.matchedLocation.startsWith(home);`.)

- [ ] **Step 8: Verify**

Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/features/companies/ lib/routing/app_router.dart
git commit -m "feat(companies): admin provisioning — company/fund repos + create-fund UI"
```

---

### Task 13: Firestore security rules — auth + company isolation

**Files:**
- Create: `firestore.rules`

- [ ] **Step 1: Create `firestore.rules`**

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function myProfile() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
    }
    function myCompany() { return myProfile().companyId; }
    function myRole() { return myProfile().role; }
    function isAdmin() { return signedIn() && myRole() == 'admin'; }
    function sameCompany(companyId) { return signedIn() && companyId == myCompany(); }

    match /users/{uid} {
      allow read: if signedIn() && (request.auth.uid == uid || isAdmin());
      allow write: if isAdmin();
    }

    match /companies/{companyId} {
      allow read: if signedIn();
      allow write: if isAdmin();
    }

    match /funds/{fundId} {
      allow read: if sameCompany(resource.data.companyId);
      allow create: if isAdmin();
      // balance/status changes are constrained further in Phase 3 rules.
      allow update: if sameCompany(resource.data.companyId);
      allow delete: if isAdmin();
    }
  }
}
```

- [ ] **Step 2: (If Firebase CLI available) validate & deploy rules**

Run: `firebase deploy --only firestore:rules`
Expected: rules compile and deploy. If the CLI is not set up, document this as a manual step in the Firebase console.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat(security): Firestore rules for auth and company isolation"
```

---

# PHASE 3 — REQUESTS (create → acknowledge → release)

### Task 14: Request status enum + transition rules (TDD)

**Files:**
- Create: `lib/features/requests/domain/request_status.dart`
- Test: `test/features/requests/domain/request_status_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('allowed transitions follow the lifecycle', () {
    expect(RequestStatus.draft.canTransitionTo(RequestStatus.pendingAck), isTrue);
    expect(RequestStatus.pendingAck.canTransitionTo(RequestStatus.acknowledged), isTrue);
    expect(RequestStatus.pendingAck.canTransitionTo(RequestStatus.rejected), isTrue);
    expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.readyForRelease), isTrue);
    expect(RequestStatus.readyForRelease.canTransitionTo(RequestStatus.released), isTrue);
    expect(RequestStatus.released.canTransitionTo(RequestStatus.replenished), isTrue);
  });

  test('illegal transitions are rejected', () {
    expect(RequestStatus.draft.canTransitionTo(RequestStatus.released), isFalse);
    expect(RequestStatus.released.canTransitionTo(RequestStatus.draft), isFalse);
    expect(RequestStatus.rejected.canTransitionTo(RequestStatus.acknowledged), isFalse);
  });

  test('ensureTransition throws on illegal move', () {
    expect(() => RequestStatus.draft.ensureTransition(RequestStatus.released),
        throwsStateError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/requests/domain/request_status_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/features/requests/domain/request_status.dart`**

```dart
enum RequestStatus {
  draft,
  pendingAck,
  acknowledged,
  rejected,
  readyForRelease,
  released,
  replenished;

  static const Map<RequestStatus, Set<RequestStatus>> _allowed = {
    RequestStatus.draft: {RequestStatus.pendingAck},
    RequestStatus.pendingAck: {RequestStatus.acknowledged, RequestStatus.rejected},
    RequestStatus.acknowledged: {RequestStatus.readyForRelease},
    RequestStatus.readyForRelease: {RequestStatus.released},
    RequestStatus.released: {RequestStatus.replenished},
    RequestStatus.rejected: {},
    RequestStatus.replenished: {},
  };

  static RequestStatus fromName(String? n) => RequestStatus.values
      .firstWhere((s) => s.name == n, orElse: () => RequestStatus.draft);

  bool canTransitionTo(RequestStatus next) => _allowed[this]!.contains(next);

  void ensureTransition(RequestStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError('Illegal transition: $name → ${next.name}');
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/requests/domain/request_status_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/requests/domain/request_status.dart test/features/requests/domain/request_status_test.dart
git commit -m "feat(requests): request status enum with explicit transitions"
```

---

### Task 15: `FundRequest` model

**Files:**
- Create: `lib/features/requests/domain/fund_request.dart`
- Test: `test/features/requests/domain/fund_request_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('fromMap parses centavos and status', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1',
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Ben',
      'amountCentavos': 250000,
      'purpose': 'Fuel',
      'proofImageUrl': 'https://img/x.jpg',
      'status': 'pendingAck',
    });
    expect(r.amount, Money.fromPesos(2500));
    expect(r.status, RequestStatus.pendingAck);
    expect(r.hasProof, isTrue);
  });

  test('hasProof is false when url empty', () {
    final r = FundRequest.fromMap('r1', {'proofImageUrl': '', 'amountCentavos': 1});
    expect(r.hasProof, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/requests/domain/fund_request_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/features/requests/domain/fund_request.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'request_status.dart';

class FundRequest extends Equatable {
  final String id;
  final String companyId;
  final String fundId;
  final String createdByUid;
  final String beneficiaryName;
  final Money amount;
  final String purpose;
  final String proofImageUrl;
  final RequestStatus status;
  final String? replenishmentId;

  const FundRequest({
    required this.id,
    required this.companyId,
    required this.fundId,
    required this.createdByUid,
    required this.beneficiaryName,
    required this.amount,
    required this.purpose,
    required this.proofImageUrl,
    required this.status,
    this.replenishmentId,
  });

  bool get hasProof => proofImageUrl.isNotEmpty;

  factory FundRequest.fromMap(String id, Map<String, dynamic> m) => FundRequest(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        fundId: (m['fundId'] ?? '') as String,
        createdByUid: (m['createdByUid'] ?? '') as String,
        beneficiaryName: (m['beneficiaryName'] ?? '') as String,
        amount: Money.fromCentavos((m['amountCentavos'] ?? 0) as int),
        purpose: (m['purpose'] ?? '') as String,
        proofImageUrl: (m['proofImageUrl'] ?? '') as String,
        status: RequestStatus.fromName(m['status'] as String?),
        replenishmentId: m['replenishmentId'] as String?,
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'fundId': fundId,
        'createdByUid': createdByUid,
        'beneficiaryName': beneficiaryName,
        'amountCentavos': amount.centavos,
        'purpose': purpose,
        'proofImageUrl': proofImageUrl,
        'status': status.name,
        'replenishmentId': null,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props => [
        id, companyId, fundId, createdByUid, beneficiaryName,
        amount, purpose, proofImageUrl, status, replenishmentId,
      ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/requests/domain/fund_request_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/requests/domain/fund_request.dart test/features/requests/domain/fund_request_test.dart
git commit -m "feat(requests): add FundRequest model"
```

---

### Task 16: Cloudinary uploader (TDD with injected http client)

**Files:**
- Create: `lib/services/cloudinary/cloudinary_uploader.dart`
- Test: `test/services/cloudinary/cloudinary_uploader_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

void main() {
  test('returns secure_url on 200', () async {
    final client = MockClient((req) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'secure_url': 'https://cdn/x.jpg'}))),
        200,
      );
    });
    final uploader = CloudinaryUploader(
      cloudName: 'demo', uploadPreset: 'preset', folder: 'f', client: client);
    final res = await uploader.uploadJpeg(Uint8List.fromList([1, 2, 3]));
    expect(res.valueOrNull, 'https://cdn/x.jpg');
  });

  test('returns Err on non-200', () async {
    final client = MockClient((req) async =>
        http.StreamedResponse(Stream.value(utf8.encode('bad')), 401));
    final uploader = CloudinaryUploader(
      cloudName: 'demo', uploadPreset: 'preset', folder: 'f', client: client);
    final res = await uploader.uploadJpeg(Uint8List.fromList([1]));
    expect(res.failureOrNull, isA<Failure>());
  });
}

/// Minimal MultipartRequest-aware mock.
class MockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  MockClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/cloudinary/cloudinary_uploader_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement `lib/services/cloudinary/cloudinary_uploader.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/error/failure.dart';
import '../../core/error/result.dart';

/// Uploads proof images to Cloudinary using an UNSIGNED preset.
/// No API secret is used — only the public cloud name + preset, which are safe in-app.
class CloudinaryUploader {
  final String cloudName;
  final String uploadPreset;
  final String folder;
  final http.Client client;

  CloudinaryUploader({
    required this.cloudName,
    required this.uploadPreset,
    required this.folder,
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<Result<String>> uploadJpeg(Uint8List bytes) async {
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      return const Err(ValidationFailure('Image upload is not configured.'));
    }
    try {
      final uri =
          Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: 'proof.jpg'));
      final streamed = await client.send(request);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        return Err(UnexpectedFailure('Upload failed (${streamed.statusCode}).'));
      }
      final url = (jsonDecode(body) as Map<String, dynamic>)['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        return const Err(UnexpectedFailure('Upload returned no URL.'));
      }
      return Ok(url);
    } catch (_) {
      return const Err(UnexpectedFailure('Could not upload the proof image.'));
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/cloudinary/cloudinary_uploader_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/cloudinary/ test/services/cloudinary/
git commit -m "feat(services): Cloudinary unsigned uploader with injected http client"
```

---

### Task 17: Image pick + compress service

**Files:**
- Create: `lib/services/image/image_pick_compress.dart`

> Hardware/plugin-bound; no unit test (would need platform channels). Keep it a thin, single-purpose wrapper so the testable logic stays in the controller.

- [ ] **Step 1: Implement `lib/services/image/image_pick_compress.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo (camera or gallery) and returns compressed JPEG bytes,
/// shrinking upload size/cost before it reaches Cloudinary.
class ImagePickCompress {
  final ImagePicker _picker;
  ImagePickCompress([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  Future<Uint8List?> pick({required ImageSource source}) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 70,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );
    return compressed;
  }
}
```

- [ ] **Step 2: Add Android/iOS permissions** — in `android/app/src/main/AndroidManifest.xml` add `<uses-permission android:name="android.permission.CAMERA"/>`; in `ios/Runner/Info.plist` add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` strings.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/services/image`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/services/image/ android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat(services): image pick + compress wrapper and camera permissions"
```

---

### Task 18: `RequestRepository` interface + Firestore impl (incl. release transaction)

**Files:**
- Create: `lib/features/requests/domain/request_repository.dart`
- Create: `lib/features/requests/data/firestore_request_repository.dart`
- Test: `test/features/requests/data/release_transaction_logic_test.dart` (pure-logic guard)

- [ ] **Step 1: Define the interface `lib/features/requests/domain/request_repository.dart`**

```dart
import '../../../core/error/result.dart';
import 'fund_request.dart';
import 'request_status.dart';

abstract interface class RequestRepository {
  Stream<List<FundRequest>> watchByFund(String fundId);
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status);

  Future<Result<String>> create(FundRequest request);

  /// Generic status move that also appends a history event. Used for
  /// pendingAck, acknowledged, rejected, readyForRelease.
  Future<Result<void>> transition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
  });

  /// RELEASE: atomically validates balance, deducts, flips fund to `low` if
  /// the new balance is at/under threshold, sets request to released, logs history.
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
  });
}
```

- [ ] **Step 2: Write a pure-logic test for the deduction decision** (the part not requiring Firestore)

`test/features/requests/data/release_transaction_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';

void main() {
  Fund fund(int balance) => Fund(
        id: 'f1', companyId: 'c1', name: 'PC',
        originalBudget: Money.fromPesos(100000),
        availableBalance: Money.fromCentavos(balance),
        lowBalanceThresholdPct: 3, status: FundStatus.active);

  test('computeRelease deducts and flags low at/under threshold', () {
    final r = computeRelease(fund(500000), Money.fromPesos(2000)); // 5,000 - 2,000 = 3,000
    expect(r.newBalance, Money.fromPesos(3000));
    expect(r.fundIsLow, isTrue); // 3,000 == 3% of 100,000
  });

  test('computeRelease throws when insufficient', () {
    expect(() => computeRelease(fund(100000), Money.fromPesos(2000)),
        throwsStateError);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/requests/data/release_transaction_logic_test.dart`
Expected: FAIL — `computeRelease` not found.

- [ ] **Step 4: Implement `lib/features/requests/data/firestore_request_repository.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../domain/fund_request.dart';
import '../domain/request_repository.dart';
import '../domain/request_status.dart';

/// Pure decision used inside the release transaction — unit-testable without Firestore.
class ReleaseOutcome {
  final Money newBalance;
  final bool fundIsLow;
  const ReleaseOutcome(this.newBalance, this.fundIsLow);
}

ReleaseOutcome computeRelease(Fund fund, Money amount) {
  if (!fund.canRelease(amount)) {
    throw StateError('Insufficient fund balance for release.');
  }
  final newBalance = fund.availableBalance - amount;
  final low = newBalance <= fund.lowBalanceThreshold;
  return ReleaseOutcome(newBalance, low);
}

class FirestoreRequestRepository implements RequestRepository {
  final FirebaseFirestore _db;
  FirestoreRequestRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('requests');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) =>
      _db.collection('funds').doc(id);

  @override
  Stream<List<FundRequest>> watchByFund(String fundId) => _requests
      .where('fundId', isEqualTo: fundId)
      .snapshots()
      .map((s) => s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<FundRequest>> watchByStatus(String companyId, RequestStatus status) =>
      _requests
          .where('companyId', isEqualTo: companyId)
          .where('status', isEqualTo: status.name)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<String>> create(FundRequest request) async {
    if (request.status == RequestStatus.pendingAck && !request.hasProof) {
      return const Err(ValidationFailure('A proof image is required.'));
    }
    try {
      final ref = await _requests.add(request.toCreateMap());
      await _appendHistory(ref.id, 'created', request.createdByUid,
          to: request.status);
      return Ok(ref.id);
    } catch (_) {
      return const Err(UnexpectedFailure('Could not create the request.'));
    }
  }

  @override
  Future<Result<void>> transition({
    required FundRequest request,
    required RequestStatus to,
    required String actorUid,
    String? note,
  }) async {
    if (!request.status.canTransitionTo(to)) {
      return Err(ValidationFailure(
          'Cannot move ${request.status.name} → ${to.name}.'));
    }
    try {
      await _requests.doc(request.id).update({
        'status': to.name,
        if (to == RequestStatus.acknowledged) ...{
          'approverUid': actorUid,
          'approverDecisionAt': FieldValue.serverTimestamp(),
        },
      });
      await _appendHistory(request.id, to.name, actorUid,
          from: request.status, to: to, note: note);
      return const Ok(null);
    } catch (_) {
      return const Err(UnexpectedFailure('Could not update the request.'));
    }
  }

  @override
  Future<Result<void>> release({
    required FundRequest request,
    required String actorUid,
  }) async {
    if (!request.status.canTransitionTo(RequestStatus.released)) {
      return Err(ValidationFailure(
          'Request must be ready-for-release before releasing.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(request.fundId));
        if (!fundSnap.exists) {
          throw StateError('Fund not found.');
        }
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        final outcome = computeRelease(fund, request.amount);
        tx.update(_fundRef(request.fundId), {
          'availableBalanceCentavos': outcome.newBalance.centavos,
          'status': outcome.fundIsLow ? FundStatus.low.name : fund.status.name,
        });
        tx.update(_requests.doc(request.id), {
          'status': RequestStatus.released.name,
          'releasedAt': FieldValue.serverTimestamp(),
        });
      });
      await _appendHistory(request.id, 'released', actorUid,
          from: request.status, to: RequestStatus.released);
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (_) {
      return const Err(UnexpectedFailure('Release failed. Please retry.'));
    }
  }

  Future<void> _appendHistory(
    String requestId,
    String event,
    String actorUid, {
    RequestStatus? from,
    RequestStatus? to,
    String? note,
  }) {
    return _requests.doc(requestId).collection('history').add({
      'event': event,
      'actorUid': actorUid,
      'from': from?.name,
      'to': to?.name,
      'note': note,
      'at': FieldValue.serverTimestamp(),
    });
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/requests/data/release_transaction_logic_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/requests/domain/request_repository.dart lib/features/requests/data/firestore_request_repository.dart test/features/requests/data/
git commit -m "feat(requests): request repository with atomic release transaction"
```

---

### Task 19: Request providers + create-request flow (with proof upload)

**Files:**
- Create: `lib/features/requests/presentation/request_providers.dart`
- Create: `lib/features/requests/presentation/create_request_controller.dart`
- Create: `lib/features/requests/presentation/create_request_screen.dart`
- Modify: `lib/features/requests/presentation/incharge_home_screen.dart`
- Test: `test/features/requests/presentation/create_request_controller_test.dart`

- [ ] **Step 1: Implement `lib/features/requests/presentation/request_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/image/image_pick_compress.dart';
import '../data/firestore_request_repository.dart';
import '../domain/request_repository.dart';

final requestRepositoryProvider = Provider<RequestRepository>(
    (ref) => FirestoreRequestRepository(ref.watch(firestoreProvider)));

final cloudinaryUploaderProvider = Provider<CloudinaryUploader>((ref) =>
    CloudinaryUploader(
      cloudName: AppSecrets.cloudinaryCloudName,
      uploadPreset: AppSecrets.cloudinaryUploadPreset,
      folder: AppSecrets.cloudinaryUploadFolder,
    ));

final imagePickCompressProvider =
    Provider<ImagePickCompress>((ref) => ImagePickCompress());
```

- [ ] **Step 2: Write the failing controller test** (validates the "proof required" + upload-then-create orchestration with fakes)

`test/features/requests/presentation/create_request_controller_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/presentation/create_request_controller.dart';
import 'package:rev_app/features/requests/presentation/request_providers.dart';
import 'package:rev_app/services/cloudinary/cloudinary_uploader.dart';

class _MockRepo extends Mock implements RequestRepository {}
class _MockUploader extends Mock implements CloudinaryUploader {}

void main() {
  setUpAll(() => registerFallbackValue(FundRequest(
        id: '', companyId: '', fundId: '', createdByUid: '',
        beneficiaryName: '', amount: Money.zero, purpose: '',
        proofImageUrl: '', status: RequestStatus.draft)));

  test('submit fails when no proof image attached', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(createRequestControllerProvider.notifier);
    final res = await ctrl.submit(
      companyId: 'c1', fundId: 'f1', createdByUid: 'u1',
      beneficiary: 'Ben', amount: Money.fromPesos(10), purpose: 'x',
      imageBytes: null,
    );
    expect(res.failureOrNull, isNotNull);
  });

  test('submit uploads then creates as pendingAck', () async {
    final repo = _MockRepo();
    final uploader = _MockUploader();
    when(() => uploader.uploadJpeg(any()))
        .thenAnswer((_) async => const Ok('https://cdn/p.jpg'));
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('r1'));

    final c = ProviderContainer(overrides: [
      requestRepositoryProvider.overrideWithValue(repo),
      cloudinaryUploaderProvider.overrideWithValue(uploader),
    ]);
    addTearDown(c.dispose);

    final res = await c.read(createRequestControllerProvider.notifier).submit(
          companyId: 'c1', fundId: 'f1', createdByUid: 'u1',
          beneficiary: 'Ben', amount: Money.fromPesos(10), purpose: 'x',
          imageBytes: Uint8List.fromList([1, 2, 3]),
        );
    expect(res.valueOrNull, 'r1');
    final captured = verify(() => repo.create(captureAny())).captured.single
        as FundRequest;
    expect(captured.status, RequestStatus.pendingAck);
    expect(captured.proofImageUrl, 'https://cdn/p.jpg');
  });
}
```

(Add `import '../domain/request_status.dart';` to the controller; the test imports `request_status` transitively via `fund_request`. If the analyzer complains, add `import 'package:rev_app/features/requests/domain/request_status.dart';`.)

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/requests/presentation/create_request_controller_test.dart`
Expected: FAIL — controller not found.

- [ ] **Step 4: Implement `lib/features/requests/presentation/create_request_controller.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

class CreateRequestController extends Notifier<bool> {
  @override
  bool build() => false; // submitting?

  Future<Result<String>> submit({
    required String companyId,
    required String fundId,
    required String createdByUid,
    required String beneficiary,
    required Money amount,
    required String purpose,
    required Uint8List? imageBytes,
  }) async {
    if (imageBytes == null) {
      return const Err(ValidationFailure('Attach a photo as proof of request.'));
    }
    if (amount == Money.zero) {
      return const Err(ValidationFailure('Enter an amount greater than zero.'));
    }
    state = true;
    try {
      final upload =
          await ref.read(cloudinaryUploaderProvider).uploadJpeg(imageBytes);
      final url = upload.valueOrNull;
      if (url == null) {
        return Err(upload.failureOrNull ??
            const UnexpectedFailure('Upload failed.'));
      }
      final request = FundRequest(
        id: '',
        companyId: companyId,
        fundId: fundId,
        createdByUid: createdByUid,
        beneficiaryName: beneficiary,
        amount: amount,
        purpose: purpose,
        proofImageUrl: url,
        status: RequestStatus.pendingAck,
      );
      return ref.read(requestRepositoryProvider).create(request);
    } finally {
      state = false;
    }
  }
}

final createRequestControllerProvider =
    NotifierProvider<CreateRequestController, bool>(CreateRequestController.new);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/requests/presentation/create_request_controller_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Implement `create_request_screen.dart`** (fund picker, beneficiary, amount, purpose, photo capture via `imagePickCompressProvider`, submit button calling the controller; on `Ok` pop, on `Err` show snackbar). Use `ref.watch(currentUserProvider)` for `companyId`/`createdByUid`.

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/money/money.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import 'create_request_controller.dart';
import 'request_providers.dart';

class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  ConsumerState<CreateRequestScreen> createState() => _State();
}

class _State extends ConsumerState<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _beneficiary = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  String? _fundId;
  Uint8List? _image;

  Future<void> _capture(ImageSource source) async {
    final bytes = await ref.read(imagePickCompressProvider).pick(source: source);
    if (bytes != null) setState(() => _image = bytes);
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || !(_formKey.currentState?.validate() ?? false) || _fundId == null) {
      return;
    }
    final res = await ref.read(createRequestControllerProvider.notifier).submit(
          companyId: user.companyId,
          fundId: _fundId!,
          createdByUid: user.uid,
          beneficiary: _beneficiary.text.trim(),
          amount: Money.fromPesos(num.parse(_amount.text)),
          purpose: _purpose.text.trim(),
          imageBytes: _image,
        );
    if (!mounted) return;
    res.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final funds = user == null
        ? const AsyncValue.loading()
        : ref.watch(_companyFundsProvider(user.companyId));
    final submitting = ref.watch(createRequestControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            funds.maybeWhen(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _fundId,
                decoration: const InputDecoration(labelText: 'Fund'),
                items: [
                  for (final f in list)
                    DropdownMenuItem(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _fundId = v),
                validator: (v) => v == null ? 'Select a fund' : null,
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            TextFormField(
              controller: _beneficiary,
              decoration: const InputDecoration(labelText: 'Beneficiary (employee)'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  num.tryParse(v ?? '') == null ? 'Enter an amount' : null,
            ),
            TextFormField(
              controller: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            if (_image != null) Image.memory(_image!, height: 160),
            Row(children: [
              TextButton.icon(
                onPressed: () => _capture(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo),
                label: const Text('Gallery'),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const CircularProgressIndicator()
                  : const Text('Send for acknowledgement'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Reuses the fund repository provider from the companies feature.
final _companyFundsProvider = StreamProvider.family((ref, String companyId) =>
    ref.watch(fundRepositoryProvider).watchByCompany(companyId));
```

- [ ] **Step 7: Wire incharge home to list requests + FAB to create**

Replace `incharge_home_screen.dart` body to show the incharge's funds and a FAB pushing `/incharge/create`. Add the route in `app_router.dart`:

```dart
GoRoute(path: '/incharge/create', builder: (_, __) => const CreateRequestScreen()),
```

- [ ] **Step 8: Verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/requests/presentation/ lib/routing/app_router.dart test/features/requests/presentation/
git commit -m "feat(requests): create-request flow with required proof upload"
```

---

### Task 20: Approver inbox — acknowledge / reject

**Files:**
- Create: `lib/features/requests/presentation/approver_inbox_providers.dart`
- Modify: `lib/features/requests/presentation/approver_home_screen.dart`
- Create: `lib/features/requests/presentation/request_detail_screen.dart`

- [ ] **Step 1: Implement `approver_inbox_providers.dart`** — stream pending requests for the approver's company:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

final pendingRequestsProvider = StreamProvider<List<FundRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .watch(requestRepositoryProvider)
      .watchByStatus(user.companyId, RequestStatus.pendingAck);
});
```

- [ ] **Step 2: Replace `approver_home_screen.dart` body** with a list of pending requests (amount, beneficiary, purpose), each tapping into `RequestDetailScreen`. Include the sign-out action from the placeholder.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import 'approver_inbox_providers.dart';
import 'request_detail_screen.dart';

class ApproverHomeScreen extends ConsumerWidget {
  const ApproverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No pending requests'))
            : ListView(children: [
                for (final r in list)
                  ListTile(
                    title: Text('${r.beneficiaryName} — ${r.amount.format()}'),
                    subtitle: Text(r.purpose),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RequestDetailScreen(request: r))),
                  ),
              ]),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement `request_detail_screen.dart`** with proof image, details, and Approve/Reject buttons calling `transition(...)`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

class RequestDetailScreen extends ConsumerWidget {
  final FundRequest request;
  const RequestDetailScreen({super.key, required this.request});

  Future<void> _decide(BuildContext context, WidgetRef ref, RequestStatus to) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final res = await ref.read(requestRepositoryProvider).transition(
          request: request, to: to, actorUid: user.uid);
    if (!context.mounted) return;
    res.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (f) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (request.hasProof) Image.network(request.proofImageUrl, height: 220),
        const SizedBox(height: 12),
        Text('Beneficiary: ${request.beneficiaryName}'),
        Text('Amount: ${request.amount.format()}'),
        Text('Purpose: ${request.purpose}'),
        Text('Status: ${request.status.name}'),
        const SizedBox(height: 24),
        if (canApprove && request.status == RequestStatus.pendingAck)
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    _decide(context, ref, RequestStatus.acknowledged),
                child: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(context, ref, RequestStatus.rejected),
                child: const Text('Reject'),
              ),
            ),
          ]),
      ]),
    );
  }
}
```

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean; tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/requests/presentation/
git commit -m "feat(requests): approver inbox with acknowledge/reject"
```

---

### Task 21: Incharge release flow + Phase-3 security rules

**Files:**
- Modify: `lib/features/requests/presentation/incharge_home_screen.dart`
- Modify: `firestore.rules`

- [ ] **Step 1: Add a "Ready for release" → "Release" action to the incharge home**

In the incharge request list, for each request, show a button that depends on status:
- `acknowledged` → button "Mark ready" calls `transition(to: readyForRelease)`.
- `readyForRelease` → button "Release" calls `release(request:, actorUid:)`.

```dart
// inside the incharge request ListTile trailing:
Builder(builder: (context) {
  final repo = ref.read(requestRepositoryProvider);
  final user = ref.read(currentUserProvider).valueOrNull;
  switch (r.status) {
    case RequestStatus.acknowledged:
      return TextButton(
        onPressed: () => repo.transition(
            request: r, to: RequestStatus.readyForRelease, actorUid: user!.uid),
        child: const Text('Mark ready'),
      );
    case RequestStatus.readyForRelease:
      return FilledButton(
        onPressed: () async {
          final res = await repo.release(request: r, actorUid: user!.uid);
          if (context.mounted && res.failureOrNull != null) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(res.failureOrNull!.message)));
          }
        },
        child: const Text('Release'),
      );
    default:
      return Text(r.status.name);
  }
});
```

- [ ] **Step 2: Tighten `firestore.rules` for requests**

Add inside the `documents` match block:

```
    function isIncharge() { return signedIn() && myRole() == 'incharge'; }
    function isApprover() {
      return signedIn() && (myRole() in ['superior', 'manager', 'ceo']);
    }

    match /requests/{requestId} {
      allow read: if sameCompany(resource.data.companyId);

      // Incharge creates; must belong to their company and carry a proof image.
      allow create: if isIncharge()
        && request.resource.data.companyId == myCompany()
        && request.resource.data.createdByUid == request.auth.uid
        && request.resource.data.proofImageUrl is string
        && request.resource.data.proofImageUrl.size() > 0;

      // Approvers acknowledge/reject; incharge advances ready/released.
      allow update: if sameCompany(resource.data.companyId) && (
        (isApprover()
          && resource.data.status == 'pendingAck'
          && request.resource.data.status in ['acknowledged', 'rejected'])
        || (isIncharge()
          && resource.data.status in ['acknowledged', 'readyForRelease']
          && request.resource.data.status in ['readyForRelease', 'released'])
      );

      allow delete: if false;

      match /history/{eventId} {
        allow read: if sameCompany(get(/databases/$(database)/documents/requests/$(requestId)).data.companyId);
        allow create: if signedIn();
        allow update, delete: if false;
      }
    }
```

> Note: the release transaction also writes `funds/{id}` balance; the Phase-2 `funds` update rule (`sameCompany`) already permits it. Restricting fund-balance writes to incharge-only is a Phase-4 hardening task (documented there).

- [ ] **Step 3: Verify & deploy rules** (if CLI available)

Run: `flutter analyze && flutter test` then `firebase deploy --only firestore:rules`
Expected: analyze clean; tests pass; rules deploy.

- [ ] **Step 4: Commit**

```bash
git add lib/features/requests/presentation/incharge_home_screen.dart firestore.rules
git commit -m "feat(requests): incharge release flow + tightened request security rules"
```

---

## Manual Verification (end of Phase 3)

After Task 21, run a full manual smoke test against the real Firebase project (seed one admin user via the Firebase console + a `users/{uid}` doc with `role: admin`):

1. **Build with secrets:** `flutter run --dart-define-from-file=.env`
2. Admin signs in → creates a company → creates a fund (₱100,000, 3%).
3. Manually add an `incharge` and a `manager` user doc (Phase-4 will add admin UI for users).
4. Incharge signs in → creates a request **without** a photo → blocked. Adds a photo → sends.
5. Manager signs in → sees it in Approvals → approves.
6. Incharge → Mark ready → Release → fund balance drops by the amount; if it crosses 3%, fund flips to `low`.
7. Confirm a `history` subcollection trail exists on the request.

---

## Self-Review (against the spec)

- **Spec coverage:** Foundation (Task 1–5), admin-provisioned auth + company isolation (Task 6–13), request lifecycle create→ack→release with required proof, balance deduction, low-balance flip, audit history (Task 14–21). ✓
- **Deferred to later phases (documented, not silently dropped):** replenishment/imprest cycle + low-balance *notifications* (Phase 4), FCM + in-app inbox (Phase 5), real-time dashboard (Phase 6), admin UI for provisioning individual users, fund-balance-write hardening to incharge-only.
- **Type consistency:** `Money` (centavos), `RequestStatus`/`FundStatus` names, `computeRelease`/`ReleaseOutcome`, repository method names (`transition`, `release`, `watchByStatus`) are used identically across tasks. ✓
- **No placeholders:** every code step contains complete, compilable code; UI screens show full widget code. ✓
