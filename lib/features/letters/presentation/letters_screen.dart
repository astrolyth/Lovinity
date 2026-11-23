import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
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

    final selfId = ref.watch(
      authSessionProvider.select((s) => s.asData?.value?.user.id),
    );
    final next = sealed.isEmpty
        ? null
        : (sealed.toList()..sort((a, b) => a.unlockAt.compareTo(b.unlockAt)))
              .first;
    final rows = <Widget>[
      for (final l in sealed) _SealedTile(letter: l, now: now),
      for (final l in open) _OpenedTile(letter: l),
    ];
    return LovPage(
      title: 'Letters',
      slivers: [
        ...lettersAsync.when(
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Could not load letters',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          data: (_) => [
            if (next != null)
              SliverToBoxAdapter(
                child: LovRise(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _Featured(
                      letter: next,
                      now: now,
                      fromMe: next.authorId == selfId,
                    ),
                  ),
                ),
              ),
            if (rows.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: LovEmpty(
                    icon: Icons.mail_outline_rounded,
                    title: 'No letters yet',
                    description:
                        'Write something for an anniversary, a reunion, or an '
                        'Eid still ahead of you.',
                  ),
                ),
              )
            else ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 28, 20, 10),
                  child: LovEyebrow('Your letters'),
                ),
              ),
              SliverToBoxAdapter(
                child: LovRise(
                  delay: const Duration(milliseconds: 100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LovSurface(
                      padding: EdgeInsets.zero,
                      clip: true,
                      child: Column(
                        children: [
                          for (final (i, r) in rows.indexed) ...[
                            if (i > 0)
                              Divider(height: 1, color: context.lov.surface2),
                            r,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  children: [
                    LovPrimaryButton(
                      label: 'Write a letter',
                      icon: Icons.edit_outlined,
                      onPressed: () => showLetterComposer(context, ref),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Send now, or seal it for a day still ahead of you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.lov.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The next letter to open, as a sealed envelope with a countdown.
class _Featured extends StatelessWidget {
  const _Featured({
    required this.letter,
    required this.now,
    required this.fromMe,
  });
  final LetterSummary letter;
  final DateTime now;
  final bool fromMe;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final until = letter.timeUntilUnlock(now);
    Widget stat(String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        child: Column(
          children: [
            Text(v, style: lovDisplay(context, size: 26)),
            Text(l, style: TextStyle(fontSize: 11, color: p.muted)),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Container(
          height: 200,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.surface2, p.surface],
            ),
            border: Border.all(color: p.line),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _Flap(p.line2))),
              Align(
                alignment: const Alignment(0, -.15),
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [p.accentHi, p.accent, p.accentLo],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: p.accent.withValues(alpha: .5),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    'م',
                    style: lovArabic(
                      context,
                      size: 24,
                      color: p.onAccent,
                    ).copyWith(height: 1.2),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Column(
                  children: [
                    Text(
                      fromMe ? 'From you' : 'From your spouse',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Opens ${DateFormat('d MMMM y').format(letter.unlockAt.toLocal())}',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            stat('${until.inDays}', 'days'),
            const SizedBox(width: 8),
            stat('${until.inHours % 24}', 'hours'),
            const SizedBox(width: 8),
            stat(
              DateFormat('d MMM').format(letter.unlockAt.toLocal()),
              'opens',
            ),
          ],
        ),
      ],
    );
  }
}

/// The envelope's closed flap.
class _Flap extends CustomPainter {
  _Flap(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height * .48)
        ..lineTo(size.width, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Flap old) => old.color != color;
}

class _SealedTile extends ConsumerWidget {
  const _SealedTile({required this.letter, required this.now});

  final LetterSummary letter;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final until = letter.timeUntilUnlock(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: theme.colorScheme.secondary,
          ),
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
                await ref.read(letterRepositoryProvider).withdraw(letter.id);
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
      authSessionProvider.select((s) => s.asData?.value?.user.id),
    );
    final fromMe = widget.letter.authorId == selfId;

    return InkWell(
      onTap: _body == null ? _open : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.mail_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: LovSpace.md),
                Expanded(
                  child: Text(
                    fromMe ? 'You wrote this' : 'From your partner',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  DateFormat(
                    'd MMM y',
                  ).format(widget.letter.unlockAt.toLocal()),
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
          _error =
              'This device does not have the key for your letters yet. '
              'Open the app on your other device, or ask your partner to '
              'open Lovinity so the key can be shared again.';
        });
        return;
      }
      final body = await ref
          .read(letterRepositoryProvider)
          .openBody(letterId: widget.letter.id, letterKey: key);
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
