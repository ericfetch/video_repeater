import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/subtitle_model.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../utils/word_lemmatizer.dart';

/// 字幕分析结果数据类
class SubtitleAnalysisResult {
  final Map<String, int> wordFrequency;
  final Map<String, String> wordToSubtitle;
  final Map<String, SubtitleEntry> wordToSubtitleEntry;
  final Set<String> subtitleWords;
  final Map<String, Set<String>> lemmaToOriginalWords;
  final int totalWords;
  final int uniqueWords;
  final int knownWords;
  final int vocabularyWords;
  final int unknownWords;
  final int familiarWords;
  final int needsLearningWords;
  final List<MapEntry<String, int>> originalSortedWords;
  final String videoTitle;
  final DateTime analysisTime;

  SubtitleAnalysisResult({
    required this.wordFrequency,
    required this.wordToSubtitle,
    required this.wordToSubtitleEntry,
    required this.subtitleWords,
    required this.lemmaToOriginalWords,
    required this.totalWords,
    required this.uniqueWords,
    required this.knownWords,
    required this.vocabularyWords,
    required this.unknownWords,
    required this.familiarWords,
    required this.needsLearningWords,
    required this.originalSortedWords,
    required this.videoTitle,
    required this.analysisTime,
  });
}

/// 字幕分析服务
/// 负责在后台静默分析字幕，缓存分析结果，只要应用不关闭就保持数据
class SubtitleAnalysisService extends ChangeNotifier {
  final VocabularyService _vocabularyService;
  final DictionaryService _dictionaryService;
  
  // 缓存分析结果，key为视频路径+字幕路径的组合
  final Map<String, SubtitleAnalysisResult> _analysisCache = {};
  
  // 正在分析的视频标识符集合
  final Set<String> _analyzingVideos = {};
  
  // 使用最先进的词形还原模式
  final LemmatizationMode _lemmatizationMode = LemmatizationMode.precise;

  SubtitleAnalysisService({
    required VocabularyService vocabularyService,
    required DictionaryService dictionaryService,
  }) : _vocabularyService = vocabularyService,
       _dictionaryService = dictionaryService;

  /// 获取视频的唯一标识符
  String _getVideoKey(String videoPath, String? subtitlePath) {
    return '$videoPath|${subtitlePath ?? ""}';
  }

  /// 检查是否有缓存的分析结果
  bool hasAnalysisResult(String videoPath, String? subtitlePath) {
    final key = _getVideoKey(videoPath, subtitlePath);
    final hasResult = _analysisCache.containsKey(key);
    debugPrint('hasAnalysisResult - key: $key, hasResult: $hasResult');
    return hasResult;
  }

  /// 调试：显示当前缓存状态
  void debugCacheStatus() {
    debugPrint('=== 分析缓存状态 ===');
    debugPrint('缓存数量: ${_analysisCache.length}');
    for (final key in _analysisCache.keys) {
      debugPrint('缓存key: $key');
    }
    debugPrint('正在分析: $_analyzingVideos');
    debugPrint('================');
  }

  /// 获取缓存的分析结果
  SubtitleAnalysisResult? getAnalysisResult(String videoPath, String? subtitlePath) {
    final key = _getVideoKey(videoPath, subtitlePath);
    return _analysisCache[key];
  }

  /// 检查是否正在分析
  bool isAnalyzing(String videoPath, String? subtitlePath) {
    final key = _getVideoKey(videoPath, subtitlePath);
    return _analyzingVideos.contains(key);
  }

  /// 静默分析字幕
  Future<void> analyzeSubtitlesSilently({
    required String videoPath,
    required String? subtitlePath,
    required String videoTitle,
    required List<SubtitleEntry> subtitles,
  }) async {
    final key = _getVideoKey(videoPath, subtitlePath);
    
    // 如果已经有缓存或正在分析，跳过
    if (_analysisCache.containsKey(key) || _analyzingVideos.contains(key)) {
      debugPrint('字幕分析: 跳过分析 - 已有缓存或正在分析: $key');
      return;
    }

    debugPrint('字幕分析: 开始静默分析: $key');
    _analyzingVideos.add(key);
    notifyListeners();

    try {
      final result = await _performAnalysis(videoTitle, subtitles);
      _analysisCache[key] = result;
      debugPrint('字幕分析: 完成静默分析: $key (缓存大小: ${_analysisCache.length})');
    } catch (e) {
      debugPrint('字幕分析: 分析失败: $e');
    } finally {
      _analyzingVideos.remove(key);
      notifyListeners();
    }
  }

  /// 执行实际的分析工作
  Future<SubtitleAnalysisResult> _performAnalysis(
    String videoTitle,
    List<SubtitleEntry> subtitles,
  ) async {
    // 使用新的逻辑进行分析：先拆句子，再拆单词
    final List<String> sentences = []; // 所有句子列表
    final Map<String, SubtitleEntry> sentenceToEntry = {}; // 句子到字幕条目的映射
    
    // 1. 将所有字幕收集为句子，并建立句子到字幕条目的映射
    for (final subtitle in subtitles) {
      sentences.add(subtitle.text);
      sentenceToEntry[subtitle.text] = subtitle;
    }
    
    // 2. 从句子中提取单词并建立映射关系
    final wordFrequency = <String, int>{};
    final wordToSubtitle = <String, String>{};
    final wordToSubtitleEntry = <String, SubtitleEntry>{};
    final subtitleWords = <String>{};
    final lemmaToOriginalWords = <String, Set<String>>{};
    final regex = RegExp(r'\b[a-zA-Z]+\b');
    
    for (final sentence in sentences) {
      final matches = regex.allMatches(sentence.toLowerCase());
      for (final match in matches) {
        final originalWord = match.group(0)!;
        if (originalWord.length > 1) { // 忽略单个字母
          // 使用改进的词形还原获取词根
          final lemma = ImprovedWordLemmatizer.lemmatize(originalWord, _lemmatizationMode);
          
          // 添加词根到字幕单词集合
          subtitleWords.add(lemma);
          
          // 记录词根到原始单词的映射
          if (!lemmaToOriginalWords.containsKey(lemma)) {
            lemmaToOriginalWords[lemma] = <String>{};
          }
          lemmaToOriginalWords[lemma]!.add(originalWord);
          
          // 使用词根更新频率
          wordFrequency[lemma] = (wordFrequency[lemma] ?? 0) + 1;
          
          // 如果这个词根第一次出现，记录它所在的句子
          if (!wordToSubtitle.containsKey(lemma)) {
            wordToSubtitle[lemma] = sentence;
            // 同时记录词根与字幕条目的对应关系
            final entry = sentenceToEntry[sentence];
            if (entry != null) {
              wordToSubtitleEntry[lemma] = entry;
            }
          }
        }
      }
    }
    
    // 统计数据
    int totalWords = 0;
    wordFrequency.forEach((_, count) => totalWords += count);
    final uniqueWords = wordFrequency.length;
    
    // 分类统计
    int knownWords = 0;
    int vocabularyWords = 0;
    int unknownWords = 0;
    int familiarWords = 0;
    int needsLearningWords = 0;
    
    final vocabularyWordsSet = _vocabularyService.getAllWords().map((w) => w.word.toLowerCase()).toSet();
    
    wordFrequency.forEach((word, _) {
      if (_dictionaryService.isFamiliar(word)) {
        familiarWords++;
      } else {
        // 所有不熟知的单词都算作需要学习
        needsLearningWords++;
        
        if (_dictionaryService.containsWord(word)) {
          knownWords++;
        } else if (vocabularyWordsSet.contains(word.toLowerCase())) {
          vocabularyWords++;
        } else {
          unknownWords++;
        }
      }
    });
    
    // 创建并排序原始单词列表（按频率排序）
    final originalWords = wordFrequency.entries.toList();
    originalWords.sort((a, b) => b.value.compareTo(a.value));
    
    return SubtitleAnalysisResult(
      wordFrequency: wordFrequency,
      wordToSubtitle: wordToSubtitle,
      wordToSubtitleEntry: wordToSubtitleEntry,
      subtitleWords: subtitleWords,
      lemmaToOriginalWords: lemmaToOriginalWords,
      totalWords: totalWords,
      uniqueWords: uniqueWords,
      knownWords: knownWords,
      vocabularyWords: vocabularyWords,
      unknownWords: unknownWords,
      familiarWords: familiarWords,
      needsLearningWords: needsLearningWords,
      originalSortedWords: originalWords,
      videoTitle: videoTitle,
      analysisTime: DateTime.now(),
    );
  }

  /// 清除指定视频的分析缓存
  void clearAnalysisCache(String videoPath, String? subtitlePath) {
    final key = _getVideoKey(videoPath, subtitlePath);
    _analysisCache.remove(key);
    _analyzingVideos.remove(key);
    debugPrint('字幕分析: 清除缓存: $key');
    notifyListeners();
  }

  /// 清除所有分析缓存
  void clearAllCache() {
    _analysisCache.clear();
    _analyzingVideos.clear();
    debugPrint('字幕分析: 清除所有缓存');
    notifyListeners();
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedVideos': _analysisCache.length,
      'analyzingVideos': _analyzingVideos.length,
      'totalMemoryUsed': _analysisCache.values.map((r) => r.wordFrequency.length).fold<int>(0, (a, b) => a + b),
    };
  }

  /// 汇总多个视频的分析结果
  MultiVideoAnalysisResult? getMultiVideoAnalysis(List<String> videoKeys) {
    final validResults = <SubtitleAnalysisResult>[];
    
    for (final key in videoKeys) {
      final result = _analysisCache[key];
      if (result != null) {
        validResults.add(result);
      }
    }
    
    if (validResults.isEmpty) return null;
    
    return _calculateMultiVideoStats(validResults);
  }

  /// 获取今日视频分析汇总（通过视频路径列表）
  MultiVideoAnalysisResult? getTodayAnalysisSummary(List<String> videoPaths, List<String?> subtitlePaths) {
    final videoKeys = <String>[];
    
    for (int i = 0; i < videoPaths.length; i++) {
      final videoPath = videoPaths[i];
      final subtitlePath = i < subtitlePaths.length ? subtitlePaths[i] : null;
      final key = _getVideoKey(videoPath, subtitlePath);
      videoKeys.add(key);
    }
    
    return getMultiVideoAnalysis(videoKeys);
  }

  /// 计算多视频统计数据
  MultiVideoAnalysisResult _calculateMultiVideoStats(List<SubtitleAnalysisResult> results) {
    // 合并所有单词频率
    final combinedWordFrequency = <String, int>{};
    final combinedWordToSubtitle = <String, String>{};
    final combinedSubtitleWords = <String>{};
    final combinedLemmaToOriginalWords = <String, Set<String>>{};
    
    int totalWords = 0;
    int totalFamiliarWords = 0;
    int totalKnownWords = 0;
    int totalVocabularyWords = 0;
    int totalUnknownWords = 0;
    int totalNeedsLearningWords = 0;
    
    for (final result in results) {
      // 合并词频
      result.wordFrequency.forEach((word, frequency) {
        combinedWordFrequency[word] = (combinedWordFrequency[word] ?? 0) + frequency;
        
        // 如果这个单词第一次出现，记录其字幕信息
        if (!combinedWordToSubtitle.containsKey(word)) {
          combinedWordToSubtitle[word] = result.wordToSubtitle[word] ?? '';
        }
      });
      
      // 合并字幕单词集合
      combinedSubtitleWords.addAll(result.subtitleWords);
      
      // 合并词根映射
      result.lemmaToOriginalWords.forEach((lemma, originalWords) {
        if (!combinedLemmaToOriginalWords.containsKey(lemma)) {
          combinedLemmaToOriginalWords[lemma] = <String>{};
        }
        combinedLemmaToOriginalWords[lemma]!.addAll(originalWords);
      });
      
      // 累加统计数据
      totalWords += result.totalWords;
      totalFamiliarWords += result.familiarWords;
      totalKnownWords += result.knownWords;
      totalVocabularyWords += result.vocabularyWords;
      totalUnknownWords += result.unknownWords;
      totalNeedsLearningWords += result.needsLearningWords;
    }
    
    // 重新计算唯一单词数（因为可能有重复）
    final uniqueWords = combinedWordFrequency.length;
    
    // 重新排序单词列表
    final sortedWords = combinedWordFrequency.entries.toList();
    sortedWords.sort((a, b) => b.value.compareTo(a.value));
    
    // 计算去重后的分类统计
    int uniqueFamiliarWords = 0;
    int uniqueKnownWords = 0;
    int uniqueVocabularyWords = 0;
    int uniqueUnknownWords = 0;
    int uniqueNeedsLearningWords = 0;
    
    final vocabularyWordsSet = _vocabularyService.getAllWords().map((w) => w.word.toLowerCase()).toSet();
    
    combinedWordFrequency.forEach((word, _) {
      if (_dictionaryService.isFamiliar(word)) {
        uniqueFamiliarWords++;
      } else {
        uniqueNeedsLearningWords++;
        
        if (_dictionaryService.containsWord(word)) {
          uniqueKnownWords++;
        } else if (vocabularyWordsSet.contains(word.toLowerCase())) {
          uniqueVocabularyWords++;
        } else {
          uniqueUnknownWords++;
        }
      }
    });
    
    return MultiVideoAnalysisResult(
      videoCount: results.length,
      combinedWordFrequency: combinedWordFrequency,
      combinedWordToSubtitle: combinedWordToSubtitle,
      combinedSubtitleWords: combinedSubtitleWords,
      combinedLemmaToOriginalWords: combinedLemmaToOriginalWords,
      totalWords: totalWords,
      uniqueWords: uniqueWords,
      totalFamiliarWords: totalFamiliarWords,
      totalKnownWords: totalKnownWords,
      totalVocabularyWords: totalVocabularyWords,
      totalUnknownWords: totalUnknownWords,
      totalNeedsLearningWords: totalNeedsLearningWords,
      uniqueFamiliarWords: uniqueFamiliarWords,
      uniqueKnownWords: uniqueKnownWords,
      uniqueVocabularyWords: uniqueVocabularyWords,
      uniqueUnknownWords: uniqueUnknownWords,
      uniqueNeedsLearningWords: uniqueNeedsLearningWords,
      sortedWords: sortedWords,
      analysisTime: DateTime.now(),
      dictionaryService: _dictionaryService,
    );
  }

  /// 获取学习进度对比（对比昨天和今天的数据）
  LearningProgressComparison? getLearningProgress(
    List<String> todayVideoKeys,
    List<String> yesterdayVideoKeys,
  ) {
    final todayResult = getMultiVideoAnalysis(todayVideoKeys);
    final yesterdayResult = getMultiVideoAnalysis(yesterdayVideoKeys);
    
    if (todayResult == null) return null;
    
    return LearningProgressComparison(
      today: todayResult,
      yesterday: yesterdayResult,
    );
  }

  @override
  void dispose() {
    clearAllCache();
    super.dispose();
  }
}

/// 多视频分析结果
class MultiVideoAnalysisResult {
  final int videoCount;
  final Map<String, int> combinedWordFrequency;
  final Map<String, String> combinedWordToSubtitle;
  final Set<String> combinedSubtitleWords;
  final Map<String, Set<String>> combinedLemmaToOriginalWords;
  final int totalWords;
  final int uniqueWords;
  final int totalFamiliarWords;
  final int totalKnownWords;
  final int totalVocabularyWords;
  final int totalUnknownWords;
  final int totalNeedsLearningWords;
  final int uniqueFamiliarWords;
  final int uniqueKnownWords;
  final int uniqueVocabularyWords;
  final int uniqueUnknownWords;
  final int uniqueNeedsLearningWords;
  final List<MapEntry<String, int>> sortedWords;
  final DateTime analysisTime;
  final DictionaryService _dictionaryService;

  MultiVideoAnalysisResult({
    required this.videoCount,
    required this.combinedWordFrequency,
    required this.combinedWordToSubtitle,
    required this.combinedSubtitleWords,
    required this.combinedLemmaToOriginalWords,
    required this.totalWords,
    required this.uniqueWords,
    required this.totalFamiliarWords,
    required this.totalKnownWords,
    required this.totalVocabularyWords,
    required this.totalUnknownWords,
    required this.totalNeedsLearningWords,
    required this.uniqueFamiliarWords,
    required this.uniqueKnownWords,
    required this.uniqueVocabularyWords,
    required this.uniqueUnknownWords,
    required this.uniqueNeedsLearningWords,
    required this.sortedWords,
    required this.analysisTime,
    required DictionaryService dictionaryService,
  }) : _dictionaryService = dictionaryService;

  /// 获取需要学习的单词列表（按频率排序）
  List<MapEntry<String, int>> get needsLearningWords {
    return sortedWords.where((entry) {
      return !_dictionaryService.isFamiliar(entry.key);
    }).toList();
  }

  /// 获取高频但未掌握的单词（前50个需要学习的单词）
  List<MapEntry<String, int>> get topNeedsLearningWords {
    return needsLearningWords.take(50).toList();
  }

  /// 词汇掌握率
  double get vocabularyMasteryRate {
    return uniqueWords > 0 ? uniqueFamiliarWords / uniqueWords : 0.0;
  }

  /// 学习潜力（未掌握单词的总频次）
  int get learningPotential {
    return needsLearningWords.fold<int>(0, (sum, entry) => sum + entry.value);
  }
}

/// 学习进度对比
class LearningProgressComparison {
  final MultiVideoAnalysisResult today;
  final MultiVideoAnalysisResult? yesterday;

  LearningProgressComparison({
    required this.today,
    this.yesterday,
  });

  /// 今日新接触的单词数量
  int get newWordsToday {
    if (yesterday == null) return today.uniqueWords;
    
    final yesterdayWords = yesterday!.combinedSubtitleWords;
    final todayWords = today.combinedSubtitleWords;
    
    return todayWords.difference(yesterdayWords).length;
  }

  /// 词汇掌握率提升
  double get masteryRateImprovement {
    if (yesterday == null) return 0.0;
    
    return today.vocabularyMasteryRate - yesterday!.vocabularyMasteryRate;
  }

  /// 学习效率（新单词与学习时长的比率）
  double getLearningEfficiency(int studyDurationMinutes) {
    if (studyDurationMinutes <= 0) return 0.0;
    return newWordsToday / studyDurationMinutes;
  }
} 