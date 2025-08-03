import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

import '../models/dictionary_word.dart';
import '../models/history_model.dart';
import '../utils/word_lemmatizer.dart';

class DictionaryService extends ChangeNotifier {
  // 盒子名称
  static const String _dictionaryBoxName = 'dictionary';
  static const String _vocabularyBoxName = 'vocabulary';
  
  // Hive盒子
  late Box<DictionaryWord> _dictionaryBox;
  late Box<DictionaryWord> _vocabularyBox;
  
  // 初始化标志
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // 单例模式
  static final DictionaryService _instance = DictionaryService._internal();
  
  factory DictionaryService() {
    return _instance;
  }
  
  DictionaryService._internal();

  // 初始化Hive数据库
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final appDocumentDir = await getApplicationDocumentsDirectory();
      
      // 尝试初始化Hive，如果已初始化则忽略错误
      try {
        Hive.init(appDocumentDir.path);
      } catch (e) {
        debugPrint('Hive可能已经初始化: $e');
      }
      
      // 注册适配器
      if (!Hive.isAdapterRegistered(31)) {
        debugPrint('注册DictionaryWordAdapter');
        Hive.registerAdapter(DictionaryWordAdapter());
      }
      
      // 数据库文件路径
      final boxDir = await getApplicationDocumentsDirectory();
      final dictionaryBoxPath = '${boxDir.path}/$_dictionaryBoxName.hive';
      final vocabularyBoxPath = '${boxDir.path}/$_vocabularyBoxName.hive';
      
      // 创建自动备份
      try {
        final dictionaryFile = File(dictionaryBoxPath);
        final vocabularyFile = File(vocabularyBoxPath);
        
        // 如果文件存在，创建备份
        if (await dictionaryFile.exists()) {
          final backupPath = '${dictionaryBoxPath}_backup_${DateTime.now().millisecondsSinceEpoch}';
          await dictionaryFile.copy(backupPath);
          debugPrint('已创建词典数据备份: $backupPath');
        }
        
        if (await vocabularyFile.exists()) {
          final backupPath = '${vocabularyBoxPath}_backup_${DateTime.now().millisecondsSinceEpoch}';
          await vocabularyFile.copy(backupPath);
          debugPrint('已创建生词本数据备份: $backupPath');
        }
      } catch (e) {
        debugPrint('创建数据备份失败，但会继续尝试打开数据库: $e');
      }
      
      // 尝试打开数据库
      try {
        debugPrint('尝试打开词典盒子: $_dictionaryBoxName');
        _dictionaryBox = await Hive.openBox<DictionaryWord>(_dictionaryBoxName);
        debugPrint('词典盒子打开成功，包含${_dictionaryBox.length}条记录');
        
        debugPrint('打开生词本盒子: $_vocabularyBoxName');
        _vocabularyBox = await Hive.openBox<DictionaryWord>(_vocabularyBoxName);
        debugPrint('生词本盒子打开成功，包含${_vocabularyBox.length}条记录');
      } catch (e) {
        debugPrint('打开盒子失败: $e');
        debugPrint('尝试从备份恢复...');
        
        // 尝试从备份恢复，而不是删除数据库
        try {
          // 查找最新的备份文件
          final directory = Directory(boxDir.path);
          final backupFiles = await directory
              .list()
              .where((entity) => entity.path.contains('_backup_') && 
                                 (entity.path.contains(_dictionaryBoxName) || 
                                  entity.path.contains(_vocabularyBoxName)))
              .toList();
          
          if (backupFiles.isNotEmpty) {
            // 按修改时间排序，找出最新的备份
            backupFiles.sort((a, b) {
              final aTime = a.statSync().modified;
              final bTime = b.statSync().modified;
              return bTime.compareTo(aTime); // 降序排列
            });
            
            debugPrint('找到 ${backupFiles.length} 个备份文件，尝试使用最新的备份');
            
            // 尝试恢复词典备份
            final dictionaryBackups = backupFiles
                .where((f) => f.path.contains(_dictionaryBoxName))
                .toList();
            
            if (dictionaryBackups.isNotEmpty) {
              final latestBackup = dictionaryBackups.first;
              debugPrint('尝试从备份恢复词典: ${latestBackup.path}');
              
              // 确保目标文件不存在
              final targetFile = File(dictionaryBoxPath);
              if (await targetFile.exists()) {
                await targetFile.rename('${dictionaryBoxPath}_corrupted');
              }
              
              // 复制备份到原位置
              await File(latestBackup.path).copy(dictionaryBoxPath);
              debugPrint('已从备份恢复词典数据库');
            }
            
            // 尝试恢复生词本备份
            final vocabularyBackups = backupFiles
                .where((f) => f.path.contains(_vocabularyBoxName))
                .toList();
            
            if (vocabularyBackups.isNotEmpty) {
              final latestBackup = vocabularyBackups.first;
              debugPrint('尝试从备份恢复生词本: ${latestBackup.path}');
              
              // 确保目标文件不存在
              final targetFile = File(vocabularyBoxPath);
              if (await targetFile.exists()) {
                await targetFile.rename('${vocabularyBoxPath}_corrupted');
              }
              
              // 复制备份到原位置
              await File(latestBackup.path).copy(vocabularyBoxPath);
              debugPrint('已从备份恢复生词本数据库');
            }
            
            // 再次尝试打开盒子
            debugPrint('从备份恢复后，再次尝试打开盒子');
            _dictionaryBox = await Hive.openBox<DictionaryWord>(_dictionaryBoxName);
            _vocabularyBox = await Hive.openBox<DictionaryWord>(_vocabularyBoxName);
            debugPrint('成功从备份恢复并打开盒子');
          } else {
            debugPrint('未找到可用的备份文件，将创建新的空数据库');
            // 创建新的空盒子，但不删除现有文件
            _dictionaryBox = await Hive.openBox<DictionaryWord>(_dictionaryBoxName, 
                                                              crashRecovery: true);
            _vocabularyBox = await Hive.openBox<DictionaryWord>(_vocabularyBoxName,
                                                             crashRecovery: true);
          }
        } catch (e2) {
          debugPrint('从备份恢复失败: $e2');
          // 最后的尝试：创建新的空盒子，但不删除现有文件
          try {
            debugPrint('尝试使用crashRecovery模式打开盒子');
            _dictionaryBox = await Hive.openBox<DictionaryWord>(_dictionaryBoxName, 
                                                              crashRecovery: true);
            _vocabularyBox = await Hive.openBox<DictionaryWord>(_vocabularyBoxName,
                                                             crashRecovery: true);
          } catch (e3) {
            debugPrint('所有恢复尝试均失败: $e3');
            throw Exception('无法初始化词典数据，请联系开发者: $e3');
          }
        }
      }
      
      _isInitialized = true;
      debugPrint('词典服务初始化成功');
      notifyListeners();
    } catch (e) {
      debugPrint('初始化词典服务失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 关闭Hive数据库
  Future<void> close() async {
    await _dictionaryBox.close();
    await _vocabularyBox.close();
    _isInitialized = false;
  }
  
  // 添加单词到词典
  Future<void> addWord(DictionaryWord word) async {
    await _dictionaryBox.put(word.word.toLowerCase(), word);
    notifyListeners();
  }
  
  // 批量添加单词到词典
  Future<void> addWords(List<DictionaryWord> words) async {
    final Map<String, DictionaryWord> wordsMap = {};
    for (var word in words) {
      wordsMap[word.word.toLowerCase()] = word;
    }
    await _dictionaryBox.putAll(wordsMap);
    notifyListeners();
  }
  
  // 从词典中删除单词
  Future<void> removeWord(String wordText) async {
    await _dictionaryBox.delete(wordText.toLowerCase());
    notifyListeners();
  }
  
  // 批量删除词典中的单词
  Future<void> removeWords(List<String> words) async {
    for (var word in words) {
      await _dictionaryBox.delete(word.toLowerCase());
    }
    notifyListeners();
  }
  
  // 更新词典中的单词
  Future<void> updateWord(DictionaryWord word) async {
    await _dictionaryBox.put(word.word.toLowerCase(), word);
    notifyListeners();
  }
  
  // 获取词典中的单词
  DictionaryWord? getWord(String wordText) {
    return _dictionaryBox.get(wordText.toLowerCase());
  }
  
  // 检查词典中是否存在单词
  bool containsWord(String wordText) {
    return _dictionaryBox.containsKey(wordText.toLowerCase());
  }
  
  // 获取所有词典单词
  List<DictionaryWord> get allWords => _dictionaryBox.values.toList();
  
  // 根据熟知状态筛选单词
  List<DictionaryWord> getWordsByFamiliarStatus(bool isFamiliar) {
    return _dictionaryBox.values.where((word) => word.isFamiliar == isFamiliar).toList();
  }
  
  // 获取所有熟知的单词
  List<DictionaryWord> get familiarWords => 
      _dictionaryBox.values.where((word) => word.isFamiliar).toList();
      
  // 获取所有未熟知的单词
  List<DictionaryWord> get unfamiliarWords => 
      _dictionaryBox.values.where((word) => !word.isFamiliar).toList();
  
  // 获取所有生词本单词
  List<DictionaryWord> get allVocabularyWords => _vocabularyBox.values.toList();
  
  // 添加单词到生词本
  Future<void> addToVocabulary(DictionaryWord word) async {
    word.isVocabulary = true;
    await _vocabularyBox.put(word.word.toLowerCase(), word);
    
    // 如果词典中也有这个单词，更新isVocabulary状态
    final dictWord = _dictionaryBox.get(word.word.toLowerCase());
    if (dictWord != null) {
      dictWord.isVocabulary = true;
      await _dictionaryBox.put(word.word.toLowerCase(), dictWord);
    }
    
    notifyListeners();
  }
  
  // 从生词本中移除单词
  Future<void> removeFromVocabulary(String wordText) async {
    await _vocabularyBox.delete(wordText.toLowerCase());
    
    // 如果词典中也有这个单词，更新isVocabulary状态
    final dictWord = _dictionaryBox.get(wordText.toLowerCase());
    if (dictWord != null) {
      dictWord.isVocabulary = false;
      await _dictionaryBox.put(wordText.toLowerCase(), dictWord);
    }
    
    notifyListeners();
  }
  
  // 检查单词是否在生词本中
  bool isInVocabulary(String wordText) {
    return _vocabularyBox.containsKey(wordText.toLowerCase());
  }
  
  // 标记单词为熟知
  Future<void> markAsFamiliar(String wordText) async {
    final word = getWord(wordText.toLowerCase());
    if (word != null) {
      word.isFamiliar = true;
      await _dictionaryBox.put(wordText.toLowerCase(), word);
      notifyListeners();
    } else {
      // 如果词典中没有这个单词，创建一个新的带有熟知标记
      final newWord = DictionaryWord(
        word: wordText.toLowerCase(),
        isFamiliar: true,
      );
      await _dictionaryBox.put(wordText.toLowerCase(), newWord);
      notifyListeners();
    }
  }
  
  // 取消标记单词为熟知
  Future<void> unmarkAsFamiliar(String wordText) async {
    final word = getWord(wordText.toLowerCase());
    if (word != null) {
      word.isFamiliar = false;
      await _dictionaryBox.put(wordText.toLowerCase(), word);
      notifyListeners();
    }
  }
  
  // 检查单词是否被标记为熟知
  bool isFamiliar(String wordText) {
    final word = getWord(wordText.toLowerCase());
    return word != null && word.isFamiliar;
  }
  
  // 从JSON文件导入词典
  Future<int> importDictionaryFromJson(String filePath) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);
      
      final words = jsonList.map((json) => DictionaryWord.fromJson(json as Map<String, dynamic>)).toList();
      await addWords(words);
      
      return words.length;
    } catch (e) {
      debugPrint('导入JSON词典失败: $e');
      return 0;
    }
  }
  
  // 从CSV文件导入词典
  Future<int> importDictionaryFromCsv(String filePath) async {
    try {
      debugPrint('开始导入CSV文件: $filePath');
      final file = File(filePath);
      
      if (!await file.exists()) {
        debugPrint('CSV文件不存在: $filePath');
        return 0;
      }
      
      debugPrint('CSV文件大小: ${await file.length()} 字节');
      
      // 尝试不同的编码格式读取文件
      String csvString;
      try {
        // 首先尝试UTF-8编码
        debugPrint('尝试使用UTF-8编码读取CSV文件');
        csvString = await file.readAsString();
        debugPrint('使用UTF-8编码成功读取CSV文件，内容长度: ${csvString.length}');
      } catch (e) {
        debugPrint('UTF-8编码读取失败，尝试使用Latin1编码: $e');
        // 如果UTF-8失败，尝试使用Latin1编码（适用于大多数欧洲语言和英语）
        final bytes = await file.readAsBytes();
        csvString = String.fromCharCodes(bytes);
        debugPrint('使用Latin1编码读取CSV文件，内容长度: ${csvString.length}');
      }
      
      debugPrint('开始解析CSV数据');
      final List<List<dynamic>> csvTable = const CsvToListConverter().convert(csvString);
      
      debugPrint('CSV解析完成，共 ${csvTable.length} 行');
      
      if (csvTable.isEmpty) {
        debugPrint('CSV文件为空或格式错误');
        return 0;
      }
      
      // 检查CSV格式
      final headers = csvTable[0].map((h) => h.toString().trim().toLowerCase()).toList();
      debugPrint('CSV表头: $headers');
      
      final List<DictionaryWord> words = [];
      
      // 跳过标题行
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.isEmpty || row[0] == null || row[0].toString().trim().isEmpty) {
          debugPrint('跳过第 $i 行: 空行或第一列为空');
          continue; // 跳过空行
        }
        
        // 获取单词文本
        final wordText = row[0].toString().trim();
        
        // 处理不同的CSV格式
        if (headers.contains('word')) {
          // 找到各列的索引
          final wordIndex = headers.indexOf('word');
          
          // 查找可能的列
          final partOfSpeechIndex = headers.contains('partofspeech') 
              ? headers.indexOf('partofspeech') 
              : headers.contains('part of speech')
                  ? headers.indexOf('part of speech')
                  : -1;
                  
          final definitionIndex = headers.contains('definition') 
              ? headers.indexOf('definition') 
              : -1;
          
          final cefrIndex = headers.contains('cefr') 
              ? headers.indexOf('cefr') 
              : -1;
              
          final phonIndex = headers.contains('phon_n_am') 
              ? headers.indexOf('phon_n_am') 
              : headers.contains('phonetic')
                  ? headers.indexOf('phonetic')
                  : -1;
          
          // 确保行有足够的列
          if (row.length > wordIndex) {
            // 获取词性和定义
            String? partOfSpeech = partOfSpeechIndex >= 0 && row.length > partOfSpeechIndex
                ? row[partOfSpeechIndex]?.toString()?.trim()
                : null;
                
            String? definition = definitionIndex >= 0 && row.length > definitionIndex
                ? row[definitionIndex]?.toString()?.trim()
                : null;
            
            // 获取音标
            String? phonetic = phonIndex >= 0 && row.length > phonIndex
                ? row[phonIndex]?.toString()?.trim()
                : null;
            
            // 获取CEFR等级
            String? cefr = cefrIndex >= 0 && row.length > cefrIndex
                ? row[cefrIndex]?.toString()?.trim()
                : null;
            
            // 获取CEFR等级作为排名
            int? rank;
            if (cefr != null && cefr.isNotEmpty) {
              // 将CEFR等级转换为数字排名
              // A1=1, A2=2, B1=3, B2=4, C1=5, C2=6
              switch (cefr.toUpperCase()) {
                case 'A1': rank = 1; break;
                case 'A2': rank = 2; break;
                case 'B1': rank = 3; break;
                case 'B2': rank = 4; break;
                case 'C1': rank = 5; break;
                case 'C2': rank = 6; break;
                default:
                  // 尝试从字符串中提取数字
                  final numericPart = RegExp(r'\d+').firstMatch(cefr)?.group(0);
                  rank = numericPart != null ? int.tryParse(numericPart) : null;
              }
            }
            
            // 收集额外信息
            final extraInfo = <String, dynamic>{};
            for (int j = 0; j < headers.length; j++) {
              if (j != wordIndex && 
                  j != partOfSpeechIndex && 
                  j != definitionIndex && 
                  j != cefrIndex && 
                  j != phonIndex && 
                  row.length > j && 
                  row[j] != null && 
                  row[j].toString().trim().isNotEmpty) {
                extraInfo[headers[j]] = row[j].toString().trim();
              }
            }
            
            words.add(DictionaryWord(
              word: wordText,
              partOfSpeech: partOfSpeech,
              definition: definition,
              rank: rank ?? i,
              phonetic: phonetic,
              cefr: cefr,
              extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
            ));
            
            if (i % 100 == 0 || i == csvTable.length - 1) {
              debugPrint('已处理 $i/${csvTable.length - 1} 行');
            }
          }
        } else {
          // 未知格式，尝试使用第一列作为单词
          if (row.isNotEmpty) {
            words.add(DictionaryWord(
              word: wordText,
              partOfSpeech: row.length > 1 ? row[1]?.toString()?.trim() : null,
              definition: row.length > 2 ? row[2]?.toString()?.trim() : null,
              rank: row.length > 3 ? int.tryParse(row[3].toString()) ?? i : i,
            ));
          }
        }
      }
      
      if (words.isEmpty) {
        debugPrint('未找到有效的单词数据');
        return 0;
      }
      
      debugPrint('准备添加 ${words.length} 个单词到词典');
      await addWords(words);
      debugPrint('成功导入 ${words.length} 个单词');
      
      return words.length;
    } catch (e, stackTrace) {
      debugPrint('导入CSV词典失败: $e');
      debugPrint('错误堆栈: $stackTrace');
      return 0;
    }
  }
  
  // 导出词典到JSON文件
  Future<bool> exportDictionaryToJson(String filePath) async {
    try {
      final words = allWords;
      final jsonList = words.map((word) => word.toJson()).toList();
      final jsonString = json.encode(jsonList);
      
      final file = File(filePath);
      await file.writeAsString(jsonString);
      
      return true;
    } catch (e) {
      debugPrint('导出JSON词典失败: $e');
      return false;
    }
  }
  
  // 导出词典到CSV文件
  Future<bool> exportDictionaryToCsv(String filePath) async {
    try {
      final words = allWords;
      final List<List<dynamic>> csvData = [
        ['word', 'partOfSpeech', 'definition', 'rank', 'isVocabulary']
      ];
      
      for (var word in words) {
        csvData.add([
          word.word,
          word.partOfSpeech ?? '',
          word.definition ?? '',
          word.rank ?? 0,
          word.isVocabulary,
        ]);
      }
      
      final csvString = const ListToCsvConverter().convert(csvData);
      final file = File(filePath);
      await file.writeAsString(csvString);
      
      return true;
    } catch (e) {
      debugPrint('导出CSV词典失败: $e');
      return false;
    }
  }
  
  // 搜索词典
  List<DictionaryWord> searchDictionary(String query) {
    query = query.toLowerCase();
    return _dictionaryBox.values.where((word) => 
      word.word.toLowerCase().contains(query) || 
      (word.definition != null && word.definition!.toLowerCase().contains(query)) ||
      (word.partOfSpeech != null && word.partOfSpeech!.toLowerCase().contains(query))
    ).toList();
  }
  
  // 根据熟知状态搜索词典
  List<DictionaryWord> searchDictionaryWithFamiliar(String query, bool? isFamiliar) {
    final results = searchDictionary(query);
    if (isFamiliar == null) return results;
    return results.where((word) => word.isFamiliar == isFamiliar).toList();
  }
  
  // 清空词典
  Future<void> clearDictionary() async {
    try {
      debugPrint('开始清空词典...');
      
      // 获取所有单词
      final allKeys = _dictionaryBox.keys.toList();
      final totalCount = allKeys.length;
      debugPrint('词典中共有 $totalCount 个单词');
      
      // 批量删除单词
      int batchSize = 100;
      for (int i = 0; i < allKeys.length; i += batchSize) {
        final end = (i + batchSize < allKeys.length) ? i + batchSize : allKeys.length;
        final batch = allKeys.sublist(i, end);
        
        for (final key in batch) {
          await _dictionaryBox.delete(key);
        }
        
        debugPrint('已删除 ${end} / $totalCount 个单词');
      }
      
      debugPrint('词典已清空');
      allWords.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('清空词典失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      throw Exception('清空词典失败: $e');
    }
  }
  
  // 清空生词本
  Future<void> clearVocabulary() async {
    try {
      debugPrint('开始清空生词本标记...');
      
      // 获取所有标记为生词的单词
      final vocabWords = allWords.where((word) => word.isVocabulary).toList();
      debugPrint('共有 ${vocabWords.length} 个单词标记为生词');
      
      // 更新词典中所有单词的isVocabulary状态
      for (var word in vocabWords) {
        word.isVocabulary = false;
        await _dictionaryBox.put(word.word.toLowerCase(), word);
      }
      
      debugPrint('生词本标记已清空');
      notifyListeners();
    } catch (e) {
      debugPrint('清空生词本标记失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      throw Exception('清空生词本标记失败: $e');
    }
  }
  
  // 通过API批量查询单词信息
  Future<Map<String, dynamic>> enrichWordsWithAPI(List<String> words, {int batchSize = 10, Function(int, int)? onProgress}) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final results = <String, dynamic>{
      'success': 0,
      'failed': 0,
      'skipped': 0,
      'total': words.length,
      'failedWords': <String>[],
    };
    
    // 分批处理单词
    for (int i = 0; i < words.length; i += batchSize) {
      final end = (i + batchSize < words.length) ? i + batchSize : words.length;
      final batch = words.sublist(i, end);
      
      // 更新进度
      if (onProgress != null) {
        onProgress(i, words.length);
      }
      
      // 并行查询每个单词
      final futures = batch.map((word) => _enrichWordWithAPI(word)).toList();
      final batchResults = await Future.wait(futures);
      
      // 统计结果
      for (final result in batchResults) {
        if (result['success']) {
          results['success'] = (results['success'] as int) + 1;
        } else if (result['skipped']) {
          results['skipped'] = (results['skipped'] as int) + 1;
        } else {
          results['failed'] = (results['failed'] as int) + 1;
          (results['failedWords'] as List<String>).add(result['word'] as String);
        }
      }
      
      // 避免API请求过于频繁
      if (end < words.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    // 更新最终进度
    if (onProgress != null) {
      onProgress(words.length, words.length);
    }
    
    notifyListeners();
    return results;
  }
  
  // 通过API查询单个单词信息
  Future<Map<String, dynamic>> _enrichWordWithAPI(String word) async {
    final result = <String, dynamic>{
      'word': word,
      'success': false,
      'skipped': false,
    };
    
    word = word.toLowerCase().trim();
    
    // 获取现有单词信息
    final existingWord = _dictionaryBox.get(word);
    
    // 检查是否需要补充信息
    bool needsEnrichment = existingWord == null || 
                          existingWord.partOfSpeech == null || 
                          existingWord.definition == null ||
                          existingWord.phonetic == null;
    
    if (!needsEnrichment) {
      result['skipped'] = true;
      return result;
    }
    
    try {
      // 使用Free Dictionary API
      final response = await http.get(
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final wordData = data[0];
          final meanings = wordData['meanings'] as List<dynamic>;
          
          if (meanings.isNotEmpty) {
            // 获取第一个词性和定义
            final firstMeaning = meanings[0];
            final partOfSpeech = firstMeaning['partOfSpeech'] as String?;
            final definitions = firstMeaning['definitions'] as List<dynamic>;
            
            String? definition;
            if (definitions.isNotEmpty) {
              definition = definitions[0]['definition'] as String?;
            }
            
            // 合并所有词性
            final allPartOfSpeech = meanings.map((m) => m['partOfSpeech'] as String).toSet().join(', ');
            
            // 获取音标
            String? phonetic = wordData['phonetic'] as String?;
            
            // 如果主音标为空，尝试从phonetics数组获取
            if (phonetic == null || phonetic.isEmpty) {
              final phonetics = wordData['phonetics'] as List<dynamic>?;
              if (phonetics != null && phonetics.isNotEmpty) {
                for (final p in phonetics) {
                  final text = p['text'] as String?;
                  if (text != null && text.isNotEmpty) {
                    phonetic = text;
                    break;
                  }
                }
              }
            }
            
            // 收集额外信息
            final extraInfo = <String, dynamic>{};
            
            // 添加例句
            final examples = <String>[];
            for (final meaning in meanings) {
              final defs = meaning['definitions'] as List<dynamic>;
              for (final def in defs) {
                final example = def['example'] as String?;
                if (example != null && example.isNotEmpty) {
                  examples.add(example);
                }
              }
            }
            
            if (examples.isNotEmpty) {
              extraInfo['examples'] = examples;
            }
            
            // 添加同义词
            final synonyms = <String>[];
            for (final meaning in meanings) {
              final syns = meaning['synonyms'] as List<dynamic>?;
              if (syns != null && syns.isNotEmpty) {
                for (final syn in syns) {
                  synonyms.add(syn as String);
                }
              }
            }
            
            if (synonyms.isNotEmpty) {
              extraInfo['synonyms'] = synonyms;
            }
            
            // 添加反义词
            final antonyms = <String>[];
            for (final meaning in meanings) {
              final ants = meaning['antonyms'] as List<dynamic>?;
              if (ants != null && ants.isNotEmpty) {
                for (final ant in ants) {
                  antonyms.add(ant as String);
                }
              }
            }
            
            if (antonyms.isNotEmpty) {
              extraInfo['antonyms'] = antonyms;
            }
            
            // 更新或创建单词
            DictionaryWord updatedWord;
            if (existingWord != null) {
              // 只更新缺失的字段
              updatedWord = existingWord;
              if (updatedWord.partOfSpeech == null) {
                updatedWord.partOfSpeech = allPartOfSpeech;
              }
              if (updatedWord.definition == null) {
                updatedWord.definition = definition;
              }
              if (updatedWord.phonetic == null) {
                updatedWord.phonetic = phonetic;
              }
              
              // 合并额外信息，而不是替换
              if (extraInfo.isNotEmpty) {
                if (updatedWord.extraInfo == null) {
                  updatedWord.extraInfo = extraInfo;
                } else {
                  // 只添加不存在的额外信息
                  extraInfo.forEach((key, value) {
                    if (!updatedWord.extraInfo!.containsKey(key)) {
                      updatedWord.extraInfo![key] = value;
                    }
                  });
                }
              }
            } else {
              // 创建新单词
              updatedWord = DictionaryWord(
                word: word,
                partOfSpeech: allPartOfSpeech,
                definition: definition,
                rank: 0,
                phonetic: phonetic,
                extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
              );
            }
            
            await _dictionaryBox.put(word, updatedWord);
            result['success'] = true;
          }
        }
      }
    } catch (e) {
      debugPrint('查询单词 $word 失败: $e');
    }
    
    return result;
  }

  // 通过API查询单个单词信息（公开方法）
  Future<bool> enrichSingleWordWithAPI(String word) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      final result = await _enrichWordWithAPI(word);
      return result['success'] == true;
    } catch (e) {
      debugPrint('查询单词 $word 释义失败: $e');
      return false;
    }
  }
  
  // 清洗词典，将词汇还原到词根并合并重复项
  Future<Map<String, dynamic>> cleanDictionary() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    debugPrint('开始清洗词典...');
    
    try {
      // 获取所有现有单词
      final allWords = _dictionaryBox.values.toList();
      final originalCount = allWords.length;
      
      if (originalCount == 0) {
        return {
          'success': true,
          'message': '词典为空，无需清洗',
          'originalCount': 0,
          'finalCount': 0,
          'merged': 0,
        };
      }
      
      debugPrint('原始词典包含 $originalCount 个单词');
      
      // 词根到合并后单词的映射
      final Map<String, DictionaryWord> lemmaToMergedWord = {};
      final Map<String, List<DictionaryWord>> lemmaToOriginalWords = {};
      
      // 第一步：按词根分组
      for (final word in allWords) {
        // 使用新的词形还原算法获取词根
        final lemma = ImprovedWordLemmatizer.lemmatize(word.word, LemmatizationMode.precise);
        
        if (!lemmaToOriginalWords.containsKey(lemma)) {
          lemmaToOriginalWords[lemma] = [];
        }
        lemmaToOriginalWords[lemma]!.add(word);
      }
      
      debugPrint('分组后得到 ${lemmaToOriginalWords.length} 个词根组');
      
      // 第二步：合并相同词根的单词
      for (final entry in lemmaToOriginalWords.entries) {
        final lemma = entry.key;
        final wordsWithSameRoot = entry.value;
        
        if (wordsWithSameRoot.length == 1) {
          // 只有一个单词，但需要更新为词根形式
          final originalWord = wordsWithSameRoot.first;
          final updatedWord = DictionaryWord(
            word: lemma, // 使用词根作为新的单词
            partOfSpeech: originalWord.partOfSpeech,
            definition: originalWord.definition,
            rank: originalWord.rank,
            isFamiliar: originalWord.isFamiliar,
            isVocabulary: originalWord.isVocabulary,
            phonetic: originalWord.phonetic,
            extraInfo: originalWord.extraInfo,
          );
          lemmaToMergedWord[lemma] = updatedWord;
        } else {
          // 多个单词需要合并
          debugPrint('合并词根 "$lemma" 的 ${wordsWithSameRoot.length} 个变形: ${wordsWithSameRoot.map((w) => w.word).join(', ')}');
          
          // 选择最完整的信息进行合并
          String? bestDefinition;
          String? bestPhonetic;
          String? bestPartOfSpeech;
          Map<String, dynamic>? mergedExtraInfo;
          int maxRank = 0;
          bool anyFamiliar = false;
          bool anyVocabulary = false;
          
          for (final word in wordsWithSameRoot) {
            // 取最完整的定义
            if (bestDefinition == null || (word.definition != null && word.definition!.length > bestDefinition.length)) {
              bestDefinition = word.definition;
            }
            
            // 取最完整的音标
            if (bestPhonetic == null || (word.phonetic != null && word.phonetic!.length > bestPhonetic.length)) {
              bestPhonetic = word.phonetic;
            }
            
            // 取最完整的词性
            if (bestPartOfSpeech == null || (word.partOfSpeech != null && word.partOfSpeech!.length > bestPartOfSpeech.length)) {
              bestPartOfSpeech = word.partOfSpeech;
            }
            
            // 取最高等级
            if (word.rank != null && word.rank! > maxRank) {
              maxRank = word.rank!;
            }
            
            // 如果任何一个是熟知的，就标记为熟知
            if (word.isFamiliar) {
              anyFamiliar = true;
            }
            
            // 如果任何一个在生词本中，就保持在生词本中
            if (word.isVocabulary) {
              anyVocabulary = true;
            }
            
            // 合并额外信息
            if (word.extraInfo != null) {
              if (mergedExtraInfo == null) {
                mergedExtraInfo = Map<String, dynamic>.from(word.extraInfo!);
              } else {
                mergedExtraInfo.addAll(word.extraInfo!);
              }
            }
          }
          
          // 创建合并后的单词
          final mergedWord = DictionaryWord(
            word: lemma, // 使用词根作为新的单词
            partOfSpeech: bestPartOfSpeech,
            definition: bestDefinition,
            rank: maxRank,
            isFamiliar: anyFamiliar,
            isVocabulary: anyVocabulary,
            phonetic: bestPhonetic,
            extraInfo: mergedExtraInfo,
          );
          
          lemmaToMergedWord[lemma] = mergedWord;
        }
      }
      
      debugPrint('合并完成，最终得到 ${lemmaToMergedWord.length} 个单词');
      
      // 第三步：清空词典并写入合并后的单词
      await _dictionaryBox.clear();
      
      final Map<String, DictionaryWord> wordsToAdd = {};
      for (final entry in lemmaToMergedWord.entries) {
        wordsToAdd[entry.key.toLowerCase()] = entry.value;
      }
      
      await _dictionaryBox.putAll(wordsToAdd);
      
      final finalCount = _dictionaryBox.length;
      final mergedCount = originalCount - finalCount;
      
      debugPrint('词典清洗完成：');
      debugPrint('- 原始单词数: $originalCount');
      debugPrint('- 最终单词数: $finalCount');
      debugPrint('- 合并单词数: $mergedCount');
      
      // 通知监听器更新
      notifyListeners();
      
      return {
        'success': true,
        'message': '词典清洗完成',
        'originalCount': originalCount,
        'finalCount': finalCount,
        'merged': mergedCount,
        'groups': lemmaToOriginalWords.length,
      };
      
    } catch (e) {
      debugPrint('清洗词典失败: $e');
      debugPrintStack();
      return {
        'success': false,
        'message': '清洗词典失败: $e',
        'originalCount': 0,
        'finalCount': 0,
        'merged': 0,
      };
    }
  }
} 