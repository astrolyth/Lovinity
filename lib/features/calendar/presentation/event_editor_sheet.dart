import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/time/hijri_dates.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_providers.dart';

/// Opens the create/edit sheet. Pass [existing] to edit, [initialDate] to
/// pre-fill a new event with the day the user tapped.
Future<void> showEventEditor(
  BuildContext context,
  WidgetRef ref, {
  CalendarEvent? existing,
  DateTime? initialDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EventEditorSheet(
      existing: existing,
      initialDate: initialDate,
    ),
  );
}

class _EventEditorSheet extends ConsumerStatefulWidget {
  const _EventEditorSheet({this.existing, this.initialDate});

  final CalendarEvent? existing;
  final DateTime? initialDate;

  @override
  ConsumerState<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<_EventEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late DateTime _date;
  TimeOfDay? _time;
  late bool _allDay;
  late bool _repeatsYearly;
  late bool _hijriAnchored;
  late CalendarEventKind _kind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _date = e?.date ?? widget.initialDate ?? DateTime.now();
    _allDay = e?.allDay ?? true;
    _time = e == null || e.allDay
        ? null
        : TimeOfDay.fromDateTime(e.startsAt.toLocal());
    _hijriAnchored = e?.hijriAnchor != null;
    _repeatsYearly = e?.recurrence?.toUpperCase().contains('YEARLY') ?? false;
    _kind = e?.kind ?? CalendarEventKind.event;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hijri = hijriFromGregorian(_date);
    final isEditing = widget.existing != null;

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
            Text(
              isEditing ? 'Edit event' : 'New event',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: LovSpace.lg),
            TextField(
              controller: _title,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Our nikah anniversary',
              ),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
            ),
            const SizedBox(height: LovSpace.lg),

            // Date — always shown in both calendars, so an event anchored to
            // one is never ambiguous about where it lands in the other.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(DateFormat('EEEE, d MMMM y').format(_date)),
              subtitle: Text(formatHijri(hijri)),
              onTap: _pickDate,
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
              title: const Text('All day'),
              subtitle: const Text(
                'All-day events show on the same date for both of you, '
                'whatever timezone each of you is in.',
              ),
            ),

            if (!_allDay)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(_time == null
                    ? 'Pick a time'
                    : _time!.format(context)),
                onTap: _pickTime,
              ),

            const SizedBox(height: LovSpace.sm),
            Text('Kind', style: theme.textTheme.labelMedium),
            const SizedBox(height: LovSpace.xs),
            Wrap(
              spacing: LovSpace.sm,
              children: [
                for (final k in CalendarEventKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      // An Islamic date is Hijri-anchored by definition;
                      // pre-select it rather than making the user find the
                      // toggle and silently getting it wrong if they don't.
                      if (k == CalendarEventKind.islamic) {
                        _hijriAnchored = true;
                        _repeatsYearly = true;
                      }
                    }),
                  ),
              ],
            ),

            const SizedBox(height: LovSpace.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _repeatsYearly,
              onChanged: (v) => setState(() => _repeatsYearly = v),
              title: const Text('Repeats every year'),
            ),

            if (_repeatsYearly)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hijriAnchored,
                onChanged: (v) => setState(() => _hijriAnchored = v),
                title: const Text('Follow the Islamic calendar'),
                subtitle: Text(
                  _hijriAnchored
                      ? 'Returns on ${formatHijri(hijri)} each year, so it '
                          'moves through the Gregorian calendar.'
                      : 'Returns on ${DateFormat('d MMMM').format(_date)} '
                          'each year.',
                ),
              ),

            const SizedBox(height: LovSpace.xl),
            LovButton(
              label: isEditing ? 'Save changes' : 'Add to calendar',
              loading: _saving,
              expand: true,
              onPressed: _title.text.trim().isEmpty ? null : _save,
            ),
            if (isEditing) ...[
              const SizedBox(height: LovSpace.sm),
              LovButton(
                label: 'Delete',
                variant: LovButtonVariant.text,
                expand: true,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  /// Combines the chosen date and time.
  ///
  /// For an all-day event the time is irrelevant and the repository pins it to
  /// UTC midnight; for a timed event this is a real local instant.
  DateTime _startsAt() {
    if (_allDay || _time == null) {
      return DateTime(_date.year, _date.month, _date.day);
    }
    return DateTime(
        _date.year, _date.month, _date.day, _time!.hour, _time!.minute);
  }

  Future<void> _save() async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;

    setState(() => _saving = true);
    final repo = ref.read(calendarRepositoryProvider);
    final anchor =
        _repeatsYearly && _hijriAnchored ? hijriFromGregorian(_date) : null;
    // A Hijri-anchored event recurs via its anchor, not via an RRULE — setting
    // both would resolve the event twice on different calendars.
    final recurrence =
        _repeatsYearly && !_hijriAnchored ? 'FREQ=YEARLY' : null;

    try {
      if (widget.existing case final existing?) {
        await repo.update(
          id: existing.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          startsAt: _startsAt(),
          allDay: _allDay,
          recurrence: recurrence,
          hijriAnchor: anchor,
          kind: _kind,
        );
      } else {
        await repo.create(
          coupleId: couple.id,
          userId: session.user.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          startsAt: _startsAt(),
          allDay: _allDay,
          recurrence: recurrence,
          hijriAnchor: anchor,
          kind: _kind,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the event')),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(calendarRepositoryProvider).delete(existing.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the event')),
      );
    }
  }
}
