# Visual Foundation + Profile & Theming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a centralized, bold/vibrant Material 3 design system with light/dark + accent presets, persist each user's theme + profile photo to their Firebase user doc, and ship a new Profile screen (circular avatar upload via Cloudinary, theme controls).

**Architecture:** A single `lib/core/theme/` token/typography/accent layer plus a `lib/core/widgets/` shared component library. `AppUser` gains `photoUrl`/`themeMode`/`accentId`; `AuthRepository.updateProfile` merge-writes them; a narrow Firestore rule lets owners self-update only those fields. A `themeControllerProvider` hydrates from `currentUserProvider` and drives `MaterialApp.router`. A new `profile` feature wires picker → cropper → compress → Cloudinary → persist.

**Tech Stack:** Flutter, Riverpod, GoRouter, Firebase (Auth + Firestore), Cloudinary (HTTP), `google_fonts`, `flutter_animate`, `shimmer`, `cached_network_image`, `image_cropper`, `image_picker`, `flutter_image_compress`. Tests: `flutter_test`, `mocktail`, `fake_cloud_firestore`.

**Scope note:** This plan delivers Phases 1–2 of the design spec (`docs/superpowers/specs/2026-06-04-visual-system-profile-theming-design.md`). The per-module visual redesigns (Phases 3–5: Dashboard, Requests, Replenishment/Admin/Auth/Notifications) are a **follow-up plan (Plan B)**, executed via the `ui-designer` agent once the foundation here exists.

---

## File Structure

**Created:**
- `lib/core/theme/app_accents.dart` — `AccentOption` + curated preset list + `byId` fallback.
- `lib/core/theme/app_tokens.dart` — radii, spacing, shadows, gradient builders.
- `lib/core/theme/app_typography.dart` — Plus Jakarta Sans `TextTheme`.
- `lib/core/widgets/app_avatar.dart` — cached avatar with initials fallback (first shared widget; the rest of the widget library is built in Plan B as screens need them).
- `lib/features/profile/presentation/profile_providers.dart` — avatar Cloudinary uploader + controller wiring.
- `lib/features/profile/presentation/profile_controller.dart` — avatar upload + save orchestration.
- `lib/features/profile/presentation/profile_screen.dart` — the Profile UI.
- Tests mirroring the above under `test/`.

**Modified:**
- `pubspec.yaml` — new dependencies.
- `lib/core/theme/app_theme.dart` — `light(Color seed)` / `dark(Color seed)`.
- `lib/features/auth/domain/app_user.dart` — new fields + serialization.
- `lib/features/auth/domain/auth_repository.dart` — `updateProfile` interface.
- `lib/features/auth/data/firebase_auth_repository.dart` — `updateProfile` impl + `toCreateMap`/bootstrap defaults.
- `lib/features/auth/presentation/auth_providers.dart` — (if `themeController` lives here) or new `lib/core/theme/theme_controller.dart`.
- `lib/core/theme/theme_controller.dart` — **Created**: `themeControllerProvider`.
- `lib/main.dart` — consume `themeControllerProvider` in `MaterialApp.router`.
- `lib/routing/app_router.dart` — `/profile` route.
- `firestore.rules` — owner self-update rule for `users/{uid}`.
- `android/app/src/main/AndroidManifest.xml` + `ios/Podfile`/Info — `image_cropper` platform setup.

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Read current dependencies block**

Run: `flutter pub deps --no-dev | head -40` and open `pubspec.yaml` to find the `dependencies:` section.

- [ ] **Step 2: Add the new dependencies**

Add under `dependencies:` (keep alphabetical-ish grouping with existing entries):

```yaml
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.0
  shimmer: ^3.0.0
  cached_network_image: ^3.4.1
  image_cropper: ^8.0.2
```

- [ ] **Step 3: Install**

Run: `flutter pub get`
Expected: `Got dependencies!` with no version-solve errors. If a constraint conflicts, relax the caret (`^`) to the resolved version `flutter pub get` reports.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add fonts, animation, shimmer, image caching + cropper"
```

---

## Task 2: Accent palette (`AppAccents`)

**Files:**
- Create: `lib/core/theme/app_accents.dart`
- Test: `test/core/theme/app_accents_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/theme/app_accents.dart';

void main() {
  group('AppAccents', () {
    test('forest is the default and is present', () {
      expect(AppAccents.defaultId, 'forest');
      expect(AppAccents.byId('forest').seed, const Color(0xFF0B6E4F));
    });

    test('byId returns the matching option', () {
      final indigo = AppAccents.byId('indigo');
      expect(indigo.id, 'indigo');
    });

    test('byId falls back to forest for unknown id', () {
      expect(AppAccents.byId('does-not-exist').id, 'forest');
    });

    test('byId falls back to forest for null', () {
      expect(AppAccents.byId(null).id, 'forest');
    });

    test('all options have unique ids and non-empty labels', () {
      final ids = AppAccents.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(AppAccents.all.every((a) => a.label.isNotEmpty), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_accents_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:rev_app/core/theme/app_accents.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter/material.dart';

/// A selectable accent preset. We store the [id] on the user doc (not the raw
/// color) so palettes can be re-tuned later without a data migration, and every
/// accent is guaranteed to seed a good Material 3 ColorScheme.
@immutable
class AccentOption {
  const AccentOption({required this.id, required this.label, required this.seed});

  final String id;
  final String label;
  final Color seed;
}

class AppAccents {
  AppAccents._();

  static const String defaultId = 'forest';

  static const List<AccentOption> all = [
    AccentOption(id: 'forest', label: 'Forest', seed: Color(0xFF0B6E4F)),
    AccentOption(id: 'indigo', label: 'Indigo', seed: Color(0xFF4F46E5)),
    AccentOption(id: 'violet', label: 'Violet', seed: Color(0xFF7C3AED)),
    AccentOption(id: 'sunset', label: 'Sunset', seed: Color(0xFFF2542D)),
    AccentOption(id: 'amber', label: 'Amber', seed: Color(0xFFF59E0B)),
    AccentOption(id: 'teal', label: 'Teal', seed: Color(0xFF0D9488)),
    AccentOption(id: 'rose', label: 'Rose', seed: Color(0xFFE11D48)),
    AccentOption(id: 'slate', label: 'Slate', seed: Color(0xFF475569)),
  ];

  static AccentOption byId(String? id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_accents_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_accents.dart test/core/theme/app_accents_test.dart
git commit -m "feat(theme): curated accent presets with safe fallback"
```

---

## Task 3: Design tokens + typography (no logic, lint-verified)

**Files:**
- Create: `lib/core/theme/app_tokens.dart`
- Create: `lib/core/theme/app_typography.dart`

- [ ] **Step 1: Write `app_tokens.dart`**

```dart
import 'package:flutter/material.dart';

/// Static design tokens shared across the app. Bold/vibrant: large radii,
/// soft shadows, accent-derived gradients.
class AppTokens {
  AppTokens._();

  // Spacing scale (multiples of 4).
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;

  // Radii.
  static const double rCard = 22, rField = 14, rPill = 999;
  static const BorderRadius brCard = BorderRadius.all(Radius.circular(rCard));
  static const BorderRadius brField = BorderRadius.all(Radius.circular(rField));

  /// Soft elevation shadow tuned for light surfaces.
  static List<BoxShadow> softShadow(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// Diagonal hero gradient derived from a seed color.
  static LinearGradient heroGradient(Color seed) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [seed, Color.lerp(seed, Colors.black, 0.28)!],
      );
}
```

- [ ] **Step 2: Write `app_typography.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plus Jakarta Sans text theme. Applied by AppTheme for both brightnesses.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
        displaySmall: GoogleFonts.plusJakartaSans(
          textStyle: base.displaySmall,
          fontWeight: FontWeight.w800,
        ),
        headlineSmall: GoogleFonts.plusJakartaSans(
          textStyle: base.headlineSmall,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          textStyle: base.titleLarge,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          textStyle: base.titleMedium,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          textStyle: base.labelLarge,
          fontWeight: FontWeight.w600,
        ),
      );
}
```

- [ ] **Step 3: Verify analyzer is clean**

Run: `flutter analyze lib/core/theme/app_tokens.dart lib/core/theme/app_typography.dart`
Expected: `No issues found!` (If `withValues` is unavailable on the pinned Flutter, replace with `.withOpacity(0.10)`.)

- [ ] **Step 4: Commit**

```bash
git add lib/core/theme/app_tokens.dart lib/core/theme/app_typography.dart
git commit -m "feat(theme): design tokens + Plus Jakarta Sans typography"
```

---

## Task 4: Theme builders (`AppTheme.light(seed)` / `dark(seed)`)

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart`

- [ ] **Step 1: Read the current file**

Run: open `lib/core/theme/app_theme.dart` (currently a single `static ThemeData light()` using `ColorScheme.fromSeed(seedColor: 0xFF0B6E4F)`).

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/theme/app_theme.dart';

void main() {
  const seed = Color(0xFF4F46E5);

  test('light() uses Material 3 and a light scheme from the given seed', () {
    final t = AppTheme.light(seed);
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.light);
  });

  test('dark() uses Material 3 and a dark scheme from the given seed', () {
    final t = AppTheme.dark(seed);
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.dark);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: FAIL — `light` expects no args / `dark` not defined.

- [ ] **Step 4: Rewrite `app_theme.dart`**

```dart
import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light(Color seed) =>
      _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light));

  static ThemeData dark(Color seed) =>
      _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: AppTypography.textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        color: scheme.surfaceContainerLow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brField),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: const OutlineInputBorder(
          borderRadius: AppTokens.brField,
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Fix the now-broken `main.dart` call site (temporary)**

In `lib/main.dart`, the existing `theme: AppTheme.light()` no longer compiles. Temporarily change it to `theme: AppTheme.light(AppAccents.byId(AppAccents.defaultId).seed)` (add the import). This is replaced properly in Task 9.

Run: `flutter analyze lib`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/theme/app_theme.dart test/core/theme/app_theme_test.dart lib/main.dart
git commit -m "feat(theme): seed-parameterized light/dark Material 3 themes"
```

---

## Task 5: Extend `AppUser` with photoUrl / themeMode / accentId

**Files:**
- Modify: `lib/features/auth/domain/app_user.dart`
- Test: `test/features/auth/domain/app_user_test.dart` (create if absent)

- [ ] **Step 1: Read the current model**

Open `lib/features/auth/domain/app_user.dart`. Current fields: `uid, companyId, role, displayName, email`, with `fromMap(uid, map)` and Equatable `props`.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/user_role.dart'; // adjust import to actual

void main() {
  group('AppUser serialization', () {
    test('fromMap reads new fields', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
        'photoUrl': 'https://cdn/x.jpg',
        'themeMode': 'dark',
        'accentId': 'indigo',
      });
      expect(u.photoUrl, 'https://cdn/x.jpg');
      expect(u.themeMode, ThemeMode.dark);
      expect(u.accentId, 'indigo');
    });

    test('fromMap applies defaults for legacy docs missing new fields', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'incharge',
        'displayName': 'Ana',
        'email': 'ana@x.com',
      });
      expect(u.photoUrl, isNull);
      expect(u.themeMode, ThemeMode.system);
      expect(u.accentId, 'forest');
    });

    test('toMap round-trips themeMode as a string', () {
      final u = AppUser.fromMap('u1', {
        'companyId': 'c1',
        'role': 'ceo',
        'displayName': 'B',
        'email': 'b@x.com',
        'themeMode': 'light',
        'accentId': 'rose',
      });
      final map = u.toMap();
      expect(map['themeMode'], 'light');
      expect(map['accentId'], 'rose');
    });
  });
}
```

(Adjust the `user_role.dart` import path to the real one — check the existing model's imports.)

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/auth/domain/app_user_test.dart`
Expected: FAIL — `photoUrl`/`themeMode`/`accentId` are not defined.

- [ ] **Step 4: Add fields + serialization**

Add to the class (preserve existing `uid, companyId, role, displayName, email`):

```dart
import 'package:flutter/material.dart' show ThemeMode;
// ...

  final String? photoUrl;
  final ThemeMode themeMode;
  final String accentId;
```

Add to the constructor with defaults:

```dart
  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.themeMode = ThemeMode.system,
    this.accentId = 'forest',
  });
```

Add a private parse helper and update `fromMap`:

```dart
  static ThemeMode _parseThemeMode(Object? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String themeModeName(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) => AppUser(
        uid: uid,
        companyId: (map['companyId'] ?? '') as String,
        role: UserRole.fromName(map['role'] as String?),
        displayName: (map['displayName'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        photoUrl: map['photoUrl'] as String?,
        themeMode: _parseThemeMode(map['themeMode']),
        accentId: (map['accentId'] as String?) ?? 'forest',
      );

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'role': role.name,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'themeMode': themeModeName(themeMode),
        'accentId': accentId,
      };
```

Add the new fields to `props` (Equatable): `[uid, companyId, role, displayName, email, photoUrl, themeMode, accentId]`.

(If `UserRole.fromName` differs, match the existing `fromMap` exactly — only add the three new lines.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/auth/domain/app_user_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/domain/app_user.dart test/features/auth/domain/app_user_test.dart
git commit -m "feat(auth): AppUser photoUrl/themeMode/accentId with legacy defaults"
```

---

## Task 6: `updateProfile` on the auth repository

**Files:**
- Modify: `lib/features/auth/domain/auth_repository.dart`
- Modify: `lib/features/auth/data/firebase_auth_repository.dart`
- Test: `test/features/auth/data/firebase_auth_repository_update_profile_test.dart`

- [ ] **Step 1: Read both files**

Open the interface and the `FirebaseFirestore`-backed impl. Note how it gets the current uid (likely `FirebaseAuth.instance.currentUser` injected via constructor) and how it writes `users/{uid}` (look at `bootstrapFirstAdmin`).

- [ ] **Step 2: Write the failing test (fake_cloud_firestore)**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart'; // adjust path
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';
// + whatever FirebaseAuth fake/mocktail wiring the existing tests use.

void main() {
  test('updateProfile merge-writes only provided fields', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('u1').set({
      'companyId': 'c1', 'role': 'incharge',
      'displayName': 'Old', 'email': 'a@x.com',
    });

    // Construct the repo with u1 as the signed-in user (mirror existing tests'
    // FirebaseAuth mock). Pseudocode — match the real constructor:
    final repo = makeRepoSignedInAs('u1', firestore); // helper in this test file

    final res = await repo.updateProfile(
      displayName: 'New', photoUrl: 'https://cdn/p.jpg',
      themeMode: ThemeMode.dark, accentId: 'violet',
    );

    expect(res, isA<Ok<void>>());
    final doc = (await firestore.collection('users').doc('u1').get()).data()!;
    expect(doc['displayName'], 'New');
    expect(doc['photoUrl'], 'https://cdn/p.jpg');
    expect(doc['themeMode'], 'dark');
    expect(doc['accentId'], 'violet');
    expect(doc['companyId'], 'c1'); // untouched
    expect(doc['role'], 'incharge'); // untouched
  });
}
```

Wire `makeRepoSignedInAs` to mirror how the existing repo tests fake `FirebaseAuth` (reuse their helper/import — do not invent a new auth-fake pattern).

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/auth/data/firebase_auth_repository_update_profile_test.dart`
Expected: FAIL — `updateProfile` not defined.

- [ ] **Step 4: Add to the interface**

In `auth_repository.dart`:

```dart
import 'package:flutter/material.dart' show ThemeMode;
// ...
  Future<Result<void>> updateProfile({
    String? displayName,
    String? photoUrl,
    ThemeMode? themeMode,
    String? accentId,
  });
```

- [ ] **Step 5: Implement in `firebase_auth_repository.dart`**

```dart
  @override
  Future<Result<void>> updateProfile({
    String? displayName,
    String? photoUrl,
    ThemeMode? themeMode,
    String? accentId,
  }) async {
    try {
      final uid = _auth.currentUser?.uid; // match the field name in this class
      if (uid == null) {
        return const Err(AuthFailure('Not signed in'));
      }
      final data = <String, dynamic>{
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (themeMode != null) 'themeMode': AppUser.themeModeName(themeMode),
        if (accentId != null) 'accentId': accentId,
      };
      if (data.isEmpty) return const Ok(null);
      await _firestore.collection('users').doc(uid).set(
            data,
            SetOptions(merge: true),
          );
      return const Ok(null);
    } catch (e, st) {
      developer.log('updateProfile failed', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not save your profile'));
    }
  }
```

Adjust field names (`_auth`, `_firestore`) and `Failure`/`Result` imports to this file's existing ones. Ensure `dart:developer` and `AppUser` are imported.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/auth/data/firebase_auth_repository_update_profile_test.dart`
Expected: PASS.

- [ ] **Step 7: Ensure bootstrap writes defaults**

In `bootstrapFirstAdmin` (or wherever the user doc is first created), confirm the created map includes `'themeMode': 'system', 'accentId': 'forest'` (photoUrl may be omitted/null). Add them if missing. Re-run the existing auth repo tests:

Run: `flutter test test/features/auth/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/auth/domain/auth_repository.dart lib/features/auth/data/firebase_auth_repository.dart test/features/auth/data/firebase_auth_repository_update_profile_test.dart
git commit -m "feat(auth): updateProfile merge-write for profile + theme fields"
```

---

## Task 7: Firestore rule — owner self-update (security-critical)

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Read the current `users/{uid}` rules**

Open `firestore.rules`, locate the `match /users/{uid}` block. Note existing `read`/`create`/`update` rules and any `isAdmin()` / `sameCompany()` helpers.

- [ ] **Step 2: Add an owner self-update allowance**

Add (or extend the existing `allow update`) so the owner may write ONLY the self-service fields, with `role`/`companyId` immutable. Keep any existing admin-update path with `||`:

```
match /users/{uid} {
  // ...existing read/create...

  allow update: if isAdmin()
    || (
      request.auth != null && request.auth.uid == uid
      && request.resource.data.diff(resource.data).affectedKeys()
           .hasOnly(['displayName', 'photoUrl', 'themeMode', 'accentId'])
      && request.resource.data.role == resource.data.role
      && request.resource.data.companyId == resource.data.companyId
    );
}
```

(Match the real helper names; if there is no `isAdmin()`, inline the existing admin condition.)

- [ ] **Step 3: Validate rules syntax**

Run: `firebase deploy --only firestore:rules --dry-run` (or `firebase emulators:exec --only firestore "true"` if available).
Expected: rules compile with no syntax errors. Do NOT deploy yet — note for the user that deploying rules is their call (`firebase deploy --only firestore`).

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m "feat(rules): allow owner self-update of profile/theme fields only"
```

---

## Task 8: `themeControllerProvider`

**Files:**
- Create: `lib/core/theme/theme_controller.dart`
- Test: `test/core/theme/theme_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/theme/theme_controller.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/domain/user_role.dart'; // adjust

void main() {
  group('themeStateForUser', () {
    test('null user → brand default (system + forest seed)', () {
      final s = themeStateForUser(null);
      expect(s.mode, ThemeMode.system);
      expect(s.seed, const Color(0xFF0B6E4F));
    });

    test('user prefs drive mode + seed', () {
      final user = AppUser(
        uid: 'u', companyId: 'c', role: UserRole.incharge,
        displayName: 'A', email: 'a@x.com',
        themeMode: ThemeMode.dark, accentId: 'indigo',
      );
      final s = themeStateForUser(user);
      expect(s.mode, ThemeMode.dark);
      expect(s.seed, const Color(0xFF4F46E5));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/theme_controller_test.dart`
Expected: FAIL — file/symbol missing.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_providers.dart';
import 'app_accents.dart';

@immutable
class ThemeState {
  const ThemeState({required this.mode, required this.seed});
  final ThemeMode mode;
  final Color seed;
}

/// Pure reducer: AppUser (or null) → ThemeState. Unit-tested.
ThemeState themeStateForUser(AppUser? user) {
  if (user == null) {
    return ThemeState(mode: ThemeMode.system, seed: AppAccents.byId(AppAccents.defaultId).seed);
  }
  return ThemeState(mode: user.themeMode, seed: AppAccents.byId(user.accentId).seed);
}

/// Drives MaterialApp. Re-derives from the auth stream; defaults while loading.
final themeControllerProvider = Provider<ThemeState>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  return themeStateForUser(user);
});
```

(Confirm `currentUserProvider` import path from `auth_providers.dart`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/theme_controller_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/theme_controller.dart test/core/theme/theme_controller_test.dart
git commit -m "feat(theme): theme controller derived from current user"
```

---

## Task 9: Wire theming into `MaterialApp.router`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Read `main.dart`**

Find the `MaterialApp.router(...)` (currently `theme: AppTheme.light(...)`). Confirm the widget is (or can be) a `ConsumerWidget` with access to `ref`.

- [ ] **Step 2: Consume the theme controller**

```dart
final theme = ref.watch(themeControllerProvider);
// ...
MaterialApp.router(
  theme: AppTheme.light(theme.seed),
  darkTheme: AppTheme.dark(theme.seed),
  themeMode: theme.mode,
  routerConfig: router,
  // ...keep existing title/debug flags
)
```

Add imports for `theme_controller.dart` and `app_theme.dart`; remove the temporary `AppAccents` import from Task 4 if now unused.

- [ ] **Step 3: Verify build**

Run: `flutter analyze lib/main.dart` → `No issues found!`
Run: `flutter test` → all green (no regressions).

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(theme): apply user theme mode + accent in MaterialApp"
```

---

## Task 10: `AppAvatar` shared widget

**Files:**
- Create: `lib/core/widgets/app_avatar.dart`
- Test: `test/core/widgets/app_avatar_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/widgets/app_avatar.dart';

void main() {
  testWidgets('shows initials when no photoUrl', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppAvatar(displayName: 'Ana Reyes', photoUrl: null, radius: 24)),
    ));
    expect(find.text('AR'), findsOneWidget);
  });

  testWidgets('falls back to a single initial for one-word names', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppAvatar(displayName: 'Ana', photoUrl: null, radius: 24)),
    ));
    expect(find.text('A'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/app_avatar_test.dart`
Expected: FAIL — `AppAvatar` missing.

- [ ] **Step 3: Implement**

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.displayName,
    required this.photoUrl,
    this.radius = 20,
  });

  final String displayName;
  final String? photoUrl;
  final double radius;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        backgroundImage: CachedNetworkImageProvider(url),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initialsOf(displayName),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
```

(Add `characters` import if needed: `import 'package:flutter/widgets.dart';` already provides `CharacterRange` via `characters` on String from `dart:core`? Use `name.substring` if `characters` isn't available — but `.characters` comes from the `characters` package re-exported by Flutter, so it's fine.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/app_avatar_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/app_avatar.dart test/core/widgets/app_avatar_test.dart
git commit -m "feat(widgets): AppAvatar with cached photo + initials fallback"
```

---

## Task 11: Profile providers (avatar Cloudinary uploader)

**Files:**
- Create: `lib/features/profile/presentation/profile_providers.dart`

- [ ] **Step 1: Read the existing Cloudinary wiring**

Open `lib/features/requests/presentation/request_providers.dart` to see `cloudinaryUploaderProvider` and `imagePickCompressProvider`, and `lib/core/config/app_secrets.dart` for `cloudinaryCloudName`/`cloudinaryUploadPreset`.

- [ ] **Step 2: Add an avatar-scoped uploader**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_secrets.dart';
import '../../../services/cloudinary/cloudinary_uploader.dart';

/// Uploads avatars to a dedicated Cloudinary folder, reusing the proof uploader.
final avatarUploaderProvider = Provider<CloudinaryUploader>((ref) {
  return CloudinaryUploader(
    cloudName: AppSecrets.cloudinaryCloudName,
    uploadPreset: AppSecrets.cloudinaryUploadPreset,
    folder: 'avatars',
    client: http.Client(),
  );
});
```

(Match the real `CloudinaryUploader` constructor param names/defaults; if it defaults `client`, omit it.)

- [ ] **Step 3: Verify analyzer**

Run: `flutter analyze lib/features/profile/presentation/profile_providers.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/presentation/profile_providers.dart
git commit -m "feat(profile): avatar-scoped Cloudinary uploader provider"
```

---

## Task 12: `ProfileController` (upload orchestration)

**Files:**
- Create: `lib/features/profile/presentation/profile_controller.dart`
- Modify: `lib/features/profile/presentation/profile_providers.dart` (add controller provider)
- Test: `test/features/profile/presentation/profile_controller_test.dart`

- [ ] **Step 1: Define the controller contract via a failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/result.dart'; // adjust
import 'package:rev_app/features/auth/domain/auth_repository.dart';
import 'package:rev_app/features/profile/presentation/profile_controller.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepo repo;
  setUp(() {
    repo = _MockAuthRepo();
    registerFallbackValue(ThemeMode.system);
  });

  test('setAccent persists via updateProfile(accentId:)', () async {
    when(() => repo.updateProfile(accentId: any(named: 'accentId')))
        .thenAnswer((_) async => const Ok(null));
    final c = ProfileController(repo);
    final res = await c.setAccent('violet');
    expect(res, isA<Ok<void>>());
    verify(() => repo.updateProfile(accentId: 'violet')).called(1);
  });

  test('setThemeMode persists via updateProfile(themeMode:)', () async {
    when(() => repo.updateProfile(themeMode: any(named: 'themeMode')))
        .thenAnswer((_) async => const Ok(null));
    final c = ProfileController(repo);
    await c.setThemeMode(ThemeMode.dark);
    verify(() => repo.updateProfile(themeMode: ThemeMode.dark)).called(1);
  });

  test('saveDisplayName trims and rejects empty', () async {
    final c = ProfileController(repo);
    final res = await c.saveDisplayName('   ');
    expect(res, isA<Err<void>>());
    verifyNever(() => repo.updateProfile(displayName: any(named: 'displayName')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/profile/presentation/profile_controller_test.dart`
Expected: FAIL — `ProfileController` missing.

- [ ] **Step 3: Implement the controller**

```dart
import 'package:flutter/material.dart';

import '../../../core/error/failure.dart'; // adjust to real paths
import '../../../core/error/result.dart';
import '../../auth/domain/auth_repository.dart';

class ProfileController {
  ProfileController(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> setAccent(String accentId) =>
      _repo.updateProfile(accentId: accentId);

  Future<Result<void>> setThemeMode(ThemeMode mode) =>
      _repo.updateProfile(themeMode: mode);

  Future<Result<void>> saveDisplayName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future.value(const Err(ValidationFailure('Name cannot be empty')));
    }
    return _repo.updateProfile(displayName: trimmed);
  }

  /// Persists an already-uploaded avatar URL.
  Future<Result<void>> savePhotoUrl(String url) =>
      _repo.updateProfile(photoUrl: url);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/profile/presentation/profile_controller_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add a controller provider**

In `profile_providers.dart`:

```dart
import '../../auth/presentation/auth_providers.dart';
import 'profile_controller.dart';

final profileControllerProvider = Provider<ProfileController>(
  (ref) => ProfileController(ref.watch(authRepositoryProvider)),
);
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/profile/presentation/profile_controller.dart lib/features/profile/presentation/profile_providers.dart test/features/profile/presentation/profile_controller_test.dart
git commit -m "feat(profile): ProfileController for theme/name/photo persistence"
```

---

## Task 13: `image_cropper` platform setup

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist` (and confirm `ios/Podfile` platform >= 12)

- [ ] **Step 1: Android — register UCropActivity**

Inside `<application>` in `AndroidManifest.xml`, add:

```xml
<activity
  android:name="com.yalantis.ucrop.UCropActivity"
  android:screenOrientation="portrait"
  android:theme="@style/Theme.AppCompat.Light.NoActionBar" />
```

- [ ] **Step 2: iOS — ensure photo permission strings exist**

In `ios/Runner/Info.plist`, confirm `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` keys exist (request flow already uses `image_picker`, so these likely exist — add if missing).

- [ ] **Step 3: Verify the app still builds**

Run: `flutter build apk --debug --dart-define-from-file=.env` (or `flutter run` on a device).
Expected: build succeeds. (macOS desktop target won't exercise the cropper; verify on a real mobile target if available, otherwise confirm analyzer + unit tests and defer device verification to the user.)

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "chore(profile): image_cropper platform configuration"
```

---

## Task 14: `ProfileScreen` UI (delegate visuals to ui-designer)

**Files:**
- Create: `lib/features/profile/presentation/profile_screen.dart`

This task is **UI composition** — dispatch it to the `ui-designer` agent with the contracts below, then verify.

- [ ] **Step 1: Build the screen against these exact contracts**

Requirements (give verbatim to ui-designer):
- `ConsumerStatefulWidget` at route `/profile`.
- Reads `currentUserProvider` for the `AppUser` (guard loading/empty).
- **Avatar block:** `AppAvatar(displayName, photoUrl, radius: 48)` with an edit affordance. Tapping runs: `image_picker` (camera/gallery sheet) → `image_cropper` (`CropStyle.circle`/square, 1:1) → `flutter_image_compress` (reuse `ImagePickCompress` if it exposes a byte API; else compress to JPEG) → `ref.read(avatarUploaderProvider).uploadJpeg(bytes)` → on `Ok(url)` call `ref.read(profileControllerProvider).savePhotoUrl(url)`. Show a progress overlay while uploading; on `Err`, show a `SnackBar` via `failure_ui` mapping. Handle user-cancels-crop (no-op).
- **Display name:** inline editable field → `profileControllerProvider.saveDisplayName(...)`; show validation error from `Err(ValidationFailure)`.
- **Role + company badges:** read-only chips.
- **Theme mode:** `SegmentedButton<ThemeMode>` (System/Light/Dark) → `setThemeMode(...)` (updates instantly since `themeControllerProvider` watches the user stream after persist; for instant feedback before the stream round-trips, it's acceptable to rely on the stream).
- **Accent grid:** swatches from `AppAccents.all`, selected = `user.accentId`, tap → `setAccent(id)`.
- **Sign out:** reuse `signOutProvider`.
- Use themed `FilledButton`, `Card`, `AppTokens` spacing. Add subtle `flutter_animate` entrance.

- [ ] **Step 2: Add the route**

In `lib/routing/app_router.dart`, add:

```dart
GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
```

Import `ProfileScreen`. No redirect changes.

- [ ] **Step 3: Add an entry point**

Add an `AppAvatar` action to at least one existing app bar (e.g. `InchargeHomeScreen` / `ApproverHomeScreen` / `AdminHomeScreen`) that `context.go('/profile')`. Reads `currentUserProvider` for the avatar.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib` → `No issues found!`
Run: `flutter test` → all green.
Manual (device, by the user or via the `verify` skill): change accent → whole app recolors; toggle dark → app switches; upload a photo → avatar appears in app bar and persists across restart.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/ lib/routing/app_router.dart lib/features/requests/presentation/ lib/features/companies/
git commit -m "feat(profile): profile screen with avatar upload + theme controls"
```

---

## Final verification

- [ ] Run full suite: `flutter test` → all pass.
- [ ] Run `flutter analyze` → `No issues found!`.
- [ ] Confirm with the user before `firebase deploy --only firestore` (rules).
- [ ] Device smoke test (verify skill): accent change, dark mode, avatar upload + persistence.

---

## Self-Review

**Spec coverage:** §4.1 accents/tokens/typography → Tasks 2–4. §4.1 theme builders → Task 4. §4.3 model → Task 5; repo → Task 6. §4.4 rules → Task 7. §4.5 runtime theming → Tasks 8–9. §4.2 shared widgets → Task 10 (`AppAvatar`; remaining widgets deferred to Plan B with their screens, intentionally). §4.6 profile → Tasks 11–14. §4.7 routing → Task 14. §5 deps → Task 1. §6 testing seams → Tasks 2,5,6,8,10,12. Phases 3–5 (per-module redesign) → **Plan B**, noted up front.

**Placeholder scan:** No TBD/"handle edge cases". Task 14 is explicitly a delegated UI task with concrete contracts (acceptable — UI composition, not unit logic). All code-bearing steps show code.

**Type consistency:** `themeModeName`/`_parseThemeMode` (Task 5) reused in Task 6 and `themeStateForUser` (Task 8); `AppAccents.byId`/`defaultId` consistent Tasks 2/4/8; `updateProfile` named params identical across Tasks 6/12; `ProfileController` methods (`setAccent`/`setThemeMode`/`saveDisplayName`/`savePhotoUrl`) consistent Tasks 12/14; `avatarUploaderProvider`/`profileControllerProvider` consistent Tasks 11/12/14.

**Known reconciliation points** (flagged inline for the implementer, not placeholders): exact import paths for `Result`/`Failure`/`UserRole`, the `FirebaseAuth` field name in the repo, the `CloudinaryUploader` constructor signature, and the existing repo tests' auth-fake helper — each task says "match the real …".
