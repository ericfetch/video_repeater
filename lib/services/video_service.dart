import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';
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
  Timer? _loopTimer;
  bool _isWaitingForLoop = false;
  SubtitleEntry? _loopingSubtitle; // 记录当前正在循环的字幕
  String? _currentVideoPath; // 当前视频路径
  ConfigService? _configService; // 配置服务
  
  Player? get player => _player;
  SubtitleData? get subtitleData => _subtitleData;
  SubtitleEntry? get currentSubtitle => _currentSubtitle;
  bool get isLooping => _isLooping;
  int get loopCount => _loopCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isWaitingForLoop => _isWaitingForLoop;
  String? get currentVideoPath => _currentVideoPath; // 获取当前视频路径
  
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
    _player = Player();
    _player!.stream.position.listen(_onPositionChanged);
    _player!.stream.playing.listen(_onPlayingChanged);
    _player!.stream.error.listen(_onPlayerError);
    
    debugPrint('播放器初始化完成');
  }
  
  void _onPositionChanged(Duration position) {
    // 如果没有字幕数据，或者没有当前字幕，不处理
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) return;
    
    // 检查是否有新的当前字幕
    final entry = _subtitleData!.getEntryAtTime(position);
    
    // 如果当前字幕变化了
    if (entry != _currentSubtitle) {
      // 如果在循环模式下，并且有循环字幕
      if (_isLooping && _loopingSubtitle != null) {
        // 如果当前位置超过了循环字幕的结束时间，说明需要循环
        if (entry != _loopingSubtitle) {
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
              final targetPosition = _loopingSubtitle!.start;
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
          
          // 更新当前字幕（虽然马上就会跳回）
          _currentSubtitle = entry;
          return; // 直接返回，不再执行后续逻辑
        }
      }
      
      _currentSubtitle = entry;
      notifyListeners();
    }
    
    // 记录最后的播放位置
    _lastPosition = position;
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
  
  // 加载视频文件
  Future<bool> loadVideo(String path) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      debugPrint('开始加载视频: $path');
      final file = File(path);
      if (!file.existsSync()) {
        _errorMessage = '视频文件不存在';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // 如果播放器未初始化，先初始化
      if (_player == null) {
        _initPlayer();
      }
      
      // 保存当前视频路径
      _currentVideoPath = path;
      
      // 打开视频文件，确保不自动加载字幕
      final media = Media(path);
      await _player!.open(media);
      
      debugPrint('视频加载成功');
      
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
      debugPrint('跳转到字幕: #${entry.index + 1} - ${entry.text}');
      _player!.seek(entry.start);
      _currentSubtitle = entry;
      
      // 如果在循环模式下，更新循环字幕
      if (_isLooping) {
        _loopingSubtitle = entry;
        debugPrint('更新循环字幕: ${entry.text}');
      }
      
      notifyListeners();
    }
  }
  
  // 下一句
  void nextSubtitle() {
    if (_subtitleData != null && _subtitleData!.entries.isNotEmpty) {
      if (_currentSubtitle != null) {
        // 有当前字幕，获取下一句
        final nextIndex = _currentSubtitle!.index + 1;
        final nextEntry = _subtitleData!.getEntryByIndex(nextIndex);
        if (nextEntry != null) {
          debugPrint('下一句: #${nextEntry.index + 1}');
          seekToSubtitle(nextEntry);
        } else {
          debugPrint('已经是最后一句');
        }
      } else {
        // 没有当前字幕，获取当前时间点之后的第一句字幕
        final currentPosition = _player?.state.position ?? Duration.zero;
        SubtitleEntry? nextEntry;
        
        // 寻找当前时间之后的第一条字幕
        for (var entry in _subtitleData!.entries) {
          if (entry.start > currentPosition) {
            nextEntry = entry;
            break;
          }
        }
        
        // 如果找不到，则使用第一条字幕
        nextEntry ??= _subtitleData!.entries.first;
        
        debugPrint('跳转到下一句: #${nextEntry.index + 1}');
        seekToSubtitle(nextEntry);
      }
    } else {
      debugPrint('无法跳转到下一句，无字幕数据');
    }
  }
  
  // 上一句
  void previousSubtitle() {
    if (_subtitleData != null && _subtitleData!.entries.isNotEmpty) {
      if (_currentSubtitle != null) {
        // 有当前字幕，获取上一句
        final prevIndex = _currentSubtitle!.index - 1;
        final prevEntry = _subtitleData!.getEntryByIndex(prevIndex);
        if (prevEntry != null) {
          debugPrint('上一句: #${prevEntry.index + 1}');
          seekToSubtitle(prevEntry);
        } else {
          debugPrint('已经是第一句');
        }
      } else {
        // 没有当前字幕，获取当前时间点之前的最后一句字幕
        final currentPosition = _player?.state.position ?? Duration.zero;
        SubtitleEntry? prevEntry;
        
        // 寻找当前时间之前的最后一条字幕
        for (var i = _subtitleData!.entries.length - 1; i >= 0; i--) {
          if (_subtitleData!.entries[i].end < currentPosition) {
            prevEntry = _subtitleData!.entries[i];
            break;
          }
        }
        
        // 如果找不到，则使用最后一条字幕
        prevEntry ??= _subtitleData!.entries.last;
        
        debugPrint('跳转到上一句: #${prevEntry.index + 1}');
        seekToSubtitle(prevEntry);
      }
    } else {
      debugPrint('无法跳转到上一句，无字幕数据');
    }
  }
  
  // 切换循环模式
  void toggleLoop() {
    _isLooping = !_isLooping;
    _loopCount = 0;
    _isWaitingForLoop = false;
    
    // 取消可能存在的定时器
    _loopTimer?.cancel();
    
    debugPrint('循环模式: ${_isLooping ? "开启" : "关闭"}');
    
    // 如果开启循环模式，设置当前字幕为循环字幕
    if (_isLooping && _currentSubtitle != null) {
      _loopingSubtitle = _currentSubtitle;
      debugPrint('设置循环字幕: ${_loopingSubtitle!.text}');
    } else {
      _loopingSubtitle = null;
    }
    
    // 如果开启循环模式且有当前字幕，确保从字幕开始位置播放
    if (_isLooping && _currentSubtitle != null && _player != null) {
      debugPrint('开启循环模式: 从 ${_currentSubtitle!.start.inSeconds} 秒开始');
      _player!.seek(_currentSubtitle!.start);
      _player!.play();
    }
    
    notifyListeners();
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
  
  // 获取当前播放位置
  Duration get currentPosition {
    return _player?.state.position ?? Duration.zero;
  }
  
  // 获取视频总时长
  Duration get duration {
    return _player?.state.duration ?? Duration.zero;
  }
  
  // 跳转到指定位置
  void seek(Duration position) {
    if (player != null) {
      player!.seek(position);
    }
  }
  
  @override
  void dispose() {
    _loopTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }
} 