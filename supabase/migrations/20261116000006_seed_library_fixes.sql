-- Fixes to the 6 pre-existing seed rows that 000004 approved with no tags.

-- "Morning dhikr" (Muslim 2723) duplicates fitrahive's own morning item.
update public.duas_library set status = 'rejected'
where source = 'seed' and category = 'morning' and reference = 'Muslim 2723';

-- Tags from the suggestion-rule vocabulary so seed rows can be suggested.
update public.duas_library set tags = '{distress,protection}'
where source = 'seed' and reference = 'Quran 3:173';
update public.duas_library set tags = '{home,protection}'
where source = 'seed' and reference = 'Abu Dawud 5096';
update public.duas_library set tags = '{distress,grief}'
where source = 'seed' and reference = 'Quran 2:250';
update public.duas_library set tags = '{marriage,gratitude}'
where source = 'seed' and reference = 'Quran 25:74';
update public.duas_library set tags = '{distress,gratitude}'
where source = 'seed' and reference = 'Quran 28:24';

-- "Entering the House" is not a marriage dua (matches tool/content_tags.json).
update public.duas_library set tags = '{home}'
where source = 'fitrahive' and source_id in ('daily-dua/12', 'daily-dua/13');

alter table public.duas_library
  add constraint duas_library_repeat_count_check check (repeat_count >= 1);
