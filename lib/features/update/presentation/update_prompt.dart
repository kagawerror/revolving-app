import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/app_version_info.dart';
import 'update_installer.dart';

/// Shows the dismissible "Update available" confirmation dialog. Returns when
/// the dialog is closed. Tapping "Update" downloads + installs in place,
/// showing live progress; "Later" dismisses (re-checked next launch).
Future<void> showUpdatePrompt(
  BuildContext context,
  AppVersionInfo latest, {
  UpdateInstaller installer = const UpdateInstaller(),
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(latest: latest, installer: installer),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.latest, required this.installer});

  final AppVersionInfo latest;
  final UpdateInstaller installer;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = not started; 0..1 while downloading.
  String? _error;
  StreamSubscription<OtaEvent>? _sub;

  void _startUpdate() {
    setState(() {
      _progress = 0;
      _error = null;
    });
    _sub = widget.installer.downloadAndInstall(widget.latest.apkUrl).listen(
      (event) {
        if (!mounted) return;
        final statusName = event.status.name;
        // The plugin delivers failures as DATA events with *_ERROR statuses
        // (and CANCELED), not via onError — handle them here so the dialog
        // surfaces the error and restores the action buttons.
        if (statusName.contains('ERROR') ||
            event.status == OtaStatus.CANCELED) {
          setState(() {
            _error = 'Update failed. Please try again later.';
            _progress = null;
          });
          return;
        }
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            final pct = int.tryParse(event.value ?? '');
            if (pct != null) setState(() => _progress = pct / 100.0);
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            // The OS installer takes over; leave progress as-is. Not an error.
            break;
          default:
            break;
        }
      },
      onError: (e) {
        // Fallback in case the plugin ever surfaces a failure via onError.
        if (mounted) {
          setState(() {
            _error = 'Update failed. Please try again later.';
            _progress = null;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading = _progress != null;

    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: Text('Update available (${widget.latest.versionName})'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.latest.notes?.isNotEmpty == true
                ? widget.latest.notes!
                : 'A newer version of the app is ready to install.',
            style: theme.textTheme.bodyMedium,
          ),
          if (downloading) ...[
            const SizedBox(height: AppTokens.md),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: AppTokens.xs),
            Text('Downloading… ${((_progress ?? 0) * 100).round()}%',
                style: theme.textTheme.bodySmall),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppTokens.md),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: downloading
          ? const []
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: _startUpdate,
                child: const Text('Update'),
              ),
            ],
    );
  }
}
