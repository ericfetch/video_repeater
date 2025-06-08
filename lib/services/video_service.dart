import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/subtitle_model.dart';
import 'config_service.dart';
import 'youtube_service.dart';

class VideoService extends ChangeNotifier {
  Player? _player;
  SubtitleData? _subtitleData;
  SubtitleEntry? _currentSubtitle;
  bool _isLooping = false;
  int _loopCount = 0;
  bool _isLoading = false;
  String? _errorMessage;
  Duration? _lastPosition;
  Duration _currentPosition = Duration.zero; // 当前播放位置
  Duration _duration = Duration.zero; // 视频总时长
  Timer? _loopTimer;
  bool _isWaitingForLoop = false;
  SubtitleEntry? _loopingSubtitle; // 记录当前正在循环的字幕
  String? _currentVideoPath; // 当前视频路径
  String? _currentSubtitlePath; // 当前字幕路径
  ConfigService? _configService; // 配置服务
  Timer? _debounceTimer;
  
  // YouTube相关属性
  final YouTubeService _youtubeService = YouTubeService();
  bool _isYouTubeVideo = false;
  String? _youtubeVideoId;
  GlobalKey<dynamic>? _youtubePlayerKey;
  
  // 下载相关属性
  String? _downloadStatus; // 下载状态文本
  double _downloadProgress = 0.0; // 下载进度（0-1）
  
  // 字幕时间偏移量（毫秒）
  int _subtitleTimeOffset = 0;
  
  Player? get player => _player;
  SubtitleData? get subtitleData => _subtitleData;
  SubtitleEntry? get currentSubtitle => _currentSubtitle;
  bool get isLooping => _isLooping;
  int get loopCount => _loopCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isWaitingForLoop => _isWaitingForLoop;
  String? get currentVideoPath => _currentVideoPath; // 获取当前视频路径
  String? get currentSubtitlePath => _currentSubtitlePath; // 获取当前字幕路径
  int get subtitleTimeOffset => _subtitleTimeOffset; // 获取字幕时间偏移量
  Duration get currentPosition => _currentPosition; // 获取当前播放位置
  Duration get duration => _duration; // 获取视频总时长
  bool get isYouTubeVideo => _isYouTubeVideo; // 是否是YouTube视频
  String? get youtubeVideoId => _youtubeVideoId; // YouTube视频ID
  GlobalKey<dynamic>? get youtubePlayerKey => _youtubePlayerKey; // YouTube播放器Key
  String? get downloadStatus => _downloadStatus; // 下载状态
  double get downloadProgress => _downloadProgress; // 下载进度
  
  // 判断是否为YouTube链接
  bool isYouTubeLink(String url) {
    return url.contains('youtube.com/watch') || url.contains('youtu.be/');
  }
  
  // 设置YouTube播放器Key
  void setYouTubePlayerKey(GlobalKey<dynamic> key) {
    _youtubePlayerKey = key;
  }
  
  VideoService() {
    _initPlayer();
  }
  
  void setConfigService(ConfigService configService) {
    _configService = configService;
    _configService!.addListener(_onConfigChanged);
    
    // 应用初始配置
    _applyConfig();
  }
  
  void _onConfigChanged() {
    if (_configService != null && _player != null) {
      _applyConfig();
    }
  }
  
  void _applyConfig() {
    if (_configService == null || _player == null) return;
    
    // 应用默认播放速度
    if (!_player!.state.playing) {
      _player!.setRate(_configService!.defaultPlaybackRate);
    }
  }
  
  void _initPlayer() {
    try {
      debugPrint('开始初始化播放器');
      _player = Player();
      _player!.stream.position.listen(_onPositionChanged);
      _player!.stream.playing.listen(_onPlayingChanged);
      _player!.stream.error.listen(_onPlayerError);
      _player!.stream.duration.listen(_onDurationChanged);
      
      // 验证播放器是否正确初始化
      if (_player != null) {
        debugPrint('播放器初始化成功: $_player');
      } else {
        debugPrint('播放器初始化失败: 对象为空');
      }
    } catch (e) {
      debugPrint('播放器初始化错误: $e');
      _errorMessage = '播放器初始化失败: $e';
      notifyListeners();
    }
  }
  
  void _onPositionChanged(Duration position) {
    // 更新当前位置
    _currentPosition = position;
    
    // 如果没有字幕数据，或者没有字幕条目，只更新UI
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      notifyListeners();
      return;
    }
    
    try {
      // 直接调用更新字幕的方法
      _updateCurrentSubtitle(position);
      
      // 循环播放逻辑
      if (_isLooping && _loopingSubtitle != null) {
        // 考虑字幕时间偏移，确保不为负值
        final adjustedPosition = Duration(
          milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
        );
        
        // 如果当前位置超过了循环字幕的结束时间，说明需要循环
        if (_loopingSubtitle!.end.inMilliseconds < adjustedPosition.inMilliseconds) {
          _loopCount++;
          debugPrint('字幕变化触发循环: 第 $_loopCount 次，等待2秒后从 ${_loopingSubtitle!.start.inSeconds} 秒重新开始');
          
          // 暂停播放
          _player!.pause();
          _isWaitingForLoop = true;
          notifyListeners();
          
          // 获取循环等待时间
          final loopWaitInterval = _configService?.loopWaitInterval ?? 2000;
          
          // 等待设定的时间后重新开始播放
          _loopTimer?.cancel();
          _loopTimer = Timer(Duration(milliseconds: loopWaitInterval), () {
            if (_isLooping && _loopingSubtitle != null && _player != null) {
              // 跳回字幕开始位置（考虑时间偏移）
              final targetPosition = Duration(
                milliseconds: _loopingSubtitle!.start.inMilliseconds + _subtitleTimeOffset
              );
              debugPrint('循环播放: 准备跳转到 ${targetPosition.inMilliseconds}ms');
              
              // 跳回字幕开始位置
              _player!.seek(targetPosition);
              
              // 确保播放
              Future.delayed(const Duration(milliseconds: 100), () {
                if (_player != null && _isLooping) {
                  _player!.play();
                  debugPrint('循环播放: 已开始播放');
                }
              });
              
              _isWaitingForLoop = false;
              notifyListeners();
            } else {
              debugPrint('循环播放: 条件不满足，取消循环');
              if (!_isLooping) debugPrint('- 循环模式已关闭');
              if (_loopingSubtitle == null) debugPrint('- 当前无循环字幕');
              if (_player == null) debugPrint('- 播放器为空');
            }
          });
        }
      }
      
      // 记录最后的播放位置
      _lastPosition = position;
      
      // 确保UI更新
      notifyListeners();
    } catch (e) {
      // 捕获并记录错误，但不影响播放
      debugPrint('字幕跟踪错误: $e');
      
      // 确保UI更新
      notifyListeners();
    }
  }
  
  void _onPlayingChanged(bool isPlaying) {
    debugPrint('播放状态变化: ${isPlaying ? "播放" : "暂停"}');
    notifyListeners();
  }
  
  void _onPlayerError(String error) {
    _errorMessage = '播放器错误: $error';
    debugPrint(_errorMessage);
    notifyListeners();
  }
  
  // 处理视频时长变化
  void _onDurationChanged(Duration duration) {
    _duration = duration;
    debugPrint('视频时长更新: ${duration.inSeconds}秒');
    notifyListeners();
  }
  
  // 加载视频文件
  Future<bool> loadVideo(String videoPath) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      // 清理之前的资源
      _clearPreviousResources();
      
      // 判断是否为YouTube链接
      if (isYouTubeLink(videoPath)) {
        // 提取YouTube视频ID
        final videoId = await _youtubeService.extractVideoId(videoPath);
        if (videoId == null) {
          _errorMessage = '无效的YouTube链接或ID';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        
        _isYouTubeVideo = true;
        return await _loadYouTubeVideo(videoId);
      } else {
        _isYouTubeVideo = false;
        return await _loadLocalVideo(videoPath);
      }
    } catch (e) {
      _errorMessage = '加载视频失败: $e';
      debugPrint(_errorMessage);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // 加载本地视频
  Future<bool> _loadLocalVideo(String videoPath) async {
    if (_player == null) {
      _errorMessage = '播放器未初始化';
      _isLoading = false;
      notifyListeners();
      return false;
    }
    
    try {
      // 验证文件是否存在
      final file = File(videoPath);
      if (!await file.exists()) {
        _errorMessage = '视频文件不存在: $videoPath';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // 记录当前视频路径
      _currentVideoPath = videoPath;
      
      // 加载视频
      await _player!.open(Media(videoPath));
      debugPrint('成功加载视频: $videoPath');
      
      // 应用配置
      if (_configService != null) {
        _player!.setRate(_configService!.defaultPlaybackRate);
      }
      
      // 尝试自动加载字幕
      if (_configService != null && _configService!.autoMatchSubtitle) {
        await _tryAutoMatchSubtitle(videoPath);
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '加载视频失败: $e';
      debugPrint(_errorMessage);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // 尝试自动匹配字幕
  Future<bool> _tryAutoMatchSubtitle(String videoPath) async {
    try {
      if (_configService == null) return false;
      
      final videoDir = path.dirname(videoPath);
      final videoName = path.basenameWithoutExtension(videoPath);
      
      // 尝试匹配字幕文件
      String? subtitlePath;
      
      // 1. 首先尝试与视频同名的字幕文件
      if (_configService!.subtitleMatchMode == 'same' || _configService!.subtitleMatchMode == 'both') {
        final sameNamePath = path.join(videoDir, '$videoName.srt');
        if (File(sameNamePath).existsSync()) {
          subtitlePath = sameNamePath;
          debugPrint('找到同名字幕文件: $subtitlePath');
        }
      }
      
      // 2. 如果没找到同名字幕，尝试后缀匹配
      if (subtitlePath == null && 
          (_configService!.subtitleMatchMode == 'suffix' || _configService!.subtitleMatchMode == 'both')) {
        for (final suffix in _configService!.subtitleSuffixes) {
          final suffixPath = path.join(videoDir, '$videoName$suffix.srt');
          if (File(suffixPath).existsSync()) {
            subtitlePath = suffixPath;
            debugPrint('找到后缀字幕文件: $subtitlePath');
            break;
          }
        }
      }
      
      // 如果找到了字幕文件，加载它
      if (subtitlePath != null) {
        final success = await loadSubtitle(subtitlePath);
        if (success) {
          debugPrint('自动加载字幕成功: $subtitlePath');
          return true;
        }
      }
      
      debugPrint('未找到匹配的字幕文件');
      return false;
    } catch (e) {
      debugPrint('自动匹配字幕错误: $e');
      return false;
    }
  }
  
  // 加载字幕文件
  Future<bool> loadSubtitle(String path) async {
    try {
      final subtitleFile = File(path);
      if (!subtitleFile.existsSync()) {
        _errorMessage = '字幕文件不存在';
        notifyListeners();
        return false;
      }
      
      final content = await subtitleFile.readAsString();
      debugPrint('字幕文件内容长度: ${content.length}');
      
      // 保存当前字幕路径
      _currentSubtitlePath = path;
      
      // 禁用播放器内部字幕显示
      if (_player != null) {
        // 首先尝试移除所有现有字幕
        try {
          await _player!.setSubtitleTrack(SubtitleTrack.no());
        } catch (e) {
          debugPrint('禁用字幕显示时出错: $e');
        }
      }
      
      // 解析SRT格式字幕
      final entries = <SubtitleEntry>[];
      final lines = content.split('\n');
      
      int index = 0;
      int entryIndex = 0;
      Duration? startTime;
      Duration? endTime;
      String text = '';
      
      while (index < lines.length) {
        final line = lines[index].trim();
        
        // 跳过空行
        if (line.isEmpty) {
          index++;
          continue;
        }
        
        // 尝试解析序号行
        if (int.tryParse(line) != null) {
          // 如果已经有完整的字幕条目，添加到列表中
          if (startTime != null && endTime != null && text.isNotEmpty) {
            entries.add(SubtitleEntry(
              index: entryIndex,
              start: startTime,
              end: endTime,
              text: text.trim(),
            ));
            entryIndex++;
            text = '';
          }
          
          index++;
          
          // 解析时间行
          if (index < lines.length) {
            final timeLine = lines[index].trim();
            final times = timeLine.split(' --> ');
            
            if (times.length == 2) {
              startTime = _parseTime(times[0]);
              endTime = _parseTime(times[1]);
            }
            
            index++;
            
            // 解析文本行
            text = '';
            while (index < lines.length && lines[index].trim().isNotEmpty) {
              if (text.isNotEmpty) {
                text += '\n';
              }
              text += lines[index].trim();
              index++;
            }
          }
        } else {
          index++;
        }
      }
      
      // 添加最后一个字幕条目
      if (startTime != null && endTime != null && text.isNotEmpty) {
        entries.add(SubtitleEntry(
          index: entryIndex,
          start: startTime,
          end: endTime,
          text: text.trim(),
        ));
      }
      
      _subtitleData = SubtitleData(entries: entries);
      debugPrint('成功加载字幕，共 ${entries.length} 条');
      
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '加载字幕失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
      return false;
    }
  }
  
  // 解析SRT时间格式 (00:00:00,000 -> Duration)
  Duration _parseTime(String timeString) {
    final parts = timeString.split(':');
    
    if (parts.length != 3) {
      return Duration.zero;
    }
    
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    
    final secondsParts = parts[2].split(',');
    final seconds = int.tryParse(secondsParts[0]) ?? 0;
    final milliseconds = int.tryParse(secondsParts.length > 1 ? secondsParts[1] : '0') ?? 0;
    
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
  
  // 加载YouTube视频
  Future<bool> _loadYouTubeVideo(String videoId, {bool showProgress = true}) async {
    try {
      _isLoading = true;
      _clearPreviousResources();
      _youtubeVideoId = videoId;
      
      _downloadStatus = '正在获取视频信息...';
      _downloadProgress = 0.0;
      notifyListeners();
      
      // 尝试最多3次下载视频
      int retryCount = 0;
      const maxRetries = 2;
      
      (String, String?)? downloadResult;
      
      while (downloadResult == null && retryCount <= maxRetries) {
        if (retryCount > 0) {
          _downloadStatus = '重试下载 (${retryCount}/${maxRetries})...';
          notifyListeners();
          await Future.delayed(const Duration(seconds: 1));
        }
        
        _downloadStatus = '正在准备下载视频...';
        notifyListeners();
        
        // 下载视频和字幕
        downloadResult = await _youtubeService.downloadVideoAndSubtitles(
          videoId, 
          onProgress: (progress) {
            if (showProgress) {
              _downloadProgress = progress;
              notifyListeners();
            }
          },
          onStatusUpdate: (status) {
            if (showProgress) {
              _downloadStatus = status;
              notifyListeners();
            }
          }
        );
        
        retryCount++;
      }
      
      if (downloadResult == null) {
        _errorMessage = '无法下载视频，请重试';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // 解包下载结果
      final (videoPath, subtitlePath) = downloadResult;
      
      _downloadStatus = '正在加载视频播放器...';
      notifyListeners();
      
      // 处理字幕
      SubtitleData? subtitleData;
      
      if (subtitlePath != null) {
        try {
          _downloadStatus = '正在加载字幕...';
          notifyListeners();
          
          // 从SRT文件加载字幕
          final subtitleContent = await File(subtitlePath).readAsString();
          subtitleData = parseSrtSubtitle(subtitleContent);
          
          if (subtitleData != null) {
            debugPrint('成功加载字幕文件: ${subtitleData.entries.length}条');
            _downloadStatus = '成功加载${subtitleData.entries.length}条字幕';
          } else {
            debugPrint('解析字幕文件失败');
            _downloadStatus = '字幕格式不正确';
          }
          notifyListeners();
        } catch (e) {
          debugPrint('加载字幕文件失败: $e');
          _downloadStatus = '加载字幕失败: $e';
          notifyListeners();
        }
      } else {
        // 如果没有下载到SRT字幕，尝试直接API获取
        try {
          _downloadStatus = '正在尝试获取字幕...';
          notifyListeners();
          subtitleData = await _youtubeService.downloadSubtitles(videoId);
          if (subtitleData != null) {
            debugPrint('成功下载YouTube字幕: ${subtitleData.entries.length}条');
            _downloadStatus = '成功获取${subtitleData.entries.length}条字幕';
          } else {
            debugPrint('下载YouTube字幕失败: 未找到字幕');
            _downloadStatus = '该视频没有可用字幕';
          }
          notifyListeners();
        } catch (e) {
          debugPrint('下载YouTube字幕失败: $e');
          _downloadStatus = '无法获取字幕: $e';
          notifyListeners();
        }
      }
      
      // 标记为YouTube视频，以便后续处理
      _isYouTubeVideo = true;
      
      // 使用媒体播放器加载视频
      _downloadStatus = '正在加载视频...';
      notifyListeners();
      await _player!.open(Media(videoPath));
      
      // 设置字幕数据
      _subtitleData = subtitleData;
      _currentSubtitle = null;
      
      // 重置循环状态
      _isLooping = false;
      _loopCount = 0;
      _loopingSubtitle = null;
      
      // 保存当前视频路径
      _currentVideoPath = 'watch?v=$videoId';
      _currentSubtitlePath = subtitlePath;
      
      // 重置字幕时间偏移
      _subtitleTimeOffset = 0;
      
      // 完成加载
      _isLoading = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('加载YouTube视频错误: $e');
      _errorMessage = '加载失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // 清理之前的资源
  void _clearPreviousResources() {
    _subtitleData = null;
    _currentSubtitle = null;
    _loopingSubtitle = null;
    _isLooping = false;
    _loopCount = 0;
    _currentPosition = Duration.zero;
    _duration = Duration.zero;
    _isYouTubeVideo = false;
    _youtubeVideoId = null;
    
    // 取消定时器
    _loopTimer?.cancel();
    _debounceTimer?.cancel();
  }
  
  // 切换播放/暂停状态
  void togglePlay() {
    if (_player != null) {
      if (_player!.state.playing) {
        _player!.pause();
        debugPrint('暂停视频');
      } else {
        _player!.play();
        debugPrint('播放视频');
      }
      notifyListeners();
    }
  }
  
  // 跳转到指定字幕
  void seekToSubtitle(SubtitleEntry entry) {
    if (_player != null) {
      try {
        debugPrint('跳转到字幕: #${entry.index + 1} - ${entry.text} (${entry.start.inMilliseconds}ms)');
        _player!.seek(entry.start);
        _currentSubtitle = entry;
        
        // 如果在循环模式下，更新循环字幕
        if (_isLooping) {
          _loopingSubtitle = entry;
          debugPrint('更新循环字幕: ${entry.text}');
        }
        
        notifyListeners();
      } catch (e) {
        debugPrint('跳转到字幕错误: $e');
        _resetSubtitleState();
      }
    }
  }
  
  // 跳转到下一个字幕
  void nextSubtitle() {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty || _player == null) {
      return;
    }
    
    try {
      // 获取当前位置
      final currentPosition = _player!.state.position;
      
      // 考虑字幕时间偏移
      final adjustedPosition = Duration(
        milliseconds: max(0, currentPosition.inMilliseconds - _subtitleTimeOffset)
      );
      
      // 找到当前字幕（如果在字幕内）
      SubtitleEntry? currentEntry;
      for (final entry in _subtitleData!.entries) {
        if (entry.start.inMilliseconds <= adjustedPosition.inMilliseconds && 
            entry.end.inMilliseconds >= adjustedPosition.inMilliseconds) {
          currentEntry = entry;
          break;
        }
      }
      
      // 找到下一个字幕
      SubtitleEntry? nextEntry;
      
      if (currentEntry != null) {
        // 如果当前在字幕内，找到紧邻的下一个字幕
        int currentIndex = currentEntry.index;
        if (currentIndex < _subtitleData!.entries.length - 1) {
          nextEntry = _subtitleData!.entries[currentIndex + 1];
        }
      } else {
        // 如果当前不在任何字幕内，找到最近的下一个字幕
        int minDistance = -1;
        for (final entry in _subtitleData!.entries) {
          if (entry.start.inMilliseconds > adjustedPosition.inMilliseconds) {
            int distance = entry.start.inMilliseconds - adjustedPosition.inMilliseconds;
            if (minDistance == -1 || distance < minDistance) {
              minDistance = distance;
              nextEntry = entry;
            }
          }
        }
      }
      
      // 如果找到下一个字幕，就跳转到它的开始位置
      if (nextEntry != null) {
        // 跳转时需要考虑时间偏移
        final seekPosition = Duration(milliseconds: nextEntry.start.inMilliseconds + _subtitleTimeOffset);
        seek(seekPosition);
        debugPrint('跳转到下一个字幕: #${nextEntry.index + 1}, 位置: ${seekPosition.inMilliseconds}ms');
      } else {
        debugPrint('没有下一个字幕');
      }
    } catch (e) {
      debugPrint('跳转到下一个字幕错误: $e');
    }
  }
  
  // 跳转到上一个字幕
  void previousSubtitle() {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty || _player == null) {
      return;
    }
    
    try {
      // 获取当前位置
      final currentPosition = _player!.state.position;
      
      // 考虑字幕时间偏移
      final adjustedPosition = Duration(
        milliseconds: max(0, currentPosition.inMilliseconds - _subtitleTimeOffset)
      );
      
      // 找到当前字幕（如果在字幕内）
      SubtitleEntry? currentEntry;
      for (final entry in _subtitleData!.entries) {
        if (entry.start.inMilliseconds <= adjustedPosition.inMilliseconds && 
            entry.end.inMilliseconds >= adjustedPosition.inMilliseconds) {
          currentEntry = entry;
          break;
        }
      }
      
      // 找到上一个字幕
      SubtitleEntry? prevEntry;
      
      if (currentEntry != null) {
        // 如果当前在字幕内，且不是第一句，就跳到当前字幕的开始位置
        // 如果已经在字幕开始附近（前1秒内），则跳到上一个字幕
        bool nearStart = (adjustedPosition.inMilliseconds - currentEntry.start.inMilliseconds) < 1000;
        
        if (nearStart && currentEntry.index > 0) {
          // 如果靠近开始且不是第一句，跳到上一句
          prevEntry = _subtitleData!.entries[currentEntry.index - 1];
        } else if (!nearStart) {
          // 如果不靠近开始，跳到当前字幕开始
          prevEntry = currentEntry;
        } else {
          // 如果靠近开始且是第一句，不做任何操作
          debugPrint('已经是第一个字幕');
          return;
        }
      } else {
        // 如果当前不在任何字幕内，找到最近的上一个字幕
        int minDistance = -1;
        for (int i = _subtitleData!.entries.length - 1; i >= 0; i--) {
          final entry = _subtitleData!.entries[i];
          if (entry.end.inMilliseconds < adjustedPosition.inMilliseconds) {
            int distance = adjustedPosition.inMilliseconds - entry.end.inMilliseconds;
            if (minDistance == -1 || distance < minDistance) {
              minDistance = distance;
              prevEntry = entry;
            }
          }
        }
      }
      
      // 如果找到上一个字幕，就跳转到它的开始位置
      if (prevEntry != null) {
        // 跳转时需要考虑时间偏移
        final seekPosition = Duration(milliseconds: prevEntry.start.inMilliseconds + _subtitleTimeOffset);
        seek(seekPosition);
        debugPrint('跳转到上一个字幕: #${prevEntry.index + 1}, 位置: ${seekPosition.inMilliseconds}ms');
      } else {
        debugPrint('没有上一个字幕');
      }
    } catch (e) {
      debugPrint('跳转到上一个字幕错误: $e');
    }
  }
  
  // 重置字幕状态
  void _resetSubtitleState() {
    try {
      if (_player != null && _subtitleData != null && _subtitleData!.entries.isNotEmpty) {
        final currentPosition = _player!.state.position;
        _currentSubtitle = _getAdjustedSubtitleAtTime(currentPosition);
        debugPrint('重置字幕状态 - 当前位置: ${currentPosition.inMilliseconds}ms, 当前字幕: ${_currentSubtitle?.index ?? "无"}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('重置字幕状态错误: $e');
    }
  }
  
  // 切换循环播放状态
  void toggleLoop() {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      debugPrint('无法切换循环状态：无字幕数据');
      return;
    }
    
    try {
      _isLooping = !_isLooping;
      
      if (_isLooping) {
        // 开始循环
        _loopCount = 0;
        
        // 获取当前位置
        Duration currentPosition;
        
        if (_isYouTubeVideo) {
          // YouTube视频使用_currentPosition
          currentPosition = _currentPosition;
        } else if (_player != null) {
          // 本地视频使用player.state.position
          currentPosition = _player!.state.position;
        } else {
          debugPrint('无法开始循环：没有播放器或当前位置');
          _isLooping = false;
          notifyListeners();
          return;
        }
        
        // 获取当前字幕（考虑时间偏移）
        final currentSubtitle = _getAdjustedSubtitleAtTime(currentPosition);
        
        if (currentSubtitle != null) {
          // 使用当前字幕作为循环字幕
          _loopingSubtitle = currentSubtitle;
          debugPrint('开始循环播放当前字幕: #${currentSubtitle.index + 1}, 内容: ${currentSubtitle.text}');
          
          // 跳转到循环字幕的开始位置（考虑时间偏移）
          final seekPosition = Duration(milliseconds: currentSubtitle.start.inMilliseconds + _subtitleTimeOffset);
          
          if (_isYouTubeVideo && _youtubePlayerKey?.currentState != null) {
            // YouTube视频使用WebView控制器跳转
            _youtubePlayerKey!.currentState!.seekTo(seekPosition);
          } else if (_player != null) {
            // 本地视频使用Player跳转
            seek(seekPosition);
          }
        } else {
          // 如果没有当前字幕，查找最近的字幕
          SubtitleEntry? nearestEntry;
          int minDistance = -1;
          
          for (final entry in _subtitleData!.entries) {
            // 考虑时间偏移计算调整后的开始时间
            final adjustedStart = Duration(milliseconds: entry.start.inMilliseconds + _subtitleTimeOffset);
            final distance = (adjustedStart.inMilliseconds - currentPosition.inMilliseconds).abs();
            
            if (minDistance < 0 || distance < minDistance) {
              minDistance = distance;
              nearestEntry = entry;
            }
          }
          
          if (nearestEntry != null) {
            _loopingSubtitle = nearestEntry;
            debugPrint('开始循环播放最近的字幕: #${nearestEntry.index + 1}, 内容: ${nearestEntry.text}');
            
            // 跳转到循环字幕的开始位置（考虑时间偏移）
            final seekPosition = Duration(milliseconds: nearestEntry.start.inMilliseconds + _subtitleTimeOffset);
            
            if (_isYouTubeVideo && _youtubePlayerKey?.currentState != null) {
              // YouTube视频使用WebView控制器跳转
              _youtubePlayerKey!.currentState!.seekTo(seekPosition);
            } else if (_player != null) {
              // 本地视频使用Player跳转
              seek(seekPosition);
            }
          } else {
            debugPrint('无法开始循环，找不到合适的字幕');
            _isLooping = false;
          }
        }
      } else {
        // 停止循环
        _loopingSubtitle = null;
        _loopCount = 0;
        debugPrint('停止循环播放');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('切换循环状态错误: $e');
      _isLooping = false;
      _loopingSubtitle = null;
      _loopCount = 0;
      notifyListeners();
    }
  }
  
  // 选择视频文件
  Future<String?> pickVideoFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    
    if (result != null && result.files.isNotEmpty) {
      return result.files.first.path;
    }
    return null;
  }
  
  // 选择字幕文件
  Future<String?> pickSubtitleFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass'],
      allowMultiple: false,
    );
    
    if (result != null && result.files.isNotEmpty) {
      return result.files.first.path;
    }
    return null;
  }
  
  // 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // 跳转到指定位置
  void seek(Duration position) {
    if (_player != null) {
      try {
        debugPrint('跳转到位置: ${position.inMilliseconds}ms');
        
        // 确保位置在有效范围内
        final safePosition = Duration(
          milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds)
        );
        
        // 执行跳转
        _player!.seek(safePosition);
        
        // 强制更新当前字幕状态
        if (_subtitleData != null && _subtitleData!.entries.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_player != null) {
              final actualPosition = _player!.state.position;
              _updateCurrentSubtitle(actualPosition);
              debugPrint('跳转后强制更新字幕状态，位置: ${actualPosition.inMilliseconds}ms');
            }
          });
        }
      } catch (e) {
        debugPrint('跳转错误: $e');
        // 尝试恢复状态
        _resetSubtitleState();
      }
    }
  }
  
  // 调整字幕时间偏移
  void adjustSubtitleTime(int seconds) {
    _subtitleTimeOffset += seconds * 1000; // 转换为毫秒
    debugPrint('调整字幕时间偏移: ${seconds > 0 ? '+' : ''}${seconds}秒，总偏移: ${_subtitleTimeOffset / 1000}秒');
    notifyListeners();
    
    // 如果正在播放，立即更新当前字幕
    if (_player != null && _player!.state.playing) {
      final currentPosition = _player!.state.position;
      debugPrint('当前位置: ${currentPosition.inSeconds}秒，调整后位置: ${max(0, currentPosition.inMilliseconds - _subtitleTimeOffset) / 1000}秒');
      _updateCurrentSubtitle(currentPosition);
    }
  }
  
  // 重置字幕时间偏移
  void resetSubtitleTime() {
    _subtitleTimeOffset = 0;
    debugPrint('重置字幕时间偏移');
    notifyListeners();
    
    // 如果正在播放，立即更新当前字幕
    if (_player != null && _player!.state.playing) {
      final currentPosition = _player!.state.position;
      _updateCurrentSubtitle(currentPosition);
    }
  }
  
  // 更新当前字幕
  void _updateCurrentSubtitle(Duration position) {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      _currentSubtitle = null;
      return;
    }
    
    // 获取调整后的字幕
    final subtitle = _getAdjustedSubtitleAtTime(position);
    
    // 检查是否需要更新当前字幕
    if (subtitle != _currentSubtitle) {
      _currentSubtitle = subtitle;
      
      // 如果有字幕变化且处于循环模式但没有选定循环字幕，自动设置当前字幕为循环字幕
      if (_isLooping && _loopingSubtitle == null && subtitle != null) {
        _loopingSubtitle = subtitle;
        debugPrint('自动设置循环字幕: "${subtitle.text}" (${subtitle.start.inSeconds}s - ${subtitle.end.inSeconds}s)');
      }
      
      // 记录字幕变化
      if (subtitle != null) {
        debugPrint('字幕更新: "${subtitle.text}" (${subtitle.start.inSeconds}s - ${subtitle.end.inSeconds}s)');
      } else {
        debugPrint('字幕更新: 无字幕');
      }
    }
  }
  
  // 获取指定时间点的字幕（考虑时间偏移）
  SubtitleEntry? _getAdjustedSubtitleAtTime(Duration position) {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      return null;
    }
    
    // 考虑字幕时间偏移，确保不为负值
    final adjustedPosition = Duration(
      milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
    );
    
    // 使用二分查找优化性能
    int low = 0;
    int high = _subtitleData!.entries.length - 1;
    
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      SubtitleEntry entry = _subtitleData!.entries[mid];
      
      // 检查当前位置是否在这个字幕的时间范围内
      if (adjustedPosition >= entry.start && adjustedPosition <= entry.end) {
        return entry;
      }
      
      // 如果当前位置在字幕开始时间之前，查找前半部分
      if (adjustedPosition < entry.start) {
        high = mid - 1;
      } else {
        // 否则查找后半部分
        low = mid + 1;
      }
    }
    
    // 如果没有找到匹配的字幕，返回最接近的前一个字幕
    // 这对于字幕导航功能很重要
    if (low > 0 && low <= _subtitleData!.entries.length) {
      // 返回前一个字幕，因为当前位置可能刚好在两个字幕之间
      return _subtitleData!.entries[low - 1];
    } else if (high >= 0 && high < _subtitleData!.entries.length) {
      // 或者返回后一个字幕，如果当前位置在第一个字幕之前
      return _subtitleData!.entries[high];
    }
    
    return null;
  }
  
  // 播放器位置监听器
  void _playerPositionListener() {
    if (_player == null) return;
    
    _player!.stream.position.listen((position) {
      // 更新字幕
      if (_subtitleData != null) {
        _updateCurrentSubtitle(position);
      }
      
      // 循环播放逻辑
      if (_isLooping && _loopingSubtitle != null) {
        // 考虑字幕时间偏移，确保不为负值
        final adjustedPosition = Duration(
          milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
        );
        final loopEnd = _loopingSubtitle!.end.inMilliseconds;
        
        // 如果超过了循环结束时间，就跳回循环开始时间
        if (adjustedPosition.inMilliseconds > loopEnd) {
          // 更新循环计数
          _loopCount++;
          debugPrint('完成循环 #$_loopCount，重新开始');
          
          // 跳回循环开始时间（考虑时间偏移）
          final seekPosition = Duration(milliseconds: _loopingSubtitle!.start.inMilliseconds + _subtitleTimeOffset);
          seek(seekPosition);
          
          notifyListeners();
        }
      }
    });
  }
  
  // 设置音量
  void setVolume(double volume) {
    if (_isYouTubeVideo && _youtubePlayerKey?.currentState != null) {
      _youtubePlayerKey!.currentState!.setVolume(volume);
      debugPrint('设置YouTube音量: $volume');
    } else if (_player != null) {
      _player!.setVolume(volume);
      debugPrint('设置本地视频音量: $volume');
    }
  }
  
  // 设置播放速度
  void setRate(double rate) {
    if (_isYouTubeVideo && _youtubePlayerKey?.currentState != null) {
      _youtubePlayerKey!.currentState!.setPlaybackRate(rate);
      debugPrint('设置YouTube播放速度: $rate');
    } else if (_player != null) {
      _player!.setRate(rate);
      debugPrint('设置本地视频播放速度: $rate');
    }
  }
  
  @override
  void dispose() {
    debugPrint('VideoService 销毁');
    
    // 取消所有定时器
    _loopTimer?.cancel();
    _debounceTimer?.cancel();
    
    // 移除配置服务监听器
    _configService?.removeListener(_onConfigChanged);
    
    // 清理字幕数据
    _subtitleData = null;
    _currentSubtitle = null;
    _loopingSubtitle = null;
    _currentVideoPath = null;
    _currentSubtitlePath = null;
    
    // 销毁播放器
    if (_player != null) {
      try {
        _player!.dispose();
        _player = null;
        debugPrint('播放器已销毁');
      } catch (e) {
        debugPrint('销毁播放器错误: $e');
      }
    }
    
    super.dispose();
  }
  
  // 从SRT格式的文本解析字幕
  SubtitleData? parseSrtSubtitle(String content) {
    try {
      final lines = content.split('\n');
      final List<SubtitleEntry> entries = [];
      
      int index = 0;
      int entryIndex = 0;
      String text = '';
      Duration start = Duration.zero;
      Duration end = Duration.zero;
      
      while (index < lines.length) {
        final line = lines[index].trim();
        index++;
        
        if (line.isEmpty) {
          // 空行表示一个字幕项结束
          if (text.isNotEmpty) {
            entries.add(SubtitleEntry(
              index: entryIndex,
              start: start,
              end: end,
              text: text.trim(),
            ));
            text = '';
            entryIndex++;
          }
          continue;
        }
        
        // 尝试解析编号行（可以忽略）
        if (int.tryParse(line) != null) {
          continue;
        }
        
        // 尝试解析时间行
        if (line.contains('-->')) {
          final parts = line.split('-->');
          if (parts.length == 2) {
            start = _parseSrtTime(parts[0].trim());
            end = _parseSrtTime(parts[1].trim());
            continue;
          }
        }
        
        // 其他行都是字幕文本
        if (text.isNotEmpty) {
          text += '\n';
        }
        text += line;
      }
      
      // 添加最后一个字幕（如果有）
      if (text.isNotEmpty) {
        entries.add(SubtitleEntry(
          index: entryIndex,
          start: start,
          end: end,
          text: text.trim(),
        ));
      }
      
      return SubtitleData(entries: entries);
    } catch (e) {
      debugPrint('解析SRT字幕出错: $e');
      return null;
    }
  }
  
  // 解析SRT时间格式为Duration
  Duration _parseSrtTime(String timeStr) {
    try {
      // 格式: 00:00:00,000
      final parts = timeStr.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        
        final secondParts = parts[2].split(',');
        if (secondParts.length == 2) {
          final seconds = int.parse(secondParts[0]);
          final milliseconds = int.parse(secondParts[1]);
          
          return Duration(
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );
        }
      }
      return Duration.zero;
    } catch (e) {
      debugPrint('解析SRT时间格式出错: $e');
      return Duration.zero;
    }
  }
} 