import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/surface_card.dart';
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.lg, AppTokens.lg, AppTokens.lg, AppTokens.xxl),
          children: [
            // --- Details card ---
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  funds.maybeWhen(
                    data: (list) => DropdownButtonFormField<String>(
                      initialValue: _fundId,
                      decoration: const InputDecoration(
                        labelText: 'Fund',
                        prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                      ),
                      items: [
                        for (final f in list)
                          DropdownMenuItem(value: f.id, child: Text(f.name)),
                      ],
                      onChanged: (v) => setState(() => _fundId = v),
                      validator: (v) => v == null ? 'Select a fund' : null,
                    ),
                    orElse: () => const LinearProgressIndicator(),
                  ),
                  const SizedBox(height: AppTokens.md),
                  TextFormField(
                    controller: _beneficiary,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Beneficiary (employee)',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppTokens.md),
                  TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₱ ',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) {
                      final n = num.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a positive amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTokens.md),
                  TextFormField(
                    controller: _purpose,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Purpose',
                      prefixIcon: Icon(Icons.notes_rounded),
                      alignLabelWithHint: true,
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),

            // --- Proof photo card ---
            const SectionHeader(title: 'Proof of request'),
            _ProofCard(
              image: _image,
              onCamera: () => _capture(ImageSource.camera),
              onGallery: () => _capture(ImageSource.gallery),
            ),

            const SizedBox(height: AppTokens.xl),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(submitting
                  ? 'Uploading…'
                  : 'Send for acknowledgement'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prominent proof-photo capture card: shows a preview thumbnail once a photo is
/// attached, otherwise a friendly prompt. Camera + gallery buttons drive the
/// existing pick/compress flow.
class _ProofCard extends StatelessWidget {
  const _ProofCard({
    required this.image,
    required this.onCamera,
    required this.onGallery,
  });

  final Uint8List? image;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final img = image;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: AppTokens.brField,
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: img != null
                  ? Image.memory(img, fit: BoxFit.cover)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        border: Border.all(
                          color: scheme.outlineVariant,
                        ),
                        borderRadius: AppTokens.brField,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                size: 40, color: scheme.onSurfaceVariant),
                            const SizedBox(height: AppTokens.sm),
                            Text(
                              'Attach a photo as proof',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(img == null ? 'Gallery' : 'Replace'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
