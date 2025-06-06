import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_model.dart';
import 'package:path/path.dart' as path;

class VocabularyService extends ChangeNotifier {
  static const String _vocabularyPrefix = 'vocabulary_';
  final Map<String, VocabularyList> _vocabularyLists = {};
  String? _currentVideoName;
  
  // 获取所有生词本列表
  Map<String, VocabularyList> get vocabularyLists => _vocabularyLists;
  
  // 获取当前视频的生词本
  VocabularyList? get currentVocabularyList => 
      _currentVideoName != null ? _vocabularyLists[_currentVideoName] : null;
  
  // 获取所有单词总数
  int get totalWordCount {
    int count = 0;
    for (final list in _vocabularyLists.values) {
      count += list.words.length;
    }
    return count;
  }
  
  // 获取所有单词列表（平铺模式）
  List<VocabularyWord> getAllWords() {
    final allWords = <VocabularyWord>[];
    for (final list in _vocabularyLists.values) {
      allWords.addAll(list.words);
    }
    // 按添加时间排序
    allWords.sort((a, b) => b.addedTime.compareTo(a.addedTime));
    return allWords;
  }
  
  // 导出生词本为文本
  String exportVocabularyAsText() {
    final buffer = StringBuffer();
    buffer.writeln('# 生词本导出 - ${DateTime.now().toString().split('.')[0]}');
    buffer.writeln('# 总计 $totalWordCount 个单词');
    buffer.writeln();
    
    // 遍历所有生词本
    for (final videoName in _vocabularyLists.keys) {
      final vocabularyList = _vocabularyLists[videoName]!;
      buffer.writeln('## 视频: $videoName');
      buffer.writeln('- 单词数量: ${vocabularyList.words.length}');
      buffer.writeln();
      
      // 添加单词列表
      for (int i = 0; i < vocabularyList.words.length; i++) {
        final word = vocabularyList.words[i];
        buffer.writeln('${i + 1}. ${word.word}');
        buffer.writeln('   上下文: ${word.context}');
        buffer.writeln('   添加时间: ${word.addedTime.toString().split('.')[0]}');
        buffer.writeln();
      }
      buffer.writeln();
    }
    
    return buffer.toString();
  }
  
  // 导出生词本为CSV
  String exportVocabularyAsCSV() {
    final buffer = StringBuffer();
    // 添加CSV头
    buffer.writeln('单词,上下文,视频,添加时间');
    
    // 遍历所有生词本
    for (final videoName in _vocabularyLists.keys) {
      final vocabularyList = _vocabularyLists[videoName]!;
      
      // 添加单词列表
      for (final word in vocabularyList.words) {
        // 处理CSV中的特殊字符
        final escapedWord = word.word.replaceAll('"', '""');
        final escapedContext = word.context.replaceAll('"', '""').replaceAll('\n', ' ');
        final escapedVideoName = videoName.replaceAll('"', '""');
        final addedTime = word.addedTime.toString().split('.')[0];
        
        buffer.writeln('"$escapedWord","$escapedContext","$escapedVideoName","$addedTime"');
      }
    }
    
    return buffer.toString();
  }
  
  // 保存生词本到文件
  Future<String?> saveVocabularyToFile(String content, String filePath) async {
    try {
      final file = File(filePath);
      await file.writeAsString(content);
      return filePath;
    } catch (e) {
      debugPrint('保存生词本失败: $e');
      return null;
    }
  }
  
  // 设置当前视频名称
  void setCurrentVideo(String videoName) {
    _currentVideoName = videoName;
    
    // 如果该视频还没有生词本，创建一个空的
    if (!_vocabularyLists.containsKey(videoName)) {
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: [],
      );
      saveVocabularyList(videoName);
    }
    
    notifyListeners();
  }
  
  // 加载所有生词本
  Future<void> loadAllVocabularyLists() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    
    // 清空当前数据
    _vocabularyLists.clear();
    
    // 加载所有以_vocabularyPrefix开头的键
    for (final key in allKeys) {
      if (key.startsWith(_vocabularyPrefix)) {
        final videoName = key.substring(_vocabularyPrefix.length);
        final jsonString = prefs.getString(key);
        
        if (jsonString != null) {
          try {
            final json = jsonDecode(jsonString);
            final vocabularyList = VocabularyList.fromJson(json);
            _vocabularyLists[videoName] = vocabularyList;
          } catch (e) {
            debugPrint('加载生词本失败: $e');
          }
        }
      }
    }
    
    notifyListeners();
  }
  
  // 加载特定视频的生词本
  Future<void> loadVocabularyList(String videoName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _vocabularyPrefix + videoName;
    final jsonString = prefs.getString(key);
    
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString);
        final vocabularyList = VocabularyList.fromJson(json);
        _vocabularyLists[videoName] = vocabularyList;
        notifyListeners();
      } catch (e) {
        debugPrint('加载生词本失败: $e');
      }
    } else {
      // 如果不存在，创建一个空的
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: [],
      );
      saveVocabularyList(videoName);
    }
  }
  
  // 保存特定视频的生词本
  Future<void> saveVocabularyList(String videoName) async {
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    final prefs = await SharedPreferences.getInstance();
    final key = _vocabularyPrefix + videoName;
    final jsonString = jsonEncode(_vocabularyLists[videoName]!.toJson());
    
    await prefs.setString(key, jsonString);
  }
  
  // 添加单词到生词本
  Future<void> addWord(String videoName, String word, String context) async {
    if (!_vocabularyLists.containsKey(videoName)) {
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: [],
      );
    }
    
    // 检查单词是否已存在
    final existingWords = _vocabularyLists[videoName]!.words;
    final existingWordIndex = existingWords.indexWhere((w) => w.word == word);
    
    if (existingWordIndex >= 0) {
      // 如果已存在，更新
      final updatedWords = List<VocabularyWord>.from(existingWords);
      updatedWords[existingWordIndex] = VocabularyWord(
        word: word,
        context: context,
        addedTime: DateTime.now(),
      );
      
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
    } else {
      // 如果不存在，添加新的
      final updatedWords = List<VocabularyWord>.from(existingWords);
      updatedWords.add(VocabularyWord(
        word: word,
        context: context,
        addedTime: DateTime.now(),
      ));
      
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
    }
    
    await saveVocabularyList(videoName);
    notifyListeners();
  }
  
  // 从生词本中删除单词
  Future<void> removeWord(String videoName, String word) async {
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    final existingWords = _vocabularyLists[videoName]!.words;
    final updatedWords = existingWords.where((w) => w.word != word).toList();
    
    _vocabularyLists[videoName] = VocabularyList(
      videoName: videoName,
      words: updatedWords,
    );
    
    await saveVocabularyList(videoName);
    notifyListeners();
  }
  
  // 删除整个生词本
  Future<void> deleteVocabularyList(String videoName) async {
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    _vocabularyLists.remove(videoName);
    
    final prefs = await SharedPreferences.getInstance();
    final key = _vocabularyPrefix + videoName;
    await prefs.remove(key);
    
    notifyListeners();
  }
  
  // 添加单词到生词本 (简化版)
  void addWordToVocabulary(String word, String context, String videoPath) {
    if (word.isEmpty) return;
    
    // 从视频路径中提取视频名称
    final videoName = path.basename(videoPath);
    
    // 如果当前没有加载生词本，或者加载的不是这个视频的生词本，先加载
    if (currentVocabularyList == null || currentVocabularyList!.videoName != videoName) {
      setCurrentVideo(videoName);
      loadVocabularyList(videoName);
    }
    
    // 添加单词
    addWord(videoName, word, context);
  }
} 