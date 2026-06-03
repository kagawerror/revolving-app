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
