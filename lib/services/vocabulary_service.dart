import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_model.dart';
import '../models/subtitle_model.dart';
import '../utils/word_lemmatizer.dart';
import '../models/dictionary_word.dart';
import '../services/dictionary_service.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../main.dart'; // 导入main.dart以获取navigatorKey

// 定义VocabularyWord适配器
class VocabularyWordAdapter extends TypeAdapter<VocabularyWord> {
  @override
  final int typeId = 41;

  @override
  VocabularyWord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    
    return VocabularyWord(
      word: fields[0] as String,
      context: fields[1] as String,
      addedTime: fields[2] as DateTime,
      videoName: fields[3] as String,
      audioPath: fields.containsKey(4) ? fields[4] as String? : null,
      rememberedCount: fields.containsKey(5) ? fields[5] as int : 0,
    );
  }

  @override
  void write(BinaryWriter writer, VocabularyWord obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.word)
      ..writeByte(1)
      ..write(obj.context)
      ..writeByte(2)
      ..write(obj.addedTime)
      ..writeByte(3)
      ..write(obj.videoName)
      ..writeByte(4)
      ..write(obj.audioPath)
      ..writeByte(5)
      ..write(obj.rememberedCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabularyWordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// 定义VocabularyList适配器
class VocabularyListAdapter extends TypeAdapter<VocabularyList> {
  @override
  final int typeId = 42;

  @override
  VocabularyList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    
    return VocabularyList(
      videoName: fields[0] as String,
      words: (fields[1] as List).cast<VocabularyWord>(),
    );
  }

  @override
  void write(BinaryWriter writer, VocabularyList obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.videoName)
      ..writeByte(1)
      ..write(obj.words);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabularyListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VocabularyService extends ChangeNotifier {
  static const String _vocabularyBoxName = 'vocabulary_words';
  static const String _vocabularyListsBoxName = 'vocabulary_lists';
  
  // 静态变量用于跟踪Hive box是否已打开
  static bool _boxesOpened = false;
  
  late Box<VocabularyWord> _vocabularyBox;
  late Box<VocabularyList> _vocabularyListsBox;
  
  final Map<String, VocabularyList> _vocabularyLists = {};
  String? _currentVideoName;
  bool _isInitialized = false;
  
  // 获取所有生词本列表
  Map<String, VocabularyList> get vocabularyLists => _vocabularyLists;
  
  // 获取当前视频的生词本
  VocabularyList? get currentVocabularyList => 
      _currentVideoName != null ? _vocabularyLists[_currentVideoName] : null;
  
  // 获取所有单词总数
  int get totalWordCount {
    if (!_isInitialized) return 0;
    return _vocabularyBox.length;
  }
  
  // 获取当前生词本的单词数量
  int get wordCount {
    if (!_isInitialized || _currentVideoName == null || !_vocabularyLists.containsKey(_currentVideoName)) {
      return 0;
    }
    return _vocabularyLists[_currentVideoName]!.words.length;
  }
  
  // 检查生词本是否已加载
  bool isVocabularyLoaded() {
    return _isInitialized;
  }
  
  // 初始化Hive数据库
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final appDocumentDir = await getApplicationDocumentsDirectory();
      
      // 尝试初始化Hive
      try {
        Hive.init(appDocumentDir.path);
      } catch (e) {
        debugPrint('Hive可能已经初始化: $e');
      }
      
      // 注册适配器
      if (!Hive.isAdapterRegistered(41)) {
        Hive.registerAdapter(VocabularyWordAdapter());
        debugPrint('注册VocabularyWordAdapter成功，typeId=41');
      }
      if (!Hive.isAdapterRegistered(42)) {
        Hive.registerAdapter(VocabularyListAdapter());
        debugPrint('注册VocabularyListAdapter成功，typeId=42');
      }
      
      // 检查box是否已经打开
      if (!_boxesOpened) {
        try {
          // 尝试获取已打开的盒子
          if (Hive.isBoxOpen(_vocabularyBoxName)) {
            debugPrint('词汇盒子已经打开，获取现有实例');
            _vocabularyBox = Hive.box<VocabularyWord>(_vocabularyBoxName);
          } else {
            debugPrint('打开词汇盒子');
            _vocabularyBox = await Hive.openBox<VocabularyWord>(_vocabularyBoxName);
          }
          
          if (Hive.isBoxOpen(_vocabularyListsBoxName)) {
            debugPrint('词汇列表盒子已经打开，获取现有实例');
            _vocabularyListsBox = Hive.box<VocabularyList>(_vocabularyListsBoxName);
          } else {
            debugPrint('打开词汇列表盒子');
            _vocabularyListsBox = await Hive.openBox<VocabularyList>(_vocabularyListsBoxName);
          }
          
          debugPrint('盒子打开成功');
          _boxesOpened = true;
        } catch (e) {
          debugPrint('打开盒子失败: $e');
          // 不要删除数据，而是抛出异常让上层处理
          throw Exception('无法打开Hive盒子: $e');
        }
      } else {
        // 如果盒子已经打开，尝试获取已打开的实例
        debugPrint('盒子已经打开，尝试获取已打开的实例');
        try {
          _vocabularyBox = Hive.box<VocabularyWord>(_vocabularyBoxName);
          _vocabularyListsBox = Hive.box<VocabularyList>(_vocabularyListsBoxName);
          debugPrint('获取已打开的盒子成功');
        } catch (e) {
          debugPrint('获取已打开的盒子失败: $e');
          throw Exception('无法获取已打开的Hive盒子: $e');
        }
      }
      
      _isInitialized = true;
      
      // 加载所有生词本
      await loadAllVocabularyLists();
    } catch (e) {
      debugPrint('生词本服务初始化失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 关闭Hive数据库
  Future<void> close() async {
    if (!_isInitialized) return;
    
    await _vocabularyBox.close();
    await _vocabularyListsBox.close();
    _isInitialized = false;
  }
  
  // 获取所有单词列表（平铺模式）
  List<VocabularyWord> _cachedWords = [];
  DateTime _lastCacheTime = DateTime.fromMillisecondsSinceEpoch(0);
  final _cacheDuration = const Duration(seconds: 1); // 缓存1秒

  // isActive参数表示是否在生词本页面激活，只有激活时才打印日志
  List<VocabularyWord> getAllWords({bool isActive = false}) {
    if (!_isInitialized) return [];
    
    // 检查缓存是否有效
    final now = DateTime.now();
    if (_cachedWords.isNotEmpty && now.difference(_lastCacheTime) < _cacheDuration) {
      return _cachedWords;
    }
    
    try {
      // 安全获取所有单词，过滤掉可能的null值
      final allWords = _vocabularyBox.values
          .where((word) => word != null)
          .toList();
      
      // 按添加时间排序
      allWords.sort((a, b) => b.addedTime.compareTo(a.addedTime));
      
      // 更新缓存
      _cachedWords = allWords;
      _lastCacheTime = now;
      
      // 只有在生词本页面激活时才打印日志
      if (isActive) {
        debugPrint('获取所有单词，共${allWords.length}个');
      }
      return allWords;
    } catch (e) {
      // 只有在生词本页面激活时才打印日志
      if (isActive) {
        debugPrint('获取单词列表失败: $e');
        debugPrintStack(stackTrace: StackTrace.current);
      }
      return _cachedWords; // 发生错误时返回上次缓存的结果
    }
  }
  
  // 清除getAllWords的缓存，在添加、删除、修改单词后调用
  void _invalidateWordsCache() {
    _cachedWords = [];
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
    
    // 获取所有单词
    final allWords = getAllWords();
    
    // 添加单词列表
    for (final word in allWords) {
      // 处理CSV中的特殊字符
      final escapedWord = word.word.replaceAll('"', '""');
      final escapedContext = word.context.replaceAll('"', '""').replaceAll('\n', ' ');
      final escapedVideoName = word.videoName.replaceAll('"', '""');
      final addedTime = word.addedTime.toString().split('.')[0];
      
      buffer.writeln('"$escapedWord","$escapedContext","$escapedVideoName","$addedTime"');
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
    if (!_isInitialized) return;
    
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
    if (!_isInitialized) await initialize();
    
    // 清空当前数据
    _vocabularyLists.clear();
    
    try {
      debugPrint('开始加载所有生词本...');
      
      // 从Hive加载所有生词本
      final lists = _vocabularyListsBox.values;
      debugPrint('找到${lists.length}个生词本列表');
      
      for (final list in lists) {
        try {
          _vocabularyLists[list.videoName] = list;
          debugPrint('加载生词本: ${list.videoName}, 包含${list.words.length}个单词');
        } catch (e) {
          debugPrint('加载生词本"${list.videoName}"失败: $e');
        }
      }
      
      // 如果Hive中没有数据，尝试从旧的SharedPreferences中迁移
      if (_vocabularyLists.isEmpty) {
        debugPrint('生词本为空，尝试从SharedPreferences迁移数据');
        final recoveredCount = await _migrateFromSharedPreferences();
        debugPrint('从SharedPreferences恢复了$recoveredCount个生词本');
      }
      
      debugPrint('所有生词本加载完成，共${_vocabularyLists.length}个');
    } catch (e) {
      debugPrint('加载生词本失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
    
    notifyListeners();
  }
  
  // 从SharedPreferences迁移数据到Hive
  Future<int> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // 查找所有以vocabulary_开头的键
      for (final key in allKeys) {
        if (key.startsWith('vocabulary_')) {
          final videoName = key.substring('vocabulary_'.length);
          final jsonString = prefs.getString(key);
          
          if (jsonString != null) {
            try {
              final json = jsonDecode(jsonString);
              final vocabularyList = VocabularyList.fromJson(json);
              
              // 将生词本保存到Hive
              _vocabularyLists[videoName] = vocabularyList;
              await _vocabularyListsBox.put(videoName, vocabularyList);
              
              // 将单词保存到Hive
              for (final word in vocabularyList.words) {
                final wordWithVideo = VocabularyWord(
                  word: word.word,
                  context: word.context,
                  addedTime: word.addedTime,
                  videoName: videoName,
                );
                await _vocabularyBox.put(word.word, wordWithVideo);
              }
              
              // 删除旧的SharedPreferences数据
              await prefs.remove(key);
            } catch (e) {
              debugPrint('迁移生词本数据失败: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('从SharedPreferences迁移数据失败: $e');
    }
    
    return _vocabularyLists.length;
  }
  
  // 加载特定视频的生词本
  Future<void> loadVocabularyList(String videoName) async {
    if (!_isInitialized) await initialize();
    
    // 从Hive加载生词本
    final list = _vocabularyListsBox.get(videoName);
    
    if (list != null) {
      _vocabularyLists[videoName] = list;
    } else {
      // 如果不存在，创建一个空的
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: [],
      );
      await saveVocabularyList(videoName);
    }
    
    notifyListeners();
  }
  
  // 保存特定视频的生词本
  Future<void> saveVocabularyList(String videoName) async {
    if (!_isInitialized) await initialize();
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    // 保存到Hive
    await _vocabularyListsBox.put(videoName, _vocabularyLists[videoName]!);
  }
  
  // 添加单词到生词本
  Future<void> addWord(String videoName, String word, String context, {String? audioPath}) async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('添加单词到生词本: $word');
      
      // 确保视频生词本存在
      if (!_vocabularyLists.containsKey(videoName)) {
        debugPrint('创建新的生词本: $videoName');
        _vocabularyLists[videoName] = VocabularyList(
          videoName: videoName,
          words: [],
        );
      }
      
      // 对单词进行词形还原，获取原形
      final lemmatizedWord = WordLemmatizer.lemmatize(word);
      debugPrint('词形还原: $word -> $lemmatizedWord');
      
      // 创建新单词，使用还原后的形式
      final newWord = VocabularyWord(
        word: lemmatizedWord,
        context: context,
        addedTime: DateTime.now(),
        videoName: videoName,
        audioPath: audioPath,
      );
      
      // 检查单词是否已存在
      final existingWords = _vocabularyLists[videoName]!.words;
      final existingWordIndex = existingWords.indexWhere((w) => w.word == lemmatizedWord);
      
      if (existingWordIndex >= 0) {
        debugPrint('单词已存在，更新: $lemmatizedWord');
        // 如果已存在，更新
        final updatedWords = List<VocabularyWord>.from(existingWords);
        updatedWords[existingWordIndex] = newWord;
        
        _vocabularyLists[videoName] = VocabularyList(
          videoName: videoName,
          words: updatedWords,
        );
      } else {
        debugPrint('添加新单词: $lemmatizedWord');
        // 如果不存在，添加新的
        final updatedWords = List<VocabularyWord>.from(existingWords);
        updatedWords.add(newWord);
        
        _vocabularyLists[videoName] = VocabularyList(
          videoName: videoName,
          words: updatedWords,
        );
      }
      
      try {
        // 保存到Hive
        debugPrint('保存单词到Hive: $lemmatizedWord');
        await _vocabularyBox.put(lemmatizedWord, newWord);
        
        debugPrint('保存生词本列表到Hive: $videoName');
        await saveVocabularyList(videoName);
        
        debugPrint('单词添加成功: $lemmatizedWord');
      } catch (e) {
        debugPrint('保存到Hive失败: $e');
        debugPrintStack(stackTrace: StackTrace.current);
      }
      
      // 清除缓存
      _invalidateWordsCache();
      
      notifyListeners();
    } catch (e) {
      debugPrint('添加单词失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 从生词本中删除单词
  Future<void> removeWord(String videoName, String word) async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('尝试从生词本"$videoName"中删除单词: $word');
      
      if (!_vocabularyLists.containsKey(videoName)) {
        debugPrint('生词本不存在: $videoName');
        return;
      }
      
      // 从视频生词本中删除
      final existingWords = _vocabularyLists[videoName]!.words;
      final wordExists = existingWords.any((w) => w.word == word);
      
      if (!wordExists) {
        debugPrint('单词"$word"不存在于生词本"$videoName"中');
        return;
      }
      
      // 创建不包含要删除单词的新列表
      final updatedWords = existingWords.where((w) => w.word != word).toList();
      
      // 更新内存中的生词本
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
      
      // 安全地从Hive中删除单词
      if (await _vocabularyBox.containsKey(word)) {
        await _vocabularyBox.delete(word);
        debugPrint('从Hive中删除单词: $word');
      } else {
        debugPrint('Hive中不存在单词: $word');
      }
      
      // 保存更新后的生词本
      await saveVocabularyList(videoName);
      debugPrint('单词"$word"已从生词本"$videoName"中删除');
      
      // 清除缓存
      _invalidateWordsCache();
      
      notifyListeners();
    } catch (e) {
      debugPrint('删除单词失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 删除整个生词本
  Future<void> deleteVocabularyList(String videoName) async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('尝试删除生词本: $videoName');
      
      if (!_vocabularyLists.containsKey(videoName)) {
        debugPrint('生词本不存在: $videoName');
        return;
      }
      
      // 获取该生词本中的所有单词
      final words = _vocabularyLists[videoName]!.words;
      debugPrint('生词本"$videoName"中有${words.length}个单词');
      
      // 从内存中删除
      _vocabularyLists.remove(videoName);
      
      // 从Hive中删除生词本
      if (await _vocabularyListsBox.containsKey(videoName)) {
        await _vocabularyListsBox.delete(videoName);
        debugPrint('从Hive中删除生词本: $videoName');
      } else {
        debugPrint('Hive中不存在生词本: $videoName');
      }
      
      // 从Hive中删除所有单词
      for (final word in words) {
        if (word != null && word.word.isNotEmpty) {
          if (await _vocabularyBox.containsKey(word.word)) {
            await _vocabularyBox.delete(word.word);
            debugPrint('从Hive中删除单词: ${word.word}');
          }
        }
      }
      
      debugPrint('生词本"$videoName"删除完成');
      
      // 清除缓存
      _invalidateWordsCache();
      
      notifyListeners();
    } catch (e) {
      debugPrint('删除生词本失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 添加单词到生词本 (简化版)
  Future<void> addWordToVocabulary(String word, String context, String? videoPath, {String? audioPath, SubtitleEntry? currentSubtitle}) async {
    if (word.isEmpty) return;
    
    // 从视频路径中提取视频名称，如果路径为空则使用"未知视频"
    final videoName = videoPath != null ? path.basename(videoPath) : "未知视频";
    
    // 如果当前没有加载生词本，或者加载的不是这个视频的生词本，先加载
    if (currentVocabularyList == null || currentVocabularyList!.videoName != videoName) {
      setCurrentVideo(videoName);
      await loadVocabularyList(videoName);
    }
    
    // 添加单词
    await addWord(videoName, word, context, audioPath: audioPath);
  }
  
  // 清空所有生词本
  Future<void> clearVocabulary() async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('开始清空所有生词本...');
      
      // 获取所有生词本键
      final listKeys = _vocabularyListsBox.keys.toList();
      debugPrint('共有 ${listKeys.length} 个生词本');
      
      // 获取所有单词键
      final wordKeys = _vocabularyBox.keys.toList();
      debugPrint('共有 ${wordKeys.length} 个单词');
      
      // 清空内存中的数据
      _vocabularyLists.clear();
      debugPrint('内存中的生词本已清空');
      
      // 批量删除生词本
      for (final key in listKeys) {
        await _vocabularyListsBox.delete(key);
      }
      debugPrint('Hive中的生词本已删除');
      
      // 批量删除单词
      int batchSize = 100;
      for (int i = 0; i < wordKeys.length; i += batchSize) {
        final end = (i + batchSize < wordKeys.length) ? i + batchSize : wordKeys.length;
        final batch = wordKeys.sublist(i, end);
        
        for (final key in batch) {
          await _vocabularyBox.delete(key);
        }
        
        debugPrint('已删除 ${end} / ${wordKeys.length} 个单词');
      }
      
      debugPrint('所有生词本已清空');
      
      // 清除缓存
      _invalidateWordsCache();
      
      notifyListeners();
    } catch (e) {
      debugPrint('清空生词本失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      throw Exception('清空生词本失败: $e');
    }
  }
  
  // 获取生词本总数
  int getTotalVocabularyCount() {
    if (!_isInitialized) return 0;
    return _vocabularyLists.length;
  }
  
  // 获取所有生词本的视频名称
  List<String> getAllVideoNames() {
    return _vocabularyLists.keys.toList();
  }
  
  // 诊断功能：列出所有存储键
  Future<List<String>> diagnosticListAllKeys() async {
    if (!_isInitialized) await initialize();
    
    final result = <String>[];
    
    // 添加Hive盒子名称
    result.add('hive:$_vocabularyBoxName');
    result.add('hive:$_vocabularyListsBoxName');
    
    // 添加词汇盒子中的所有键
    for (final key in _vocabularyBox.keys) {
      result.add('$_vocabularyBoxName:$key');
    }
    
    // 添加词汇列表盒子中的所有键
    for (final key in _vocabularyListsBox.keys) {
      result.add('$_vocabularyListsBoxName:$key');
    }
    
    // 尝试获取SharedPreferences中的键，用于迁移检查
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.contains('vocabulary')) {
          result.add('prefs:$key');
        }
      }
    } catch (e) {
      debugPrint('获取SharedPreferences键失败: $e');
    }
    
    result.sort();
    return result;
  }
  
  // 紧急恢复：尝试恢复所有可能的生词本数据
  Future<int> emergencyRecoverAllVocabularyData() async {
    if (!_isInitialized) await initialize();
    int recoveredCount = 0;
    
    try {
      // 从SharedPreferences迁移数据
      recoveredCount += await _migrateFromSharedPreferencesEmergency();
      
      // 重新加载所有生词本
      await loadAllVocabularyLists();
    } catch (e) {
      debugPrint('紧急恢复生词本数据失败: $e');
    }
    
    return recoveredCount;
  }
  
  // 紧急从SharedPreferences迁移数据
  Future<int> _migrateFromSharedPreferencesEmergency() async {
    int recoveredCount = 0;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // 查找所有可能包含生词本数据的键
      for (final key in allKeys) {
        if (key.contains('vocabulary') || key.contains('word')) {
          final jsonString = prefs.getString(key);
          
          if (jsonString != null) {
            try {
              // 尝试解析JSON
              final json = jsonDecode(jsonString);
              
              // 检查是否包含videoName和words字段
              if (json is Map<String, dynamic> && 
                  json.containsKey('videoName') && 
                  json.containsKey('words')) {
                
                final videoName = json['videoName'] as String;
                final vocabularyList = VocabularyList.fromJson(json);
                
                // 将生词本保存到Hive
                await _vocabularyListsBox.put(videoName, vocabularyList);
                
                // 将单词保存到Hive
                for (final word in vocabularyList.words) {
                  final wordWithVideo = VocabularyWord(
                    word: word.word,
                    context: word.context,
                    addedTime: word.addedTime,
                    videoName: videoName,
                  );
                  await _vocabularyBox.put(word.word, wordWithVideo);
                }
                
                recoveredCount++;
              }
            } catch (e) {
              debugPrint('尝试恢复键 $key 失败: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('紧急从SharedPreferences迁移数据失败: $e');
    }
    
    return recoveredCount;
  }
  
  // 直接添加单词到生词本，不进行词形还原处理
  Future<void> addWordDirectly(String videoName, VocabularyWord word) async {
    if (!_isInitialized) await initialize();
    
    // 确保视频生词本存在
    if (!_vocabularyLists.containsKey(videoName)) {
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: [],
      );
    }
    
    // 检查单词是否已存在
    final existingWords = _vocabularyLists[videoName]!.words;
    final existingWordIndex = existingWords.indexWhere((w) => w.word == word.word);
    
    if (existingWordIndex >= 0) {
      // 如果已存在，更新
      final updatedWords = List<VocabularyWord>.from(existingWords);
      updatedWords[existingWordIndex] = word;
      
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
    } else {
      // 如果不存在，添加新的
      final updatedWords = List<VocabularyWord>.from(existingWords);
      updatedWords.add(word);
      
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
    }
    
    // 保存到Hive
    await _vocabularyBox.put(word.word, word);
    await saveVocabularyList(videoName);
    
    // 清除缓存
    _invalidateWordsCache();
    
    notifyListeners();
  }
  
  // 安全检查并修复生词本数据
  Future<Map<String, int>> safeRepairVocabularyData() async {
    if (!_isInitialized) await initialize();
    
    final results = {
      'fixedLists': 0,
      'fixedWords': 0,
      'scannedLists': 0,
      'scannedWords': 0,
    };
    
    try {
      debugPrint('开始安全检查生词本数据...');
      
      // 检查生词本列表
      final listKeys = _vocabularyListsBox.keys.toList();
      results['scannedLists'] = listKeys.length;
      
      for (final key in listKeys) {
        try {
          final list = _vocabularyListsBox.get(key);
          
          if (list != null) {
            // 检查生词本中是否有无效单词
            final validWords = list.words.where((w) => w != null).toList();
            results['scannedWords'] = results['scannedWords']! + list.words.length;
            
            if (validWords.length != list.words.length) {
              // 只修复列表，不删除任何数据
              debugPrint('修复生词本"$key"，过滤掉${list.words.length - validWords.length}个无效单词');
              
              final fixedList = VocabularyList(
                videoName: list.videoName,
                words: validWords,
              );
              
              await _vocabularyListsBox.put(key, fixedList);
              results['fixedLists'] = results['fixedLists']! + 1;
              results['fixedWords'] = results['fixedWords']! + (list.words.length - validWords.length);
            }
          }
        } catch (e) {
          debugPrint('处理生词本"$key"时出错: $e');
        }
      }
      
      // 重新加载数据
      await loadAllVocabularyLists();
      
      debugPrint('安全检查完成，共修复了${results['fixedLists']}个生词本，${results['fixedWords']}个单词');
    } catch (e) {
      debugPrint('安全检查生词本数据时出错: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
    
    return results;
  }
  
  // 导出生词本为JSON格式（用于备份）
  String exportVocabularyAsJSON() {
    try {
      final Map<String, dynamic> backupData = {
        'version': '1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'totalWords': totalWordCount,
        'vocabularyLists': {},
      };
      
      // 将所有生词本转换为JSON格式
      for (final videoName in _vocabularyLists.keys) {
        final vocabularyList = _vocabularyLists[videoName]!;
        final List<Map<String, dynamic>> wordsJson = [];
        
        for (final word in vocabularyList.words) {
          wordsJson.add({
            'word': word.word,
            'context': word.context,
            'addedTime': word.addedTime.toIso8601String(),
            'videoName': word.videoName,
          });
        }
        
        backupData['vocabularyLists'][videoName] = {
          'videoName': videoName,
          'words': wordsJson,
        };
      }
      
      // 转换为格式化的JSON字符串
      return const JsonEncoder.withIndent('  ').convert(backupData);
    } catch (e) {
      debugPrint('导出生词本为JSON失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      return '{"error": "导出失败: $e"}';
    }
  }
  
  // 从JSON字符串导入生词本数据
  Future<Map<String, dynamic>> importVocabularyFromJSON(String jsonString) async {
    if (!_isInitialized) await initialize();
    
    int importedLists = 0;
    int importedWords = 0;
    
    try {
      final Map<String, dynamic> backupData = jsonDecode(jsonString);
      final version = backupData['version'] ?? '1.0';
      
      // 检查备份版本
      if (version != '1.0') {
        debugPrint('警告：导入的备份版本($version)可能与当前版本不兼容');
      }
      
      // 导入生词本
      final vocabularyLists = backupData['vocabularyLists'] as Map<String, dynamic>;
      
      for (final videoName in vocabularyLists.keys) {
        final listData = vocabularyLists[videoName] as Map<String, dynamic>;
        final wordsJsonList = listData['words'] as List;
        
        final List<VocabularyWord> words = [];
        
        // 导入单词
        for (final wordJson in wordsJsonList) {
          final word = VocabularyWord(
            word: wordJson['word'],
            context: wordJson['context'] ?? '',
            addedTime: DateTime.parse(wordJson['addedTime']),
            videoName: wordJson['videoName'] ?? videoName,
          );
          
          words.add(word);
          
          // 保存到Hive
          await _vocabularyBox.put(word.word, word);
          importedWords++;
        }
        
        // 创建生词本并保存
        final vocabularyList = VocabularyList(
          videoName: videoName,
          words: words,
        );
        
        _vocabularyLists[videoName] = vocabularyList;
        await _vocabularyListsBox.put(videoName, vocabularyList);
        importedLists++;
      }
      
      // 清除缓存
      _invalidateWordsCache();
      
      // 通知监听器
      notifyListeners();
      
      debugPrint('成功导入 $importedLists 个生词本，共 $importedWords 个单词');
      return {
        'lists': importedLists,
        'words': importedWords,
      };
    } catch (e) {
      debugPrint('导入生词本失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      return {
        'lists': 0,
        'words': 0,
        'error': e.toString(),
      };
    }
  }
  
  // 从文件导入生词本数据
  Future<Map<String, dynamic>> importVocabularyFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {
          'lists': 0,
          'words': 0,
          'error': '文件不存在',
        };
      }
      
      final content = await file.readAsString();
      return await importVocabularyFromJSON(content);
    } catch (e) {
      debugPrint('从文件导入生词本失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      return {
        'lists': 0,
        'words': 0,
        'error': e.toString(),
      };
    }
  }
  
  // 更新单词的记忆次数
  Future<void> increaseRememberedCount(String videoName, String word) async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('增加单词"$word"的记忆次数');
      
      if (!_vocabularyLists.containsKey(videoName)) {
        debugPrint('生词本不存在: $videoName');
        return;
      }
      
      // 从生词本中获取单词
      final existingWords = _vocabularyLists[videoName]!.words;
      final wordIndex = existingWords.indexWhere((w) => w.word == word);
      
      if (wordIndex < 0) {
        debugPrint('单词"$word"不存在于生词本"$videoName"中');
        return;
      }
      
      // 获取当前单词
      final currentWord = existingWords[wordIndex];
      
      // 创建更新后的单词（记忆次数+1）
      final updatedWord = currentWord.copyWithIncreasedRememberedCount();
      
      // 更新内存中的单词
      final updatedWords = List<VocabularyWord>.from(existingWords);
      updatedWords[wordIndex] = updatedWord;
      
      _vocabularyLists[videoName] = VocabularyList(
        videoName: videoName,
        words: updatedWords,
      );
      
      // 保存到Hive
      await _vocabularyBox.put(word, updatedWord);
      await saveVocabularyList(videoName);
      
      debugPrint('单词"$word"的记忆次数已更新为: ${updatedWord.rememberedCount}');
      
      // 清除缓存
      _invalidateWordsCache();
      
      notifyListeners();
      
      // 如果记忆次数达到阈值，标记为熟知
      if (updatedWord.rememberedCount >= 10) {
        await markWordAsMastered(videoName, word);
      }
    } catch (e) {
      debugPrint('更新单词记忆次数失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 将单词标记为熟知（添加到词典并从生词本中删除）
  Future<void> markWordAsMastered(String videoName, String word) async {
    try {
      debugPrint('将单词"$word"标记为熟知');
      
      // 获取词典服务
      final dictionaryService = Provider.of<DictionaryService>(navigatorKey.currentContext!, listen: false);
      
      // 检查词典中是否已存在该单词
      final existingWord = dictionaryService.getWord(word);
      
      if (existingWord == null) {
        // 如果词典中不存在，则添加
        final dictionaryWord = DictionaryWord(
          word: word,
          definition: '用户标记为熟知',
          isFamiliar: true,
        );
        
        await dictionaryService.addWord(dictionaryWord);
        debugPrint('已将单词"$word"添加到词典并标记为熟知');
      } else if (!existingWord.isFamiliar) {
        // 如果词典中存在但未标记为熟知，则更新
        final updatedWord = DictionaryWord(
          word: existingWord.word,
          definition: existingWord.definition,
          phonetic: existingWord.phonetic,
          partOfSpeech: existingWord.partOfSpeech,
          cefr: existingWord.cefr,
          isFamiliar: true,
        );
        
        await dictionaryService.updateWord(updatedWord);
        debugPrint('已将词典中的单词"$word"标记为熟知');
      }
      
      // 从生词本中删除
      await removeWord(videoName, word);
      debugPrint('已从生词本中删除单词"$word"');
    } catch (e) {
      debugPrint('标记单词为熟知失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
} 