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
  String? _currentSubtitlePath; // 当前字幕路径
  ConfigService? _configService; // 配置服务
  Timer? _debounceTimer;
  
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
    // 如果没有字幕数据，或者没有字幕条目，不处理
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) return;
    
    try {
      // 检查是否有新的当前字幕
      final entry = _subtitleData!.getEntryAtTime(position);
      
      // 调试日志
      if (entry != _currentSubtitle) {
        if (entry == null) {
          debugPrint('字幕变化: 当前位置 ${position.inMilliseconds}ms 没有对应字幕');
        } else {
          debugPrint('字幕变化: 当前位置 ${position.inMilliseconds}ms, 字幕 #${entry.index + 1}');
        }
      }
      
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
    } catch (e) {
      // 捕获并记录错误，但不影响播放
      debugPrint('字幕跟踪错误: $e');
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
  
  // 加载视频文件
  Future<bool> loadVideo(String path) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      debugPrint('开始加载视频: $path');
      final file = File(path);
      if (!file.existsSync()) {
        _errorMessage = '视频文件不存在: $path';
        debugPrint(_errorMessage);
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      debugPrint('视频文件存在，大小: ${await file.length()} 字节');
      
      // 如果播放器未初始化，先初始化
      if (_player == null) {
        debugPrint('播放器为空，重新初始化');
        _initPlayer();
        
        // 再次检查初始化是否成功
        if (_player == null) {
          _errorMessage = '播放器初始化失败';
          debugPrint(_errorMessage);
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }
      
      // 保存当前视频路径
      _currentVideoPath = path;
      
      // 打开视频文件，确保不自动加载字幕
      final media = Media(path);
      debugPrint('创建Media对象，准备打开视频');
      
      // 先尝试停止当前播放
      try {
        if (_player!.state.playing) {
          await _player!.pause();
          debugPrint('已暂停当前播放');
        }
      } catch (e) {
        debugPrint('暂停当前播放时出错: $e');
      }
      
      // 打开新视频
      await _player!.open(media);
      debugPrint('视频打开成功');
      
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
  
  // 下一句
  void nextSubtitle() {
    // 防止短时间内重复调用
    if (_debounceTimer?.isActive ?? false) {
      debugPrint('防抖: 忽略快速连续的nextSubtitle调用');
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {});
    
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      debugPrint('无法跳转到下一句，无字幕数据');
      return;
    }
    
    if (_player == null) {
      debugPrint('无法跳转到下一句，播放器未初始化');
      return;
    }
    
    try {
      // 获取当前播放位置
      final currentPosition = _player?.state.position ?? Duration.zero;
      debugPrint('当前位置: ${currentPosition.inMilliseconds}ms');
      
      // 强制重新获取当前字幕
      final currentSubtitle = _subtitleData!.getEntryAtTime(currentPosition);
      if (currentSubtitle != null) {
        _currentSubtitle = currentSubtitle;
        debugPrint('重新确认当前字幕: #${currentSubtitle.index + 1}');
      }
      
      if (_currentSubtitle != null) {
        // 有当前字幕，获取下一句
        final nextIndex = _currentSubtitle!.index + 1;
        final nextEntry = _subtitleData!.getEntryByIndex(nextIndex);
        if (nextEntry != null) {
          debugPrint('下一句: #${nextEntry.index + 1} (${nextEntry.start.inMilliseconds}ms)');
          
          // 使用固定的seek方法确保跳转成功
          _player!.seek(nextEntry.start);
          _currentSubtitle = nextEntry;
          
          // 如果在循环模式下，更新循环字幕
          if (_isLooping) {
            _loopingSubtitle = nextEntry;
            debugPrint('更新循环字幕: ${nextEntry.text}');
          }
          
          notifyListeners();
        } else {
          debugPrint('已经是最后一句');
        }
      } else {
        // 没有当前字幕，查找当前时间点之后的第一句字幕
        SubtitleEntry? nextEntry;
        
        // 先尝试获取当前时间的字幕
        nextEntry = _subtitleData!.getEntryAtTime(currentPosition);
        
        // 如果当前没有字幕，寻找下一条字幕
        if (nextEntry == null) {
          for (var entry in _subtitleData!.entries) {
            if (entry.start > currentPosition) {
              nextEntry = entry;
              break;
            }
          }
        } else {
          // 如果当前有字幕，获取下一条
          final nextIndex = nextEntry.index + 1;
          nextEntry = _subtitleData!.getEntryByIndex(nextIndex) ?? nextEntry;
        }
        
        // 如果找不到，则使用第一条字幕
        nextEntry ??= _subtitleData!.entries.first;
        
        debugPrint('跳转到下一句: #${nextEntry.index + 1} (${nextEntry.start.inMilliseconds}ms)');
        
        // 使用固定的seek方法确保跳转成功
        _player!.seek(nextEntry.start);
        _currentSubtitle = nextEntry;
        
        // 如果在循环模式下，更新循环字幕
        if (_isLooping) {
          _loopingSubtitle = nextEntry;
          debugPrint('更新循环字幕: ${nextEntry.text}');
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('下一句处理错误: $e');
      // 尝试恢复状态
      _resetSubtitleState();
    }
  }
  
  // 上一句
  void previousSubtitle() {
    // 防止短时间内重复调用
    if (_debounceTimer?.isActive ?? false) {
      debugPrint('防抖: 忽略快速连续的previousSubtitle调用');
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {});
    
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      debugPrint('无法跳转到上一句，无字幕数据');
      return;
    }
    
    if (_player == null) {
      debugPrint('无法跳转到上一句，播放器未初始化');
      return;
    }
    
    try {
      // 获取当前播放位置
      final currentPosition = _player?.state.position ?? Duration.zero;
      debugPrint('当前位置: ${currentPosition.inMilliseconds}ms');
      
      // 强制重新获取当前字幕
      final currentSubtitle = _subtitleData!.getEntryAtTime(currentPosition);
      if (currentSubtitle != null) {
        _currentSubtitle = currentSubtitle;
        debugPrint('重新确认当前字幕: #${currentSubtitle.index + 1}');
      }
      
      if (_currentSubtitle != null) {
        // 有当前字幕，获取上一句
        final prevIndex = _currentSubtitle!.index - 1;
        final prevEntry = _subtitleData!.getEntryByIndex(prevIndex);
        if (prevEntry != null) {
          debugPrint('上一句: #${prevEntry.index + 1} (${prevEntry.start.inMilliseconds}ms)');
          
          // 使用固定的seek方法确保跳转成功
          _player!.seek(prevEntry.start);
          _currentSubtitle = prevEntry;
          
          // 如果在循环模式下，更新循环字幕
          if (_isLooping) {
            _loopingSubtitle = prevEntry;
            debugPrint('更新循环字幕: ${prevEntry.text}');
          }
          
          notifyListeners();
        } else {
          debugPrint('已经是第一句');
        }
      } else {
        // 没有当前字幕，查找当前时间点之前的最后一句字幕
        SubtitleEntry? prevEntry;
        
        // 先尝试获取当前时间的字幕
        prevEntry = _subtitleData!.getEntryAtTime(currentPosition);
        
        // 如果当前没有字幕，寻找前一条字幕
        if (prevEntry == null) {
          for (var i = _subtitleData!.entries.length - 1; i >= 0; i--) {
            if (_subtitleData!.entries[i].end < currentPosition) {
              prevEntry = _subtitleData!.entries[i];
              break;
            }
          }
        } else {
          // 如果当前有字幕，获取上一条
          final prevIndex = prevEntry.index - 1;
          prevEntry = _subtitleData!.getEntryByIndex(prevIndex) ?? prevEntry;
        }
        
        // 如果找不到，则使用最后一条字幕
        prevEntry ??= _subtitleData!.entries.last;
        
        debugPrint('跳转到上一句: #${prevEntry.index + 1} (${prevEntry.start.inMilliseconds}ms)');
        
        // 使用固定的seek方法确保跳转成功
        _player!.seek(prevEntry.start);
        _currentSubtitle = prevEntry;
        
        // 如果在循环模式下，更新循环字幕
        if (_isLooping) {
          _loopingSubtitle = prevEntry;
          debugPrint('更新循环字幕: ${prevEntry.text}');
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('上一句处理错误: $e');
      // 尝试恢复状态
      _resetSubtitleState();
    }
  }
  
  // 重置字幕状态
  void _resetSubtitleState() {
    try {
      if (_player != null && _subtitleData != null && _subtitleData!.entries.isNotEmpty) {
        final currentPosition = _player!.state.position;
        _currentSubtitle = _subtitleData!.getEntryAtTime(currentPosition);
        debugPrint('重置字幕状态 - 当前位置: ${currentPosition.inMilliseconds}ms, 当前字幕: ${_currentSubtitle?.index ?? "无"}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('重置字幕状态错误: $e');
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
    
    try {
      // 如果开启循环模式，设置当前字幕为循环字幕
      if (_isLooping && _player != null) {
        // 获取当前位置
        final currentPosition = _player!.state.position;
        
        // 重新获取当前字幕，确保准确性
        if (_subtitleData != null && _subtitleData!.entries.isNotEmpty) {
          final entry = _subtitleData!.getEntryAtTime(currentPosition);
          
          if (entry != null) {
            _currentSubtitle = entry;
            _loopingSubtitle = entry;
            debugPrint('设置循环字幕: #${entry.index + 1} - ${entry.text}');
            
            // 确保从字幕开始位置播放
            debugPrint('开启循环模式: 从 ${entry.start.inMilliseconds}ms 开始');
            _player!.seek(entry.start);
            
            if (!_player!.state.playing) {
              _player!.play();
            }
          } else {
            debugPrint('无法设置循环字幕: 当前位置没有字幕');
            
            // 尝试找到最近的字幕
            SubtitleEntry? nearestEntry;
            for (var e in _subtitleData!.entries) {
              if (e.start > currentPosition) {
                nearestEntry = e;
                break;
              }
            }
            
            // 如果找到了最近的字幕，使用它
            if (nearestEntry != null) {
              _currentSubtitle = nearestEntry;
              _loopingSubtitle = nearestEntry;
              debugPrint('设置最近的字幕作为循环字幕: #${nearestEntry.index + 1}');
              
              // 跳转到这个字幕
              _player!.seek(nearestEntry.start);
              
              if (!_player!.state.playing) {
                _player!.play();
              }
            } else if (_subtitleData!.entries.isNotEmpty) {
              // 如果找不到最近的字幕，使用第一条字幕
              _currentSubtitle = _subtitleData!.entries.first;
              _loopingSubtitle = _subtitleData!.entries.first;
              debugPrint('设置第一条字幕作为循环字幕: #${_subtitleData!.entries.first.index + 1}');
              
              // 跳转到第一条字幕
              _player!.seek(_subtitleData!.entries.first.start);
              
              if (!_player!.state.playing) {
                _player!.play();
              }
            }
          }
        }
      } else {
        _loopingSubtitle = null;
      }
    } catch (e) {
      debugPrint('切换循环模式错误: $e');
      _loopingSubtitle = null;
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
          Future.delayed(const Duration(milliseconds: 50), () {
            final actualPosition = _player!.state.position;
            final entry = _subtitleData!.getEntryAtTime(actualPosition);
            if (entry != null && entry != _currentSubtitle) {
              _currentSubtitle = entry;
              debugPrint('跳转后更新字幕: #${entry.index + 1}');
              notifyListeners();
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