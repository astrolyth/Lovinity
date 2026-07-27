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
