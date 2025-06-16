import 'package:hive/hive.dart';

part 'dictionary_word.g.dart';

@HiveType(typeId: 31)
class DictionaryWord extends HiveObject {
  @HiveField(0)
  String word;

  @HiveField(1)
  String? partOfSpeech;

  @HiveField(2)
  String? definition;

  @HiveField(3)
  int? rank;

  @HiveField(4)
  bool isVocabulary;
  
  @HiveField(5)
  String? phonetic;
  
  @HiveField(6)
  String? cefr;
  
  @HiveField(7)
  Map<String, dynamic>? extraInfo;
  
  @HiveField(8)
  bool isFamiliar;

  DictionaryWord({
    required this.word,
    this.partOfSpeech,
    this.definition,
    this.rank,
    this.isVocabulary = false,
    this.phonetic,
    this.cefr,
    this.extraInfo,
    this.isFamiliar = false,
  });

  factory DictionaryWord.fromJson(Map<String, dynamic> json) {
    return DictionaryWord(
      word: json['word'] as String,
      partOfSpeech: json['partOfSpeech'] as String?,
      definition: json['definition'] as String?,
      rank: json['rank'] as int?,
      isVocabulary: json['isVocabulary'] as bool? ?? false,
      phonetic: json['phonetic'] as String?,
      cefr: json['cefr'] as String?,
      extraInfo: json['extraInfo'] != null 
          ? Map<String, dynamic>.from(json['extraInfo'] as Map) 
          : null,
      isFamiliar: json['isFamiliar'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'partOfSpeech': partOfSpeech,
      'definition': definition,
      'rank': rank,
      'isVocabulary': isVocabulary,
      'phonetic': phonetic,
      'cefr': cefr,
      'extraInfo': extraInfo,
      'isFamiliar': isFamiliar,
    };
  }
  
  // 获取CEFR等级字符串
  String? getCefrString() {
    if (cefr != null) return cefr;
    if (rank == null) return null;
    
    switch (rank) {
      case 1: return 'A1';
      case 2: return 'A2';
      case 3: return 'B1';
      case 4: return 'B2';
      case 5: return 'C1';
      case 6: return 'C2';
      default: return null;
    }
  }
} 