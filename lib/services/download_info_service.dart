import 'package:flutter/foundation.dart';

/// 下载信息服务
/// 用于在YouTube视频下载过程中传递信息到UI面板
class DownloadInfoService extends ChangeNotifier {
  // 下载信息列表
  final List<String> _messages = [];
  
  // 是否显示下载面板
  bool _isVisible = false;
  
  // 下载进度 (0.0 - 1.0)
  double _progress = 0.0;
  
  // 是否正在下载
  bool _isDownloading = false;
  
  // Getters
  List<String> get messages => List.unmodifiable(_messages);
  bool get isVisible => _isVisible;
  double get progress => _progress;
  bool get isDownloading => _isDownloading;
  
  // 添加新消息
  void addMessage(String message) {
    _messages.add(message);
    notifyListeners();
  }
  
  // 设置进度
  void setProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    notifyListeners();
  }
  
  // 开始下载
  void startDownload() {
    _isDownloading = true;
    _isVisible = true;
    _messages.clear();
    _progress = 0.0;
    notifyListeners();
  }
  
  // 结束下载
  void endDownload() {
    _isDownloading = false;
    // 不立即隐藏面板，让用户可以看到完成信息
    addMessage("下载完成");
    
    // 5秒后自动隐藏面板
    Future.delayed(const Duration(seconds: 5), () {
      hidePanel();
    });
  }
  
  // 显示面板
  void showPanel() {
    _isVisible = true;
    notifyListeners();
  }
  
  // 隐藏面板
  void hidePanel() {
    _isVisible = false;
    notifyListeners();
  }
  
  // 清空消息
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }
  
  // 下载出错
  void downloadError(String errorMessage) {
    _isDownloading = false;
    addMessage("错误: $errorMessage");
  }
} 