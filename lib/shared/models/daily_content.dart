class VerseOfDay {
  const VerseOfDay({
    required this.id,
    required this.surahName,
    required this.surahNumber,
    required this.ayahNumber,
    required this.arabicText,
    required this.translation,
    required this.reference,
    this.transliteration,
  });

  final String id;
  final String surahName;
  final int surahNumber;
  final int ayahNumber;
  final String arabicText;
  final String translation;
  final String reference;
  final String? transliteration;

  factory VerseOfDay.fromRow(Map<String, dynamic> row) => VerseOfDay(
        id: row['id'] as String,
        surahName: row['surah_name'] as String,
        surahNumber: (row['surah_number'] as num).toInt(),
        ayahNumber: (row['ayah_number'] as num).toInt(),
        arabicText: row['arabic_text'] as String,
        translation: row['translation_en'] as String,
        reference: row['reference'] as String,
        transliteration: row['transliteration'] as String?,
      );
}

class HadithOfDay {
  const HadithOfDay({
    required this.id,
    required this.translation,
    required this.narrator,
    required this.source,
    required this.reference,
    this.arabicText,
    this.grading,
  });

  final String id;
  final String? arabicText;
  final String translation;
  final String? narrator;
  final String source;
  final String reference;
  final String? grading;

  factory HadithOfDay.fromRow(Map<String, dynamic> row) => HadithOfDay(
        id: row['id'] as String,
        arabicText: row['arabic_text'] as String?,
        translation: row['translation'] as String,
        narrator: row['narrator'] as String?,
        source: row['source'] as String,
        reference: row['reference'] as String,
        grading: row['grading'] as String?,
      );
}

class QuestionOfDay {
  const QuestionOfDay({
    required this.id,
    required this.question,
    this.category,
  });

  final String id;
  final String question;
  final String? category;

  factory QuestionOfDay.fromRow(Map<String, dynamic> row) => QuestionOfDay(
        id: row['id'] as String,
        question: row['question'] as String,
        category: row['category'] as String?,
      );
}

class DailyContent {
  const DailyContent({
    required this.date,
    required this.verse,
    required this.hadith,
    required this.question,
  });

  final DateTime date;
  final VerseOfDay? verse;
  final HadithOfDay? hadith;
  final QuestionOfDay? question;
}
