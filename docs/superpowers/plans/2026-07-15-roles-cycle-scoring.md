# Roles, Cycle, Scoring & Care Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add role-based onboarding, a menstrual cycle tracker, cycle-aware prayer scoring, role-specific care dashboards, and an extensible settings tab to Sakīnah.

**Architecture:** Five modules built in dependency order (roles → cycle → scoring → care → settings). Feature-first layout (`features/<name>/{data,domain,presentation}`). Supabase + RLS for persistence; Riverpod for state; go_router with redirect guards. Scoring logic lives in a shared, unit-tested pure-Dart `ScoreEngine` (one code path both partners run — the single source of truth), fed by raw rows from repositories; this replaces the spec's SQL-RPC idea because the toolchain has no SQL test harness and the fairness math must be TDD-covered.

**Tech Stack:** Flutter 3.44, flutter_riverpod ^3.3, go_router ^17.3, supabase_flutter ^2.16, mocktail ^1.0 (tests), Supabase CLI (local Postgres on `127.0.0.1:54322`).

## Global Constraints

- Feature-first layout: `lib/features/<name>/{data,domain,presentation}`; shared models in `lib/shared/models/`; verbatim from spec.
- Every new couple-scoped table enables RLS with `is_couple_member(couple_id)` and grants CRUD to `authenticated`.
- Care content: **no ḥadīth fabricated or paraphrased from memory**; every drafted religious seed row is inserted with `review_status = 'pending_review'` and surfaced with a "verify with a qualified scholar" note.
- Health content carries the visible disclaimer: *"General guidance, not medical advice; consult a doctor for health concerns."*
- Cycle data private by default; a spouse may read another member's `cycle_records` row **only when `visibility = 'shared'`**.
- Gender values: `'male' | 'female'`. Role derivation: male member = husband, female member = wife.
- Gender editable while unpaired; locked once paired.
- Retroactive prayer logging allowed for **today and yesterday only**.
- Migration verification uses local Supabase: `supabase db reset` then `psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "..."`.
- Commit after every task.

---

## Phase 1 — Roles & onboarding

### Task 1: Migration — `users.gender` + same-gender pairing rejection

**Files:**
- Create: `supabase/migrations/20260715000001_roles.sql`

**Interfaces:**
- Produces: `public.users.gender text check (gender in ('male','female'))`; updated `accept_pairing_invite(text)` raising `same_gender_pairing`.

- [ ] **Step 1: Write the migration**

```sql
-- Roles: gender on users, same-gender pairing rejection.
alter table public.users
  add column if not exists gender text
    check (gender in ('male','female'));

-- Recreate accept_pairing_invite with a gender-difference guard.
create or replace function public.accept_pairing_invite(p_code text)
returns public.couples
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_invite  public.pairing_invites%rowtype;
  v_a       uuid;
  v_b       uuid;
  v_couple  public.couples%rowtype;
  v_my_gender      text;
  v_inviter_gender text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_invite from public.pairing_invites
   where code = upper(trim(p_code)) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if v_invite.consumed_at is not null then raise exception 'invite_already_used'; end if;
  if v_invite.expires_at < now() then raise exception 'invite_expired'; end if;
  if v_invite.inviter_id = v_uid then raise exception 'cannot_pair_with_self'; end if;

  if exists (select 1 from public.couples
             where v_uid in (member_a, member_b) and status = 'active') then
    raise exception 'already_paired';
  end if;
  if exists (select 1 from public.couples
             where v_invite.inviter_id in (member_a, member_b) and status = 'active') then
    raise exception 'inviter_already_paired';
  end if;

  select gender into v_my_gender      from public.users where id = v_uid;
  select gender into v_inviter_gender from public.users where id = v_invite.inviter_id;
  if v_my_gender is null or v_inviter_gender is null then
    raise exception 'gender_required';
  end if;
  if v_my_gender = v_inviter_gender then
    raise exception 'same_gender_pairing';
  end if;

  if v_invite.inviter_id < v_uid then
    v_a := v_invite.inviter_id; v_b := v_uid;
  else
    v_a := v_uid; v_b := v_invite.inviter_id;
  end if;

  update public.pairing_invites
     set consumed_at = now(), consumed_by = v_uid
   where code = v_invite.code;

  insert into public.couples (member_a, member_b)
       values (v_a, v_b) returning * into v_couple;
  return v_couple;
end;
$$;

grant execute on function public.accept_pairing_invite(text) to authenticated;
```

- [ ] **Step 2: Apply and verify migration**

Run: `supabase db reset`
Expected: completes without error, applying `20260715000001_roles.sql`.

- [ ] **Step 3: Verify column + guard exist**

Run:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select column_name from information_schema.columns where table_name='users' and column_name='gender';"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select prosrc like '%same_gender_pairing%' as has_guard from pg_proc where proname='accept_pairing_invite';"
```
Expected: first prints `gender`; second prints `has_guard | t`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260715000001_roles.sql
git commit -m "feat(db): add users.gender and same-gender pairing rejection"
```

---

### Task 2: `UserProfile.gender` + `Role` derivation

**Files:**
- Modify: `lib/shared/models/user_profile.dart`
- Create: `lib/shared/models/role.dart`
- Test: `test/shared/models/role_test.dart`

**Interfaces:**
- Consumes: `UserProfile` (existing), `Couple` (`lib/shared/models/couple.dart`).
- Produces: `enum Gender { male, female }`; `UserProfile.gender` (`String?`); `enum Role { husband, wife }`; `Role? roleOfGender(String? gender)`; `Role? roleOfUser(Couple couple, String userId, {required String? memberAGender, required String? memberBGender})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/models/role_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/shared/models/role.dart';
import 'package:sakinah/shared/models/couple.dart';

void main() {
  test('roleOfGender maps male->husband, female->wife, null->null', () {
    expect(roleOfGender('male'), Role.husband);
    expect(roleOfGender('female'), Role.wife);
    expect(roleOfGender(null), isNull);
  });

  test('roleOfUser uses the member gender for the given user', () {
    const couple = Couple(
      id: 'c', memberA: 'aaa', memberB: 'bbb',
      status: 'active', longDistance: false,
    );
    final r = roleOfUser(couple, 'aaa',
        memberAGender: 'female', memberBGender: 'male');
    expect(r, Role.wife);
    final r2 = roleOfUser(couple, 'bbb',
        memberAGender: 'female', memberBGender: 'male');
    expect(r2, Role.husband);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/models/role_test.dart`
Expected: FAIL — `role.dart` not found / `Role` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/shared/models/role.dart
import 'couple.dart';

enum Gender { male, female }

enum Role { husband, wife }

Role? roleOfGender(String? gender) => switch (gender) {
      'male' => Role.husband,
      'female' => Role.wife,
      _ => null,
    };

/// Role of [userId] within [couple], given each member's gender.
Role? roleOfUser(
  Couple couple,
  String userId, {
  required String? memberAGender,
  required String? memberBGender,
}) {
  final g = userId == couple.memberA ? memberAGender : memberBGender;
  return roleOfGender(g);
}
```

Then add `gender` to `UserProfile` (`lib/shared/models/user_profile.dart`): add `final String? gender;` field, `this.gender` in the constructor, `gender: row['gender'] as String?` in `fromRow`, and `String? gender` param + `gender: gender ?? this.gender` in `copyWith`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/shared/models/role_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/models/role.dart lib/shared/models/user_profile.dart test/shared/models/role_test.dart
git commit -m "feat: add Gender/Role model and UserProfile.gender"
```

---

### Task 3: Onboarding repository + provider

**Files:**
- Create: `lib/features/onboarding/data/onboarding_repository.dart`
- Create: `lib/features/onboarding/domain/onboarding_providers.dart`
- Test: `test/features/onboarding/onboarding_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `authSessionProvider`, `ownProfileProvider` (`lib/features/home/domain/home_providers.dart`).
- Produces: `OnboardingRepository(SupabaseClient)` with `Future<void> saveProfile({required String userId, required String displayName, required String gender, required String madhhab, String? timezone, double? latitude, double? longitude})`; `onboardingRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/onboarding/onboarding_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sakinah/features/onboarding/data/onboarding_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockFilter extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('saveProfile updates the users row with gender + profile fields', () async {
    final client = _MockClient();
    final builder = _MockBuilder();
    final filter = _MockFilter();
    when(() => client.from('users')).thenReturn(builder);
    when(() => builder.update(any())).thenReturn(filter);
    when(() => filter.eq('id', any())).thenAnswer((_) async => null);

    final repo = OnboardingRepository(client);
    await repo.saveProfile(
      userId: 'u1', displayName: 'Aisha', gender: 'female', madhhab: 'hanafi',
    );

    final captured =
        verify(() => builder.update(captureAny())).captured.single as Map;
    expect(captured['gender'], 'female');
    expect(captured['display_name'], 'Aisha');
    expect(captured['madhhab'], 'hanafi');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/onboarding/onboarding_repository_test.dart`
Expected: FAIL — `OnboardingRepository` undefined.

- [ ] **Step 3: Implement repository + provider**

```dart
// lib/features/onboarding/data/onboarding_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingRepository {
  OnboardingRepository(this._client);
  final SupabaseClient _client;

  Future<void> saveProfile({
    required String userId,
    required String displayName,
    required String gender,
    required String madhhab,
    String? timezone,
    double? latitude,
    double? longitude,
  }) async {
    final data = <String, dynamic>{
      'display_name': displayName,
      'gender': gender,
      'madhhab': madhhab,
      if (timezone != null) 'timezone': timezone,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _client.from('users').update(data).eq('id', userId);
  }
}
```

```dart
// lib/features/onboarding/domain/onboarding_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.read(supabaseClientProvider));
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/onboarding/onboarding_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/onboarding test/features/onboarding
git commit -m "feat(onboarding): profile repository writing gender + settings"
```

---

### Task 4: Onboarding screen + router guard

**Files:**
- Create: `lib/features/onboarding/presentation/onboarding_screen.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/home/domain/home_providers.dart` (add `needsOnboardingProvider`)
- Test: `test/features/onboarding/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `onboardingRepositoryProvider`, `ownProfileProvider`, `authSessionProvider`.
- Produces: `OnboardingScreen` widget at route `/onboarding`; `needsOnboardingProvider` (`Provider<bool>` — true when signed in and `ownProfile.gender == null`).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/onboarding/onboarding_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('onboarding shows male/female selection and disables continue until chosen',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: OnboardingScreen()),
    ));
    expect(find.text('Man'), findsOneWidget);
    expect(find.text('Woman'), findsOneWidget);
    final continueBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'));
    expect(continueBtn.onPressed, isNull); // disabled until gender chosen
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/onboarding/onboarding_screen_test.dart`
Expected: FAIL — `OnboardingScreen` undefined.

- [ ] **Step 3: Implement the screen**

```dart
// lib/features/onboarding/presentation/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../domain/onboarding_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  String? _gender;
  String _madhhab = 'shafi';
  bool _saving = false;

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null || _gender == null) return;
    setState(() => _saving = true);
    await ref.read(onboardingRepositoryProvider).saveProfile(
          userId: session.user.id,
          displayName: _name.text.trim(),
          gender: _gender!,
          madhhab: _madhhab,
        );
    ref.invalidate(ownProfileProvider);
    if (mounted) context.go('/pair');
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _gender != null && _name.text.trim().isNotEmpty && !_saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          const Text('I am a'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _GenderChip(
              label: 'Man', selected: _gender == 'male',
              onTap: () => setState(() => _gender = 'male'))),
            const SizedBox(width: 12),
            Expanded(child: _GenderChip(
              label: 'Woman', selected: _gender == 'female',
              onTap: () => setState(() => _gender = 'female'))),
          ]),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _madhhab,
            decoration: const InputDecoration(labelText: 'Madhhab'),
            items: const [
              DropdownMenuItem(value: 'shafi', child: Text('Shāfiʿī / other')),
              DropdownMenuItem(value: 'hanafi', child: Text('Ḥanafī')),
            ],
            onChanged: (v) => setState(() => _madhhab = v ?? 'shafi'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: canContinue ? _submit : null,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
          ),
        ]),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1),
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
        ),
        child: Text(label),
      ),
    );
  }
}
```

- [ ] **Step 4: Add `needsOnboardingProvider`**

Append to `lib/features/home/domain/home_providers.dart`:
```dart
/// True when signed in but the profile has no gender yet (onboarding pending).
final needsOnboardingProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return false;
  final profile = ref.watch(ownProfileProvider).asData?.value;
  return profile != null && profile.gender == null;
});
```

- [ ] **Step 5: Wire the router guard**

In `lib/core/router/app_router.dart`: import the onboarding screen and `home_providers.dart`. Inside `redirect`, after the `if (!signedIn)` block and before the couple checks, add:
```dart
final profile = ref.read(ownProfileProvider);
final isOnboarding = path == '/onboarding';
if (!profile.hasValue) {
  return isSplash ? null : '/splash';
}
if (ref.read(needsOnboardingProvider)) {
  return isOnboarding ? null : '/onboarding';
}
if (isOnboarding) return '/pair';
```
Register the route: `GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen())`. Add `ref.listen(ownProfileProvider, ...)` to `_RouterRefresh` so the guard re-evaluates after the profile loads.

- [ ] **Step 6: Run tests**

Run: `flutter test test/features/onboarding/onboarding_screen_test.dart`
Expected: PASS.
Run: `flutter analyze lib/core/router/app_router.dart lib/features/onboarding`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/onboarding lib/core/router/app_router.dart lib/features/home/domain/home_providers.dart test/features/onboarding/onboarding_screen_test.dart
git commit -m "feat(onboarding): gender screen + router guard"
```

---

## Phase 2 — Cycle tracker

### Task 5: Migration — tighten `cycle_records` RLS

**Files:**
- Create: `supabase/migrations/20260715000002_cycle_rls.sql`

**Interfaces:**
- Produces: replacement RLS on `public.cycle_records` — own rows full CRUD; spouse SELECT only when `visibility='shared'`.

- [ ] **Step 1: Write the migration**

```sql
-- Tighten cycle_records privacy: own rows always; spouse reads only shared rows.
drop policy if exists cycle_records_couple_rls on public.cycle_records;

create policy cycle_records_own on public.cycle_records
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_couple_member(couple_id));

create policy cycle_records_spouse_shared_read on public.cycle_records
  for select
  using (
    visibility = 'shared'
    and public.is_couple_member(couple_id)
    and user_id <> auth.uid()
  );
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db reset`
Expected: applies cleanly.

- [ ] **Step 3: Verify policies exist**

Run:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select policyname from pg_policies where tablename='cycle_records' order by policyname;"
```
Expected: lists `cycle_records_own` and `cycle_records_spouse_shared_read` (and no `cycle_records_couple_rls`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260715000002_cycle_rls.sql
git commit -m "feat(db): visibility-aware RLS on cycle_records"
```

---

### Task 6: `CycleRecord` model + `CycleRepository`

**Files:**
- Create: `lib/shared/models/cycle_record.dart`
- Create: `lib/features/cycle/data/cycle_repository.dart`
- Test: `test/features/cycle/cycle_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`.
- Produces: `CycleRecord` (`id`, `userId`, `coupleId`, `startedOn` `DateTime`, `endedOn` `DateTime?`, `visibility` `String`, `note` `String?`), `CycleRecord.fromRow`, `bool isActiveOn(DateTime day)`; `CycleRepository` with `startCycle`, `endCycle`, `fetchHistory`, `watchOwn`, `setVisibility`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cycle/cycle_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/shared/models/cycle_record.dart';

void main() {
  CycleRecord rec({DateTime? start, DateTime? end}) => CycleRecord(
        id: 'r', userId: 'u', coupleId: 'c',
        startedOn: start ?? DateTime(2026, 7, 1),
        endedOn: end, visibility: 'private',
      );

  test('isActiveOn true within an open cycle, false before start', () {
    final r = rec(start: DateTime(2026, 7, 10));
    expect(r.isActiveOn(DateTime(2026, 7, 12)), isTrue);
    expect(r.isActiveOn(DateTime(2026, 7, 9)), isFalse);
  });

  test('isActiveOn respects endedOn (inclusive)', () {
    final r = rec(start: DateTime(2026, 7, 10), end: DateTime(2026, 7, 15));
    expect(r.isActiveOn(DateTime(2026, 7, 15)), isTrue);
    expect(r.isActiveOn(DateTime(2026, 7, 16)), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/cycle/cycle_repository_test.dart`
Expected: FAIL — `CycleRecord` undefined.

- [ ] **Step 3: Implement the model**

```dart
// lib/shared/models/cycle_record.dart
class CycleRecord {
  const CycleRecord({
    required this.id,
    required this.userId,
    required this.coupleId,
    required this.startedOn,
    required this.endedOn,
    required this.visibility,
    this.note,
  });

  final String id;
  final String userId;
  final String coupleId;
  final DateTime startedOn;
  final DateTime? endedOn;
  final String visibility; // 'private' | 'shared'
  final String? note;

  bool get isOpen => endedOn == null;

  /// Whether [day] falls within [startedOn]..[endedOn] (inclusive), treating
  /// an open cycle as active from start onward.
  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startedOn.year, startedOn.month, startedOn.day);
    if (d.isBefore(s)) return false;
    if (endedOn == null) return true;
    final e = DateTime(endedOn!.year, endedOn!.month, endedOn!.day);
    return !d.isAfter(e);
  }

  static DateTime _date(String s) => DateTime.parse(s);

  factory CycleRecord.fromRow(Map<String, dynamic> row) => CycleRecord(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        coupleId: row['couple_id'] as String,
        startedOn: _date(row['started_on'] as String),
        endedOn: row['ended_on'] == null ? null : _date(row['ended_on'] as String),
        visibility: (row['visibility'] ?? 'private') as String,
        note: row['note'] as String?,
      );
}
```

- [ ] **Step 4: Implement the repository**

```dart
// lib/features/cycle/data/cycle_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/cycle_record.dart';

class CycleRepository {
  CycleRepository(this._client);
  final SupabaseClient _client;

  String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<CycleRecord> startCycle({
    required String userId,
    required String coupleId,
    required DateTime startedOn,
    String visibility = 'private',
  }) async {
    final row = await _client.from('cycle_records').insert({
      'user_id': userId,
      'couple_id': coupleId,
      'started_on': _d(startedOn),
      'visibility': visibility,
    }).select().single();
    return CycleRecord.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> endCycle({required String recordId, required DateTime endedOn}) async {
    await _client.from('cycle_records')
        .update({'ended_on': _d(endedOn)}).eq('id', recordId);
  }

  Future<void> setVisibility({required String recordId, required String visibility}) async {
    await _client.from('cycle_records')
        .update({'visibility': visibility}).eq('id', recordId);
  }

  Future<List<CycleRecord>> fetchHistory({required String userId}) async {
    final rows = await _client.from('cycle_records')
        .select().eq('user_id', userId).order('started_on', ascending: false);
    return [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Stream<List<CycleRecord>> watchOwn({required String userId}) {
    return _client.from('cycle_records').stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) => [for (final r in rows) CycleRecord.fromRow(Map<String, dynamic>.from(r))]
          ..sort((a, b) => b.startedOn.compareTo(a.startedOn)));
  }
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/cycle/cycle_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/models/cycle_record.dart lib/features/cycle/data/cycle_repository.dart test/features/cycle/cycle_repository_test.dart
git commit -m "feat(cycle): CycleRecord model + repository"
```

---

### Task 7: Cycle prediction pure functions

**Files:**
- Create: `lib/features/cycle/domain/cycle_prediction.dart`
- Test: `test/features/cycle/cycle_prediction_test.dart`

**Interfaces:**
- Consumes: `CycleRecord`.
- Produces: `int maxHaidDays(String madhhab)`; `class CyclePrediction { DateTime? nextStart; int? avgCycleLength; int? avgPeriodLength; }`; `CyclePrediction predictCycle(List<CycleRecord> historyNewestFirst, {DateTime? today})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cycle/cycle_prediction_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/shared/models/cycle_record.dart';
import 'package:sakinah/features/cycle/domain/cycle_prediction.dart';

void main() {
  CycleRecord r(String id, DateTime s, DateTime? e) =>
      CycleRecord(id: id, userId: 'u', coupleId: 'c',
          startedOn: s, endedOn: e, visibility: 'private');

  test('maxHaidDays: hanafi 10, shafi 15', () {
    expect(maxHaidDays('hanafi'), 10);
    expect(maxHaidDays('shafi'), 15);
  });

  test('predictCycle averages start-to-start gaps and projects next start', () {
    // Starts 28 days apart: Jun 1, Jun 29, Jul 27.
    final history = [
      r('3', DateTime(2026, 7, 27), DateTime(2026, 8, 1)),
      r('2', DateTime(2026, 6, 29), DateTime(2026, 7, 4)),
      r('1', DateTime(2026, 6, 1), DateTime(2026, 6, 6)),
    ];
    final p = predictCycle(history);
    expect(p.avgCycleLength, 28);
    expect(p.avgPeriodLength, 5); // Jun1-6 => 5 day gaps averaged
    expect(p.nextStart, DateTime(2026, 8, 24)); // Jul 27 + 28
  });

  test('predictCycle returns nulls with fewer than two cycles', () {
    final p = predictCycle([r('1', DateTime(2026, 6, 1), DateTime(2026, 6, 6))]);
    expect(p.avgCycleLength, isNull);
    expect(p.nextStart, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/cycle/cycle_prediction_test.dart`
Expected: FAIL — `cycle_prediction.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/cycle/domain/cycle_prediction.dart
import '../../../shared/models/cycle_record.dart';

int maxHaidDays(String madhhab) => madhhab == 'hanafi' ? 10 : 15;

class CyclePrediction {
  const CyclePrediction({this.nextStart, this.avgCycleLength, this.avgPeriodLength});
  final DateTime? nextStart;
  final int? avgCycleLength;
  final int? avgPeriodLength;
}

/// [history] newest-first. Needs >= 2 records to predict.
CyclePrediction predictCycle(List<CycleRecord> history, {DateTime? today}) {
  if (history.length < 2) return const CyclePrediction();
  // Oldest-first for gap math.
  final ordered = [...history]..sort((a, b) => a.startedOn.compareTo(b.startedOn));

  final cycleGaps = <int>[];
  for (var i = 1; i < ordered.length; i++) {
    cycleGaps.add(ordered[i].startedOn.difference(ordered[i - 1].startedOn).inDays);
  }
  final periodLengths = <int>[];
  for (final rec in ordered) {
    if (rec.endedOn != null) {
      // inclusive day count
      periodLengths.add(rec.endedOn!.difference(rec.startedOn).inDays);
    }
  }

  int? avg(List<int> xs) =>
      xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();

  final avgCycle = avg(cycleGaps);
  final lastStart = ordered.last.startedOn;
  final next = avgCycle == null ? null : lastStart.add(Duration(days: avgCycle));

  return CyclePrediction(
    nextStart: next,
    avgCycleLength: avgCycle,
    avgPeriodLength: avg(periodLengths),
  );
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/cycle/cycle_prediction_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cycle/domain/cycle_prediction.dart test/features/cycle/cycle_prediction_test.dart
git commit -m "feat(cycle): prediction math + madhhab-aware max"
```

---

### Task 8: Cycle providers

**Files:**
- Create: `lib/features/cycle/domain/cycle_providers.dart`
- Test: `test/features/cycle/cycle_providers_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `authSessionProvider`, `currentCoupleProvider`, `ownProfileProvider`, `CycleRepository`, `predictCycle`.
- Produces: `cycleRepositoryProvider`; `ownCycleHistoryProvider` (`StreamProvider<List<CycleRecord>>`); `activeCycleProvider` (`Provider<CycleRecord?>` — the record active today); `cyclePredictionProvider` (`Provider<CyclePrediction>`); `isWifeProvider` (`Provider<bool>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/cycle/cycle_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/shared/models/cycle_record.dart';
import 'package:sakinah/features/cycle/domain/cycle_providers.dart';

void main() {
  test('activeCycleProvider picks the record active today', () {
    final today = DateTime.now();
    final active = CycleRecord(
      id: 'a', userId: 'u', coupleId: 'c',
      startedOn: today.subtract(const Duration(days: 2)),
      endedOn: null, visibility: 'private');
    final container = ProviderContainer(overrides: [
      ownCycleHistoryProvider.overrideWith((ref) => Stream.value([active])),
    ]);
    addTearDown(container.dispose);
    // Prime the stream.
    container.listen(ownCycleHistoryProvider, (_, __) {});
    return Future<void>.delayed(Duration.zero, () {
      expect(container.read(activeCycleProvider)?.id, 'a');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/cycle/cycle_providers_test.dart`
Expected: FAIL — providers undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/cycle/domain/cycle_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../data/cycle_repository.dart';
import 'cycle_prediction.dart';

final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  return CycleRepository(ref.read(supabaseClientProvider));
});

final isWifeProvider = Provider<bool>((ref) {
  final profile = ref.watch(ownProfileProvider).asData?.value;
  return profile?.gender == 'female';
});

final ownCycleHistoryProvider = StreamProvider<List<CycleRecord>>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return Stream.value(const []);
  return ref.read(cycleRepositoryProvider).watchOwn(userId: session.user.id);
});

final activeCycleProvider = Provider<CycleRecord?>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  final today = DateTime.now();
  for (final r in history) {
    if (r.isActiveOn(today)) return r;
  }
  return null;
});

final cyclePredictionProvider = Provider<CyclePrediction>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  return predictCycle(history);
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/cycle/cycle_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cycle/domain/cycle_providers.dart test/features/cycle/cycle_providers_test.dart
git commit -m "feat(cycle): providers (active, history, prediction, isWife)"
```

---

### Task 9: Cycle screen (wife-only)

**Files:**
- Create: `lib/features/cycle/presentation/cycle_screen.dart`
- Test: `test/features/cycle/cycle_screen_test.dart`

**Interfaces:**
- Consumes: `activeCycleProvider`, `ownCycleHistoryProvider`, `cyclePredictionProvider`, `cycleRepositoryProvider`, `ownProfileProvider`, `authSessionProvider`, `currentCoupleProvider`.
- Produces: `CycleScreen` at route `/home/cycle`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/cycle/cycle_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/shared/models/cycle_record.dart';
import 'package:sakinah/features/cycle/domain/cycle_providers.dart';
import 'package:sakinah/features/cycle/presentation/cycle_screen.dart';

void main() {
  testWidgets('shows Start button when no active cycle', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    expect(find.text('Start period'), findsOneWidget);
  });

  testWidgets('shows End button + resting message during active cycle', (tester) async {
    final active = CycleRecord(
      id: 'a', userId: 'u', coupleId: 'c',
      startedOn: DateTime.now().subtract(const Duration(days: 1)),
      endedOn: null, visibility: 'private');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ownCycleHistoryProvider.overrideWith((ref) => Stream.value([active])),
      ],
      child: const MaterialApp(home: CycleScreen()),
    ));
    await tester.pump();
    expect(find.text('End period'), findsOneWidget);
    expect(find.textContaining('Resting'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/cycle/cycle_screen_test.dart`
Expected: FAIL — `CycleScreen` undefined.

- [ ] **Step 3: Implement the screen**

```dart
// lib/features/cycle/presentation/cycle_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/cycle_providers.dart';

class CycleScreen extends ConsumerWidget {
  const CycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCycleProvider);
    final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
    final prediction = ref.watch(cyclePredictionProvider);
    final df = DateFormat.MMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (active != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resting 🤍', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Prayers are excused and your score is paused. '
                  'This is a mercy — take care of yourself.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await ref.read(cycleRepositoryProvider)
                      .endCycle(recordId: active.id, endedOn: DateTime.now());
                },
                child: const Text('End period'),
              ),
            ]),
          ))
        else
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Track your cycle', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Starting your period pauses prayer scoring and marks '
                  'prayers as excused until you end it.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final session = ref.read(authSessionProvider).asData?.value;
                  final couple = ref.read(currentCoupleProvider).asData?.value;
                  if (session == null || couple == null) return;
                  await ref.read(cycleRepositoryProvider).startCycle(
                        userId: session.user.id,
                        coupleId: couple.id,
                        startedOn: DateTime.now(),
                      );
                },
                child: const Text('Start period'),
              ),
            ]),
          )),
        const SizedBox(height: 16),
        if (prediction.nextStart != null)
          Card(child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text('Next period around ${df.format(prediction.nextStart!)}'),
            subtitle: Text('Avg cycle ${prediction.avgCycleLength} days · '
                'period ${prediction.avgPeriodLength} days'),
          )),
        const SizedBox(height: 16),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        for (final r in history)
          ListTile(
            dense: true,
            leading: const Icon(Icons.circle, size: 10),
            title: Text(r.endedOn == null
                ? '${df.format(r.startedOn)} — ongoing'
                : '${df.format(r.startedOn)} – ${df.format(r.endedOn!)}'),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/cycle/cycle_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cycle/presentation/cycle_screen.dart test/features/cycle/cycle_screen_test.dart
git commit -m "feat(cycle): tracker screen (start/end, prediction, history)"
```

---

## Phase 3 — Cycle-aware scoring

### Task 10: `ScoreEngine` (pure Dart)

**Files:**
- Create: `lib/features/scoring/domain/score_engine.dart`
- Test: `test/features/scoring/score_engine_test.dart`

**Interfaces:**
- Consumes: `Prayer` (`lib/core/time/prayer_engine.dart`), `CycleRecord`.
- Produces:
  - `class DayLog { final DateTime date; final Set<Prayer> prayed; }`
  - `class ScoreResult { final int prayed; final int due; final int currentStreak; final int longestStreak; double get pct; }`
  - `bool isExempt(List<CycleRecord> cycles, DateTime day)`
  - `ScoreResult computeScore({required List<DayLog> logs, required List<CycleRecord> cycles, required DateTime from, required DateTime toInclusive})` — over completed days `from..toInclusive`; a day is worth 5 due prayers unless exempt (then 0 due); streak = consecutive most-recent non-exempt days fully prayed, exempt days frozen (skipped, not breaking).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scoring/score_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/core/time/prayer_engine.dart';
import 'package:sakinah/shared/models/cycle_record.dart';
import 'package:sakinah/features/scoring/domain/score_engine.dart';

void main() {
  final all = {Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha};
  DayLog full(DateTime d) => DayLog(date: d, prayed: {...all});
  DayLog some(DateTime d, Set<Prayer> p) => DayLog(date: d, prayed: p);

  test('pct = prayed / due over the window', () {
    final logs = [
      full(DateTime(2026, 7, 1)),
      some(DateTime(2026, 7, 2), {Prayer.fajr, Prayer.dhuhr}),
    ];
    final r = computeScore(
      logs: logs, cycles: const [],
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 2));
    expect(r.due, 10);
    expect(r.prayed, 7);
    expect(r.pct, closeTo(0.7, 1e-9));
  });

  test('exempt days are removed from the denominator', () {
    final cycles = [CycleRecord(
      id: 'c', userId: 'u', coupleId: 'c', visibility: 'private',
      startedOn: DateTime(2026, 7, 2), endedOn: DateTime(2026, 7, 2))];
    final logs = [full(DateTime(2026, 7, 1))]; // nothing logged on the 2nd
    final r = computeScore(
      logs: logs, cycles: cycles,
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 2));
    expect(r.due, 5); // only the 1st counts
    expect(r.prayed, 5);
    expect(r.pct, 1.0);
  });

  test('streak freezes across an exempt gap instead of breaking', () {
    final cycles = [CycleRecord(
      id: 'c', userId: 'u', coupleId: 'c', visibility: 'private',
      startedOn: DateTime(2026, 7, 3), endedOn: DateTime(2026, 7, 4))];
    final logs = [
      full(DateTime(2026, 7, 1)),
      full(DateTime(2026, 7, 2)),
      // 3rd & 4th exempt, no logs
      full(DateTime(2026, 7, 5)),
    ];
    final r = computeScore(
      logs: logs, cycles: cycles,
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 5));
    expect(r.currentStreak, 3); // 1,2,(skip 3,4),5 all prayed
  });

  test('a missed non-exempt day breaks the streak', () {
    final logs = [
      full(DateTime(2026, 7, 1)),
      some(DateTime(2026, 7, 2), {Prayer.fajr}), // missed day
      full(DateTime(2026, 7, 3)),
    ];
    final r = computeScore(
      logs: logs, cycles: const [],
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 3));
    expect(r.currentStreak, 1); // only the 3rd
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scoring/score_engine_test.dart`
Expected: FAIL — `score_engine.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/scoring/domain/score_engine.dart
import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/cycle_record.dart';

const int prayersPerDay = 5;

class DayLog {
  const DayLog({required this.date, required this.prayed});
  final DateTime date;
  final Set<Prayer> prayed;
}

class ScoreResult {
  const ScoreResult({
    required this.prayed,
    required this.due,
    required this.currentStreak,
    required this.longestStreak,
  });
  final int prayed;
  final int due;
  final int currentStreak;
  final int longestStreak;
  double get pct => due == 0 ? 1.0 : prayed / due;
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

bool isExempt(List<CycleRecord> cycles, DateTime day) {
  for (final c in cycles) {
    if (c.isActiveOn(day)) return true;
  }
  return false;
}

ScoreResult computeScore({
  required List<DayLog> logs,
  required List<CycleRecord> cycles,
  required DateTime from,
  required DateTime toInclusive,
}) {
  final byDate = <DateTime, Set<Prayer>>{
    for (final l in logs) _d(l.date): l.prayed,
  };

  var due = 0;
  var prayed = 0;
  var current = 0;
  var longest = 0;
  var streakBroken = false; // once we hit a missed (non-exempt) day, current stops growing

  // Walk newest -> oldest for current-streak semantics.
  final days = <DateTime>[];
  for (var d = _d(toInclusive);
      !d.isBefore(_d(from));
      d = d.subtract(const Duration(days: 1))) {
    days.add(d);
  }

  var run = 0;
  for (final day in days) {
    if (isExempt(cycles, day)) {
      // Frozen: neither counts toward due/prayed nor breaks a streak.
      continue;
    }
    due += prayersPerDay;
    final p = byDate[day]?.length ?? 0;
    prayed += p;
    final complete = p >= prayersPerDay;
    if (complete) {
      run += 1;
      if (run > longest) longest = run;
      if (!streakBroken) current = run;
    } else {
      run = 0;
      streakBroken = true;
    }
  }

  return ScoreResult(
    prayed: prayed, due: due,
    currentStreak: current, longestStreak: longest);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/scoring/score_engine_test.dart`
Expected: PASS (all four cases).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scoring/domain/score_engine.dart test/features/scoring/score_engine_test.dart
git commit -m "feat(scoring): cycle-aware ScoreEngine (pct + frozen streaks)"
```

---

### Task 11: Scoreboard repository + providers

**Files:**
- Create: `lib/features/scoring/data/scoreboard_repository.dart`
- Create: `lib/features/scoring/domain/scoreboard_providers.dart`
- Test: `test/features/scoring/scoreboard_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `authSessionProvider`, `currentCoupleProvider`, `computeScore`, `DayLog`, `CycleRecord`.
- Produces:
  - `ScoreboardRepository` with `Future<List<DayLog>> fetchDayLogs({required String coupleId, required String userId, required DateTime from, required DateTime toInclusive})` and `Future<List<CycleRecord>> fetchCycles({required String userId, required DateTime from, required DateTime toInclusive})`.
  - `scoreboardProvider` (`FutureProvider<CoupleScoreboard>`), where `class CoupleScoreboard { final ScoreResult own; final ScoreResult spouse; final bool spouseCycleShared; }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scoring/scoreboard_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sakinah/core/time/prayer_engine.dart';
import 'package:sakinah/features/scoring/data/scoreboard_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockFilter extends Mock implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {}

void main() {
  test('fetchDayLogs groups prayed statuses by date', () async {
    final client = _MockClient();
    final builder = _MockBuilder();
    final filter = _MockFilter();
    when(() => client.from('prayer_logs')).thenReturn(builder);
    when(() => builder.select()).thenReturn(filter);
    when(() => filter.eq(any(), any())).thenReturn(filter);
    when(() => filter.gte(any(), any())).thenReturn(filter);
    when(() => filter.lte(any(), any())).thenReturn(filter);
    when(() => filter.then(any(), onError: any(named: 'onError')))
        .thenAnswer((inv) async {
      final rows = [
        {'user_id': 'u', 'date': '2026-07-01', 'prayer': 'fajr', 'status': 'prayed'},
        {'user_id': 'u', 'date': '2026-07-01', 'prayer': 'isha', 'status': 'missed'},
      ];
      return (inv.positionalArguments.first as Function)(rows);
    });

    final repo = ScoreboardRepository(client);
    final logs = await repo.fetchDayLogs(
      coupleId: 'c', userId: 'u',
      from: DateTime(2026, 7, 1), toInclusive: DateTime(2026, 7, 1));
    expect(logs.single.prayed, {Prayer.fajr}); // 'missed' excluded
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scoring/scoreboard_repository_test.dart`
Expected: FAIL — `ScoreboardRepository` undefined.

- [ ] **Step 3: Implement repository**

```dart
// lib/features/scoring/data/scoreboard_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/models/prayer_log.dart';
import '../domain/score_engine.dart';

class ScoreboardRepository {
  ScoreboardRepository(this._client);
  final SupabaseClient _client;

  String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<DayLog>> fetchDayLogs({
    required String coupleId,
    required String userId,
    required DateTime from,
    required DateTime toInclusive,
  }) async {
    final rows = await _client
        .from('prayer_logs')
        .select()
        .eq('couple_id', coupleId)
        .eq('user_id', userId)
        .gte('date', _d(from))
        .lte('date', _d(toInclusive));
    final byDate = <String, Set<Prayer>>{};
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      if ((m['status'] as String) != 'prayed') continue;
      final entry = PrayerLogEntry.fromRow(m);
      final key = _d(entry.date);
      (byDate[key] ??= <Prayer>{}).add(entry.prayer);
    }
    return [
      for (final e in byDate.entries)
        DayLog(date: DateTime.parse(e.key), prayed: e.value),
    ];
  }

  Future<List<CycleRecord>> fetchCycles({
    required String userId,
    required DateTime from,
    required DateTime toInclusive,
  }) async {
    final rows = await _client
        .from('cycle_records')
        .select()
        .eq('user_id', userId)
        .lte('started_on', _d(toInclusive));
    return [
      for (final r in rows)
        CycleRecord.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
```

- [ ] **Step 4: Implement providers**

```dart
// lib/features/scoring/domain/scoreboard_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../home/domain/home_providers.dart';
import '../data/scoreboard_repository.dart';
import 'score_engine.dart';

final scoreboardRepositoryProvider = Provider<ScoreboardRepository>((ref) {
  return ScoreboardRepository(ref.read(supabaseClientProvider));
});

class CoupleScoreboard {
  const CoupleScoreboard({
    required this.own,
    required this.spouse,
    required this.spouseCycleShared,
  });
  final ScoreResult own;
  final ScoreResult spouse;
  final bool spouseCycleShared;
}

/// Window length in days for the headline comparison.
const int scoreWindowDays = 30;

final scoreboardProvider = FutureProvider<CoupleScoreboard?>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (session == null || couple == null) return null;

  // Recompute when today's logs change.
  ref.watch(prayerLogRefreshTickProvider);

  final repo = ref.read(scoreboardRepositoryProvider);
  final today = DateTime.now();
  final toInclusive = today.subtract(const Duration(days: 1)); // completed days only
  final from = toInclusive.subtract(const Duration(days: scoreWindowDays - 1));

  final myId = session.user.id;
  final spouseId = couple.spouseOf(myId);

  final ownLogs = await repo.fetchDayLogs(
      coupleId: couple.id, userId: myId, from: from, toInclusive: toInclusive);
  final ownCycles = await repo.fetchCycles(userId: myId, from: from, toInclusive: toInclusive);
  final spouseLogs = await repo.fetchDayLogs(
      coupleId: couple.id, userId: spouseId, from: from, toInclusive: toInclusive);
  // Spouse cycles are only readable when shared (RLS). Empty => not shared / none.
  final spouseCycles = await repo.fetchCycles(
      userId: spouseId, from: from, toInclusive: toInclusive);

  final own = computeScore(logs: ownLogs, cycles: ownCycles, from: from, toInclusive: toInclusive);
  final spouse = computeScore(
      logs: spouseLogs, cycles: spouseCycles, from: from, toInclusive: toInclusive);

  return CoupleScoreboard(
    own: own, spouse: spouse, spouseCycleShared: spouseCycles.isNotEmpty);
});
```

Add a refresh tick to `lib/features/home/domain/home_providers.dart`:
```dart
/// Bump to force score recompute after a prayer is logged/unlogged.
final prayerLogRefreshTickProvider = StateProvider<int>((ref) => 0);
```
And in `PrayerLogRepository.logPrayer`/`unlogPrayer` callers (the prayer log screen), after a successful write call `ref.read(prayerLogRefreshTickProvider.notifier).state++;` (wire in Task 13).

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/scoring/scoreboard_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/scoring test/features/scoring/scoreboard_repository_test.dart lib/features/home/domain/home_providers.dart
git commit -m "feat(scoring): scoreboard repository + providers"
```

---

### Task 12: Scoreboard card on home

**Files:**
- Create: `lib/features/scoring/presentation/scoreboard_card.dart`
- Modify: `lib/features/home/presentation/home_screen.dart` (insert the card)
- Test: `test/features/scoring/scoreboard_card_test.dart`

**Interfaces:**
- Consumes: `scoreboardProvider`, `isWifeProvider`, `activeCycleProvider`.
- Produces: `ScoreboardCard` widget.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/scoring/scoreboard_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/features/scoring/domain/score_engine.dart';
import 'package:sakinah/features/scoring/domain/scoreboard_providers.dart';
import 'package:sakinah/features/scoring/presentation/scoreboard_card.dart';

void main() {
  testWidgets('renders both percentages', (tester) async {
    const board = CoupleScoreboard(
      own: ScoreResult(prayed: 95, due: 100, currentStreak: 7, longestStreak: 9),
      spouse: ScoreResult(prayed: 90, due: 100, currentStreak: 4, longestStreak: 6),
      spouseCycleShared: false,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scoreboardProvider.overrideWith((ref) async => board),
      ],
      child: const MaterialApp(home: Scaffold(body: ScoreboardCard())),
    ));
    await tester.pump();
    expect(find.textContaining('95%'), findsOneWidget);
    expect(find.textContaining('90%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scoring/scoreboard_card_test.dart`
Expected: FAIL — `ScoreboardCard` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/scoring/presentation/scoreboard_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scoreboard_providers.dart';

class ScoreboardCard extends ConsumerWidget {
  const ScoreboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scoreboardProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const SizedBox(
            height: 72, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('Could not load scores: $e'),
          data: (board) {
            if (board == null) return const SizedBox.shrink();
            String pct(int prayed, int due) =>
                '${(due == 0 ? 100 : (prayed / due * 100)).round()}%';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This month', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _Stat(label: 'You',
                    value: pct(board.own.prayed, board.own.due),
                    streak: board.own.currentStreak),
                _Stat(label: 'Spouse',
                    value: pct(board.spouse.prayed, board.spouse.due),
                    streak: board.spouse.currentStreak),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.streak});
  final String label; final String value; final int streak;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Text(value, style: t.headlineMedium),
      Text(label, style: t.bodySmall),
      const SizedBox(height: 4),
      Text('🔥 $streak', style: t.bodySmall),
    ]);
  }
}
```

Then insert `const ScoreboardCard()` into the home screen's scrolling column (follow the existing card placement in `home_screen.dart`). If the current user is the wife and `activeCycleProvider != null`, the card still renders (her % simply excludes exempt days); no special-casing required beyond copy.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/scoring/scoreboard_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scoring/presentation/scoreboard_card.dart lib/features/home/presentation/home_screen.dart test/features/scoring/scoreboard_card_test.dart
git commit -m "feat(scoring): scoreboard card on home"
```

---

### Task 13: Retroactive logging (today + yesterday)

**Files:**
- Modify: `lib/features/prayer_log/domain/prayer_log_providers.dart` (allow yesterday in `PrayerLogSelectedDate.set`)
- Modify: `lib/features/prayer_log/presentation/prayer_log_screen.dart` (day toggle Today/Yesterday + bump refresh tick)
- Test: `test/features/prayer_log/retro_logging_test.dart`

**Interfaces:**
- Consumes: `prayerLogSelectedDateProvider`, `prayerLogRefreshTickProvider`.
- Produces: `bool isLoggableDate(DateTime date, {DateTime? now})` (true only for today/yesterday) in `prayer_log_providers.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/prayer_log/retro_logging_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/features/prayer_log/domain/prayer_log_providers.dart';

void main() {
  test('only today and yesterday are loggable', () {
    final now = DateTime(2026, 7, 15, 10);
    expect(isLoggableDate(DateTime(2026, 7, 15), now: now), isTrue);
    expect(isLoggableDate(DateTime(2026, 7, 14), now: now), isTrue);
    expect(isLoggableDate(DateTime(2026, 7, 13), now: now), isFalse);
    expect(isLoggableDate(DateTime(2026, 7, 16), now: now), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/prayer_log/retro_logging_test.dart`
Expected: FAIL — `isLoggableDate` undefined.

- [ ] **Step 3: Implement**

Add to `lib/features/prayer_log/domain/prayer_log_providers.dart`:
```dart
/// Prayers may be logged/corrected for today and yesterday only.
bool isLoggableDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = today.difference(d).inDays;
  return diff == 0 || diff == 1;
}
```

In `prayer_log_screen.dart`: add a small Today/Yesterday segmented control that calls `ref.read(prayerLogSelectedDateProvider.notifier).set(...)`; gate the log/unlog buttons with `isLoggableDate(selectedDate)`; after a successful `logPrayer`/`unlogPrayer`, call `ref.read(prayerLogRefreshTickProvider.notifier).state++;`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/prayer_log/retro_logging_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/prayer_log test/features/prayer_log/retro_logging_test.dart
git commit -m "feat(prayer): allow retro logging for yesterday + refresh scores"
```

---

## Phase 4 — Care dashboards

### Task 14: Migration — `cycle_care_tips` + seed

**Files:**
- Create: `supabase/migrations/20260715000003_care_tips.sql`

**Interfaces:**
- Produces: `public.cycle_care_tips` (world-readable) seeded with `pending_review` rows.

- [ ] **Step 1: Write the migration**

```sql
create table public.cycle_care_tips (
  id                   uuid primary key default gen_random_uuid(),
  audience             text not null check (audience in ('wife','husband')),
  category             text not null check (category in
                         ('physical','emotional','spiritual','support','intimacy','empathy')),
  title                text not null,
  body                 text not null,
  islamic_reference    text,
  scientific_reference text,
  source_url           text,
  review_status        text not null default 'pending_review'
                         check (review_status in ('pending_review','verified')),
  language             text not null default 'en',
  sort_order           integer not null default 0
);

alter table public.cycle_care_tips enable row level security;
create policy cycle_care_tips_read on public.cycle_care_tips for select using (true);
grant select on public.cycle_care_tips to authenticated;

-- Seed content. Religious references are drafted and left pending_review; the
-- app surfaces a "verify with a scholar" note until an authority confirms them.
insert into public.cycle_care_tips (audience, category, title, body, islamic_reference, scientific_reference, sort_order) values
('wife','spiritual','You are still close to Allah',
 'Being excused from salah and fasting during your period is a mercy, not a shortfall. You can still make dhikr, duʿā, send salawat, listen to the Qurʾān, give sadaqah, and seek knowledge.',
 'Qurʾān 2:185 (Allah intends ease, not hardship) — verify wording/scope with a scholar.', null, 1),
('wife','physical','Rest and replenish',
 'Prioritise rest, warmth for cramps, hydration, and iron-rich foods. Gentle movement can ease discomfort.',
 null, 'General menstrual-health guidance; not medical advice — see a doctor for concerns.', 2),
('wife','emotional','Be gentle with yourself',
 'Mood shifts around your period are normal. Lower the bar on productivity and give yourself compassion.',
 null, 'Premenstrual mood changes are widely documented; consult a clinician if severe.', 3),
('husband','support','Show up with patience',
 'Offer emotional presence and practical help — chores, comfort foods, warmth, and understanding. Small kindnesses matter most now.',
 'The Prophet ﷺ was gentle with his family; reports describe closeness with his wife during her menses — verify exact narration and reference with a scholar.',
 null, 1),
('husband','intimacy','What is permitted',
 'Intercourse is avoided during menstruation; affection, companionship, and closeness otherwise remain. Keep communication kind.',
 'Qurʾān 2:222 — verify interpretation and scope with a qualified scholar.', null, 2),
('husband','empathy','Understand what she feels',
 'Cramps, fatigue, and mood changes are real and physical. A little empathy and a duʿā for her wellbeing go a long way.',
 null, 'Dysmenorrhea (period pain) is a recognised medical phenomenon.', 3);
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db reset`
Then:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select count(*) as pending from public.cycle_care_tips where review_status='pending_review';"
```
Expected: `pending | 6` (all seeded rows pending review).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260715000003_care_tips.sql
git commit -m "feat(db): cycle_care_tips table + pending-review seed"
```

---

### Task 15: `CareTip` model + repository + providers

**Files:**
- Create: `lib/shared/models/care_tip.dart`
- Create: `lib/features/care/data/care_repository.dart`
- Create: `lib/features/care/domain/care_providers.dart`
- Test: `test/features/care/care_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `isWifeProvider`.
- Produces: `CareTip` (`audience`, `category`, `title`, `body`, `islamicReference?`, `scientificReference?`, `reviewStatus`), `CareTip.fromRow`; `CareRepository.fetchForAudience(String audience)`; `careTipsProvider` (`FutureProvider<List<CareTip>>` keyed to own role).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/care/care_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/shared/models/care_tip.dart';

void main() {
  test('CareTip.fromRow maps columns + flags pending review', () {
    final t = CareTip.fromRow({
      'audience': 'wife', 'category': 'spiritual', 'title': 'T', 'body': 'B',
      'islamic_reference': 'Q 2:185', 'scientific_reference': null,
      'review_status': 'pending_review',
    });
    expect(t.audience, 'wife');
    expect(t.islamicReference, 'Q 2:185');
    expect(t.isPendingReview, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/care/care_repository_test.dart`
Expected: FAIL — `CareTip` undefined.

- [ ] **Step 3: Implement model, repository, providers**

```dart
// lib/shared/models/care_tip.dart
class CareTip {
  const CareTip({
    required this.audience,
    required this.category,
    required this.title,
    required this.body,
    required this.reviewStatus,
    this.islamicReference,
    this.scientificReference,
  });
  final String audience;
  final String category;
  final String title;
  final String body;
  final String reviewStatus;
  final String? islamicReference;
  final String? scientificReference;

  bool get isPendingReview => reviewStatus == 'pending_review';

  factory CareTip.fromRow(Map<String, dynamic> row) => CareTip(
        audience: row['audience'] as String,
        category: row['category'] as String,
        title: row['title'] as String,
        body: row['body'] as String,
        reviewStatus: (row['review_status'] ?? 'pending_review') as String,
        islamicReference: row['islamic_reference'] as String?,
        scientificReference: row['scientific_reference'] as String?,
      );
}
```

```dart
// lib/features/care/data/care_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/care_tip.dart';

class CareRepository {
  CareRepository(this._client);
  final SupabaseClient _client;

  Future<List<CareTip>> fetchForAudience(String audience) async {
    final rows = await _client
        .from('cycle_care_tips')
        .select()
        .eq('audience', audience)
        .order('sort_order');
    return [for (final r in rows) CareTip.fromRow(Map<String, dynamic>.from(r as Map))];
  }
}
```

```dart
// lib/features/care/domain/care_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/care_tip.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../data/care_repository.dart';

final careRepositoryProvider = Provider<CareRepository>((ref) {
  return CareRepository(ref.read(supabaseClientProvider));
});

/// Tips for the current user's role (wife -> self-care, husband -> support).
final careTipsProvider = FutureProvider<List<CareTip>>((ref) async {
  final audience = ref.watch(isWifeProvider) ? 'wife' : 'husband';
  return ref.read(careRepositoryProvider).fetchForAudience(audience);
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/care/care_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/models/care_tip.dart lib/features/care test/features/care/care_repository_test.dart
git commit -m "feat(care): CareTip model + repository + role-keyed provider"
```

---

### Task 16: Care dashboard screen (role-specific)

**Files:**
- Create: `lib/features/care/presentation/care_screen.dart`
- Test: `test/features/care/care_screen_test.dart`

**Interfaces:**
- Consumes: `careTipsProvider`, `isWifeProvider`.
- Produces: `CareScreen` at route `/home/care`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/care/care_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/shared/models/care_tip.dart';
import 'package:sakinah/features/care/domain/care_providers.dart';
import 'package:sakinah/features/care/presentation/care_screen.dart';

void main() {
  testWidgets('shows a tip, its pending-review note, and medical disclaimer',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        careTipsProvider.overrideWith((ref) async => const [
          CareTip(audience: 'wife', category: 'spiritual', title: 'Close to Allah',
              body: 'Body', reviewStatus: 'pending_review',
              islamicReference: 'Q 2:185'),
        ]),
      ],
      child: const MaterialApp(home: CareScreen()),
    ));
    await tester.pump();
    expect(find.text('Close to Allah'), findsOneWidget);
    expect(find.textContaining('verify'), findsWidgets); // pending-review note
    expect(find.textContaining('not medical advice'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/care/care_screen_test.dart`
Expected: FAIL — `CareScreen` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/care/presentation/care_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/care_tip.dart';
import '../domain/care_providers.dart';
import '../../cycle/domain/cycle_providers.dart';

class CareScreen extends ConsumerWidget {
  const CareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWife = ref.watch(isWifeProvider);
    final async = ref.watch(careTipsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(isWife ? 'Caring for you' : 'Caring for her')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (tips) => ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10)),
            child: const Text('General guidance, not medical advice; '
                'consult a doctor for health concerns.',
                style: TextStyle(fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 12),
          for (final t in tips) _TipCard(tip: t),
        ]),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip});
  final CareTip tip;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tip.title, style: t.titleMedium),
        const SizedBox(height: 6),
        Text(tip.body),
        if (tip.islamicReference != null) ...[
          const SizedBox(height: 8),
          Text(tip.islamicReference!, style: t.bodySmall),
        ],
        if (tip.scientificReference != null) ...[
          const SizedBox(height: 4),
          Text(tip.scientificReference!, style: t.bodySmall),
        ],
        if (tip.isPendingReview && tip.islamicReference != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, size: 14),
            const SizedBox(width: 4),
            Expanded(child: Text('Please verify this reference with a qualified scholar.',
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic))),
          ]),
        ],
      ]),
    ));
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/care/care_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/care/presentation/care_screen.dart test/features/care/care_screen_test.dart
git commit -m "feat(care): role-specific care dashboard with disclaimers"
```

---

## Phase 5 — Settings tab

### Task 17: Migration — `user_preferences`

**Files:**
- Create: `supabase/migrations/20260715000004_user_preferences.sql`

**Interfaces:**
- Produces: `public.user_preferences(user_id pk, prefs jsonb, updated_at)` with own-row RLS.

- [ ] **Step 1: Write the migration**

```sql
create table public.user_preferences (
  user_id     uuid primary key references public.users(id) on delete cascade,
  prefs       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.user_preferences enable row level security;
create policy user_prefs_own on public.user_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.user_preferences to authenticated;
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db reset`
Then:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select policyname from pg_policies where tablename='user_preferences';"
```
Expected: prints `user_prefs_own`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260715000004_user_preferences.sql
git commit -m "feat(db): user_preferences table + own-row RLS"
```

---

### Task 18: Preferences repository + provider

**Files:**
- Create: `lib/features/settings/data/preferences_repository.dart`
- Create: `lib/features/settings/domain/settings_providers.dart`
- Test: `test/features/settings/preferences_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `authSessionProvider`.
- Produces: `PreferencesRepository` with `Future<Map<String, dynamic>> fetch(String userId)` and `Future<void> setKey({required String userId, required String key, required dynamic value})`; `preferencesProvider` (`FutureProvider<Map<String,dynamic>>`); `shareCycleByDefaultProvider` (`Provider<bool>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/preferences_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sakinah/features/settings/data/preferences_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockFilter extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  test('setKey upserts prefs jsonb merged with the new key', () async {
    final client = _MockClient();
    final builder = _MockBuilder();
    final filter = _MockFilter();
    when(() => client.from('user_preferences')).thenReturn(builder);
    when(() => builder.upsert(any())).thenReturn(filter);
    when(() => filter.then(any(), onError: any(named: 'onError')))
        .thenAnswer((_) async => null);

    final repo = PreferencesRepository(client);
    await repo.setKey(userId: 'u', key: 'share_cycle_default', value: true,
        current: {'foo': 1});

    final captured = verify(() => builder.upsert(captureAny())).captured.single as Map;
    expect((captured['prefs'] as Map)['share_cycle_default'], true);
    expect((captured['prefs'] as Map)['foo'], 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/preferences_repository_test.dart`
Expected: FAIL — `PreferencesRepository` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/settings/data/preferences_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class PreferencesRepository {
  PreferencesRepository(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> fetch(String userId) async {
    final row = await _client.from('user_preferences')
        .select('prefs').eq('user_id', userId).maybeSingle();
    if (row == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(row['prefs'] as Map);
  }

  Future<void> setKey({
    required String userId,
    required String key,
    required dynamic value,
    Map<String, dynamic> current = const {},
  }) async {
    final merged = {...current, key: value};
    await _client.from('user_preferences').upsert({
      'user_id': userId,
      'prefs': merged,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
```

```dart
// lib/features/settings/domain/settings_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/preferences_repository.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return PreferencesRepository(ref.read(supabaseClientProvider));
});

final preferencesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return <String, dynamic>{};
  return ref.read(preferencesRepositoryProvider).fetch(session.user.id);
});

final shareCycleByDefaultProvider = Provider<bool>((ref) {
  final prefs = ref.watch(preferencesProvider).asData?.value ?? const {};
  return prefs['share_cycle_default'] == true;
});
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/settings/preferences_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/data lib/features/settings/domain test/features/settings/preferences_repository_test.dart
git commit -m "feat(settings): user preferences repository + providers"
```

---

### Task 19: Settings screen (section registry) + cycle privacy toggle

**Files:**
- Create: `lib/features/settings/presentation/settings_screen.dart`
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `preferencesProvider`, `preferencesRepositoryProvider`, `shareCycleByDefaultProvider`, `isWifeProvider`, `ownProfileProvider`, `activeCycleProvider`, `cycleRepositoryProvider`, `authSessionProvider`, `authRepositoryProvider`.
- Produces: `SettingsScreen` at route `/home/settings`. Section list: Profile, Privacy & Sharing (wife-only cycle toggle), Notifications (stub), Security (stub), About/Account (sign out).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/settings/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakinah/features/cycle/domain/cycle_providers.dart';
import 'package:sakinah/features/settings/domain/settings_providers.dart';
import 'package:sakinah/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('wife sees the cycle privacy toggle', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isWifeProvider.overrideWithValue(true),
        preferencesProvider.overrideWith((ref) async => <String, dynamic>{}),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });

  testWidgets('husband does not see the cycle privacy toggle', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isWifeProvider.overrideWithValue(false),
        preferencesProvider.overrideWith((ref) async => <String, dynamic>{}),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_controller.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../domain/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWife = ref.watch(isWifeProvider);
    final shareDefault = ref.watch(shareCycleByDefaultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _SectionHeader('Privacy & Sharing'),
        if (isWife)
          SwitchListTile(
            title: const Text('Share cycle with spouse by default'),
            subtitle: const Text(
                'When off, your spouse only sees that your score is resting.'),
            value: shareDefault,
            onChanged: (v) async {
              final session = ref.read(authSessionProvider).asData?.value;
              if (session == null) return;
              final current = ref.read(preferencesProvider).asData?.value ?? const {};
              await ref.read(preferencesRepositoryProvider).setKey(
                    userId: session.user.id,
                    key: 'share_cycle_default',
                    value: v,
                    current: Map<String, dynamic>.from(current),
                  );
              // Apply to an active cycle immediately, if any.
              final active = ref.read(activeCycleProvider);
              if (active != null) {
                await ref.read(cycleRepositoryProvider).setVisibility(
                      recordId: active.id,
                      visibility: v ? 'shared' : 'private');
              }
              ref.invalidate(preferencesProvider);
            },
          )
        else
          const ListTile(
            title: Text('Privacy'),
            subtitle: Text('Sharing controls appear here as features are added.'),
          ),
        const _SectionHeader('Notifications'),
        const ListTile(
          title: Text('Reminders'),
          subtitle: Text('Prayer and cycle reminders (coming soon).')),
        const _SectionHeader('Security'),
        const ListTile(
          title: Text('App lock'),
          subtitle: Text('Biometric lock (coming soon).')),
        const _SectionHeader('Account'),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
      );
}
```

> Note: confirm `AuthRepository` exposes `signOut()`; if the method has a different name, match it. Check `lib/features/auth/data/auth_repository.dart` before implementing this tile.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/presentation/settings_screen.dart test/features/settings/settings_screen_test.dart
git commit -m "feat(settings): settings screen + cycle privacy toggle"
```

---

### Task 20: Router wiring + home entry points

**Files:**
- Modify: `lib/core/router/app_router.dart` (routes for cycle, care, settings)
- Modify: `lib/features/home/presentation/home_screen.dart` (entry buttons: Cycle/Care wife-only-aware; Settings always)
- Test: `test/features/navigation_test.dart`

**Interfaces:**
- Consumes: `CycleScreen`, `CareScreen`, `SettingsScreen`, `isWifeProvider`, `activeCycleProvider`.
- Produces: routes `/home/cycle`, `/home/care`, `/home/settings`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/navigation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakinah/features/settings/presentation/settings_screen.dart';
import 'package:sakinah/features/care/presentation/care_screen.dart';
import 'package:sakinah/features/cycle/presentation/cycle_screen.dart';

void main() {
  test('destination screens are const-constructible (smoke)', () {
    expect(const SettingsScreen(), isA<Widget>());
    expect(const CareScreen(), isA<Widget>());
    expect(const CycleScreen(), isA<Widget>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails (or passes trivially, then wire routes)**

Run: `flutter test test/features/navigation_test.dart`
Expected: PASS (smoke). The real deliverable is route registration verified by `flutter analyze`.

- [ ] **Step 3: Wire routes**

In `lib/core/router/app_router.dart`, import the three screens and add child routes under `/home`:
```dart
GoRoute(path: 'cycle', builder: (_, _) => const CycleScreen()),
GoRoute(path: 'care', builder: (_, _) => const CareScreen()),
GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
```

- [ ] **Step 4: Add home entry points**

In `lib/features/home/presentation/home_screen.dart`, add navigation entries following the existing card/tile pattern:
- A **Settings** action (e.g. an `IconButton(icon: Icon(Icons.settings))` in the app bar) → `context.go('/home/settings')`.
- A **Care** tile → `context.go('/home/care')` (label "Caring for you" if `isWifeProvider`, else "Caring for her"); surface it prominently when the current user is the wife with an active cycle, or (for the husband) when the spouse's shared cycle is active.
- A **Cycle** tile shown only when `ref.watch(isWifeProvider)` → `context.go('/home/cycle')`.

- [ ] **Step 5: Verify build**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/home/presentation/home_screen.dart test/features/navigation_test.dart
git commit -m "feat: wire cycle, care, settings routes + home entry points"
```

---

## Self-Review

**Spec coverage:**
- Roles & onboarding → Tasks 1–4. ✅
- Cycle tracker (log + prediction + madhhab max + exemption + visibility) → Tasks 5–9. ✅
- Cycle-aware scoring (%, frozen streaks, fairness, retro logging) → Tasks 10–13. ✅
- Care dashboards (role-specific, sourced, pending-review, disclaimer) → Tasks 14–16. ✅
- Settings tab (extensible, cycle privacy toggle) → Tasks 17–19. ✅
- Privacy/RLS (visibility-aware cycle reads, own-row prefs) → Tasks 5, 17. ✅
- Navigation/entry points → Task 20. ✅

**Deviation from spec (intentional, flagged to user):** scoring computed in a shared pure-Dart `ScoreEngine` (Task 10) rather than a Postgres RPC, because the toolchain has no SQL test framework and the fairness math must be TDD-tested. Same single-source-of-truth guarantee (one shared code path); the spec's `get_couple_scoreboard` RPC is not created.

**Placeholder scan:** No TBD/TODO; every code step has complete code. UI entry-point wiring in Task 20 Step 4 is described against the existing home layout (which the implementer will have open) rather than reproduced, since the home screen's exact structure is established code to follow, not new code to specify.

**Type consistency:** `CycleRecord.isActiveOn`, `computeScore`, `ScoreResult`, `DayLog`, `CareTip`, `CoupleScoreboard`, `PreferencesRepository.setKey(current:)` names are used consistently across tasks. `prayerLogRefreshTickProvider` defined in Task 11, consumed in Tasks 11 and 13.

**Open verification the implementer must do (noted inline):** confirm `AuthRepository.signOut()` method name (Task 19); confirm the mocktail `.then(...)` stubbing style against the installed supabase_flutter version — if the Postgrest builder isn't directly awaitable in mocks, switch those repository tests to a thin integration test against local Supabase.
