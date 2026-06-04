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
