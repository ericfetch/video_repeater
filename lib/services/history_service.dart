import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_model.dart';

class HistoryService extends ChangeNotifier {
  static const String _historyKey = 'video_history';
  List<VideoHistory> _history = [];
  VideoHistory? _currentHistory;
  
  List<VideoHistory> get history => _history;
  VideoHistory? get currentHistory => _currentHistory;
  
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
} 