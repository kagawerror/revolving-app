import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Name-only "Edit company" dialog — a prefilled clone of
/// [showAddCompanyDialog]. Presentation-only: returns the trimmed new name to
/// the caller (or `null` if cancelled). [onSubmit] performs the async update and
/// returns `true` on success (dialog closes, returns the name) or `false` on
/// failure (dialog stays open, buttons re-enable for retry). Save is disabled
/// until the name is non-empty AND actually changed.
///
/// INTEGRATION (caller): wire onSubmit to
///   ref.read(companyRepositoryProvider).update(company.id, name)
/// then `.showOnError(context)`.
Future<String?> showEditCompanyDialog(
  BuildContext context, {
  required String initialName,
  required Future<bool> Function(String name) onSubmit,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditCompanyDialog(
      initialName: initialName,
      onSubmit: onSubmit,
    ),
  );
}

class _EditCompanyDialog extends StatefulWidget {
  const _EditCompanyDialog({
    required this.initialName,
    required this.onSubmit,
  });
  final String initialName;
  final Future<bool> Function(String name) onSubmit;
  @override
  State<_EditCompanyDialog> createState() => _EditCompanyDialogState();
}

class _EditCompanyDialogState extends State<_EditCompanyDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  bool _saving = false;

  String get _name => _controller.text.trim();
  bool get _changed => _name != widget.initialName.trim();
  bool get _canSave => _name.isNotEmpty && _changed && !_saving;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final name = _name;
    setState(() => _saving = true);
    final ok = await widget.onSubmit(name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(name);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          Icons.edit_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Edit company',
        ),
      ),
      title: const Text('Edit company'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _canSave ? _save() : null,
        decoration: const InputDecoration(
          labelText: 'Company name',
          prefixIcon: Icon(Icons.business_outlined),
        ),
      ),
      actionsPadding:
          const EdgeInsets.fromLTRB(AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
