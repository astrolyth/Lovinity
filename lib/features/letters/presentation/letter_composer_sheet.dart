import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/letter_providers.dart';

Future<void> showLetterComposer(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _LetterComposerSheet(),
  );
}

class _LetterComposerSheet extends ConsumerStatefulWidget {
  const _LetterComposerSheet();

  @override
  ConsumerState<_LetterComposerSheet> createState() =>
      _LetterComposerSheetState();
}

class _LetterComposerSheetState extends ConsumerState<_LetterComposerSheet> {
  final _body = TextEditingController();
  DateTime _unlockAt = DateTime.now().add(const Duration(days: 365));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: LovSpace.lg,
        right: LovSpace.lg,
        top: LovSpace.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + LovSpace.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('A letter for later', style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.xs),
            Text(
              'Sealed until the day you choose. Neither of you can read it '
              'before then.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LovSpace.lg),
            TextField(
              controller: _body,
              autofocus: true,
              maxLines: 10,
              minLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What do you want them to read that day?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: LovSpace.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(DateFormat('EEEE, d MMMM y').format(_unlockAt)),
              subtitle: const Text('Opens on this day'),
              onTap: _pickDate,
            ),
            if (_error != null) ...[
              const SizedBox(height: LovSpace.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: LovSpace.xl),
            LovButton(
              label: 'Seal it',
              loading: _saving,
              expand: true,
              onPressed: _seal,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _unlockAt,
      // Tomorrow at the earliest: a letter that unlocks today is just a
      // message, and the database constraint rejects it anyway.
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 50)),
    );
    if (picked != null) setState(() => _unlockAt = picked);
  }

  Future<void> _seal() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write something first.');
      return;
    }
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Refuse to seal without a key both devices share. A letter encrypted
      // under a key the recipient will never hold is worse than no letter: it
      // looks written and arrives unreadable, years later, with no way to
      // recover it.
      final key = await ref.read(ensureLetterKeyProvider.future);
      if (key == null) {
        setState(() {
          _saving = false;
          _error = 'Your devices could not agree on a key for letters yet. '
              'Make sure you are both online and try again.';
        });
        return;
      }

      await ref.read(letterRepositoryProvider).seal(
            coupleId: couple.id,
            authorId: session.user.id,
            body: body,
            unlockAt: _unlockAt,
            letterKey: key,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not seal the letter.';
      });
    }
  }
}
