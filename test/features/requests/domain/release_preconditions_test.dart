import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/requests/domain/release_preconditions.dart';

void main() {
  group('ensureReleaseSignature', () {
    test('missing proof -> ValidationFailure', () {
      expect(
        ensureReleaseSignature(
          releaseProofUrl: '',
          releaseSignatureUrl: 'https://x/sig.png',
        ),
        isA<ValidationFailure>(),
      );
    });

    test('missing signature -> ValidationFailure', () {
      expect(
        ensureReleaseSignature(
          releaseProofUrl: 'https://x/proof.jpg',
          releaseSignatureUrl: '',
        ),
        isA<ValidationFailure>(),
      );
    });

    test('both empty -> ValidationFailure', () {
      expect(
        ensureReleaseSignature(releaseProofUrl: '', releaseSignatureUrl: ''),
        isA<ValidationFailure>(),
      );
    });

    test('whitespace-only -> ValidationFailure', () {
      expect(
        ensureReleaseSignature(
          releaseProofUrl: '   ',
          releaseSignatureUrl: '\t\n',
        ),
        isA<ValidationFailure>(),
      );
    });

    test('both present -> null', () {
      expect(
        ensureReleaseSignature(
          releaseProofUrl: 'https://x/proof.jpg',
          releaseSignatureUrl: 'https://x/sig.png',
        ),
        isNull,
      );
    });
  });
}
