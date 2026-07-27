import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/daily_content_providers.dart';

class VerseReaderScreen extends ConsumerWidget {
  const VerseReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(dailyContentProvider);

    return LovScaffold(
      title: 'Verse',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: async.when(
        loading: () => const Center(
          child: LovShimmerBox(width: 240, height: 24, radius: LovRadius.sm),
        ),
        error: (e, _) => Center(
          child: Text('Could not load', style: theme.textTheme.bodyMedium),
        ),
        data: (content) {
          final v = content?.verse;
          if (v == null) {
            return Center(
              child: Text('No verse today', style: theme.textTheme.bodyMedium),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: LovSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LovEnter(
                  child: Text(
                    '${v.surahName} · ${v.surahNumber}:${v.ayahNumber}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: LovSpace.xxl),
                LovEnter(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    v.arabicText,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: LovTypography.arabicText(
                      fontSize: 32,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (v.transliteration != null) ...[
                  const SizedBox(height: LovSpace.lg),
                  LovEnter(
                    delay: const Duration(milliseconds: 160),
                    child: Text(
                      v.transliteration!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: LovSpace.xl),
                LovEnter(
                  delay: const Duration(milliseconds: 240),
                  child: Text(
                    v.translation,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      height: 1.55,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: LovSpace.xxl),
                LovEnter(
                  delay: const Duration(milliseconds: 320),
                  child: Text(
                    v.reference,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
