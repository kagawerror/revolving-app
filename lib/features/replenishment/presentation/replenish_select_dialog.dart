import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import '../../sync/presentation/sync_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

/// Modal bottom sheet for the incharge to pick released requests to replenish —
/// each Full or Partial (amount + remarks) — and submit them for approval in one
/// tap. Pops `true` on a successful submit so the caller can show the success
/// overlay. [releasable] is the already-filtered released list (remaining > 0).
class ReplenishSelectDialog extends ConsumerStatefulWidget {
  final Fund fund;
  final List<FundRequest> releasable;
  const ReplenishSelectDialog({
    super.key,
    required this.fund,
    required this.releasable,
  });

  @override
  ConsumerState<ReplenishSelectDialog> createState() =>
      _ReplenishSelectDialogState();
}

class _ReplenishSelectDialogState extends ConsumerState<ReplenishSelectDialog> {
  final _selected = <String>{};
  final _partial = <String>{};
  final _amount = <String, String>{}; // requestId -> raw pesos text
  final _remarks = <String, String>{};
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Parsed partial centavos for a row, or null if blank/invalid.
  int? _partialCentavos(String id) {
    final t = (_amount[id] ?? '').trim();
    if (t.isEmpty) return null;
    final pesos = num.tryParse(t);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  bool _rowValid(FundRequest r) {
    if (!_partial.contains(r.id)) return true; // Full is always valid
    final c = _partialCentavos(r.id);
    if (c == null || c <= 0 || c >= r.remaining.centavos) return false;
    return (_remarks[r.id] ?? '').trim().isNotEmpty;
  }

  bool get _canSubmit =>
      !_busy &&
      _selected.isNotEmpty &&
      widget.releasable.where((r) => _selected.contains(r.id)).every(_rowValid);

  Money get _total {
    var sum = Money.zero;
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        final c = _partialCentavos(r.id);
        if (c != null && c > 0 && c < r.remaining.centavos) {
          sum += Money.fromCentavos(c);
        }
      } else {
        sum += r.remaining;
      }
    }
    return sum;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || !_canSubmit) return;
    // A replenishment is created via a Firestore transaction, which can only run
    // against a live server — offline it never resolves and the button would
    // appear to do nothing. Guard here too (not just in the disabled button) in
    // case connectivity dropped between build and tap.
    final online = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!online) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text(
              'You\'re offline — a replenishment needs a connection. '
              'Reconnect and try again.'),
        ));
      return;
    }
    final items = <ReplenishmentItem>[];
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        items.add(
          ReplenishmentItem(
            requestId: r.id,
            isPartial: true,
            amount: Money.fromCentavos(_partialCentavos(r.id)!),
            remarks: (_remarks[r.id] ?? '').trim(),
          ),
        );
      } else {
        items.add(
          ReplenishmentItem(
            requestId: r.id,
            isPartial: false,
            amount: r.remaining,
          ),
        );
      }
    }
    setState(() => _busy = true);
    final res = await ref
        .read(replenishmentRepositoryProvider)
        .createAndSubmit(
          fundId: widget.fund.id,
          items: items,
          actorUid: user.uid,
          notes: _notes.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = media.size.height * 0.85;
    final empty = widget.releasable.isEmpty;
    // Watch (not read) so the footer reactively enables/disables as connectivity
    // changes while the sheet is open, and the probe stays warm for the
    // submit-time guard. Loading/unknown is treated as offline (safer).
    final online = ref.watch(connectivityProvider).valueOrNull ?? false;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      // Lift the sheet above the keyboard so the Notes/amount fields stay
      // visible while editing. `useSafeArea` on showModalBottomSheet already
      // handles the system insets.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                fundName: widget.fund.name,
                total: _total,
                count: _selected.length,
              ),
              if (empty)
                const Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTokens.xl),
                      child: EmptyState(
                        title: 'Nothing to replenish',
                        message:
                            'There are no released requests waiting to be '
                            'replenished for this fund.',
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.lg,
                      AppTokens.lg,
                      AppTokens.lg,
                      AppTokens.lg,
                    ),
                    itemCount: widget.releasable.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppTokens.md),
                    itemBuilder: (context, i) => _row(widget.releasable[i]),
                  ),
                ),
              _Footer(
                notes: _notes,
                busy: _busy,
                showNotes: !empty,
                online: online,
                canSubmit: _canSubmit,
                onCancel: _busy ? null : () => Navigator.of(context).pop(false),
                // Offline disables submit entirely: the create transaction can
                // only run against a live server, so allowing the tap would hang.
                onSubmit: (_canSubmit && online) ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(FundRequest r) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final checked = _selected.contains(r.id);
    final isPartial = _partial.contains(r.id);

    void toggle() {
      if (_busy) return;
      setState(() {
        if (checked) {
          _selected.remove(r.id);
          _partial.remove(r.id);
        } else {
          _selected.add(r.id);
        }
      });
    }

    final borderColor = checked ? scheme.primary : scheme.outlineVariant;
    final bg = checked
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.surfaceContainerLow;

    return Semantics(
      button: true,
      selected: checked,
      label: '${r.beneficiaryName}, remaining ${r.remaining.format()}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppTokens.brCard,
          border: Border.all(color: borderColor, width: checked ? 1.5 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _busy ? null : toggle,
                borderRadius: AppTokens.brCard,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _SelectionDot(checked: checked),
                      const SizedBox(width: AppTokens.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.beneficiaryName,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.purpose,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTokens.md),
                      Text(
                        r.remaining.format(),
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: checked ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (checked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.md,
                    0,
                    AppTokens.md,
                    AppTokens.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Full'),
                            icon: Icon(Icons.payments_outlined),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Partial'),
                            icon: Icon(Icons.pie_chart_outline),
                          ),
                        ],
                        selected: {isPartial},
                        onSelectionChanged: _busy
                            ? null
                            : (s) => setState(() {
                                if (s.first) {
                                  _partial.add(r.id);
                                } else {
                                  _partial.remove(r.id);
                                }
                              }),
                      ),
                      if (isPartial) ...[
                        const SizedBox(height: AppTokens.md),
                        TextField(
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Partial amount',
                            helperText: 'Less than ${r.remaining.format()}',
                            prefixIcon: const Icon(Icons.tag_outlined),
                          ),
                          onChanged: (v) => setState(() => _amount[r.id] = v),
                        ),
                        const SizedBox(height: AppTokens.sm),
                        TextField(
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Remarks',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          onChanged: (v) => setState(() => _remarks[r.id] = v),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky gradient hero header: drag handle, title, and the live total figure.
class _Header extends StatelessWidget {
  const _Header({
    required this.fundName,
    required this.total,
    required this.count,
  });

  final String fundName;
  final Money total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const onHero = Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(scheme.primary),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rCard),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.lg,
        AppTokens.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppTokens.md),
              decoration: BoxDecoration(
                color: onHero.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTokens.rPill),
              ),
            ),
          ),
          Text(
            'Replenish · $fundName',
            style: textTheme.titleMedium?.copyWith(
              color: onHero,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppTokens.md),
          Semantics(
            label:
                'Selected total ${total.format()}, $count item${count == 1 ? '' : 's'}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    total.format(),
                    style: textTheme.headlineMedium?.copyWith(
                      color: onHero,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                Text(
                  '· $count item${count == 1 ? '' : 's'}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: onHero.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
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

/// Sticky footer: optional Notes field + Cancel / Submit actions.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.notes,
    required this.busy,
    required this.showNotes,
    required this.online,
    required this.canSubmit,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController notes;
  final bool busy;
  final bool showNotes;
  final bool online;
  final bool canSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) ...[
            _OfflineNotice(scheme: scheme),
            const SizedBox(height: AppTokens.md),
          ],
          if (showNotes) ...[
            TextField(
              controller: notes,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
              minLines: 1,
              maxLines: 2,
            ),
            const SizedBox(height: AppTokens.md),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Submit for approval'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline banner shown in the footer when the device is offline, explaining why
/// the submit button is disabled (a replenishment must be created against a live
/// server). Styled with the scheme's tertiary container so it reads as an
/// informational notice rather than an error.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: AppTokens.brCard,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Text(
              'You\'re offline. Replenishing needs a connection — reconnect to '
              'submit this report.',
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small animated circular selection indicator (checkmark when selected).
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: checked ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
          : null,
    );
  }
}
