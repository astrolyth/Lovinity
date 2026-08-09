import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/time/tz_sync.dart';
import '../../../core/widgets/widgets.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../../calendar/presentation/calendar_card.dart';
import '../../chat/domain/chat_providers.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../daily/domain/question_providers.dart';
import '../../daily/presentation/question_card.dart';
import '../../daily/presentation/verse_card.dart';
import '../../duas/domain/dua_providers.dart';
import '../../duas/presentation/dua_card.dart';
import '../../gratitude/domain/gratitude_providers.dart';
import '../../gratitude/presentation/gratitude_card.dart';
import '../../location/data/location_service.dart';
import '../../location/domain/location_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../planning/domain/planning_providers.dart';
import '../../planning/presentation/planning_card.dart';
import '../../prayer_log/domain/prayer_log_providers.dart';
import '../../prayer_log/presentation/prayer_log_card.dart';
import '../../scoring/presentation/scoreboard_card.dart';
import '../domain/home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mounted here (the always-present authed screen) rather than only in
    // ChatScreen so a push that wakes the app syncs + decrypts new messages
    // and updates the unread badge even while chat isn't open. Both are
    // plain (non-autoDispose) `Provider<void>`s, so watching them from
    // multiple widgets (here and chat_screen.dart) resolves to the same
    // single underlying subscription -- no double pump.
    ref.watch(inboxPumpProvider);
    ref.watch(receiptPumpProvider);
    ref.watch(pairingNotificationPumpProvider);
    ref.watch(prayerNotificationPumpProvider);
    ref.watch(cycleNotificationPumpProvider);
    ref.watch(questionNotificationPumpProvider);
    ref.watch(duaNotificationPumpProvider);
    ref.watch(gratitudeNotificationPumpProvider);
    ref.watch(calendarNotificationPumpProvider);
    ref.watch(groceryNotificationPumpProvider);

    // Publishes this device's IANA zone to `users.timezone` when it changes,
    // so the spouse's device can anchor this user's prayer day (and dual
    // clock) to the right place. Watched here for the same reason as the
    // pumps: it must run for the whole authed session, not only while the
    // prayer log is open.
    ref.watch(timezonePublishProvider);

    final theme = Theme.of(context);
    final own = ref.watch(ownProfileProvider);
    final spouse = ref.watch(spouseProfileProvider);
    final couple = ref.watch(currentCoupleProvider);
    final nextPrayer = ref.watch(nextPrayerProvider);
    // Derive from the profile already watched above rather than watching the
    // separate isWifeProvider — watching both the async profile and a sync
    // provider derived from it in one build re-enters and throws
    // "setState during build".
    final isWife = own.asData?.value?.gender == 'female';
    final locationState = ref.watch(locationControllerProvider);

    // Surface a location-capture failure as a snackbar.
    ref.listen(locationControllerProvider, (prev, next) {
      final err = next.error;
      if (next.hasError && err is LocationFailure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(err.userMessage)));
      }
    });

    final now = DateTime.now();
    final greeting = greetingForHour(now.hour);
    final ownName = own.asData?.value?.displayName;
    final spouseName = spouse.asData?.value?.displayName;
    final profileReady = own.hasValue;

    return LovScaffold(
      padded: false,
      showAppBar: false,
      floatingActionButton: const _ChatFab(),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LovSpace.lg,
                LovSpace.md,
                LovSpace.lg,
                LovSpace.md,
              ),
              sliver: SliverToBoxAdapter(
                child: LovEnter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TodayCrescent(
                        size: 20,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: LovSpace.sm),
                      Expanded(child: HijriDate(date: now)),
                      _NotificationBell(),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Settings',
                        onPressed: () => context.go('/home/settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: LovSpace.lg),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: LovSpace.sm),
                  child: profileReady
                      ? _Greeting(
                          greeting: greeting,
                          name: ownName ?? '',
                          spouseName: spouseName,
                        )
                      : const _GreetingSkeleton(),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: LovSpace.xxl),
            ),

            // Next prayer card
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: LovSpace.lg),
              sliver: SliverToBoxAdapter(
                child: LovEnter(
                  delay: const Duration(milliseconds: 380),
                  child: profileReady
                      ? _NextPrayerCard(
                          next: nextPrayer,
                          hasLocation:
                              own.asData?.value?.latitude != null &&
                                  own.asData?.value?.longitude != null,
                          busy: locationState.isLoading,
                          onSetLocation: () => ref
                              .read(locationControllerProvider.notifier)
                              .captureAndSave(),
                        )
                      : const _NextPrayerSkeleton(),
                ),
              ),
            ),

            // Feature cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LovSpace.lg,
                LovSpace.xl,
                LovSpace.lg,
                LovSpace.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  LovStagger(
                    initialDelay: const Duration(milliseconds: 460),
                    stagger: const Duration(milliseconds: 90),
                    slideFrom: 16,
                    children: [
                      const PrayerLogCard(),
                      const SizedBox(height: LovSpace.md),
                      const ScoreboardCard(),
                      const SizedBox(height: LovSpace.md),
                      if (isWife) ...[
                        const _CycleTile(),
                        const SizedBox(height: LovSpace.md),
                      ],
                      _CareTile(isWife: isWife),
                      const SizedBox(height: LovSpace.md),
                      const VerseCard(),
                      const SizedBox(height: LovSpace.md),
                      const QuestionCard(),
                      const SizedBox(height: LovSpace.md),
                      const GratitudeCard(),
                      const SizedBox(height: LovSpace.md),
                      const CalendarCard(),
                      const SizedBox(height: LovSpace.md),
                      const PlanningCard(),
                      const SizedBox(height: LovSpace.md),
                      const DuaCard(),
                    ],
                  ),
                  const SizedBox(height: LovSpace.xxxl),
                ]),
              ),
            ),

            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: LovSpace.xxl),
                  child: LovEnter(
                    delay: const Duration(milliseconds: 900),
                    child: Text(
                      couple.asData?.value == null
                          ? 'Getting things ready…'
                          : 'Together, today.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.greeting,
    required this.name,
    this.spouseName,
  });

  final String greeting;
  final String name;
  final String? spouseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LovEnter(
          delay: const Duration(milliseconds: 120),
          child: Text(
            '$greeting,',
            style: theme.textTheme.displayLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        LovEnter(
          delay: const Duration(milliseconds: 260),
          slideFrom: 16,
          child: Text(
            name.isEmpty ? '' : '$name.',
            style: theme.textTheme.displayLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (spouseName != null && spouseName!.isNotEmpty) ...[
          const SizedBox(height: LovSpace.sm),
          LovEnter(
            delay: const Duration(milliseconds: 380),
            child: Text(
              'You and $spouseName, together.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GreetingSkeleton extends StatelessWidget {
  const _GreetingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LovShimmerBox(width: 180, height: 42, radius: LovRadius.sm),
        SizedBox(height: LovSpace.sm),
        LovShimmerBox(width: 240, height: 42, radius: LovRadius.sm),
        SizedBox(height: LovSpace.md),
        LovShimmerBox(width: 200, height: 16, radius: LovRadius.xs),
      ],
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({
    required this.next,
    required this.hasLocation,
    this.busy = false,
    this.onSetLocation,
  });

  final ScheduledPrayer? next;
  final bool hasLocation;
  final bool busy;
  final VoidCallback? onSetLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!hasLocation) {
      return LovCard(
        variant: LovCardVariant.tonal,
        onTap: busy ? null : onSetLocation,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(LovRadius.md),
              ),
              child: Icon(
                Icons.place_outlined,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: LovSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set your location',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    busy
                        ? 'Getting your location…'
                        : 'So we can show your next prayer time.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.chevron_right,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
          ],
        ),
      );
    }

    final label = nextPrayerLabel(next);
    final name = next?.prayer.displayName ?? '';

    return LovBreathing(
      child: Container(
        padding: const EdgeInsets.all(LovSpace.xl),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(LovRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next prayer',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.7),
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: LovSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedSwitcher(
                  duration: LovMotion.gentle,
                  switchInCurve: LovMotion.enter,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    name,
                    key: ValueKey(name),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: LovSpace.md),
                Expanded(
                  child: Text(
                    label.replaceFirst('$name ', ''),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary.withValues(alpha: 0.8),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: LovSpace.lg),
              AnimatedSwitcher(
                duration: LovMotion.slow,
                child: Text(
                  _arabicNameFor(name),
                  key: ValueKey('ar_$name'),
                  style: LovTypography.arabicText(
                    fontSize: 22,
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _arabicNameFor(String english) => switch (english.toLowerCase()) {
        'fajr' => 'ٱلْفَجْر',
        'dhuhr' => 'ٱلظُّهْر',
        'asr' => 'ٱلْعَصْر',
        'maghrib' => 'ٱلْمَغْرِب',
        'isha' => 'ٱلْعِشَاء',
        _ => '',
      };
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final button = IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: 'Notifications',
      onPressed: () => context.go('/home/notifications'),
    );
    if (count <= 0) return button;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      offset: const Offset(-6, 6),
      child: button,
    );
  }
}

/// Messenger-style floating chat button with a live unread-message badge.
class _ChatFab extends ConsumerWidget {
  const _ChatFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadChatCountProvider).asData?.value ?? 0;
    final fab = FloatingActionButton(
      heroTag: 'chat-fab',
      tooltip: 'Chat',
      onPressed: () => context.go('/home/chat'),
      child: const Icon(Icons.chat_bubble_rounded),
    );
    if (count <= 0) return fab;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      offset: const Offset(-6, 6),
      child: fab,
    );
  }
}

class _CycleTile extends StatelessWidget {
  const _CycleTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LovCard(
      variant: LovCardVariant.tonal,
      onTap: () => context.go('/home/cycle'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(LovRadius.md),
            ),
            child: Icon(
              Icons.favorite_border,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cycle', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Track your cycle and see predictions.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _CareTile extends StatelessWidget {
  const _CareTile({required this.isWife});

  final bool isWife;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = isWife ? 'Caring for you' : 'Caring for her';
    return LovCard(
      variant: LovCardVariant.tonal,
      onTap: () => context.go('/home/care'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(LovRadius.md),
            ),
            child: Icon(
              Icons.spa_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Guidance and gentle tips.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _NextPrayerSkeleton extends StatelessWidget {
  const _NextPrayerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LovSpace.xl),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LovRadius.lg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LovShimmerBox(width: 100, height: 12, radius: LovRadius.xs),
          SizedBox(height: LovSpace.lg),
          LovShimmerBox(width: 200, height: 28, radius: LovRadius.sm),
          SizedBox(height: LovSpace.lg),
          LovShimmerBox(width: 80, height: 22, radius: LovRadius.xs),
        ],
      ),
    );
  }
}
