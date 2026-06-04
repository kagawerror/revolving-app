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
