-- Seed content for co-studied lessons.
--
-- HAND-AUTHORED, NOT GENERATED, and deliberately so. These rows make religious
-- claims: an invented ḥadīth, a mis-attributed verse or a ruling stated more
-- firmly than the scholars state it is a real harm to the couple reading it,
-- not a cosmetic defect. Every row therefore carries a `reference`.
--
-- SCOPE DISCIPLINE for the fiqh entries: these stay on points of broad
-- agreement and describe rights and manners rather than adjudicating disputed
-- questions. Where madhhabs differ, the lesson says so and points the reader to
-- a scholar instead of picking a side. This app does not issue fatwa.
--
-- REVIEW STATUS: seeded with `approved = false`. The serving policy added in
-- 20260808000001 returns only approved rows, so nothing here reaches a couple
-- until a reviewer with database access flips the flag. That gate is the point
-- -- these lessons should be read by someone qualified before they ship.

insert into public.learning_lessons
  (title, category, language, body, arabic_body, reference, questions, approved)
values
  (
    'Garments for one another',
    'fiqh_marriage',
    'en',
    E'The Qur''an describes spouses as clothing for each other. Clothing is the closest thing to the body: it covers what should be covered, it protects from what is harsh outside, and it adorns. Scholars have long drawn all three meanings from the image — that each spouse guards the other''s faults rather than exposing them, shelters them from hardship, and is a source of dignity to them.\n\nRead it together and notice the order: the covering comes first. Much of what marriage asks of us is simply not repeating what we have seen.',
    'هُنَّ لِبَاسٌ لَّكُمْ وَأَنتُمْ لِبَاسٌ لَّهُنَّ',
    'Qur''an 2:187',
    '["Where has your spouse covered for you in a way you never acknowledged out loud?",
      "What is one fault of your spouse''s you have repeated to someone else, and will stop repeating?"]'::jsonb,
    false
  ),
  (
    'The best of you',
    'fiqh_marriage',
    'en',
    E'The Prophet ﷺ said: "The best of you is the one who is best to his family, and I am the best of you to my family." The measure offered here is not public reputation, length of prayer, or knowledge — it is conduct at home, where no one is watching and no one is impressed.\n\nIt is worth sitting with how uncomfortable that standard is. Most of us are more careful with our manners toward guests than toward the person we share a room with.',
    'خَيْرُكُمْ خَيْرُكُمْ لِأَهْلِهِ وَأَنَا خَيْرُكُمْ لِأَهْلِي',
    'Sunan al-Tirmidhī 3895 — graded ṣaḥīḥ by al-Albānī',
    '["Where are you gentler with strangers than with me?",
      "What is one thing I do at home that you wish I did more of?"]'::jsonb,
    false
  ),
  (
    'The mahr belongs to her',
    'fiqh_marriage',
    'en',
    E'The mahr is the wife''s own property, given to her and not to her family. The Qur''an instructs that it be given willingly, and that what she chooses to return of it is hers to choose — which only makes sense if it was hers to begin with.\n\nThe schools differ on questions of amount, timing and deferral, and those details are matters for a scholar who knows your situation. What is not disputed is whose property it is.',
    'وَآتُوا النِّسَاءَ صَدُقَاتِهِنَّ نِحْلَةً',
    'Qur''an 4:4',
    '["Do we both actually know what was agreed as mahr, and whether it was settled?",
      "Is there anything about our finances that one of us assumes and the other has never confirmed?"]'::jsonb,
    false
  ),
  (
    'Khadījah, before anyone believed',
    'seerah',
    'en',
    E'When the Prophet ﷺ returned from the cave of Ḥirā'' shaken and asked to be covered, Khadījah (may Allah be pleased with her) did not first ask him to explain himself or prove anything. She covered him, calmed him, listed back to him the good she had watched him do for years, and then took him to someone who might understand.\n\nShe believed him before anyone else did, and she did it by reasoning from his character — she had the evidence because she had been paying attention to how he lived.',
    null,
    'Ṣaḥīḥ al-Bukhārī 3 (the opening of revelation)',
    '["When was the last time I came to you unsettled, and what did you do?",
      "What good in me have you noticed that I have never heard you say out loud?"]'::jsonb,
    false
  ),
  (
    'Al-Wadūd — the Loving',
    'names_of_allah',
    'en',
    E'Al-Wadūd comes from *wudd*: love that shows itself in action, not merely love that is felt. It appears in the Qur''an paired with forgiveness — "And He is the Forgiving, the Loving" — placing divine love next to the covering of faults rather than in opposition to it.\n\nThe same root gives *mawadda*, the word used for what Allah places between spouses. It is worth noticing that the love named as a sign between a husband and wife is the demonstrated kind.',
    'وَهُوَ الْغَفُورُ الْوَدُودُ',
    'Qur''an 85:14; cf. 30:21 for mawadda between spouses',
    '["What does love look like from you when it is demonstrated rather than said?",
      "Which of my faults do you cover most often, and does it cost you something?"]'::jsonb,
    false
  ),
  (
    'Ar-Raḥmān and ar-Raḥīm',
    'names_of_allah',
    'en',
    E'Both names come from the root *r-ḥ-m*, which is also the root of *raḥim*, the womb. Classical commentators draw the connection out: a mercy bound up with nurture and closeness rather than mere leniency.\n\nEvery chapter of the Qur''an but one opens with these two names. Whatever else is being said, this is the frame it is said inside.',
    'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
    'Qur''an 1:1; on the r-ḥ-m / raḥim connection see Ṣaḥīḥ al-Bukhārī 5988',
    '["Where do you need mercy from me rather than fairness?",
      "When have I been technically right with you but not merciful?"]'::jsonb,
    false
  );
