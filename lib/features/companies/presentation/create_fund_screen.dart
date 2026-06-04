import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/fund.dart';
import 'admin_providers.dart';

/// Create-fund form. Presentation-only redesign — every field, validator, the
/// Money input handling (`Money.fromPesos`), the create action, and the
/// pop-on-success navigation are preserved exactly.
class CreateFundScreen extends ConsumerStatefulWidget {
  const CreateFundScreen({super.key});
  @override
  ConsumerState<CreateFundScreen> createState() => _CreateFundScreenState();
}

class _CreateFundScreenState extends ConsumerState<CreateFundScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _budget = TextEditingController();
  final _pct = TextEditingController(text: '3');
  String? _companyId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _pct.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _companyId == null) return;
    setState(() => _saving = true);
    try {
      final budget = Money.fromPesos(num.parse(_budget.text));
      final res = await ref.read(fundRepositoryProvider).create(Fund(
            id: '',
            companyId: _companyId!,
            name: _name.text.trim(),
            originalBudget: budget,
            availableBalance: budget,
            lowBalanceThresholdPct: int.parse(_pct.text),
            status: FundStatus.active,
          ));
      if (!mounted) return;
      if (res.showOnError(context)) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create fund. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New fund')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.lg),
          children: [
            const _FundHero(),
            const SectionHeader(title: 'Fund details'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  companies.maybeWhen(
                    data: (list) => DropdownButtonFormField<String>(
                      initialValue: _companyId,
                      decoration: const InputDecoration(
                        labelText: 'Company',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _companyId = v),
                      validator: (v) => v == null ? 'Select a company' : null,
                    ),
                    orElse: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTokens.lg),
                      child: LinearProgressIndicator(),
                    ),
                  ),
                  const SizedBox(height: AppTokens.lg),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Fund name',
                      prefixIcon: Icon(Icons.savings_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppTokens.lg),
                  TextFormField(
                    controller: _budget,
                    decoration: const InputDecoration(
                      labelText: 'Budget (₱)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = num.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a positive amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTokens.lg),
                  TextFormField(
                    controller: _pct,
                    decoration: const InputDecoration(
                      labelText: 'Low-balance alert (%)',
                      prefixIcon: Icon(Icons.notifications_active_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 100) return 'Enter 1–100';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Create fund'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0),
    );
  }
}

/// Gradient banner setting context for the create-fund form.
class _FundHero extends StatelessWidget {
  const _FundHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.xl),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(scheme.primary),
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(scheme.primary),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: 32,
            semanticLabel: 'New fund',
          ),
          const SizedBox(width: AppTokens.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a new fund',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  'Set the company, starting budget, and low-balance alert.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
