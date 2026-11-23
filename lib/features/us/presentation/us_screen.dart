import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../care/domain/care_providers.dart';
import '../../dates/domain/date_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../lovemap/domain/lovemap_providers.dart';
import '../../pairing/domain/pairing_providers.dart';

/// "Us": the two of you, your love map, gentle care and date ideas.
/// Each card opens its full screen.
class UsScreen extends ConsumerWidget {
  const UsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final own = ref.watch(ownProfileProvider).asData?.value;
    final spouse = ref.watch(spouseProfileProvider).asData?.value;
    final couple = ref.watch(currentCoupleProvider).asData?.value;
    String first(String? n) => (n ?? '').trim().split(RegExp(r'\s+')).first;
    final a = first(own?.displayName), b = first(spouse?.displayName);
    final anniversary = couple?.anniversaryGreg;
    final married = anniversary == null
        ? null
        : DateTime.now().difference(anniversary).inDays;

    return LovPage(
      title: 'Us',
      action: LovIconButton(
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: () => context.push('/home/settings'),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: LovRise(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  SizedBox(
                    width: 112,
                    height: 64,
                    child: Stack(
                      children: [
                        LovAvatar(initial: a, size: 64),
                        Positioned(
                          left: 48,
                          child: LovAvatar(initial: b, size: 64, partner: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    [a, b].where((s) => s.isNotEmpty).join(' & '),
                    style: lovDisplay(context, size: 22),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    married == null
                        ? 'Your space of two'
                        : 'Married $married days · anniversary '
                              '${DateFormat('d MMM').format(anniversary!)}',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: LovRise(
            delay: Duration(milliseconds: 100),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _LoveMapCard(),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: LovRise(
            delay: Duration(milliseconds: 200),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _CareCard(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 8, 6),
            child: Row(
              children: [
                const Expanded(child: LovEyebrow('Date ideas')),
                TextButton(
                  onPressed: () => context.push('/home/dates'),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _DateStrip()),
      ],
    );
  }
}

class _LoveMapCard extends ConsumerWidget {
  const _LoveMapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final quizzes = ref.watch(loveMapQuizzesProvider).asData?.value ?? const [];
    final score = ref.watch(loveMapScoreProvider);
    final total = quizzes.length;
    final done = score.graded;
    final next = quizzes.length > done ? quizzes[done] : null;
    return LovSurface(
      onTap: () => context.push('/home/lovemap'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LovEyebrow(
                  total == 0 ? 'Love map' : 'Love map · $done of $total',
                ),
              ),
              SizedBox(
                width: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 4,
                    color: p.accent,
                    backgroundColor: p.line,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            next?.question ?? 'How well do you know each other?',
            style: lovDisplay(context, size: 19, height: 1.3),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (score.graded > 0)
                Text(
                  '${score.percent}% matched so far',
                  style: TextStyle(fontSize: 13, color: p.accentInk),
                ),
              const Spacer(),
              Text(
                next == null ? 'Open' : 'Answer',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.accent,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: p.accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _CareCard extends ConsumerWidget {
  const _CareCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final tips = ref.watch(careTipsProvider).asData?.value ?? const [];
    return LovSurface(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      onTap: () => context.push('/home/care'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LovEyebrow('Caring for each other today'),
          if (tips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Gentle tips appear here.',
                style: TextStyle(fontSize: 14, color: p.muted),
              ),
            ),
          for (final (i, t) in tips.take(2).indexed) ...[
            if (i > 0) Divider(height: 1, color: p.surface2),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.partnerSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.volunteer_activism_outlined,
                      size: 18,
                      color: p.partner,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateStrip extends ConsumerWidget {
  const _DateStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final ideas = ref.watch(dateIdeasProvider).asData?.value ?? const [];
    if (ideas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Date ideas are on their way.',
          style: TextStyle(fontSize: 14, color: p.muted),
        ),
      );
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ideas.length.clamp(0, 8),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final d = ideas[i];
          return SizedBox(
            width: 200,
            child: LovSurface(
              radius: 20,
              padding: const EdgeInsets.all(16),
              onTap: () => context.push('/home/dates'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.setting.name[0].toUpperCase()}${d.setting.name.substring(1)}'
                    ' · ${d.costBand}',
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      d.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Text(
                    'Plan it',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.accent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
