import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/subtitle_model.dart';
import 'config_service.dart';

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
      
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        _errorMessage = '视频文件不存在';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // 停止当前播放
      if (_player != null) {
        await _player!.stop();
      }
      
      // 重置字幕状态
      _subtitleData = null;
      _currentSubtitle = null;
      _subtitleTimeOffset = 0;
      
      // 保存当前视频路径
      _currentVideoPath = videoPath;
      
      // 打开新视频
      await _player!.open(Media(videoPath));
      
      // 尝试自动匹配字幕
      if (_configService != null && _configService!.autoMatchSubtitle) {
        await _tryAutoMatchSubtitle(videoPath);
      }
      
      // 等待视频元数据加载
      int attempts = 0;
      const maxAttempts = 10;
      
      while (attempts < maxAttempts && _player!.state.duration == Duration.zero) {
        debugPrint('等待视频元数据加载，尝试 ${attempts + 1}/$maxAttempts');
        await Future.delayed(const Duration(milliseconds: 200));
        attempts++;
      }
      
      if (_player!.state.duration == Duration.zero) {
        debugPrint('警告：视频元数据可能未完全加载，持续时间为零');
      } else {
        debugPrint('视频元数据加载完成，持续时间: ${_player!.state.duration.inSeconds}秒');
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
      
      final videoFile = File(videoPath);
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
  
  // 播放/暂停
  void togglePlay() {
    if (_player != null) {
      if (_player!.state.playing) {
        _player!.pause();
      } else {
        _player!.play();
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
    if (_player == null || _subtitleData == null || _subtitleData!.entries.isEmpty) {
      return;
    }
    
    try {
      final currentPosition = _player!.state.position;
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
        
        // 如果没找到，可能是在最后一个字幕之后，不做任何操作
        if (nextEntry == null) {
          debugPrint('没有下一个字幕');
          return;
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
    if (_player == null || _subtitleData == null || _subtitleData!.entries.isEmpty) {
      return;
    }
    
    try {
      final currentPosition = _player!.state.position;
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
        
        // 如果没找到，可能是在第一个字幕之前，不做任何操作
        if (prevEntry == null) {
          debugPrint('没有上一个字幕');
          return;
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
    if (_player == null || _subtitleData == null || _subtitleData!.entries.isEmpty) {
      debugPrint('无法切换循环状态：播放器未初始化或无字幕数据');
      return;
    }
    
    try {
      _isLooping = !_isLooping;
      
      if (_isLooping) {
        // 开始循环
        _loopCount = 0;
        
        // 获取当前位置
        final currentPosition = _player!.state.position;
        
        // 获取当前字幕（考虑时间偏移）
        final currentSubtitle = _getAdjustedSubtitleAtTime(currentPosition);
        
        if (currentSubtitle != null) {
          // 使用当前字幕作为循环字幕
          _loopingSubtitle = currentSubtitle;
          debugPrint('开始循环播放当前字幕: #${currentSubtitle.index + 1}, 内容: ${currentSubtitle.text}');
          
          // 跳转到循环字幕的开始位置（考虑时间偏移）
          final seekPosition = Duration(milliseconds: currentSubtitle.start.inMilliseconds + _subtitleTimeOffset);
          seek(seekPosition);
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
            seek(seekPosition);
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
  
  // 根据当前位置更新字幕，考虑时间偏移
  void _updateCurrentSubtitle(Duration position) {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      _currentSubtitle = null;
      notifyListeners();
      return;
    }
    
    // 应用时间偏移，确保不为负值
    final adjustedPosition = Duration(
      milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
    );
    final positionMs = adjustedPosition.inMilliseconds;
    
    // 查找当前字幕
    SubtitleEntry? subtitle;
    
    for (int i = 0; i < _subtitleData!.entries.length; i++) {
      final sub = _subtitleData!.entries[i];
      if (positionMs >= sub.start.inMilliseconds && positionMs <= sub.end.inMilliseconds) {
        subtitle = sub;
        break;
      }
    }
    
    // 字幕变化或状态变化时通知监听器
    if (_currentSubtitle != subtitle) {
      if (subtitle == null) {
        debugPrint('更新字幕: 当前位置 ${position.inMilliseconds}ms (调整后 ${positionMs}ms) 没有对应字幕');
      } else {
        debugPrint('更新字幕: 当前位置 ${position.inMilliseconds}ms (调整后 ${positionMs}ms), 字幕 #${subtitle.index + 1}');
      }
      
      _currentSubtitle = subtitle;
      notifyListeners();
    }
  }
  
  // 修改_getAdjustedSubtitleAtTime方法，考虑时间偏移
  SubtitleEntry? _getAdjustedSubtitleAtTime(Duration position) {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) return null;
    
    // 应用时间偏移，确保不为负值
    final adjustedPosition = Duration(
      milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
    );
    final positionMs = adjustedPosition.inMilliseconds;
    
    // 调试信息
    if (_subtitleTimeOffset != 0 && (position.inMilliseconds / 1000).round() % 10 == 0) {
      debugPrint('字幕时间偏移: 原始位置=${position.inSeconds}秒, 调整后=${adjustedPosition.inSeconds}秒, 偏移=${_subtitleTimeOffset/1000}秒');
    }
    
    // 查找当前字幕
    for (final sub in _subtitleData!.entries) {
      if (positionMs >= sub.start.inMilliseconds && positionMs <= sub.end.inMilliseconds) {
        return sub;
      }
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
} 