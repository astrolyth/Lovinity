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

class _LibraryDuaSheet extends ConsumerWidget {
  const _LibraryDuaSheet({required this.dua});
  final LibraryDua dua;

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    var ok = false;
    try {
      final chat = await ref.read(chatServiceProvider.future);
      if (chat != null) {
        await chat.sendText(formatDuaForChat(dua));
        ok = true;
      }
    } catch (_) {}
    if (context.mounted) {
      _snack(
        context,
        ok ? 'Sent to your spouse' : "Couldn't send — try again from chat",
      );
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    var ok = false;
    try {
      final couple = await ref.read(currentCoupleProvider.future);
      final session = await ref.read(authSessionProvider.future);
      if (couple != null && session != null) {
        await ref
            .read(duaRepositoryProvider)
            .add(
              coupleId: couple.id,
              userId: session.user.id,
              title: dua.title,
              body: duaListBody(dua),
              visibility: 'shared',
            );
        ok = true;
      }
    } catch (_) {}
    if (context.mounted) {
      _snack(
        context,
        ok ? 'Added to your shared list' : "Couldn't add — try again",
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onPressed: () => _send(context, ref),
              child: const Text('Send to spouse'),
            ),
            const SizedBox(height: LovSpace.sm),
            OutlinedButton(
              onPressed: () => _add(context, ref),
              child: const Text('Add to our list'),
            ),
          ],
        ),
      ),
    );
  }
}
