import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_model.dart';
import '../utils/word_lemmatizer.dart';
import 'package:path/path.dart' as path;

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
    );
  }

  @override
  void write(BinaryWriter writer, VocabularyWord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.word)
      ..writeByte(1)
      ..write(obj.context)
      ..writeByte(2)
      ..write(obj.addedTime)
      ..writeByte(3)
      ..write(obj.videoName);
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
      
      try {
        // 打开盒子
        debugPrint('尝试打开生词本盒子');
        _vocabularyBox = await Hive.openBox<VocabularyWord>(_vocabularyBoxName);
        _vocabularyListsBox = await Hive.openBox<VocabularyList>(_vocabularyListsBoxName);
        debugPrint('盒子打开成功');
      } catch (e) {
        debugPrint('打开盒子失败，尝试删除并重建: $e');
        
        // 如果打开失败，尝试删除并重新创建
        try {
          await Hive.deleteBoxFromDisk(_vocabularyBoxName);
          await Hive.deleteBoxFromDisk(_vocabularyListsBoxName);
          
          _vocabularyBox = await Hive.openBox<VocabularyWord>(_vocabularyBoxName);
          _vocabularyListsBox = await Hive.openBox<VocabularyList>(_vocabularyListsBoxName);
          debugPrint('盒子重建成功');
        } catch (e) {
          debugPrint('盒子重建失败: $e');
          throw Exception('无法初始化生词本: $e');
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
  List<VocabularyWord> getAllWords() {
    if (!_isInitialized) return [];
    
    final allWords = _vocabularyBox.values.toList();
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
  Future<void> addWord(String videoName, String word, String context) async {
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
      
      notifyListeners();
    } catch (e) {
      debugPrint('添加单词失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 从生词本中删除单词
  Future<void> removeWord(String videoName, String word) async {
    if (!_isInitialized) await initialize();
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    // 从视频生词本中删除
    final existingWords = _vocabularyLists[videoName]!.words;
    final updatedWords = existingWords.where((w) => w.word != word).toList();
    
    _vocabularyLists[videoName] = VocabularyList(
      videoName: videoName,
      words: updatedWords,
    );
    
    // 从Hive中删除
    await _vocabularyBox.delete(word);
    await saveVocabularyList(videoName);
    
    notifyListeners();
  }
  
  // 删除整个生词本
  Future<void> deleteVocabularyList(String videoName) async {
    if (!_isInitialized) await initialize();
    if (!_vocabularyLists.containsKey(videoName)) return;
    
    // 获取该生词本中的所有单词
    final words = _vocabularyLists[videoName]!.words;
    
    // 从内存中删除
    _vocabularyLists.remove(videoName);
    
    // 从Hive中删除生词本
    await _vocabularyListsBox.delete(videoName);
    
    // 从Hive中删除所有单词
    for (final word in words) {
      await _vocabularyBox.delete(word.word);
    }
    
    notifyListeners();
  }
  
  // 添加单词到生词本 (简化版)
  Future<void> addWordToVocabulary(String word, String context, String? videoPath) async {
    if (word.isEmpty) return;
    
    // 从视频路径中提取视频名称，如果路径为空则使用"未知视频"
    final videoName = videoPath != null ? path.basename(videoPath) : "未知视频";
    
    // 如果当前没有加载生词本，或者加载的不是这个视频的生词本，先加载
    if (currentVocabularyList == null || currentVocabularyList!.videoName != videoName) {
      setCurrentVideo(videoName);
      await loadVocabularyList(videoName);
    }
    
    // 添加单词
    await addWord(videoName, word, context);
  }
  
  // 清空所有生词本
  Future<void> clearVocabulary() async {
    if (!_isInitialized) await initialize();
    
    // 清空内存中的数据
    _vocabularyLists.clear();
    
    // 清空Hive中的数据
    await _vocabularyBox.clear();
    await _vocabularyListsBox.clear();
    
    notifyListeners();
  }
  
  // 检查生词本数据是否已加载
  bool isVocabularyLoaded() {
    return _isInitialized && _vocabularyLists.isNotEmpty;
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
    
    notifyListeners();
  }
} 