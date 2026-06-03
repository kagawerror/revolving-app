import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_providers.dart';
import 'create_request_controller.dart';
import 'request_providers.dart';

class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  ConsumerState<CreateRequestScreen> createState() => _State();
}

class _State extends ConsumerState<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _beneficiary = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  String? _fundId;
  Uint8List? _image;

  @override
  void dispose() {
    _beneficiary.dispose();
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    final bytes = await ref.read(imagePickCompressProvider).pick(source: source);
    if (bytes != null && mounted) setState(() => _image = bytes);
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null ||
        !(_formKey.currentState?.validate() ?? false) ||
        _fundId == null) {
      return;
    }
    final res = await ref.read(createRequestControllerProvider.notifier).submit(
          companyId: user.companyId,
          fundId: _fundId!,
          createdByUid: user.uid,
          beneficiary: _beneficiary.text.trim(),
          amount: Money.fromPesos(num.parse(_amount.text)),
          purpose: _purpose.text.trim(),
          imageBytes: _image,
        );
    if (!mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final funds = user == null
        ? const AsyncValue.loading()
        : ref.watch(companyFundsProvider(user.companyId));
    final submitting = ref.watch(createRequestControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            funds.maybeWhen(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _fundId,
                decoration: const InputDecoration(labelText: 'Fund'),
                items: [
                  for (final f in list)
                    DropdownMenuItem(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _fundId = v),
                validator: (v) => v == null ? 'Select a fund' : null,
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            TextFormField(
              controller: _beneficiary,
              decoration:
                  const InputDecoration(labelText: 'Beneficiary (employee)'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = num.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Enter a positive amount';
                return null;
              },
            ),
            TextFormField(
              controller: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            if (_image != null) Image.memory(_image!, height: 160),
            Row(children: [
              TextButton.icon(
                onPressed: () => _capture(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo),
                label: const Text('Gallery'),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Uploading…'),
                      ],
                    )
                  : const Text('Send for acknowledgement'),
            ),
          ]),
        ),
      ),
    );
  }
}
