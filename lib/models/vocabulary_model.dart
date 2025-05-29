class VocabularyWord {
  final String word;        // 单词
  final String context;     // 上下文(字幕文本)
  final DateTime addedTime; // 添加时间
  
  VocabularyWord({
    required this.word,
    required this.context,
    required this.addedTime,
  });
  
  // 从JSON转换
  factory VocabularyWord.fromJson(Map<String, dynamic> json) {
    return VocabularyWord(
      word: json['word'] as String,
      context: json['context'] as String,
      addedTime: DateTime.parse(json['addedTime'] as String),
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'context': context,
      'addedTime': addedTime.toIso8601String(),
    };
  }
}

class VocabularyList {
  final String videoName;             // 视频名称
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