import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/company.dart';
import 'admin_providers.dart';

/// Holds the company an admin is currently "operating in" while inside the
/// incharge / approval shells. `null` until the admin explicitly picks one.
///
/// Lives here next to the picker so both the bar and the screens that read it
/// share one source of truth. The coder wires the incharge/approver providers
/// to read this (falling back to `currentUser.companyId` for non-admins).
///
/// NOTE (coder): keep this as a top-level `StateProvider<String?>` — do not
/// auto-reset it, so an admin's choice survives navigating into a request
/// detail and back. Invalidate it on sign-out alongside the other per-session
/// providers.
final adminActiveCompanyProvider = StateProvider<String?>((ref) => null);

/// A role-gated header bar that lets an **admin** choose which company's data
/// the incharge / approval shell should show. For every non-admin role it
/// renders nothing (`SizedBox.shrink`), so those screens are visually
/// unchanged.
///
/// Reuse on both [InchargeHomeScreen] and [ApproverHomeScreen]: drop it in as
/// the first child above the scrolling content. It owns its own loading / error
/// states for [companiesProvider] so callers don't have to special-case admin.
class AdminCompanyContextBar extends ConsumerWidget {
  const AdminCompanyContextBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(currentUserProvider).valueOrNull?.role.isAdmin ?? false;
    // Non-admins never see the bar — their company is fixed by their profile.
    if (!isAdmin) return const SizedBox.shrink();

    final companies = ref.watch(companiesProvider);
    final activeId = ref.watch(adminActiveCompanyProvider);

    return companies.when(
      loading: () => const _ContextBarShell(child: _ContextBarLoading()),
      error: (_, _) => _ContextBarShell(
        tone: _BarTone.error,
        child: _ContextBarError(
          onRetry: () => ref.invalidate(companiesProvider),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _ContextBarShell(
            child: _ContextBarMessage(
              text: 'No companies provisioned yet.',
            ),
          );
        }
        // Guard against a stale selection (company deleted under us).
        final selected = list.where((c) => c.id == activeId).firstOrNull;
        return _ContextBarShell(
          child: _CompanyDropdown(
            companies: list,
            selected: selected,
            onChanged: (id) =>
                ref.read(adminActiveCompanyProvider.notifier).state = id,
          ),
        );
      },
    );
  }
}

enum _BarTone { normal, error }

/// Shared chrome for the bar: a full-bleed banner tinted with the primary
/// container so it reads as an "operating context", not page content. Sits
/// flush under the app bar.
class _ContextBarShell extends StatelessWidget {
  const _ContextBarShell({required this.child, this.tone = _BarTone.normal});

  final Widget child;
  final _BarTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, border) = switch (tone) {
      _BarTone.error => (scheme.errorContainer, scheme.error),
      _BarTone.normal => (scheme.primaryContainer, scheme.primary),
    };
    return Material(
      color: bg,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: border.withValues(alpha: 0.20),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg,
          vertical: AppTokens.sm,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                size: 20,
                color: tone == _BarTone.error
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer,
                semanticLabel: 'Operating company',
              ),
              const SizedBox(width: AppTokens.sm),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// The interactive dropdown. Renders a borderless [DropdownButton] styled to
/// sit on the container tint, with a quiet "Operating in" eyebrow so an admin
/// always knows the picker drives the whole screen.
class _CompanyDropdown extends StatelessWidget {
  const _CompanyDropdown({
    required this.companies,
    required this.selected,
    required this.onChanged,
  });

  final List<Company> companies;
  final Company? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasSelection = selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Operating in',
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        // 48dp target: the dropdown's own row plus the eyebrow clears it.
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            value: selected?.id,
            icon: Icon(
              Icons.expand_more_rounded,
              color: scheme.onPrimaryContainer,
            ),
            dropdownColor: scheme.surfaceContainerHigh,
            borderRadius: AppTokens.brField,
            hint: Text(
              'Select a company',
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
            selectedItemBuilder: (context) => [
              for (final c in companies)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
            items: [
              for (final c in companies)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 18,
                        color: c.id == selected?.id
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppTokens.sm),
                      Expanded(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: c.id == selected?.id
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (c.id == selected?.id)
                        Icon(Icons.check_rounded,
                            size: 18, color: scheme.primary),
                    ],
                  ),
                ),
            ],
            onChanged: (id) {
              if (id != null) onChanged(id);
            },
          ),
        ),
        if (!hasSelection)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'Pick a company to load its funds and requests.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
    );
  }
}

class _ContextBarLoading extends StatelessWidget {
  const _ContextBarLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Skeleton.box(width: 64, height: 10, radius: 5),
        const SizedBox(height: AppTokens.xs),
        Skeleton.box(width: 180, height: 16, radius: 8),
      ],
    );
  }
}

class _ContextBarError extends StatelessWidget {
  const _ContextBarError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Couldn’t load companies.',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onErrorContainer,
            minimumSize: const Size(0, 48),
          ),
        ),
      ],
    );
  }
}

class _ContextBarMessage extends StatelessWidget {
  const _ContextBarMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Text(
      text,
      style: textTheme.bodyMedium?.copyWith(
        color: scheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Full-height prompt shown in the body of an admin's incharge / approval shell
/// when no company is selected yet. Mirrors the app's [EmptyState] tone but is
/// purpose-built for the "choose context first" moment, so it doesn't show the
/// mascot (which would read as "nothing here" rather than "do this next").
///
/// Use it as the `Expanded`/body child when `adminActiveCompanyProvider` is
/// null. Non-admins never reach this — they always have a company.
class AdminSelectCompanyPrompt extends StatelessWidget {
  const AdminSelectCompanyPrompt({
    super.key,
    this.message = 'Choose a company in the bar above to view its funds and '
        'requests.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: AppTokens.brCard,
              ),
              child: Icon(
                Icons.apartment_rounded,
                size: 36,
                color: scheme.onPrimaryContainer,
                semanticLabel: 'Select a company',
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            Text(
              'Select a company',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
