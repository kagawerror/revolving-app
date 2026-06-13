import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../sync/presentation/sync_providers.dart';
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
  final _amountFocus = FocusNode();
  final _purpose = TextEditingController();
  String? _fundId;
  Uint8List? _image;

  /// Display formatter for the amount field: thousands separators + 2 decimals,
  /// no peso symbol (the field already shows a `₱ ` prefix).
  static final _amountFormat = NumberFormat('#,##0.00', 'en_PH');

  @override
  void initState() {
    super.initState();
    // Reformat the amount only once focus leaves the field, so typing stays
    // smooth (no cursor jumps mid-entry).
    _amountFocus.addListener(_handleAmountFocusChange);
  }

  @override
  void dispose() {
    _amountFocus.removeListener(_handleAmountFocusChange);
    _amountFocus.dispose();
    _beneficiary.dispose();
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  /// Parses user-entered text, tolerating grouping commas this screen inserts on
  /// blur (e.g. `1,000.00`). Returns null for empty/invalid input.
  num? _parseAmount(String raw) => num.tryParse(raw.replaceAll(',', '').trim());

  void _handleAmountFocusChange() {
    if (_amountFocus.hasFocus) return; // only on blur
    final value = _parseAmount(_amount.text);
    // Leave invalid/empty input untouched so the validator can flag it.
    if (value == null || value <= 0) return;
    _amount.text = _amountFormat.format(value);
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
    // Admins are not pinned to a company; their scope is the in-session
    // selection. Resolve it the same way the fund dropdown does so the submitted
    // companyId matches the funds the user actually picked from. A non-empty id
    // is guaranteed here because the form is gated below when it's empty.
    final companyId =
        effectiveCompanyId(user, ref.read(adminActiveCompanyProvider));
    if (companyId.isEmpty) return;

    // Every money/state decision is confirmed first. Creating a request commits
    // a spend amount against the fund, so it goes through a confirmation dialog
    // — with offline-aware copy when the device is queuing locally.
    final online = ref.read(connectivityProvider).valueOrNull ?? false;
    final amount = Money.fromPesos(_parseAmount(_amount.text)!);
    final confirmed = await _confirmCreate(
      online: online,
      amount: amount,
      beneficiary: _beneficiary.text.trim(),
    );
    if (confirmed != true || !mounted) return;

    final res = await ref.read(createRequestControllerProvider.notifier).submit(
          companyId: companyId,
          fundId: _fundId!,
          createdByUid: user.uid,
          beneficiary: _beneficiary.text.trim(),
          amount: amount,
          purpose: _purpose.text.trim(),
          imageBytes: _image,
        );
    if (!mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  /// Confirmation dialog for the create decision. Same component/style for both
  /// paths; only the body copy branches on connectivity so the incharge knows
  /// an offline create is saved on-device and synced later.
  Future<bool?> _confirmCreate({
    required bool online,
    required Money amount,
    required String beneficiary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(online
            ? Icons.send_rounded
            : Icons.cloud_off_rounded),
        title: const Text('Create this request?'),
        content: Text(
          online
              ? 'This will send a ${amount.format()} request for '
                  '$beneficiary for acknowledgement.'
              : 'You\'re offline — this ${amount.format()} request for '
                  '$beneficiary will be saved on your device and synced when '
                  'you\'re back online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: Icon(online ? Icons.send_rounded : Icons.save_rounded,
                size: 18),
            label: Text(online ? 'Send' : 'Save offline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Keep the connectivity probe warm while the form is open so the submit-time
    // read reflects the live value (rather than an initial loading→offline) and
    // the confirmation dialog shows the right copy.
    ref.watch(connectivityProvider);
    // Non-admins resolve to their own pinned companyId (unchanged). Admins
    // resolve to their in-session selection, which may be empty if they reached
    // this screen without choosing a company.
    final companyId = user == null
        ? ''
        : effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));

    // Admin with no company picked: show the context bar so they can choose a
    // company here, plus a friendly prompt instead of an empty, un-submittable
    // form. Non-admins never hit this (they always resolve to a company).
    if (user != null && companyId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('New request')),
        body: const Column(
          children: [
            CompanyContextBar(),
            Expanded(
              child: AdminSelectCompanyPrompt(
                message: 'Choose a company in the bar above before creating a '
                    'request.',
              ),
            ),
          ],
        ),
      );
    }

    final funds = user == null
        ? const AsyncValue.loading()
        : ref.watch(companyFundsProvider(companyId));
    final submitting = ref.watch(createRequestControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Lets a multi-company incharge (or admin superuser) switch the
            // operating company before filling the form. Renders nothing for a
            // single-company non-admin.
            const CompanyContextBar(),
            Expanded(
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
                    focusNode: _amountFocus,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₱ ',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) {
                      final n = _parseAmount(v ?? '');
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
              // Full-width primary submit. The parent Column is start-aligned
              // (loose width), so opt in to full width explicitly now that the
              // global theme no longer forces it.
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
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
