import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../data/letter_repository.dart';
import '../domain/letter_providers.dart';
import 'letter_composer_sheet.dart';

/// Letters written now, opened later.
class LettersScreen extends ConsumerWidget {
  const LettersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lettersAsync = ref.watch(lettersProvider);
    final sealed = ref.watch(sealedLettersProvider);
    final open = ref.watch(openedLettersProvider);
    final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();

    return LovScaffold(
      title: 'Letters',
      subtitle: const Text('Written now, opened later'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showLetterComposer(context, ref),
        child: const Icon(Icons.edit_outlined),
      ),
      child: lettersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child:
              Text('Could not load letters', style: theme.textTheme.bodyMedium),
        ),
        data: (_) {
          if (sealed.isEmpty && open.isEmpty) {
            return const LovEmpty(
              icon: Icons.mail_outline_rounded,
              title: 'No letters yet',
              description:
                  'Write something for an anniversary, a reunion, or an Eid '
                  'still ahead of you.',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
            children: [
              if (sealed.isNotEmpty) ...[
                const LovSectionHeader(
                  title: 'Sealed',
                  subtitle: 'Waiting for their day',
                ),
                for (final l in sealed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LovSpace.sm),
                    child: _SealedTile(letter: l, now: now),
                  ),
              ],
              if (open.isNotEmpty) ...[
                const LovSectionHeader(title: 'Opened'),
                for (final l in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LovSpace.sm),
                    child: _OpenedTile(letter: l),
                  ),
              ],
              const SizedBox(height: LovSpace.xxxl),
            ],
          );
        },
      ),
    );
  }
}

class _SealedTile extends ConsumerWidget {
  const _SealedTile({required this.letter, required this.now});

  final LetterSummary letter;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final until = letter.timeUntilUnlock(now);

    return LovCard(
      variant: LovCardVariant.plain,
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 20, color: theme.colorScheme.secondary),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opens ${DateFormat('d MMMM y').format(letter.unlockAt.toLocal())}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  _remaining(until),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Withdraw',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Withdraw this letter?'),
                  content: const Text(
                    'It will be deleted and cannot be recovered.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Keep'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Withdraw'),
                    ),
                  ],
                ),
              );
              if (confirmed ?? false) {
                await ref
                    .read(letterRepositoryProvider)
                    .withdraw(letter.id);
              }
            },
          ),
        ],
      ),
    );
  }

  String _remaining(Duration d) {
    if (d.inDays > 365) return 'in ${(d.inDays / 365).floor()} years';
    if (d.inDays > 30) return 'in ${(d.inDays / 30).floor()} months';
    if (d.inDays > 0) return 'in ${d.inDays} days';
    if (d.inHours > 0) return 'in ${d.inHours} hours';
    return 'opening soon';
  }
}

class _OpenedTile extends ConsumerStatefulWidget {
  const _OpenedTile({required this.letter});

  final LetterSummary letter;

  @override
  ConsumerState<_OpenedTile> createState() => _OpenedTileState();
}

class _OpenedTileState extends ConsumerState<_OpenedTile> {
  String? _body;
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selfId = ref.watch(
        authSessionProvider.select((s) => s.asData?.value?.user.id));
    final fromMe = widget.letter.authorId == selfId;

    return LovCard(
      variant: LovCardVariant.plain,
      onTap: _body == null ? _open : null,
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline_rounded,
                  size: 20, color: theme.colorScheme.secondary),
              const SizedBox(width: LovSpace.md),
              Expanded(
                child: Text(
                  fromMe ? 'You wrote this' : 'From your partner',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                DateFormat('d MMM y')
                    .format(widget.letter.unlockAt.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: LovSpace.md),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: LovSpace.md),
            Text(_error!, style: theme.textTheme.bodySmall),
          ],
          if (_body != null) ...[
            const SizedBox(height: LovSpace.md),
            Text(_body!, style: theme.textTheme.bodyMedium),
          ],
          if (_body == null && !_loading && _error == null) ...[
            const SizedBox(height: LovSpace.sm),
            Text(
              'Tap to open',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final key = await ref.read(ensureLetterKeyProvider.future);
      if (key == null) {
        setState(() {
          _loading = false;
          // Honest about the cause: this device has no key and could not get
          // one. Pretending the letter is corrupt would be misleading.
          _error = 'This device does not have the key for your letters yet. '
              'Open the app on your other device, or ask your partner to '
              'open Lovinity so the key can be shared again.';
        });
        return;
      }
      final body = await ref.read(letterRepositoryProvider).openBody(
            letterId: widget.letter.id,
            letterKey: key,
          );
      if (!mounted) return;
      if (body == null) {
        setState(() {
          _loading = false;
          _error = 'This letter is not available yet.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _body = body;
      });
      if (widget.letter.unlockedAt == null) {
        await ref.read(letterRepositoryProvider).markOpened(widget.letter.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this letter.';
      });
    }
  }
}
