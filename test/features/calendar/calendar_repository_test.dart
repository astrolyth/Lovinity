// Integration test against LOCAL Supabase for the shared calendar.
//
// Covers the two things that fail silently rather than loudly:
//
//   1. **RLS isolation** — a calendar is a couple's private life. A user
//      outside the couple must get zero rows, not a permissions error the
//      client might swallow.
//   2. **Round-tripping an all-day date** — the anniversary trap. `starts_at`
//      is `timestamptz`, so an all-day event written as a local instant comes
//      back as the previous day for whoever is far enough west. Stored at UTC
//      midnight and read date-only, both spouses see the same day.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/hijri_dates.dart';
import 'package:lovinity/features/calendar/data/calendar_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

late SupabaseClient adminClient;

SupabaseClient _anonClient() => SupabaseClient(
      _url,
      _anon,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

Future<String> _signUp(SupabaseClient client, String email, String gender) async {
  final res = await client.auth.signUp(email: email, password: 'password123');
  final id = res.user!.id;
  addTearDown(() => adminClient.auth.admin.deleteUser(id));
  await client.from('users').update({'gender': gender}).eq('id', id);
  return id;
}

Future<String> _pair(SupabaseClient a, SupabaseClient b) async {
  final inviteRes = await a.rpc('create_pairing_invite');
  final inviteRow = Map<String, dynamic>.from(
    (inviteRes is List ? inviteRes.first : inviteRes) as Map,
  );
  await b.rpc('accept_pairing_invite',
      params: {'p_code': inviteRow['code'] as String});
  return await a.rpc('current_couple') as String;
}

void main() {
  setUpAll(() {
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test('both spouses see an event; an outsider sees none', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final outsider = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'cal-h-$stamp@test.local', 'male');
    await _signUp(wife, 'cal-w-$stamp@test.local', 'female');
    await _signUp(outsider, 'cal-o-$stamp@test.local', 'male');
    final coupleId = await _pair(husband, wife);

    final repoHusband = CalendarRepository(husband);
    final repoWife = CalendarRepository(wife);
    final repoOutsider = CalendarRepository(outsider);

    await repoHusband.create(
      coupleId: coupleId,
      userId: husbandId,
      title: 'Our nikah',
      startsAt: DateTime(2026, 3, 14),
      allDay: true,
      recurrence: 'FREQ=YEARLY',
      kind: CalendarEventKind.anniversary,
    );

    final asWife = await repoWife.watchAll(coupleId: coupleId).first;
    expect(asWife.map((e) => e.title), ['Our nikah']);

    // RLS, not a client-side filter, is what makes this empty.
    final asOutsider = await repoOutsider.watchAll(coupleId: coupleId).first;
    expect(asOutsider, isEmpty,
        reason: "a non-member must not read a couple's calendar");
  });

  test('an all-day event round-trips to the same calendar date', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'cal2-h-$stamp@test.local', 'male');
    await _signUp(wife, 'cal2-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    await CalendarRepository(husband).create(
      coupleId: coupleId,
      userId: husbandId,
      title: 'Anniversary',
      startsAt: DateTime(2026, 3, 14),
      allDay: true,
      kind: CalendarEventKind.anniversary,
    );

    final fetched =
        (await CalendarRepository(wife).watchAll(coupleId: coupleId).first)
            .single;
    expect(fetched.allDay, isTrue);
    expect(fetched.date, DateTime(2026, 3, 14),
        reason: 'an all-day date must not shift by a day through storage');
    expect(fetched.startsAt.toUtc().hour, 0,
        reason: 'all-day events are pinned to UTC midnight');
  });

  test('a Hijri anchor survives the round trip and resolves forward',
      () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'cal3-h-$stamp@test.local', 'male');
    await _signUp(wife, 'cal3-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    await CalendarRepository(husband).create(
      coupleId: coupleId,
      userId: husbandId,
      title: 'Eid al-Fitr',
      startsAt: DateTime(2019, 6, 4),
      allDay: true,
      hijriAnchor: const HijriDay(1440, 10, 1),
      kind: CalendarEventKind.islamic,
    );

    final fetched =
        (await CalendarRepository(wife).watchAll(coupleId: coupleId).first)
            .single;
    expect(fetched.hijriAnchor, const HijriDay(1440, 10, 1));

    // Stored in 2019, but must resolve to a future 1 Shawwal rather than
    // vanishing as a past event.
    final next = fetched.nextOccurrence(from: DateTime(2026, 8, 7));
    expect(next, isNotNull);
    expect(next!.isAfter(DateTime(2026, 8, 7)), isTrue);
    expect(hijriFromGregorian(next).month, 10);
    expect(hijriFromGregorian(next).day, 1);
  });

  test('delete removes the event for both spouses', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final husbandId = await _signUp(husband, 'cal4-h-$stamp@test.local', 'male');
    await _signUp(wife, 'cal4-w-$stamp@test.local', 'female');
    final coupleId = await _pair(husband, wife);

    final repoHusband = CalendarRepository(husband);
    await repoHusband.create(
      coupleId: coupleId,
      userId: husbandId,
      title: 'Dentist',
      startsAt: DateTime(2026, 9, 1),
      allDay: true,
    );

    final created =
        (await repoHusband.watchAll(coupleId: coupleId).first).single;

    // Either spouse may remove a shared event — the RLS policy is couple-wide,
    // not author-scoped.
    await CalendarRepository(wife).delete(created.id);

    final after = await repoHusband.watchAll(coupleId: coupleId).first;
    expect(after, isEmpty);
  });
}
