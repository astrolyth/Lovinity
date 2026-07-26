import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/gratitude_repository.dart';
import '../domain/gratitude_providers.dart';

class GratitudeScreen extends ConsumerStatefulWidget {
  const GratitudeScreen({super.key});

  @override
  ConsumerState<GratitudeScreen> createState() => _GratitudeScreenState();
}

class _GratitudeScreenState extends ConsumerState<GratitudeScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _revealNow = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(gratitudeRepositoryProvider).add(
            coupleId: couple.id,
            userId: session.user.id,
            body: text,
            revealToSpouse: _revealNow,
          );
      unawaited(LovHaptics.medium());
      _controller.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(gratitudeNotesProvider);
    final session = ref.watch(authSessionProvider).asData?.value;
    final myId = session?.user.id;

    return LovScaffold(
      title: 'Jar of good memories',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: notesAsync.when(
        loading: () => const Center(
          child: LovShimmerBox(height: 200, radius: LovRadius.lg),
        ),
        error: (e, _) => Center(
          child: Text('Could not load', style: theme.textTheme.bodyMedium),
        ),
        data: (notes) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LovEnter(
                child: LovCard(
                  variant: LovCardVariant.tonal,
                  padding: const EdgeInsets.all(LovSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'One thing you appreciated today',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: LovSpace.md),
                      TextField(
                        controller: _controller,
                        maxLines: 5,
                        minLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Small things count.',
                        ),
                      ),
                      const SizedBox(height: LovSpace.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _revealNow
                                  ? 'Reveal to your spouse now.'
                                  : 'Keep private for now.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Switch.adaptive(
                            value: _revealNow,
                            onChanged: (v) {
                              setState(() => _revealNow = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: LovSpace.sm),
                      LovButton(
                        label: 'Drop in the jar',
                        icon: Icons.favorite_outline_rounded,
                        onPressed: _submitting ? null : _submit,
                        loading: _submitting,
                        expand: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: LovSpace.xl),
              if (notes.isEmpty)
                LovEnter(
                  delay: const Duration(milliseconds: 100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: LovSpace.xxl),
                    child: Center(
                      child: Text(
                        'The jar is empty for now. Fill it together.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                )
              else
                LovStagger(
                  initialDelay: const Duration(milliseconds: 100),
                  stagger: const Duration(milliseconds: 40),
                  children: [
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: LovSpace.md),
                        child: _NoteTile(
                          note: n,
                          isOwn: n.authorId == myId,
                          onReveal: n.authorId == myId && !n.revealToSpouse
                              ? () => ref
                                  .read(gratitudeRepositoryProvider)
                                  .reveal(n.id)
                              : null,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: LovSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.isOwn, this.onReveal});
  final GratitudeNote note;
  final bool isOwn;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = !isOwn && !note.revealToSpouse;
    return LovCard(
      variant: LovCardVariant.plain,
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isOwn
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: LovSpace.sm),
              Text(
                isOwn ? 'From you' : 'From your spouse',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat.MMMd().format(note.createdAt),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: LovSpace.sm),
          hidden
              ? Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: LovSpace.xs),
                    Text(
                      'Kept for now.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              : Text(
                  note.body,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
          if (onReveal != null && !note.revealToSpouse) ...[
            const SizedBox(height: LovSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: LovButton(
                label: 'Reveal to your spouse',
                variant: LovButtonVariant.text,
                size: LovButtonSize.small,
                onPressed: onReveal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
