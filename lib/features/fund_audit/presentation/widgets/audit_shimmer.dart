import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_tokens.dart';

/// A single shimmering rounded block, themed off the surface containers so the
/// loading state never jumps against the real layout that replaces it.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.radius = AppTokens.rField,
  });

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerLow,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Skeleton list used by the history screen while audits stream in. Mirrors the
/// real tile metrics (date + chip + amounts) so there's no reflow on load.
class AuditListSkeleton extends StatelessWidget {
  const AuditListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.lg),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: AppTokens.md),
      itemBuilder: (_, _) => const _SkeletonTile(),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerBox(height: 16, width: 120),
              ShimmerBox(height: 26, width: 96, radius: AppTokens.rPill),
            ],
          ),
          SizedBox(height: AppTokens.md),
          ShimmerBox(height: 14, width: 180),
          SizedBox(height: AppTokens.sm),
          ShimmerBox(height: 14, width: 140),
        ],
      ),
    );
  }
}
