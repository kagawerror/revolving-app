import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../../../core/money/money.dart';
import '../../../../core/theme/app_tokens.dart';

/// Full-screen pad where the cash *recipient* signs to confirm receipt. This is
/// legal proof of receipt, so the UI is deliberately formal: a white "paper"
/// card (the exported PNG must not be transparent), a printed signing baseline,
/// a context watermark (who / how much / what), and a save that is impossible
/// when the pad is empty (the mandatory-signature invariant).
///
/// Returns the rasterised PNG (`Uint8List`) on confirm, or `null` on cancel/back.
/// The caller (the release controller) uploads the bytes and commits.
///
/// Targets the `signature` package `^5.5.0`
/// (`SignatureController` + `.isEmpty` / `.isNotEmpty`, `.clear()`,
/// `.toPngBytes()`, `.addListener`). Add to pubspec:
/// ```yaml
/// signature: ^5.5.0
/// ```
///
/// Usage from the controller:
/// ```dart
/// final bytes = await Navigator.of(context).push<Uint8List?>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => SignatureCaptureScreen(
///       recipientName: request.beneficiaryName,
///       requestTitle: request.purpose,
///       amount: request.amount,
///     ),
///   ),
/// );
/// if (bytes == null) { /* user cancelled mid-flow */ }
/// ```
class SignatureCaptureScreen extends StatefulWidget {
  const SignatureCaptureScreen({
    super.key,
    required this.recipientName,
    required this.requestTitle,
    required this.amount,
  });

  /// Person acknowledging receipt (the request beneficiary). Shown on-screen as
  /// a watermark for signing context. Not logged.
  final String recipientName;

  /// Short request context line (the request purpose/title).
  final String requestTitle;

  /// Amount being released, rendered via the app's [Money] formatter.
  final Money amount;

  @override
  State<SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<SignatureCaptureScreen> {
  late final SignatureController _controller;
  bool _hasStrokes = false;
  bool _rasterizing = false;

  @override
  void initState() {
    super.initState();
    // penColor stays on-brand-neutral ink; the pad background is painted by the
    // surrounding white Container (penStrokeWidth tuned for finger signing).
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: const Color(0xFF1A1A1A),
      exportBackgroundColor: Colors.white,
    );
    _controller.addListener(_onStrokesChanged);
  }

  void _onStrokesChanged() {
    final has = _controller.isNotEmpty;
    if (has != _hasStrokes) setState(() => _hasStrokes = has);
  }

  @override
  void dispose() {
    // Leak-safety: the controller owns a ChangeNotifier + gesture buffers.
    _controller.removeListener(_onStrokesChanged);
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    // isNotEmpty flips via the listener, but clear() is synchronous so nudge UI.
    setState(() => _hasStrokes = _controller.isNotEmpty);
  }

  Future<void> _confirm() async {
    if (!_hasStrokes || _rasterizing) return;
    setState(() => _rasterizing = true);
    Uint8List? bytes;
    try {
      bytes = await _controller.toPngBytes();
    } catch (_) {
      bytes = null; // surfaced as the generic guard below; no PII in logs.
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _rasterizing = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't capture the signature. Please try again."),
          ),
        );
      return;
    }
    Navigator.of(context).pop<Uint8List>(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      // Back gesture / system back returns null (treated as cancel by caller).
      canPop: true,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: _rasterizing
                ? null
                : () => Navigator.of(context).pop<Uint8List?>(null),
          ),
          title: const Text('Recipient Signature'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ContextHeader(
                  recipientName: widget.recipientName,
                  requestTitle: widget.requestTitle,
                  amount: widget.amount,
                ),
                const SizedBox(height: AppTokens.md),
                Expanded(
                  child: _SignaturePad(
                    controller: _controller,
                    recipientName: widget.recipientName,
                    hasStrokes: _hasStrokes,
                  ),
                ),
                const SizedBox(height: AppTokens.md),
                Text(
                  'By signing, ${widget.recipientName} confirms receipt of '
                  '${widget.amount.format()} in cash.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppTokens.md),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        enabled: _hasStrokes && !_rasterizing,
                        label: 'Clear signature',
                        child: OutlinedButton.icon(
                          onPressed:
                              (_hasStrokes && !_rasterizing) ? _clear : null,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Clear'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.md),
                    Expanded(
                      flex: 2,
                      child: Semantics(
                        button: true,
                        enabled: _hasStrokes && !_rasterizing,
                        label: 'Save signature and confirm receipt',
                        child: FilledButton.icon(
                          onPressed:
                              (_hasStrokes && !_rasterizing) ? _confirm : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          icon: _rasterizing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                              _rasterizing ? 'Saving…' : 'Save & confirm'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The request context strip above the pad: amount is the dominant figure
/// (tabular, never truncated) with beneficiary + purpose beneath it.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.recipientName,
    required this.requestTitle,
    required this.amount,
  });

  final String recipientName;
  final String requestTitle;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: AppTokens.brCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: AppTokens.brField,
              ),
              child: Icon(Icons.draw_rounded, color: scheme.onPrimary),
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirming receipt of',
                    style: textTheme.labelMedium?.copyWith(
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    amount.format(),
                    style: textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$recipientName · $requestTitle',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: 0.9)),
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

/// The "paper" itself: a white card (so the PNG export has a solid background),
/// a printed baseline + "✕ sign above the line" hint that hides once signing
/// starts, a faint name watermark for context, and the live [Signature] pad
/// on top. The whole stack shares one rounded clip.
class _SignaturePad extends StatelessWidget {
  const _SignaturePad({
    required this.controller,
    required this.recipientName,
    required this.hasStrokes,
  });

  final SignatureController controller;
  final String recipientName;
  final bool hasStrokes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Signature pad. Draw your signature with your finger above the line.',
      child: ClipRRect(
        borderRadius: AppTokens.brCard,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppTokens.brCard,
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: AppTokens.softShadow(scheme.shadow),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Printed guide layer (baseline + ✕ hint + watermark). Painted
              // behind the strokes; export only captures the drawn ink + white,
              // so these guides never end up in the saved PNG.
              const Positioned.fill(
                child: IgnorePointer(child: _GuidePainter()),
              ),
              if (!hasStrokes)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        recipientName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ),
                ),
              // The live pad. Transparent so the white Container shows through;
              // export background is forced white via the controller.
              Signature(
                controller: controller,
                backgroundColor: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the signing baseline and the "✕ sign above the line" hint using a
/// custom painter so it scales to the pad without layout math.
class _GuidePainter extends StatelessWidget {
  const _GuidePainter();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _GuideLine());
}

class _GuideLine extends CustomPainter {
  const _GuideLine();

  @override
  void paint(Canvas canvas, Size size) {
    // Baseline sits ~70% down — leaves a comfortable signing band above it.
    final y = size.height * 0.70;
    const inset = AppTokens.xl;
    final line = Paint()
      ..color = const Color(0xFF1A1A1A).withValues(alpha: 0.22)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), line);

    // The "✕" anchor at the left of the line.
    final mark = TextPainter(
      text: const TextSpan(
        text: '✕',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0x551A1A1A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    mark.paint(canvas, Offset(inset, y - mark.height - 4));

    final hint = TextPainter(
      text: const TextSpan(
        text: 'Sign above the line',
        style: TextStyle(fontSize: 12, color: Color(0x551A1A1A)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hint.paint(canvas, Offset(inset, y + 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
