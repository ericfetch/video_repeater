import 'package:hive/hive.dart';

part 'vocabulary_model.g.dart';

@HiveType(typeId: 4)
class VocabularyWord {
  @HiveField(0)
  final String word;        // 单词
  
  @HiveField(1)
  final String context;     // 上下文(字幕文本)
  
  @HiveField(2)
  final DateTime addedTime; // 添加时间
  
  @HiveField(3)
  final String videoName;   // 所属视频名称
  
  VocabularyWord({
    required this.word,
    required this.context,
    required this.addedTime,
    required this.videoName,
  });
  
  // 从JSON转换
  factory VocabularyWord.fromJson(Map<String, dynamic> json) {
    return VocabularyWord(
      word: json['word'] as String,
      context: json['context'] as String,
      addedTime: DateTime.parse(json['addedTime'] as String),
      videoName: json['videoName'] as String? ?? '',
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'context': context,
      'addedTime': addedTime.toIso8601String(),
      'videoName': videoName,
    };
  }
}

@HiveType(typeId: 5)
class VocabularyList {
  @HiveField(0)
  final String videoName;             // 视频名称
  
  @HiveField(1)
  final List<VocabularyWord> words;   // 单词列表
  
  VocabularyList({
    required this.videoName,
    required this.words,
  });
  
  // 从JSON转换
  factory VocabularyList.fromJson(Map<String, dynamic> json) {
    return VocabularyList(
      videoName: json['videoName'] as String,
      words: (json['words'] as List)
          .map((word) => VocabularyWord.fromJson(word as Map<String, dynamic>))
          .toList(),
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'videoName': videoName,
      'words': words.map((word) => word.toJson()).toList(),
    };
  }
} 