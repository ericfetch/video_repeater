import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_model.dart';

class HistoryService extends ChangeNotifier {
  static const String _historyKey = 'video_history';
  static const String _lastPlayStateKey = 'last_play_state';
  List<VideoHistory> _history = [];
  VideoHistory? _currentHistory;
  VideoHistory? _lastPlayState;
  
  List<VideoHistory> get history => _history;
  VideoHistory? get currentHistory => _currentHistory;
  VideoHistory? get lastPlayState => _lastPlayState;
  
  // 加载历史记录
  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey);
    
    if (historyJson != null) {
      _history = historyJson
          .map((item) => VideoHistory.fromJson(json.decode(item)))
          .toList();
      
      // 按时间戳排序，最新的在前面
      _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
    }
  }
  
  // 保存历史记录
  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _history
        .map((item) => json.encode(item.toJson()))
        .toList();
    
    await prefs.setStringList(_historyKey, historyJson);
  }
  
  // 添加历史记录
  Future<void> addHistory(VideoHistory history) async {
    // 保存当前历史记录的引用
    final oldCurrentHistory = _currentHistory;
    
    // 检查是否已存在相同视频路径的记录
    final existingIndex = _history.indexWhere(
      (item) => item.videoPath == history.videoPath && item.subtitlePath == history.subtitlePath
    );
    
    if (existingIndex != -1) {
      // 更新现有记录
      _history.removeAt(existingIndex);
    }
    
    // 添加到列表顶部
    _history.insert(0, history);
    
    // 限制历史记录数量为20条
    if (_history.length > 20) {
      _history = _history.sublist(0, 20);
    }
    
    await saveHistory();
    
    // 如果当前历史记录被错误地更新，恢复它
    if (_currentHistory != oldCurrentHistory && oldCurrentHistory != null) {
      debugPrint('检测到添加历史记录时currentHistory被错误更新，恢复原值');
      _currentHistory = oldCurrentHistory;
    }
    
    notifyListeners();
  }
  
  // 删除历史记录
  Future<void> removeHistory(int index) async {
    if (index >= 0 && index < _history.length) {
      _history.removeAt(index);
      await saveHistory();
      notifyListeners();
    }
  }
  
  // 清空历史记录
  Future<void> clearHistory() async {
    _history.clear();
    await saveHistory();
    notifyListeners();
  }
  
  // 设置当前历史记录
  void setCurrentHistory(VideoHistory history) {
    _currentHistory = history;
    notifyListeners();
  }
  
  // 保存最后播放状态
  Future<void> saveLastPlayState(VideoHistory lastState) async {
    final prefs = await SharedPreferences.getInstance();
    final stateJson = json.encode(lastState.toJson());
    
    await prefs.setString(_lastPlayStateKey, stateJson);
    
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
  }
  
  // 加载最后播放状态
  Future<void> loadLastPlayState() async {
    final prefs = await SharedPreferences.getInstance();
    final stateJson = prefs.getString(_lastPlayStateKey);
    
    if (stateJson != null) {
      try {
        _lastPlayState = VideoHistory.fromJson(json.decode(stateJson));
        debugPrint('已加载最后播放状态: ${_lastPlayState?.videoName}');
      } catch (e) {
        debugPrint('加载最后播放状态时出错: $e');
        _lastPlayState = null;
      }
      notifyListeners();
    } else {
      debugPrint('没有找到最后播放状态');
      _lastPlayState = null;
    }
  }
} 