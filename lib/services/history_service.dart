import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_model.dart';


// DateTime适配器
class DateTimeAdapter extends TypeAdapter<DateTime> {
  @override
  final int typeId = 16;

  @override
  DateTime read(BinaryReader reader) {
    final micros = reader.readInt();
    return DateTime.fromMicrosecondsSinceEpoch(micros);
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.microsecondsSinceEpoch);
  }
}

// Duration适配器
class DurationAdapter extends TypeAdapter<Duration> {
  @override
  final int typeId = 17;

  @override
  Duration read(BinaryReader reader) {
    final micros = reader.readInt();
    return Duration(microseconds: micros);
  }

  @override
  void write(BinaryWriter writer, Duration obj) {
    writer.writeInt(obj.inMicroseconds);
  }
}

// 自定义VideoHistory适配器已删除，使用生成的适配器

class HistoryService extends ChangeNotifier {
  static const String _historyBoxName = 'video_history';
  static const String _lastPlayStateKey = 'last_play_state';
  
  late Box<VideoHistory> _historyBox;
  List<VideoHistory> _history = [];
  VideoHistory? _currentHistory;
  VideoHistory? _lastPlayState;
  bool _isInitialized = false;
  
  List<VideoHistory> get history => _history;
  VideoHistory? get currentHistory => _currentHistory;
  VideoHistory? get lastPlayState => _lastPlayState;
  
  // 初始化Hive数据库
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('历史记录服务已经初始化，跳过');
      return;
    }
    
    debugPrint('开始初始化历史记录服务...');
    
    try {
      final appDocumentDir = await getApplicationDocumentsDirectory();
      debugPrint('应用文档目录: ${appDocumentDir.path}');
      
      // 初始化Hive (如果在main中已经初始化过，这里会被忽略)
      try {
        Hive.init(appDocumentDir.path);
      } catch (e) {
        debugPrint('Hive已经初始化，继续注册适配器');
      }
      
      debugPrint('Hive初始化成功');
      
      // 注册内置类型适配器
      try {
        if (!Hive.isAdapterRegistered(16)) {
          debugPrint('注册DateTimeAdapter...');
          Hive.registerAdapter(DateTimeAdapter());
          debugPrint('DateTimeAdapter注册成功');
        }
        
        if (!Hive.isAdapterRegistered(17)) {
          debugPrint('注册DurationAdapter...');
          Hive.registerAdapter(DurationAdapter());
          debugPrint('DurationAdapter注册成功');
        }
      } catch (e) {
        debugPrint('注册内置类型适配器时出错: $e');
      }
      
      // 注册VideoHistory适配器
      try {
        if (!Hive.isAdapterRegistered(21)) {
          debugPrint('注册VideoHistoryAdapter...');
          // 使用生成的适配器
          Hive.registerAdapter(VideoHistoryAdapter());
          debugPrint('VideoHistoryAdapter注册成功');
        } else {
          debugPrint('VideoHistoryAdapter已注册，跳过');
        }
      } catch (e) {
        debugPrint('注册适配器时出错: $e');
        debugPrintStack(stackTrace: StackTrace.current);
        throw Exception('无法注册VideoHistory适配器: $e');
      }
      
      // 打开盒子
      try {
        debugPrint('打开历史记录盒子: $_historyBoxName');
        _historyBox = await Hive.openBox<VideoHistory>(_historyBoxName);
        debugPrint('历史记录盒子打开成功，包含${_historyBox.length}条记录');
      } catch (e) {
        debugPrint('打开历史记录盒子失败: $e');
        debugPrintStack(stackTrace: StackTrace.current);
        throw Exception('无法打开历史记录盒子: $e');
      }
      
      _isInitialized = true;
      debugPrint('历史记录服务初始化成功');
      
      // 加载历史记录
      await loadHistory();
      
      // 尝试从SharedPreferences迁移数据
      await _migrateFromSharedPreferences();
      
      // 加载最后播放状态
      await loadLastPlayState();
      
    } catch (e) {
      debugPrint('初始化历史记录服务失败: $e');
      // 打印完整的堆栈跟踪
      debugPrintStack(stackTrace: StackTrace.current);
      rethrow; // 重新抛出异常，让调用者知道初始化失败
    }
  }
  
  // 关闭Hive数据库
  Future<void> close() async {
    if (!_isInitialized) return;
    
    await _historyBox.close();
    _isInitialized = false;
  }
  
  // 从SharedPreferences迁移数据到Hive
  Future<void> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('video_history');
      final lastPlayStateJson = prefs.getString('last_play_state');
      
      if (historyJson != null && historyJson.isNotEmpty) {
        debugPrint('从SharedPreferences迁移历史记录数据...');
        
        // 解析历史记录
        final oldHistory = historyJson
            .map((item) => VideoHistory.fromJson(json.decode(item)))
            .toList();
        
        // 按时间戳排序，最新的在前面
        oldHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // 添加到Hive
        for (final item in oldHistory) {
          // 使用视频路径作为键，确保唯一性
          await _historyBox.put(item.videoPath, item);
        }
        
        // 重新加载历史记录
        await loadHistory();
        
        // 删除旧数据
        await prefs.remove('video_history');
        
        debugPrint('历史记录数据迁移完成，共${oldHistory.length}条记录');
      }
      
      // 迁移最后播放状态
      if (lastPlayStateJson != null) {
        debugPrint('从SharedPreferences迁移最后播放状态...');
        
        try {
          final lastState = VideoHistory.fromJson(json.decode(lastPlayStateJson));
          _lastPlayState = lastState;
          
          // 保存到Hive
          await _historyBox.put(_lastPlayStateKey, lastState);
          
          // 删除旧数据
          await prefs.remove('last_play_state');
          
          debugPrint('最后播放状态迁移完成');
        } catch (e) {
          debugPrint('迁移最后播放状态失败: $e');
        }
      }
    } catch (e) {
      debugPrint('从SharedPreferences迁移数据失败: $e');
    }
  }
  
  // 加载历史记录
  Future<void> loadHistory() async {
    debugPrint('开始加载历史记录...');
    
    if (!_isInitialized) {
      debugPrint('历史记录服务未初始化，尝试初始化...');
      await initialize();
    }
    
    try {
      // 从Hive加载历史记录
      debugPrint('从Hive加载历史记录...');
      final values = _historyBox.values.where((item) => item.videoPath != _lastPlayStateKey).toList();
      debugPrint('从Hive加载了${values.length}条历史记录');
      
      // 按时间戳排序，最新的在前面
      values.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      _history = values;
      
      // 打印历史记录内容
      if (_history.isNotEmpty) {
        debugPrint('历史记录列表:');
        for (int i = 0; i < _history.length; i++) {
          final item = _history[i];
          debugPrint('[$i] 视频: ${item.videoName}, 路径: ${item.videoPath}, 时间: ${item.timestamp}');
        }
      } else {
        debugPrint('历史记录为空');
      }
      
      notifyListeners();
      
      debugPrint('历史记录加载完成，共${_history.length}条记录');
    } catch (e) {
      debugPrint('加载历史记录失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 添加历史记录
  Future<void> addHistory(VideoHistory history) async {
    debugPrint('添加历史记录 - 开始');
    debugPrint('视频路径: ${history.videoPath}');
    debugPrint('字幕路径: ${history.subtitlePath}');
    debugPrint('视频名称: ${history.videoName}');
    debugPrint('播放位置: ${history.lastPosition.inSeconds}秒');
    
    if (!_isInitialized) {
      debugPrint('历史记录服务未初始化，尝试初始化...');
      await initialize();
    }
    
    if (history.videoPath.isEmpty) {
      debugPrint('错误: 视频路径为空，无法添加历史记录');
      throw Exception('视频路径为空，无法添加历史记录');
    }
    
    // 保存当前历史记录的引用
    final oldCurrentHistory = _currentHistory;
    
    try {
      debugPrint('保存历史记录到Hive...');
      // 保存到Hive
      await _historyBox.put(history.videoPath, history);
      debugPrint('历史记录已保存到Hive');
      
      // 更新内存中的列表
      // 移除相同视频路径的记录
      _history.removeWhere(
        (item) => item.videoPath == history.videoPath && item.subtitlePath == history.subtitlePath
      );
      
      // 添加到列表顶部
      _history.insert(0, history);
      debugPrint('历史记录已添加到内存列表');
      
      // 限制历史记录数量为20条
      if (_history.length > 20) {
        debugPrint('历史记录超过20条，删除旧记录');
        _history = _history.sublist(0, 20);
        
        // 删除多余的记录
        final keysToKeep = _history.map((e) => e.videoPath).toSet();
        keysToKeep.add(_lastPlayStateKey); // 保留最后播放状态
        
        final allKeys = _historyBox.keys.cast<String>().toList();
        for (final key in allKeys) {
          if (!keysToKeep.contains(key)) {
            await _historyBox.delete(key);
            debugPrint('删除多余历史记录: $key');
          }
        }
      }
      
      // 如果当前历史记录被错误地更新，恢复它
      if (_currentHistory != oldCurrentHistory && oldCurrentHistory != null) {
        debugPrint('检测到添加历史记录时currentHistory被错误更新，恢复原值');
        _currentHistory = oldCurrentHistory;
      }
      
      debugPrint('历史记录添加完成，通知监听器');
      notifyListeners();
    } catch (e) {
      debugPrint('添加历史记录失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      throw Exception('添加历史记录失败: $e');
    }
  }
  
  // 删除历史记录
  Future<void> removeHistory(int index) async {
    if (!_isInitialized) await initialize();
    
    if (index >= 0 && index < _history.length) {
      try {
        final item = _history[index];
        
        // 从Hive中删除
        await _historyBox.delete(item.videoPath);
        
        // 从内存列表中删除
        _history.removeAt(index);
        
        notifyListeners();
      } catch (e) {
        debugPrint('删除历史记录失败: $e');
      }
    }
  }
  
  // 清空历史记录
  Future<void> clearHistory() async {
    if (!_isInitialized) await initialize();
    
    try {
      debugPrint('开始清空历史记录...');
      
      // 保留最后播放状态
      final lastState = _historyBox.get(_lastPlayStateKey);
      debugPrint('保存最后播放状态: ${lastState?.videoName ?? "无"}');
      
      // 获取所有键，除了最后播放状态的键
      final keysToDelete = _historyBox.keys
          .where((key) => key != _lastPlayStateKey)
          .toList();
      
      debugPrint('需要删除 ${keysToDelete.length} 条历史记录');
      
      // 逐个删除历史记录，而不是使用clear()
      for (final key in keysToDelete) {
        await _historyBox.delete(key);
      }
      
      // 恢复最后播放状态
      if (lastState != null) {
        await _historyBox.put(_lastPlayStateKey, lastState);
        debugPrint('已恢复最后播放状态');
      }
      
      // 清空内存列表
      _history.clear();
      debugPrint('内存历史记录列表已清空');
      
      notifyListeners();
      debugPrint('历史记录清空完成');
    } catch (e) {
      debugPrint('清空历史记录失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      throw Exception('清空历史记录失败: $e');
    }
  }
  
  // 设置当前历史记录
  void setCurrentHistory(VideoHistory history) {
    _currentHistory = history;
    notifyListeners();
  }
  
  // 保存最后播放状态
  Future<void> saveLastPlayState(VideoHistory lastState) async {
    debugPrint('开始保存最后播放状态...');
    debugPrint('视频: ${lastState.videoName}, 路径: ${lastState.videoPath}');
    debugPrint('位置: ${lastState.lastPosition.inSeconds}秒');
    
    if (!_isInitialized) {
      debugPrint('历史记录服务未初始化，尝试初始化...');
      await initialize();
    }
    
    try {
      // 保存到Hive
      debugPrint('保存最后播放状态到Hive...');
      await _historyBox.put(_lastPlayStateKey, lastState);
      debugPrint('最后播放状态已保存到Hive');
      
      // 保存当前历史记录的引用
      final oldCurrentHistory = _currentHistory;
      
      // 更新最后播放状态，但不触发通知
      _lastPlayState = lastState;
      
      // 如果当前历史记录被错误地更新，恢复它
      if (_currentHistory != oldCurrentHistory && oldCurrentHistory != null) {
        debugPrint('检测到currentHistory被错误更新，恢复原值');
        _currentHistory = oldCurrentHistory;
      }
      
      debugPrint('已保存最后播放状态: ${lastState.videoName}');
      debugPrint('当前历史记录: ${_currentHistory?.videoName ?? "无"}');
      
      // 仅通知最后播放状态的变化
      notifyListeners();
    } catch (e) {
      debugPrint('保存最后播放状态失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 加载最后播放状态
  Future<void> loadLastPlayState() async {
    if (!_isInitialized) await initialize();
    
    try {
      // 从Hive加载
      _lastPlayState = _historyBox.get(_lastPlayStateKey);
      
      if (_lastPlayState != null) {
        debugPrint('已加载最后播放状态: ${_lastPlayState?.videoName}');
      } else {
        debugPrint('没有找到最后播放状态');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('加载最后播放状态失败: $e');
      _lastPlayState = null;
    }
  }
} 