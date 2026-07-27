-- Sakīnah — Phase 1
--   • get_daily_content RPC: idempotently assigns today's verse/hadith/question
--     to the calling couple. Deterministic per (couple_id, date) so both
--     spouses see the same content.
--   • Curated seed content for verses / hadith / duas / daily_questions
--     focused on marriage, mercy, patience, family life.

------------------------------------------------------------------
-- RPC: get_daily_content
------------------------------------------------------------------

create or replace function public.get_daily_content(p_date date default null)
returns table (
  the_date date,
  verse_id uuid,
  hadith_id uuid,
  question_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple  uuid := public.current_couple();
  v_date    date := coalesce(p_date, current_date);
  v_verse   uuid;
  v_hadith  uuid;
  v_qod     uuid;
  v_seed    integer;
  v_row     public.daily_content%rowtype;
begin
  if v_couple is null then
    raise exception 'no_couple';
  end if;

  -- Fast path: already assigned for this couple + date.
  select * into v_row from public.daily_content
    where couple_id = v_couple and daily_content.date = v_date;

  if found then
    the_date := v_row.date;
    verse_id := v_row.verse_id;
    hadith_id := v_row.hadith_id;
    question_id := v_row.question_id;
    return next;
    return;
  end if;

  -- Deterministic per (couple, date) so both members always see the same picks
  -- even if they call this at the same time. hashtext handles the seed.
  v_seed := abs(hashtext(v_couple::text || v_date::text));
  perform setseed(least(0.99999, greatest(0, (v_seed::double precision / 2147483648.0))));

  select id into v_verse from public.verses order by random() limit 1;
  select id into v_hadith from public.hadiths order by random() limit 1;
  select id into v_qod from public.daily_questions order by random() limit 1;

  insert into public.daily_content (couple_id, date, verse_id, hadith_id, question_id)
    values (v_couple, v_date, v_verse, v_hadith, v_qod)
    on conflict (couple_id, date) do update set
      verse_id = excluded.verse_id,
      hadith_id = excluded.hadith_id,
      question_id = excluded.question_id
    returning * into v_row;

  the_date := v_row.date;
  verse_id := v_row.verse_id;
  hadith_id := v_row.hadith_id;
  question_id := v_row.question_id;
  return next;
end;
$$;

grant execute on function public.get_daily_content(date) to authenticated;

------------------------------------------------------------------
-- Seed: verses
------------------------------------------------------------------
insert into public.verses (surah_number, ayah_number, surah_name, arabic_text, translation_en, reference, theme_tags) values
(30, 21, 'Ar-Rum',
  'وَمِنْ آيَاتِهِ أَنْ خَلَقَ لَكُم مِّنْ أَنفُسِكُمْ أَزْوَاجًا لِّتَسْكُنُوا إِلَيْهَا وَجَعَلَ بَيْنَكُم مَّوَدَّةً وَرَحْمَةً',
  'And of His signs is that He created for you from yourselves mates that you may find tranquility in them; and He placed between you affection and mercy.',
  'Quran 30:21', array['marriage','mercy','tranquility']),
(2, 187, 'Al-Baqarah',
  'هُنَّ لِبَاسٌ لَّكُمْ وَأَنتُمْ لِبَاسٌ لَّهُنَّ',
  'They are a garment for you and you are a garment for them.',
  'Quran 2:187', array['marriage','protection','intimacy']),
(25, 74, 'Al-Furqan',
  'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ',
  'Our Lord, grant us from among our spouses and offspring comfort to our eyes.',
  'Quran 25:74', array['marriage','family','dua']),
(4, 19, 'An-Nisa',
  'وَعَاشِرُوهُنَّ بِالْمَعْرُوفِ',
  'And live with them in kindness.',
  'Quran 4:19', array['marriage','kindness']),
(3, 134, 'Aal Imran',
  'وَالْكَاظِمِينَ الْغَيْظَ وَالْعَافِينَ عَنِ النَّاسِ ۗ وَاللَّهُ يُحِبُّ الْمُحْسِنِينَ',
  'Those who restrain anger and pardon people — Allah loves those who do good.',
  'Quran 3:134', array['forgiveness','patience','virtue']),
(49, 10, 'Al-Hujurat',
  'إِنَّمَا الْمُؤْمِنُونَ إِخْوَةٌ فَأَصْلِحُوا بَيْنَ أَخَوَيْكُمْ',
  'Indeed the believers are brothers, so make peace between your brothers.',
  'Quran 49:10', array['reconciliation','peace']),
(2, 195, 'Al-Baqarah',
  'وَأَحْسِنُوا ۛ إِنَّ اللَّهَ يُحِبُّ الْمُحْسِنِينَ',
  'And do good; indeed, Allah loves the doers of good.',
  'Quran 2:195', array['virtue','love']),
(31, 22, 'Luqman',
  'وَمَن يُسْلِمْ وَجْهَهُ إِلَى اللَّهِ وَهُوَ مُحْسِنٌ فَقَدِ اسْتَمْسَكَ بِالْعُرْوَةِ الْوُثْقَىٰ',
  'Whoever submits his face to Allah while being a doer of good has grasped the most trustworthy handhold.',
  'Quran 31:22', array['trust','faith'])
on conflict (surah_number, ayah_number) do nothing;

------------------------------------------------------------------
-- Seed: hadiths
------------------------------------------------------------------
insert into public.hadiths (arabic_text, translation, narrator, source, reference, grading, theme_tags) values
(null,
  'The best of you are those who are best to their wives.',
  'Abu Hurayrah', 'Tirmidhi', 'Jami at-Tirmidhi 1162', 'sahih',
  array['marriage','kindness']),
(null,
  'None of you truly believes until he loves for his brother what he loves for himself.',
  'Anas ibn Malik', 'Bukhari', 'Sahih al-Bukhari 13', 'sahih',
  array['love','brotherhood']),
(null,
  'The strong man is not the one who wrestles others, but the one who controls himself in anger.',
  'Abu Hurayrah', 'Bukhari', 'Sahih al-Bukhari 6114', 'sahih',
  array['patience','self-control']),
(null,
  'A believing man should not resent a believing woman: if he dislikes one of her characteristics, he will be pleased with another.',
  'Abu Hurayrah', 'Muslim', 'Sahih Muslim 1469', 'sahih',
  array['marriage','patience']),
(null,
  'Kindness is not to be found in anything but that it adds to its beauty, and it is not withdrawn from anything but it makes it defective.',
  'Aisha', 'Muslim', 'Sahih Muslim 2594', 'sahih',
  array['kindness']),
(null,
  'Smiling at your brother is charity.',
  'Abu Dharr', 'Tirmidhi', 'Jami at-Tirmidhi 1956', 'hasan',
  array['charity','joy']),
(null,
  'He who does not thank people has not thanked Allah.',
  'Abu Hurayrah', 'Tirmidhi', 'Jami at-Tirmidhi 1954', 'sahih',
  array['gratitude']),
(null,
  'The most complete of the believers in faith are those with the best character, and the best of you are those who are best to their wives.',
  'Abu Hurayrah', 'Tirmidhi', 'Jami at-Tirmidhi 1162', 'sahih',
  array['marriage','character'])
on conflict do nothing;

------------------------------------------------------------------
-- Seed: daily_questions
------------------------------------------------------------------
insert into public.daily_questions (question, category, language) values
('What is one memory of us that made you smile this week?', 'reflective', 'en'),
('If we could take one trip together next year, where would it be?', 'future', 'en'),
('What is one dua you would like us to make together tonight?', 'deen', 'en'),
('What did I do recently that you appreciated but did not tell me?', 'reflective', 'en'),
('What is one habit we could build together to bring us closer to Allah?', 'deen', 'en'),
('If we had a full quiet day tomorrow, how would you want to spend it?', 'playful', 'en'),
('What is one thing about our life together you are most grateful for?', 'reflective', 'en'),
('What was the hardest thing for you this week — how can I help?', 'reflective', 'en'),
('Which surah do you want us to memorize together first?', 'deen', 'en'),
('What is one small thing I could do this week that would mean a lot?', 'reflective', 'en'),
('What is your favourite thing about us?', 'playful', 'en'),
('If we were to write a letter to our future children, what is one thing you would want them to know?', 'future', 'en'),
('Which sunnah of the Prophet ﷺ do you want us to revive together?', 'deen', 'en'),
('Name one moment this month you felt closest to me.', 'reflective', 'en')
on conflict do nothing;

------------------------------------------------------------------
-- Seed: duas_library — suggestions the users can add to their shared list
------------------------------------------------------------------
insert into public.duas_library (title, arabic_text, transliteration, translation, reference, category) values
(
  'Dua for spouses and offspring',
  'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا',
  'Rabbanā hab lanā min azwājinā wa dhurriyyātinā qurrata aʿyunin wajʿalnā lil-muttaqīna imāmā',
  'Our Lord, grant us from among our spouses and offspring comfort to our eyes, and make us a leader for the righteous.',
  'Quran 25:74', 'marriage'
),
(
  'Dua for entering a home',
  'اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَ الْمَوْلِجِ وَخَيْرَ الْمَخْرَجِ',
  'Allahumma innī asʾaluka khayra al-mawliji wa khayra al-makhraji',
  'O Allah, I ask You for the best of entrance and the best of exit.',
  'Abu Dawud 5096', 'home'
),
(
  'Dua for a difficult moment',
  'حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ',
  'Ḥasbunallāhu wa niʿma al-wakīl',
  'Sufficient for us is Allah, and He is the best Disposer of affairs.',
  'Quran 3:173', 'hardship'
),
(
  'Dua of Prophet Musa',
  'رَبِّ إِنِّي لِمَا أَنزَلْتَ إِلَيَّ مِنْ خَيْرٍ فَقِيرٌ',
  'Rabbi innī limā anzalta ilayya min khayrin faqīr',
  'My Lord, I am truly in need of whatever good You send down to me.',
  'Quran 28:24', 'sustenance'
),
(
  'Dua for patience',
  'رَبَّنَا أَفْرِغْ عَلَيْنَا صَبْرًا وَثَبِّتْ أَقْدَامَنَا',
  'Rabbanā afrigh ʿalaynā ṣabran wa thabbit aqdāmanā',
  'Our Lord, pour upon us patience and steady our feet.',
  'Quran 2:250', 'patience'
),
(
  'Morning dhikr',
  'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ',
  'Aṣbaḥnā wa aṣbaḥa al-mulku lillāh',
  'We have entered the morning and to Allah belongs all dominion.',
  'Muslim 2723', 'morning'
)
on conflict do nothing;
