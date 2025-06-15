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
  
  // 字幕相关
  List<Map<String, dynamic>> _availableSubtitleTracks = [];
  Map<String, dynamic>? _selectedSubtitleTrack;
  bool _isSubtitleDownloading = false;
  bool _subtitleDownloadFailed = false;
  String? _videoId; // 当前视频ID
  
  // Getters
  List<String> get messages => List.unmodifiable(_messages);
  bool get isVisible => _isVisible;
  double get progress => _progress;
  bool get isDownloading => _isDownloading;
  List<Map<String, dynamic>> get availableSubtitleTracks => _availableSubtitleTracks;
  Map<String, dynamic>? get selectedSubtitleTrack => _selectedSubtitleTrack;
  bool get isSubtitleDownloading => _isSubtitleDownloading;
  bool get subtitleDownloadFailed => _subtitleDownloadFailed;
  String? get videoId => _videoId;
  
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
    _availableSubtitleTracks = [];
    _selectedSubtitleTrack = null;
    _isSubtitleDownloading = false;
    _subtitleDownloadFailed = false;
    notifyListeners();
  }
  
  // 结束下载
  void endDownload() {
    _isDownloading = false;
    // 不立即隐藏面板，让用户可以看到完成信息
    addMessage("下载完成");
    
    // 如果有字幕轨道，不自动隐藏面板，让用户选择字幕
    if (_availableSubtitleTracks.isNotEmpty) {
      addMessage("请选择要下载的字幕");
    } else {
      // 5秒后自动隐藏面板
      Future.delayed(const Duration(seconds: 5), () {
        hidePanel();
      });
    }
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
  
  // 设置可用字幕轨道
  void setAvailableSubtitleTracks(List<Map<String, dynamic>> tracks, String videoId) {
    _availableSubtitleTracks = tracks;
    _videoId = videoId;
    notifyListeners();
  }
  
  // 选择字幕轨道
  void selectSubtitleTrack(Map<String, dynamic> track) {
    _selectedSubtitleTrack = track;
    notifyListeners();
  }
  
  // 开始下载字幕
  void startSubtitleDownload() {
    _isSubtitleDownloading = true;
    _subtitleDownloadFailed = false;
    addMessage("开始下载字幕: ${_selectedSubtitleTrack?['name'] ?? '未知'}");
    notifyListeners();
  }
  
  // 字幕下载完成
  void subtitleDownloadComplete(bool success) {
    _isSubtitleDownloading = false;
    _subtitleDownloadFailed = !success;
    
    if (success) {
      addMessage("字幕下载完成");
    } else {
      addMessage("字幕下载失败");
    }
    
    notifyListeners();
  }
  
  // 重置字幕状态
  void resetSubtitleState() {
    _isSubtitleDownloading = false;
    _subtitleDownloadFailed = false;
    notifyListeners();
  }
} 