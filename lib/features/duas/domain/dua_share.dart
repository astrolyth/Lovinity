import '../data/dua_library_repository.dart';

String formatDuaForChat(LibraryDua d) => [
  '🤲 ${d.title}',
  d.arabic,
  if (d.transliteration != null) d.transliteration!,
  '"${d.translation}"',
  if (d.reference != null) '— ${d.reference}',
].join('\n');

String duaListBody(LibraryDua d) =>
    '${d.arabic}\n\n${d.translation}${d.reference != null ? '\n\n— ${d.reference}' : ''}';
