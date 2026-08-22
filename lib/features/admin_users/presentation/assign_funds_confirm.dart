import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Confirmation gate for saving an incharge's fund assignment — a business
/// decision (it changes what funds that custodian can release against), so it
/// gets an explicit confirm step like every other money-adjacent mutation.
///
/// Two tones:
///   * **neutral** (default): a calm summary of how many funds across how many
///     companies the incharge will be scoped to.
///   * **warning** (`isZeroFundWarning == true`): used when an EXISTING incharge
///     is about to be saved with ZERO funds — a valid but easy-to-miss state, so
///     we surface an error-toned heads-up that they'll see no funds until some
///     are assigned. Returns `true` to proceed, `false`/null to cancel.
Future<bool> showAssignFundsConfirm(
  BuildContext context, {
  required String name,
  required int fundCount,
  required int companyCount,
  bool isZeroFundWarning = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final textTheme = Theme.of(ctx).textTheme;
      final warn = isZeroFundWarning;

      final iconBg = warn ? scheme.errorContainer : scheme.primaryContainer;
      final iconFg = warn ? scheme.onErrorContainer : scheme.onPrimaryContainer;

      final String message;
      if (warn) {
        message =
            '$name will be saved with no funds assigned. They’ll see no funds '
            'until you assign some.';
      } else if (companyCount <= 1) {
        message = 'Assign $fundCount '
            '${fundCount == 1 ? 'fund' : 'funds'} to $name? '
            'They’ll be able to release against '
            '${fundCount == 1 ? 'it' : 'them'}.';
      } else {
        message = 'Assign $fundCount funds across $companyCount companies to '
            '$name? They’ll be able to release against them.';
      }

      return AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: AppTokens.brField,
          ),
          child: Icon(
            warn
                ? Icons.warning_amber_rounded
                : Icons.account_balance_wallet_rounded,
            color: iconFg,
            semanticLabel: warn ? 'Warning' : 'Assign funds',
          ),
        ),
        title: Text(warn ? 'Save with no funds?' : 'Confirm fund assignment'),
        content: Text(message, style: textTheme.bodyMedium),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppTokens.lg,
          0,
          AppTokens.lg,
          AppTokens.lg,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          if (warn)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save anyway'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
        ],
      );
    },
  );
  return result ?? false;
}
