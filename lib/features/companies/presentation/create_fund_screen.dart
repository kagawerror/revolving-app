import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../domain/fund.dart';
import 'admin_providers.dart';

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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _companyId == null) return;
    setState(() => _saving = true);
    try {
      final budget = Money.fromPesos(num.parse(_budget.text));
      await ref.read(fundRepositoryProvider).create(Fund(
            id: '',
            companyId: _companyId!,
            name: _name.text.trim(),
            originalBudget: budget,
            availableBalance: budget,
            lowBalanceThresholdPct: int.parse(_pct.text),
            status: FundStatus.active,
          ));
      if (mounted) Navigator.of(context).pop();
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            companies.maybeWhen(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'Company'),
                items: [
                  for (final c in list)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _companyId = v),
                validator: (v) => v == null ? 'Select a company' : null,
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Fund name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _budget,
              decoration: const InputDecoration(labelText: 'Budget (₱)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = num.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Enter a positive amount';
                return null;
              },
            ),
            TextFormField(
              controller: _pct,
              decoration: const InputDecoration(labelText: 'Low-balance alert (%)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 100) return 'Enter 1–100';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Create fund'),
            ),
          ]),
        ),
      ),
    );
  }
}
