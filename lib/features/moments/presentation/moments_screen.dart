import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../wall/domain/wall_providers.dart';
import '../domain/moment.dart';
import '../domain/moments_providers.dart';

/// The Moments tab: today's two shots side by side (theirs stays veiled
/// until you share yours), this week as paired days, and past days.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final list = ref.watch(momentsProvider);
    final self = ref.watch(wallSelfIdProvider) ?? '';
    final spouse = ref.watch(wallSpouseNameProvider) ?? 'Your spouse';
    final now = DateTime.now();
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Padding(
                padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LovEyebrow(DateFormat('EEEE d MMMM').format(now)),
                    const SizedBox(height: 4),
                    Text('Moments', style: lovDisplay(context, size: 30)),
                    const Spacer(),
                    Center(
                      child: TextButton(
                        onPressed: () => ref.invalidate(momentsProvider),
                        child: const Text(
                          "Couldn't load moments — tap to retry",
                        ),
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
              data: (all) {
                final days = groupByDay(all);
                final today = vlogDay(now);
                final todays = days
                    .where((d) => d.$1 == today)
                    .expand((d) => d.$2)
                    .toList();
                final hers = todays
                    .where((m) => m.senderId != self)
                    .firstOrNull;
                final mine = todays
                    .where((m) => m.senderId == self)
                    .firstOrNull;
                final locked = mine == null;
                final week = [
                  for (var i = 6; i >= 0; i--)
                    today.subtract(Duration(days: i)),
                ];
                List<Moment> on(DateTime d) =>
                    days.where((x) => x.$1 == d).expand((x) => x.$2).toList();
                final both = week
                    .where(
                      (d) =>
                          on(d).any((m) => m.senderId == self) &&
                          on(d).any((m) => m.senderId != self),
                    )
                    .length;

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LovEyebrow(
                                    DateFormat('EEEE d MMMM').format(now),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Moments',
                                    style: lovDisplay(context, size: 30),
                                  ),
                                ],
                              ),
                            ),
                            LovIconButton(
                              icon: Icons.history_rounded,
                              label: 'Past moments',
                              onTap: () => _openArchive(context, days, self),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: LovRise(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Text(
                            'Live updates for each other, camera only. '
                            "$spouse's stays hidden until you share yours.",
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: p.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: LovRise(
                        delay: const Duration(milliseconds: 100),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _Shot(
                                  moment: hers,
                                  locked: locked,
                                  name: spouse,
                                  partner: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Shot(
                                  moment: mine,
                                  locked: false,
                                  name: 'You',
                                  partner: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!locked && hers?.caption != null)
                      SliverToBoxAdapter(
                        child: LovRise(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: LovSurface(
                              radius: 18,
                              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '"${hers!.caption}"',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        context.push('/moments/${hers.id}'),
                                    child: const Text('Reply'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: LovSectionLabel(
                        'This week',
                        padding: const EdgeInsets.fromLTRB(20, 28, 8, 12),
                        trailing: TextButton.icon(
                          onPressed: todays.isEmpty && days.isEmpty
                              ? null
                              : () => _playDay(
                                  context,
                                  todays.isNotEmpty ? today : days.first.$1,
                                ),
                          icon: const Icon(
                            Icons.play_circle_outline_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Play as vlog',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 84,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: week.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final d = week[i];
                            final items = on(d);
                            return _DayPair(
                              label: d == today
                                  ? 'Today'
                                  : DateFormat.E().format(d),
                              today: d == today,
                              mine: items
                                  .where((m) => m.senderId == self)
                                  .firstOrNull,
                              hers: items
                                  .where((m) => m.senderId != self)
                                  .firstOrNull,
                              onTap: items.isEmpty
                                  ? null
                                  : () => _playDay(context, d),
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Text(
                          both == 1
                              ? '1 of 7 days together this week.'
                              : '$both of 7 days together this week.',
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                      ),
                    ),
                    // Clears the floating tab bar.
                    const SliverToBoxAdapter(child: SizedBox(height: 112)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _playDay(BuildContext context, DateTime day) =>
    context.push('/moments/vlog/${DateFormat('yyyy-MM-dd').format(day)}');

void _openArchive(
  BuildContext context,
  List<(DateTime, List<Moment>)> days,
  String self,
) {
  final together = days
      .where(
        (d) =>
            d.$2.any((m) => m.senderId == self) &&
            d.$2.any((m) => m.senderId != self),
      )
      .length;
  showLovSheet<void>(
    context,
    title: 'Past moments',
    subtitle: days.isEmpty
        ? 'Your shared days will collect here.'
        : 'Every day you shared. $together together.',
    builder: (sheet) => GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3 / 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6),
      children: [
        for (final (i, (day, items)) in days.indexed)
          LovRise(
            delay: Duration(milliseconds: 30 * i),
            offset: const Offset(0, 12),
            child: _ArchiveTile(
              day: day,
              preview: items.firstOrNull?.previewPath,
              onTap: () {
                Navigator.pop(sheet);
                _playDay(context, day);
              },
            ),
          ),
      ],
    ),
  );
}

/// One of today's two shots. Theirs is veiled until you've shared.
class _Shot extends StatelessWidget {
  const _Shot({
    required this.moment,
    required this.locked,
    required this.name,
    required this.partner,
  });
  final Moment? moment;
  final bool locked;
  final String name;
  final bool partner;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final m = moment;
    final time = m == null ? '' : DateFormat.jm().format(m.createdAt);
    Widget body;
    if (m == null && !partner) {
      body = _Capture(onTap: () => context.push('/moments/camera'));
    } else if (m == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Nothing from $name yet today',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ),
      );
    } else {
      final preview = m.previewPath;
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (preview != null)
            AnimatedScale(
              scale: locked ? 1.15 : 1,
              duration: const Duration(milliseconds: 700),
              curve: const Cubic(.16, 1, .3, 1),
              child: ImageFiltered(
                enabled: locked,
                imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: _SignedImage(path: preview),
              ),
            ),
          if (locked)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 22),
                  const SizedBox(height: 8),
                  Text(
                    '$name posted at $time',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 10,
            bottom: 10,
            child: _Tag(
              initial: partner ? name : 'Y',
              label: partner ? name : 'You · $time',
              partner: partner,
            ),
          ),
          if (m.isVideo && !locked)
            const Positioned(
              right: 10,
              top: 10,
              child: Icon(
                Icons.videocam_rounded,
                color: Colors.white,
                size: 18,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
        ],
      );
    }
    final canOpen = m != null && !locked;
    return Semantics(
      button: canOpen,
      label: m == null
          ? (partner ? 'Nothing from $name yet today' : 'Take yours')
          : locked
          ? "$name's moment, hidden until you post yours"
          : "${partner ? name : 'Your'} moment at $time",
      excludeSemantics: true,
      child: LovPressable(
        onTap: canOpen ? () => context.push('/moments/${m.id}') : null,
        child: Container(
          height: 260,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(24),
            border: m == null && !partner ? null : Border.all(color: p.line),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(p.line2, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: p.accentSoft, spreadRadius: 6)],
              ),
              child: Icon(
                Icons.photo_camera_outlined,
                color: p.onAccent,
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Take yours',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final metric in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.initial,
    required this.label,
    required this.partner,
  });
  final String initial;
  final String label;
  final bool partner;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return LovGlass(
      borderRadius: BorderRadius.circular(999),
      blur: 10,
      color: p.bg.withValues(alpha: .6),
      border: Border.all(color: Colors.transparent, width: 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: partner ? p.partner : p.accent,
              ),
              child: Text(
                initial.characters.first.toUpperCase(),
                style: lovDisplay(
                  context,
                  size: 10,
                  weight: FontWeight.w600,
                  color: partner ? p.onPartner : p.onAccent,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// One day this week: your shot and theirs as two slim halves.
class _DayPair extends StatelessWidget {
  const _DayPair({
    required this.label,
    required this.today,
    required this.mine,
    required this.hers,
    required this.onTap,
  });
  final String label;
  final bool today;
  final Moment? mine;
  final Moment? hers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    Widget half(Moment? m, Color empty) => Expanded(
      child: m?.previewPath == null
          ? ColoredBox(color: m == null ? empty : empty.withValues(alpha: .6))
          : _SignedImage(path: m!.previewPath!),
    );
    return Semantics(
      button: onTap != null,
      label:
          '$label: ${mine == null ? 'no moment from you' : 'you shared'}, '
          '${hers == null ? 'none from your spouse' : 'your spouse shared'}',
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 44,
              height: 58,
              padding: today ? const EdgeInsets.all(2) : EdgeInsets.zero,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(today ? 14 : 12),
                border: today ? Border.all(color: p.text, width: 1.5) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(today ? 10 : 12),
                child: Row(
                  children: [
                    half(mine, p.surface2),
                    const SizedBox(width: 2),
                    half(hers, p.partnerSoft),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: today ? p.text : p.muted,
                fontWeight: today ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.day,
    required this.preview,
    required this.onTap,
  });
  final DateTime day;
  final String? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final today = vlogDay(DateTime.now());
    final label = day == today
        ? 'Today'
        : today.difference(day).inDays < 7
        ? DateFormat.E().format(day)
        : DateFormat('d MMM').format(day);
    return Semantics(
      button: true,
      label: 'Play $label',
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                _SignedImage(path: preview!)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.accent, p.accent, p.partner, p.partner],
                      stops: const [0, .5, .5, 1],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.shadow.withValues(alpha: 0),
                      p.shadow.withValues(alpha: .55),
                    ],
                    stops: const [.4, 1],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 7,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedImage extends ConsumerWidget {
  const _SignedImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ColoredBox(color: context.lov.surface2);
    return ref
        .watch(momentSignedUrlProvider(path))
        .when(
          data: (u) => Image.network(
            u,
            fit: BoxFit.cover,
            cacheWidth: 480,
            errorBuilder: (_, _, _) => placeholder,
          ),
          loading: () => placeholder,
          error: (_, _) => placeholder,
        );
  }
}
