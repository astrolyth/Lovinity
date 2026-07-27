import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
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
    final email = ref
        .watch(authSessionProvider)
        .asData
        ?.value
        ?.user
        .email;

    return LovScaffold(
      padded: false,
      title: 'Lovinity',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LovSpace.lg,
              LovSpace.xl,
              LovSpace.lg,
              LovSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A space of two',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: LovSpace.xs),
                Text(
                  'Share a code with your spouse, or enter theirs. Only the two of you will be here.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LovSpace.lg),
            child: Container(
              padding: const EdgeInsets.all(LovSpace.xs),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(LovRadius.pill),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(LovRadius.pill),
                  boxShadow: LovElevation.subtle,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: theme.colorScheme.onSurface,
                unselectedLabelColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.55),
                labelStyle: theme.textTheme.labelLarge,
                unselectedLabelStyle: theme.textTheme.labelLarge,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
                tabs: const [
                  Tab(text: 'Invite'),
                  Tab(text: 'Join'),
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
