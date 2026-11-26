import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../auth/domain/auth_controller.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/meal_plan_repository.dart';
import '../domain/planning_providers.dart';

/// Slot key holding who cooks a day's dinner: a user id, `together` or `none`.
String dinnerCookKey(int weekdayIndex) =>
    '${mealSlotKey(weekdayIndex, MealSlot.dinner)}_cook';

/// "You cook" / "Naziha cooks" / "Cook together" / "No cooking".
String? cookLabel(String? cook, {String? self, required String spouseName}) =>
    switch (cook) {
      null || '' => null,
      'together' => 'Cook together',
      'none' => 'No cooking',
      final id when id == self => 'You cook',
      _ => '$spouseName cooks',
    };

enum _When { morning, afternoon, afterMaghrib, afterIsha }

extension on _When {
  String get label => switch (this) {
    _When.morning => 'Morning',
    _When.afternoon => 'Afternoon',
    _When.afterMaghrib => 'After Maghrib',
    _When.afterIsha => 'After Isha',
  };
}

/// "New plan": title, day, time of day and who it's for. [week] defaults to
/// the seven days starting today.
Future<void> showNewPlanSheet(
  BuildContext context, {
  List<DateTime>? week,
  DateTime? day,
  String title = '',
}) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return showLovSheet<void>(
    context,
    title: 'New plan',
    builder: (_) => _NewPlanForm(
      week: week ?? [for (var i = 0; i < 7; i++) today.add(Duration(days: i))],
      initialDay: day ?? today,
      initialTitle: title,
    ),
  );
}

class _NewPlanForm extends ConsumerStatefulWidget {
  const _NewPlanForm({
    required this.week,
    required this.initialDay,
    required this.initialTitle,
  });
  final List<DateTime> week;
  final DateTime initialDay;
  final String initialTitle;

  @override
  ConsumerState<_NewPlanForm> createState() => _NewPlanFormState();
}

class _NewPlanFormState extends ConsumerState<_NewPlanForm> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late DateTime _day = widget.initialDay;
  _When _when = _When.afterMaghrib;
  int _who = 0; // 0 together, 1 you, 2 spouse
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// The chosen slot as a local time on [_day]. Maghrib/Isha come from today's
  /// times (they move only minutes across a week), with a fallback when no
  /// location is set.
  DateTime _startsAt() {
    final times = ref.read(ownPrayerTimesProvider);
    DateTime after(Prayer p, int h, int m) {
      final t = times?.where((s) => s.prayer == p).firstOrNull?.at;
      final at = t == null
          ? DateTime(_day.year, _day.month, _day.day, h, m)
          : DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);
      return at.add(const Duration(minutes: 15));
    }

    return switch (_when) {
      _When.morning => DateTime(_day.year, _day.month, _day.day, 9),
      _When.afternoon => DateTime(_day.year, _day.month, _day.day, 14),
      _When.afterMaghrib => after(Prayer.maghrib, 18, 15),
      _When.afterIsha => after(Prayer.isha, 20, 0),
    };
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final self = ref.read(authSessionProvider).asData?.value?.user.id;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    if (title.isEmpty || self == null || couple == null) return;
    setState(() => _busy = true);
    final spouseName =
        ref.read(spouseProfileProvider).asData?.value?.displayName ??
        'Your spouse';
    try {
      await ref
          .read(calendarRepositoryProvider)
          .create(
            coupleId: couple.id,
            userId: self,
            title: title,
            startsAt: _startsAt(),
            assigneeId: switch (_who) {
              1 => self,
              2 => couple.spouseOf(self),
              _ => null,
            },
          );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      // The sheet's own context dies on pop; the navigator's outlives it.
      final host = Navigator.of(context).context;
      Navigator.of(context).pop();
      if (!host.mounted) return;
      showLovToast(
        host,
        'Added to ${DateFormat.EEEE().format(_day)}. $spouseName can see it',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showLovToast(
        context,
        "Couldn't add the plan",
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Widget _chips<T>(List<T> values, T selected, String Function(T) label,
      void Function(T) pick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            showCheckmark: false,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => pick(v));
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Spouse';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What are you planning?'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 18),
          const LovEyebrow('Day'),
          const SizedBox(height: 8),
          _chips(widget.week, _day, (d) => DateFormat.E().format(d),
              (d) => _day = d),
          const SizedBox(height: 18),
          const LovEyebrow('When'),
          const SizedBox(height: 8),
          _chips(_When.values, _when, (w) => w.label, (w) => _when = w),
          const SizedBox(height: 18),
          const LovEyebrow('Who'),
          const SizedBox(height: 8),
          _chips([0, 1, 2], _who,
              (i) => ['Together', 'You', spouseName][i], (i) => _who = i),
          const SizedBox(height: 24),
          LovPrimaryButton(
            label: 'Add to the week',
            loading: _busy,
            onPressed: _title.text.trim().isEmpty || _busy ? null : _save,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// "Dinner for Wed": pick who cooks, then a recipe, a recent dinner, "Order
/// in", or type something new.
Future<void> showDinnerSheet(BuildContext context, {required DateTime day}) =>
    showLovSheet<void>(
      context,
      title: 'Dinner for ${DateFormat.EEEE().format(day)}',
      builder: (_) => _DinnerForm(day: day),
    );

class _DinnerForm extends ConsumerStatefulWidget {
  const _DinnerForm({required this.day});
  final DateTime day;

  @override
  ConsumerState<_DinnerForm> createState() => _DinnerFormState();
}

class _DinnerFormState extends ConsumerState<_DinnerForm> {
  final _custom = TextEditingController();
  String? _cook;
  bool _busy = false;

  int get _dayIndex => widget.day.weekday - 1;

  @override
  void initState() {
    super.initState();
    final plan = ref.read(viewedMealPlanProvider);
    _cook = plan?.slots[dinnerCookKey(_dayIndex)] ??
        ref.read(authSessionProvider).asData?.value?.user.id;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _pick(String meal) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    if (meal.trim().isEmpty || couple == null || _busy) return;
    setState(() => _busy = true);
    final repo = ref.read(mealPlanRepositoryProvider);
    try {
      await repo.setSlot(
        coupleId: couple.id,
        week: widget.day,
        slotKey: mealSlotKey(_dayIndex, MealSlot.dinner),
        value: meal,
      );
      await repo.setSlot(
        coupleId: couple.id,
        week: widget.day,
        slotKey: dinnerCookKey(_dayIndex),
        value: meal == 'Order in' ? 'none' : _cook,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      final host = Navigator.of(context).context;
      Navigator.of(context).pop();
      if (host.mounted) showLovToast(host, 'Dinner set: ${meal.trim()}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showLovToast(
        context,
        "Couldn't set dinner",
        icon: Icons.error_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final self = ref.watch(authSessionProvider).asData?.value?.user.id;
    final spouseId = self == null
        ? null
        : ref.watch(currentCoupleProvider).asData?.value?.spouseOf(self);
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Spouse';
    final recipes = ref.watch(recipesProvider).asData?.value ?? const [];
    // Recent dinners from every planned week, newest weeks first.
    final plans = [...ref.watch(mealPlansProvider).asData?.value ?? const []]
      ..sort((a, b) => b.weekStarting.compareTo(a.weekStarting));
    final options = <String>{
      for (final r in recipes.take(6)) r.title,
      for (final plan in plans)
        for (final e in plan.slots.entries)
          if (e.key.endsWith('_dinner')) e.value,
      'Order in',
    }.take(10).toList();
    final cooks = [?self, ?spouseId, 'together', 'none'];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LovEyebrow('Who cooks'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cooks)
                ChoiceChip(
                  label: Text(
                    cookLabel(c, self: self, spouseName: spouseName) ?? '',
                  ),
                  selected: _cook == c,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _cook = c);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (i, meal) in options.indexed)
            LovRise(
              delay: Duration(milliseconds: 25 * i),
              child: LovSheetRow(
                icon: meal == 'Order in'
                    ? Icons.delivery_dining_outlined
                    : Icons.restaurant_outlined,
                title: meal,
                onTap: _busy ? null : () => _pick(meal),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _custom,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Something else…',
              suffixIcon: IconButton(
                tooltip: 'Set dinner',
                icon: Icon(Icons.arrow_upward_rounded, color: p.accent),
                onPressed: () => _pick(_custom.text),
              ),
            ),
            onSubmitted: _pick,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
