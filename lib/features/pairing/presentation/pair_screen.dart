import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/presentation/welcome_screen.dart' show LovEmblem;
import 'invite_tab.dart';
import 'join_tab.dart';

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(authSessionProvider).asData?.value?.user.email;

    return LovScaffold(
      padded: false,
      title: 'Your space of two',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) {
            if (v == 'logout') {
              ref.read(signOutProvider)();
            }
          },
          itemBuilder: (_) => [
            if (email != null)
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'Signed in as $email',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout_outlined, size: 18),
                  SizedBox(width: LovSpace.sm),
                  Text('Sign out'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: LovSpace.sm),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(height: 128, child: FittedBox(child: LovEmblem())),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              'Share a code with your spouse, or enter theirs. '
              'Only the two of you will be here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: context.lov.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.lov.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.lov.line),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: context.lov.line,
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: context.lov.text,
                unselectedLabelColor: context.lov.muted,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                tabs: const [
                  Tab(text: 'Invite'),
                  Tab(text: 'I have a code'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [InviteTab(), JoinTab()],
            ),
          ),
        ],
      ),
    );
  }
}
