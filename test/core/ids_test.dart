import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/ids.dart';

void main() {
  group('newClientId', () {
    test('is non-empty and dash-separated', () {
      final id = newClientId();
      expect(id, isNotEmpty);
      expect(id.contains('-'), isTrue);
    });

    test('two calls produce different ids', () {
      expect(newClientId() == newClientId(), isFalse);
    });

    test('accepts an injected Random for determinism', () {
      final id = newClientId(Random(1));
      expect(id, isNotEmpty);
    });
  });
}
