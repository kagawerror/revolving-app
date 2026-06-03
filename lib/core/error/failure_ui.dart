import 'package:flutter/material.dart';

import 'failure.dart';
import 'result.dart';

extension FailureSnackBar on BuildContext {
  void showFailure(Failure failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(this)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

extension ResultUi<T> on Result<T> {
  /// Shows a snackbar if this is an Err. Returns true when Ok.
  bool showOnError(BuildContext context) {
    final f = failureOrNull;
    if (f != null) context.showFailure(f);
    return f == null;
  }
}
