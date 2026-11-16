-- Seed content for the love-map game and the date-idea library.
--
-- Unlike the lessons, these rows make no religious claims — they are prompts
-- and suggestions. That is why the risk split in the roadmap puts them on the
-- generated-plus-approval side while lessons are hand-authored: a weak prompt
-- is a dull evening, a wrong ruling is a different category of harm.
--
-- This is a curated starter set so the features are usable before any
-- generation pipeline runs. Seeded `approved = true`: each line has been read,
-- and unlike a model's output there is nothing here awaiting review. Anything
-- the edge function generates later lands `approved = false` by column default
-- and must be reviewed before it is served.

insert into public.love_map_quizzes (question, category, approved) values
  ('What is the surah your spouse turns to when they are struggling?', 'deen', true),
  ('Which act of worship does your spouse find hardest to keep consistent?', 'deen', true),
  ('What does your spouse most want to be different about their deen in a year?', 'deen', true),
  ('Which masjid or place has meant the most to your spouse?', 'deen', true),
  ('If money were not a constraint, where would your spouse want to live?', 'dreams', true),
  ('What is a skill your spouse has quietly wanted to learn for years?', 'dreams', true),
  ('What does your spouse hope people say about them at their janāzah?', 'dreams', true),
  ('What does your spouse want your home to feel like to a guest?', 'dreams', true),
  ('What is your spouse most looking forward to in the next five years?', 'dreams', true),
  ('What was your spouse most afraid of before you married?', 'history', true),
  ('Who outside your family has shaped your spouse the most?', 'history', true),
  ('What is a moment from your spouse''s childhood they still think about?', 'history', true),
  ('What was your spouse''s first impression of you, honestly?', 'history', true),
  ('How does your spouse most like to be comforted after a hard day?', 'preferences', true),
  ('What is a small thing you do that your spouse genuinely loves?', 'preferences', true),
  ('What is your spouse''s idea of a restful day?', 'preferences', true),
  ('Which meal would your spouse never get tired of?', 'preferences', true),
  ('Does your spouse prefer to be asked, or to be surprised?', 'preferences', true);

insert into public.date_ideas
  (title, description, setting, category, effort, cost_band, approved)
values
  ('Cook one thing neither of you has made',
   'Pick a dish you have both only eaten out. Split the steps and accept it may go badly — that is most of the fun.',
   'home', 'food', 'medium', 'low', true),
  ('Read one page aloud each night',
   'Choose a short book and take turns. A page is small enough that neither of you can reasonably skip it.',
   'home', 'learning', 'low', 'free', true),
  ('Memorise a short surah together',
   'Take a few āyāt each week and test each other. Progress you can both hear is unusually motivating.',
   'home', 'deen', 'low', 'free', true),
  ('Plan the week over good coffee',
   'Do the boring admin deliberately, with something nice to drink. It stops logistics leaking into the rest of the week.',
   'home', 'planning', 'low', 'free', true),
  ('Rearrange one room together',
   'Pick a single room and change it. Shared physical effort with a visible result at the end.',
   'home', 'home', 'medium', 'free', true),
  ('Pray fajr and then walk',
   'Stay up or wake together, pray, and walk while it is still quiet. Very few things feel like that hour does.',
   'out', 'deen', 'medium', 'free', true),
  ('Visit a masjid you have never prayed in',
   'Somewhere neither of you knows. Stay afterwards rather than leaving straight away.',
   'out', 'deen', 'medium', 'free', true),
  ('Walk a market with no intention to buy',
   'Set a rule that you are only looking. It turns shopping into wandering.',
   'out', 'outdoors', 'low', 'free', true),
  ('Take the long way somewhere',
   'Pick a destination and deliberately take the slower route. The point is the transit, not the arrival.',
   'out', 'outdoors', 'low', 'low', true),
  ('Feed someone else',
   'Cook or buy a meal and give it away together. Shared sadaqah is a different kind of evening.',
   'out', 'sadaqah', 'medium', 'low', true),
  ('Eat the same meal on camera',
   'Agree the dish in advance, cook separately, eat together on a call. Closer to a shared meal than it sounds.',
   'virtual', 'food', 'medium', 'low', true),
  ('Watch one lecture in sync',
   'Start the same talk at the same moment and pause whenever either of you wants to say something.',
   'virtual', 'deen', 'low', 'free', true),
  ('Recite to each other over a call',
   'Take turns reciting and correcting. It works as well down a phone line as it does in a room.',
   'virtual', 'deen', 'low', 'free', true),
  ('Plan the reunion in detail',
   'Actually build the itinerary for when you are next together. Planning it is most of the anticipation.',
   'virtual', 'planning', 'medium', 'free', true),
  ('Take the same walk apart',
   'Both go outside at the same time, stay on the call, and describe what you can see.',
   'virtual', 'outdoors', 'low', 'free', true),
  ('Write to each other instead of calling',
   'Swap a long written letter one evening rather than talking. You say different things in writing.',
   'virtual', 'connection', 'low', 'free', true);
