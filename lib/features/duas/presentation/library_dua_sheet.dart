import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../auth/domain/auth_controller.dart';
import '../../chat/domain/chat_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/dua_library_repository.dart';
import '../domain/dua_providers.dart';
import '../domain/dua_share.dart';

Future<void> showLibraryDuaSheet(BuildContext context, LibraryDua dua) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LovRadius.lg)),
    ),
    builder: (_) => _LibraryDuaSheet(dua: dua),
  );
}

class _LibraryDuaSheet extends ConsumerStatefulWidget {
  const _LibraryDuaSheet({required this.dua});
  final LibraryDua dua;

  @override
  ConsumerState<_LibraryDuaSheet> createState() => _LibraryDuaSheetState();
}

class _LibraryDuaSheetState extends ConsumerState<_LibraryDuaSheet> {
  bool _busy = false;
  LibraryDua get dua => widget.dua;

  /// Runs [action] once at a time. The messenger and navigator are captured
  /// before any await so the SnackBar survives the sheet being popped.
  Future<void> _run(
    Future<bool> Function() action,
    String okMsg,
    String failMsg,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var ok = false;
    try {
      ok = await action();
    } catch (_) {}
    if (ok && navigator.mounted) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(ok ? okMsg : failMsg)));
    if (!ok && mounted) setState(() => _busy = false);
  }

  Future<void> _send() => _run(
    () async {
      final chat = await ref.read(chatServiceProvider.future);
      if (chat == null) return false;
      await chat.sendText(formatDuaForChat(dua));
      return true;
    },
    'Sent to your spouse',
    "Couldn't send — try again from chat",
  );

  Future<void> _add() {
    // Read up-front: ref is unusable once the sheet is dismissed.
    final coupleF = ref.read(currentCoupleProvider.future);
    final sessionF = ref.read(authSessionProvider.future);
    final repo = ref.read(duaRepositoryProvider);
    return _run(
      () async {
        final couple = await coupleF;
        final session = await sessionF;
        if (couple == null || session == null) return false;
        await repo.add(
          coupleId: couple.id,
          userId: session.user.id,
          title: dua.title,
          body: duaListBody(dua),
          visibility: 'shared',
        );
        return true;
      },
      'Added to your shared list',
      "Couldn't add — try again",
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LovSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dua.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.lg),
            Text(
              dua.arabic,
              textDirection: TextDirection.rtl,
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.8),
            ),
            if (dua.transliteration != null) ...[
              const SizedBox(height: LovSpace.md),
              Text(
                dua.transliteration!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: LovSpace.md),
            Text(dua.translation, style: theme.textTheme.bodyLarge),
            if (dua.reference != null) ...[
              const SizedBox(height: LovSpace.sm),
              Text(dua.reference!, style: theme.textTheme.labelMedium),
            ],
            if (dua.repeatCount > 1) ...[
              const SizedBox(height: LovSpace.sm),
              Text(
                'Repeat ${dua.repeatCount}×',
                style: theme.textTheme.labelMedium,
              ),
            ],
            if (dua.benefit != null) ...[
              const SizedBox(height: LovSpace.sm),
              Text(dua.benefit!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: LovSpace.lg),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: const Text('Send to spouse'),
            ),
            const SizedBox(height: LovSpace.sm),
            OutlinedButton(
              onPressed: _busy ? null : _add,
              child: const Text('Add to our list'),
            ),
          ],
        ),
      ),
    );
  }
}
