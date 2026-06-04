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

  test('when folds the err branch', () {
    const Result<int> r = Err(ValidationFailure('bad'));
    final out = r.when(ok: (v) => 'v$v', err: (f) => 'e:${f.message}');
    expect(out, 'e:bad');
  });

  test('failures differ by type even with same message', () {
    expect(const AuthFailure('x') == const ValidationFailure('x'), isFalse);
    expect(const AuthFailure('x'), const AuthFailure('x'));
  });
}
