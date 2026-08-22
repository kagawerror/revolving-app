import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import 'report_providers.dart';

/// Format chooser for the Reports export action.
///
/// Step one of the two-step export flow: tap the AppBar Export action → this
/// sheet → the existing confirm dialog (with the chosen format echoed back).
///
/// Idiom: a [showModalBottomSheet] with `showDragHandle: true` and tappable
/// rows, matching the app's existing chooser sheets (the profile avatar
/// source picker). It's promoted over a three-`ListTile` `AlertDialog` because
/// (a) a sheet gives each option a comfortable two-line target with a tinted
/// leading badge — the same affordance the request-detail sheet uses — and
/// (b) it reads as a "pick one then continue" step rather than a terminal
/// decision, which is exactly what this is (the confirm dialog follows).
///
/// Returns the picked [ReportExportFormat], or `null` if dismissed.
Future<ReportExportFormat?> showExportFormatSheet(BuildContext context) {
  return showModalBottomSheet<ReportExportFormat>(
    context: context,
    showDragHandle: true,
    // Match the app's sheet shape (large top radius) explicitly; the theme's
    // bottomSheetTheme already rounds, but we pin it so it can't drift.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.rCard),
      ),
    ),
    builder: (sheetContext) => const _ExportFormatSheet(),
  );
}

class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.lg,
              0,
              AppTokens.lg,
              AppTokens.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export as',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  'Choose a file format. You will confirm the details before '
                  'anything is shared.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const _FormatOption(
            format: ReportExportFormat.pdf,
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            subtitle: 'Formatted, print-ready document',
          ),
          const _FormatOption(
            format: ReportExportFormat.csv,
            icon: Icons.grid_on_outlined,
            label: 'CSV',
            subtitle: 'Comma-separated, opens in any spreadsheet',
          ),
          const _FormatOption(
            format: ReportExportFormat.excel,
            icon: Icons.table_chart_outlined,
            label: 'Excel',
            subtitle: 'Native .xlsx workbook',
          ),
          const SizedBox(height: AppTokens.sm),
        ],
      ),
    );
  }
}

/// One format row: a tinted leading icon badge + label + subtitle, popping the
/// sheet with its [format] on tap. The whole row is a ≥48dp target.
class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final ReportExportFormat format;
  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.lg,
        vertical: AppTokens.xs,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          icon,
          color: scheme.onPrimaryContainer,
          // The visible label names the option; the badge is decorative, so we
          // hand the icon an empty semantic label to avoid double-reading.
          semanticLabel: '',
        ),
      ),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: () => Navigator.of(context).pop(format),
    );
  }
}
