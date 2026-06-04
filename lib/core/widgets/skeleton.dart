import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_tokens.dart';

/// Shimmer placeholder primitives used while async content loads, so layout
/// never jumps from a bare spinner to populated content.
class Skeleton extends StatelessWidget {
  const Skeleton._({
    this.width,
    required this.height,
    required this.radius,
  });

  /// A rectangular block (e.g. an avatar, image, or button placeholder).
  factory Skeleton.box({double? width, double height = 16, double radius = 8}) =>
      Skeleton._(width: width, height: height, radius: radius);

  /// A single text-line placeholder.
  factory Skeleton.line({double? width}) =>
      Skeleton._(width: width, height: 12, radius: 6);

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHigh,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// A stack of shimmering row placeholders that mirror an [AppListTile]-style
/// list: a leading box plus two stacked text lines.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : AppTokens.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Skeleton.box(width: 44, height: 44, radius: AppTokens.rField),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 160),
                    const SizedBox(height: AppTokens.sm),
                    Skeleton.line(width: 100),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
