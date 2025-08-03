import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';
import '../models/subtitle_model.dart';
import 'config_service.dart';
import 'youtube_service.dart';
import 'download_info_service.dart';
import 'subtitle_analysis_service.dart';

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
  String _videoTitle = '视频复读机'; // 视频标题
  ConfigService? _configService; // 配置服务
  Timer? _debounceTimer;
  
  // YouTube相关属性
  final YouTubeService _youtubeService = YouTubeService();
  bool _isYouTubeVideo = false;
  String? _youtubeVideoId;
  GlobalKey<dynamic>? _youtubePlayerKey;
  dynamic _youtubeController; // 用于存储YouTube播放器控制器
  bool _isUsingWebView = false; // 是否使用WebView播放
  
  // 下载信息服务
  DownloadInfoService? _downloadInfoService;
  
  // 字幕分析服务
  SubtitleAnalysisService? _subtitleAnalysisService;
  
  // 播放位置监听
  StreamSubscription<Duration>? _positionSubscription;
  
  // 下载相关属性
  String? _downloadStatus; // 下载状态文本
  double _downloadProgress = 0.0; // 下载进度（0-1）
  List<String> _downloadMessages = []; // 累加的下载信息列表
  bool _showDownloadPanel = false; // 是否显示下载信息面板
  
  // 字幕时间偏移量（毫秒）
  int _subtitleTimeOffset = 0;
  
  int _lastKnownSubtitleCount = 0;
  
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
  List<String> get downloadMessages => _downloadMessages; // 获取下载信息列表
  bool get showDownloadPanel => _showDownloadPanel; // 是否显示下载信息面板
  dynamic get youtubeController => _youtubeController; // YouTube播放器控制器
  bool get isUsingWebView => _isUsingWebView; // 是否使用WebView播放
  String get videoTitle => _videoTitle; // 获取视频标题
  
  // 获取播放状态
  bool get isPlaying => _player?.state.playing ?? false;
  
  // 获取当前循环字幕
  SubtitleEntry? get loopingSubtitle => _loopingSubtitle;
  
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
    
    // 设置YouTubeService的配置
    _youtubeService.setConfigService(configService);
    
    // 应用初始配置
    _applyConfig();
  }
  
  // 设置下载信息服务
  void setDownloadInfoService(DownloadInfoService downloadInfoService) {
    _downloadInfoService = downloadInfoService;
  }
  
  // 设置字幕分析服务
  void setSubtitleAnalysisService(SubtitleAnalysisService subtitleAnalysisService) {
    _subtitleAnalysisService = subtitleAnalysisService;
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
          if (_player != null) {
          _player!.pause();
          }
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
      debugPrint('位置变化处理错误: $e');
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
      
      // 额外确保字幕数据被彻底清除
      _subtitleData = null;
      _currentSubtitle = null;
      _loopingSubtitle = null;
      _currentSubtitlePath = null;
      
      // 判断是否为YouTube链接
      if (isYouTubeLink(videoPath)) {
        // 提取YouTube视频ID
        final videoId = _youtubeService.extractVideoId(videoPath);
        if (videoId == null) {
          _errorMessage = '无效的YouTube链接或ID';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        
        // 检查用户指定的下载目录中是否已有该视频
        final downloadDir = _configService?.youtubeDownloadPath;
        if (downloadDir != null && downloadDir.isNotEmpty) {
          // 直接在用户目录中查找以videoId开头的MP4文件
          final dir = Directory(downloadDir);
          if (await dir.exists()) {
            debugPrint('===== 检查用户下载目录中是否存在该YouTube视频 =====');
            final files = await dir.list().toList();
            for (final file in files) {
              if (file is File && 
                  path.basename(file.path).startsWith(videoId) && 
                  path.basename(file.path).toLowerCase().endsWith('.mp4')) {
                // 找到视频文件，交由本地视频逻辑处理
                final videoFilePath = file.path;
                debugPrint('发现本地已下载的YouTube视频: $videoFilePath，交由本地视频逻辑处理');
                _isYouTubeVideo = false; // 标记为本地视频处理流程
                return await _loadLocalVideo(videoFilePath);
              }
            }
          }
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
      
      // 从文件名更新视频标题
      final fileName = path.basename(videoPath);
      _videoTitle = fileName;
      debugPrint('更新视频标题: $_videoTitle');
      
      // 加载视频
      await _player!.open(Media(videoPath));
      debugPrint('成功加载视频: $videoPath');
      
      // 应用配置
      if (_configService != null) {
        _player!.setRate(_configService!.defaultPlaybackRate);
      }
      
      // 确保字幕数据被清除，防止使用上一个视频的字幕
      _subtitleData = null;
      _currentSubtitle = null;
      _currentSubtitlePath = null;
      
      // 尝试自动加载字幕
      if (_configService != null && _configService!.autoMatchSubtitle) {
        await _tryAutoMatchSubtitle(videoPath);
      }
      
      _isLoading = false;
      
      // 如果是从YouTube下载的视频，结束下载信息面板
      if (_youtubeVideoId != null && _downloadInfoService != null) {
        _downloadInfoService!.addMessage('视频加载成功，准备播放');
        _downloadInfoService!.endDownload();
      }
      
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
      final videoBasename = path.basename(videoPath);
      
      // 获取不带扩展名的文件名
      String videoName = videoBasename;
      final lastDotIndex = videoBasename.lastIndexOf('.');
      if (lastDotIndex > 0) {
        videoName = videoBasename.substring(0, lastDotIndex);
      }
      
      // 特殊处理: 检查是否为YouTube下载的视频
      bool isYoutubeDownload = false;
      if (videoName.contains('_')) {
        final parts = videoName.split('_');
        if (parts.length >= 2 && parts[0].length == 11) {
          // YouTube视频ID通常是11个字符
          isYoutubeDownload = true;
          debugPrint('检测到YouTube下载的视频，视频ID: ${parts[0]}');
          
          // 尝试提取原始视频名称
          final originalName = parts.sublist(1).join('_');
          debugPrint('原始视频名称可能为: $originalName');
          
          // 也尝试使用视频ID作为文件名
          debugPrint('也将尝试使用视频ID作为文件名: ${parts[0]}');
        }
      }
      
      debugPrint('===== 开始自动匹配字幕 =====');
      debugPrint('视频路径: $videoPath');
      debugPrint('视频目录: $videoDir');
      debugPrint('视频基本名称: $videoBasename');
      debugPrint('视频名称(无扩展名): $videoName');
      debugPrint('匹配模式: ${_configService!.subtitleMatchMode}');
      debugPrint('后缀列表: ${_configService!.subtitleSuffixes.join(", ")}');
      
      // 尝试匹配字幕文件
      String? subtitlePath;
      
      // 支持的字幕格式
      final subtitleExtensions = ['.srt', '.vtt', '.ass', '.ssa'];
      
      // 1. 首先尝试后缀匹配
      if (_configService!.subtitleMatchMode == 'suffix' || _configService!.subtitleMatchMode == 'both') {
        for (final suffix in _configService!.subtitleSuffixes) {
          // 尝试不同的字幕扩展名
          for (final ext in subtitleExtensions) {
            final suffixPath = path.join(videoDir, '$videoName$suffix$ext');
            if (File(suffixPath).existsSync()) {
              subtitlePath = suffixPath;
              debugPrint('找到后缀字幕文件: $subtitlePath (扩展名: $ext)');
              break;
            }
          }
          if (subtitlePath != null) break; // 如果找到了字幕文件，跳出循环
        }
      }
      
      // 2. 如果没找到后缀字幕，尝试与视频同名的字幕文件
      if (subtitlePath == null && 
          (_configService!.subtitleMatchMode == 'same' || _configService!.subtitleMatchMode == 'both')) {
        debugPrint('开始查找同名字幕文件...');
        
        // 准备要尝试的文件名列表
        List<String> filenamesToTry = [videoName];
        
        // 如果是YouTube下载的视频，添加额外的尝试
        if (isYoutubeDownload && videoName.contains('_')) {
          final parts = videoName.split('_');
          if (parts.length >= 2) {
            // 尝试使用视频ID
            filenamesToTry.add(parts[0]);
            
            // 尝试使用原始视频名称
            final originalName = parts.sublist(1).join('_');
            filenamesToTry.add(originalName);
            
            // 尝试使用不带下划线的名称
            filenamesToTry.add(videoName.replaceAll('_', ' '));
          }
        }
        
        // 尝试每个可能的文件名
        for (final filename in filenamesToTry) {
          debugPrint('尝试文件名: $filename');
          
          // 尝试不同的字幕扩展名
          for (final ext in subtitleExtensions) {
            final sameNamePath = path.join(videoDir, '$filename$ext');
            debugPrint('检查文件: $sameNamePath, 是否存在: ${File(sameNamePath).existsSync()}');
            if (File(sameNamePath).existsSync()) {
              subtitlePath = sameNamePath;
              debugPrint('找到同名字幕文件: $subtitlePath (扩展名: $ext)');
              break;
            }
          }
          
          if (subtitlePath != null) break;
        }
      }
      
      // 如果仍然没有找到字幕，尝试直接列出目录中的所有SRT文件
      if (subtitlePath == null) {
        debugPrint('未找到匹配的字幕文件，尝试列出目录中的所有字幕文件...');
        try {
          final dir = Directory(videoDir);
          if (dir.existsSync()) {
            final files = dir.listSync().where((f) => 
              f is File && 
              subtitleExtensions.any((ext) => f.path.toLowerCase().endsWith(ext))
            ).toList();
            
            debugPrint('目录中的字幕文件数量: ${files.length}');
            for (var file in files) {
              debugPrint('  - ${file.path}');
            }
            
            // 如果只有一个字幕文件，直接使用它
            if (files.length == 1) {
              subtitlePath = files.first.path;
              debugPrint('目录中只有一个字幕文件，直接使用: $subtitlePath');
            }
            // 如果有多个字幕文件，尝试查找与视频名称最相似的
            else if (files.length > 1) {
              debugPrint('尝试查找与视频名称最相似的字幕文件...');
              
              // 简单的相似度匹配：检查文件名中是否包含视频名称的一部分
              for (var file in files) {
                final fileName = path.basenameWithoutExtension(file.path).toLowerCase();
                final videoNameLower = videoName.toLowerCase();
                
                // 检查字幕文件名是否包含视频名称的前几个字符
                if (videoNameLower.length > 3 && fileName.contains(videoNameLower.substring(0, 4))) {
                  subtitlePath = file.path;
                  debugPrint('找到可能匹配的字幕文件: $subtitlePath');
                  break;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('列出目录文件时出错: $e');
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
      debugPrint('开始加载字幕文件: $path');
      
      // 检查当前是否有加载视频
      if (_currentVideoPath == null) {
        debugPrint('错误：尝试加载字幕但当前没有加载视频');
        _errorMessage = '请先加载视频再加载字幕';
        notifyListeners();
        return false;
      }
      
      final subtitleFile = File(path);
      if (!subtitleFile.existsSync()) {
        _errorMessage = '字幕文件不存在';
        notifyListeners();
        return false;
      }
      
      final content = await subtitleFile.readAsString();
      debugPrint('字幕文件内容长度: ${content.length} 字节');
      
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
      
      // 根据文件扩展名选择解析方法
      final fileExt = path.toLowerCase().endsWith('.srt') ? 'srt' :
                      path.toLowerCase().endsWith('.vtt') ? 'vtt' :
                      path.toLowerCase().endsWith('.ass') || path.toLowerCase().endsWith('.ssa') ? 'ass' :
                      'unknown';
                      
      debugPrint('字幕文件格式: $fileExt');
      
      // 目前只支持SRT格式，其他格式需要转换或特殊处理
      if (fileExt != 'srt') {
        debugPrint('警告: 目前只完全支持SRT格式，其他格式可能解析不正确');
      }
      
      // 先清空之前的字幕数据
      _subtitleData = null;
      _currentSubtitle = null;
      _loopingSubtitle = null;
      
      // 解析字幕内容
      final entries = <SubtitleEntry>[];
      final lines = content.split('\n');
      
      debugPrint('字幕文件总行数: ${lines.length}');
      
      int index = 0;
      int entryIndex = 0;
      Duration? startTime;
      Duration? endTime;
      String text = '';
      int processedEntries = 0;
      
      // 使用更健壮的解析逻辑
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
            processedEntries++;
            
            // 每处理50个条目打印一次进度
            if (processedEntries % 50 == 0) {
              debugPrint('已处理 $processedEntries 条字幕');
            }
            
            text = '';
            startTime = null;
            endTime = null;
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
          // 不是序号行，可能是格式错误，跳过
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
        processedEntries++;
      }
      
      debugPrint('字幕解析完成，共处理 $processedEntries 条字幕');
      
      // 检查是否有字幕被解析出来
      if (entries.isEmpty) {
        _errorMessage = '未能解析出任何字幕';
        debugPrint(_errorMessage);
        notifyListeners();
        return false;
      }
      
      // 检查是否恰好有48条字幕（可能是截断问题）
      if (entries.length == 48) {
        debugPrint('警告: 解析出恰好48条字幕，可能存在截断问题。请检查字幕文件完整性。');
      }
      
      // 创建新的字幕数据对象
      _subtitleData = SubtitleData(entries: entries);
      _lastKnownSubtitleCount = entries.length; // 记录字幕数量
      debugPrint('成功加载字幕，共 ${entries.length} 条');
      
      // 打印字幕数据的详细信息
      _debugPrintSubtitleInfo();
      
      // 触发静默字幕分析
      _triggerSilentAnalysis();
      
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '加载字幕失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
      return false;
    }
  }
  
  // 调试方法：打印字幕数据信息
  void _debugPrintSubtitleInfo() {
    if (_subtitleData == null) {
      debugPrint('字幕数据为空');
      return;
    }
    
    final entries = _subtitleData!.entries;
    debugPrint('========== 字幕数据信息 ==========');
    debugPrint('总字幕条数: ${entries.length}');
    
    if (entries.isNotEmpty) {
      debugPrint('第一条字幕: #${entries.first.index + 1}, 时间: ${entries.first.start.inSeconds}s - ${entries.first.end.inSeconds}s');
      debugPrint('最后一条字幕: #${entries.last.index + 1}, 时间: ${entries.last.start.inSeconds}s - ${entries.last.end.inSeconds}s');
      
      // 检查是否有48条字幕的限制
      if (entries.length == 48) {
        debugPrint('警告: 字幕条数恰好为48，可能存在限制问题');
      }
    }
    
    // 检查字幕索引是否连续
    bool hasGap = false;
    for (int i = 0; i < entries.length - 1; i++) {
      if (entries[i].index + 1 != entries[i + 1].index) {
        hasGap = true;
        debugPrint('警告: 字幕索引不连续，在 #${entries[i].index + 1} 和 #${entries[i + 1].index + 1} 之间有间隙');
      }
    }
    
    if (!hasGap) {
      debugPrint('字幕索引连续，无间隙');
    }
    
    debugPrint('================================');
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
  
  // 使用PodPlayer加载YouTube视频
  Future<bool> _loadYouTubeVideo(String videoId) async {
    try {
      _isLoading = true;
      _clearPreviousResources();
      _youtubeVideoId = videoId;
      _isYouTubeVideo = true;
      _isUsingWebView = false;
      
      // 初始化下载信息面板
      if (_downloadInfoService != null) {
        _downloadInfoService!.startDownload();
        _downloadInfoService!.addMessage('正在解析YouTube视频ID: $videoId');
      }
      
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
          
          // 更新下载信息面板
          if (_downloadInfoService != null) {
            _downloadInfoService!.addMessage('重试下载 (${retryCount}/${maxRetries})...');
          }
          
          notifyListeners();
          await Future.delayed(const Duration(seconds: 1));
        }
        
        _downloadStatus = '正在准备下载视频...';
        notifyListeners();
        
        // 下载视频和字幕
        downloadResult = await _youtubeService.downloadVideoAndSubtitles(
          videoId, 
          onProgress: (progress) {
            _downloadProgress = progress;
            
            // 更新下载信息面板的进度
            if (_downloadInfoService != null) {
              _downloadInfoService!.setProgress(progress);
            }
            
            notifyListeners();
          },
          onStatusUpdate: (status) {
            _downloadStatus = status;
            
            // 更新下载信息面板的消息
            if (_downloadInfoService != null && status.isNotEmpty) {
              _downloadInfoService!.addMessage(status);
            }
            
            notifyListeners();
          },
          downloadInfoService: _downloadInfoService,
        );
        
        retryCount++;
      }
      
      if (downloadResult == null) {
        _errorMessage = '无法下载视频，请重试';
        _isLoading = false;
        
        // 更新下载信息面板
        if (_downloadInfoService != null) {
          _downloadInfoService!.downloadError('无法下载视频，请重试');
        }
        
        notifyListeners();
        return false;
      }
      
      // 解包下载结果
      final (videoPath, subtitlePath) = downloadResult;
      
      _downloadStatus = '下载完成，正在加载视频...';
      
      // 更新下载信息面板
      if (_downloadInfoService != null) {
        _downloadInfoService!.addMessage('下载完成，正在加载视频...');
        _downloadInfoService!.addMessage('视频路径: $videoPath');
        if (subtitlePath != null) {
          _downloadInfoService!.addMessage('字幕路径: $subtitlePath');
        }
      }
      
      notifyListeners();
      
      // 切换到本地视频加载逻辑
      _isYouTubeVideo = false; // 重要：标记为本地视频
      
      // 保存当前视频信息，以便后续需要时能够识别它是YouTube视频
      _currentVideoPath = videoPath;
      _youtubeVideoId = videoId;
      
      // 使用本地视频逻辑加载
      return await _loadLocalVideo(videoPath);
    } catch (e) {
      debugPrint('加载YouTube视频错误: $e');
      _errorMessage = '加载失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // 使用WebView播放YouTube视频
  Future<bool> playYouTubeWithWebView(String url) async {
    try {
      _isLoading = true;
      _clearPreviousResources();
      
      // 提取YouTube视频ID
      final videoId = _youtubeService.extractVideoId(url);
      if (videoId == null) {
        _errorMessage = '无效的YouTube链接或ID';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      _youtubeVideoId = videoId;
      _isYouTubeVideo = true;
      _isUsingWebView = true;
      
      // WebView不支持字幕，仅设置视频ID
      _currentVideoPath = 'watch?v=$videoId';
      
      // 完成加载
      _isLoading = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('加载YouTube WebView错误: $e');
      _errorMessage = '加载失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // 尝试下载字幕的辅助方法
  Future<void> _tryDownloadSubtitles(String videoId) async {
    try {
      _downloadStatus = '正在尝试获取字幕...';
      
      // 更新下载信息面板
      if (_downloadInfoService != null) {
        _downloadInfoService!.addMessage('正在尝试获取字幕...');
      }
      
      notifyListeners();
      
      // 获取字幕内容
      String? subtitlePath;
      
      // 检查是否有用户选择的字幕轨道
      if (_downloadInfoService != null && _downloadInfoService!.selectedSubtitleTrack != null) {
        // 使用用户选择的字幕轨道
        final selectedTrack = _downloadInfoService!.selectedSubtitleTrack!;
        debugPrint('使用用户选择的字幕轨道: ${selectedTrack['name']}');
        subtitlePath = await _youtubeService.downloadSpecificSubtitle(
          videoId, 
          selectedTrack,
          onStatusUpdate: (status) {
            _downloadStatus = status;
            notifyListeners();
          }
        );
      } else {
        // 使用默认字幕（通常是自动检测或首选语言）
        subtitlePath = await _youtubeService.downloadSubtitles(
          videoId, 
          onStatusUpdate: (status) {
            _downloadStatus = status;
            notifyListeners();
          }
        );
      }
      
      // 如果下载成功，从文件中加载字幕内容
      if (subtitlePath != null && await File(subtitlePath).exists()) {
        final subtitleContent = await File(subtitlePath).readAsString();
        final subtitleData = parseSrtSubtitle(subtitleContent);
        
        if (subtitleData != null) {
          debugPrint('成功下载YouTube字幕: ${subtitleData.entries.length}条');
          _downloadStatus = '成功获取${subtitleData.entries.length}条字幕';
          
          // 保存字幕数据
          _subtitleData = subtitleData;
          _youtubeVideoId = videoId;
          _currentSubtitlePath = subtitlePath;
          
          // 如果下载的字幕路径已经是正确的用户目录中的文件，不需要再保存
          // 只有当字幕在临时目录或文件名不匹配时才需要保存到用户目录
          if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
            final isInUserDir = subtitlePath.startsWith(_configService!.youtubeDownloadPath);
            final hasCorrectNameFormat = path.basename(subtitlePath).startsWith('${videoId}_') && 
                                        !path.basename(subtitlePath).contains('subtitle');
            
            if (!isInUserDir || !hasCorrectNameFormat) {
              debugPrint('字幕需要保存到用户目录或重命名: $subtitlePath');
              await saveCurrentSubtitlesToFile();
            } else {
              debugPrint('字幕已在正确位置，无需重新保存: $subtitlePath');
            }
          }
        } else {
          debugPrint('解析字幕文件失败');
          _downloadStatus = '字幕格式不正确';
        }
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
  
  // 清理之前的资源
  void _clearPreviousResources() {
    debugPrint('清理之前的资源');
    
    // 清理字幕相关数据
    if (_subtitleData != null) {
      debugPrint('清理字幕数据，原有条数: ${_subtitleData!.entries.length}');
      _subtitleData = null;
    }
    _currentSubtitle = null;
    _loopingSubtitle = null;
    _isLooping = false;
    _loopCount = 0;
    _currentPosition = Duration.zero;
    _duration = Duration.zero;
    _isYouTubeVideo = false;
    _youtubeVideoId = null;
    _lastKnownSubtitleCount = 0;
    _subtitleTimeOffset = 0;
    
    // 取消定时器
    _loopTimer?.cancel();
    _loopTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    
    // 重置路径和标题信息（确保完全清理）
    final oldVideoPath = _currentVideoPath;
    final oldSubtitlePath = _currentSubtitlePath;
    final oldVideoTitle = _videoTitle;
    
    _currentVideoPath = null;
    _currentSubtitlePath = null;
    _videoTitle = '视频复读机'; // 重置为默认标题
    
    debugPrint('资源清理完成 - 旧路径: $oldVideoPath -> null');
    debugPrint('字幕路径: $oldSubtitlePath -> null');
    debugPrint('视频标题: $oldVideoTitle -> $_videoTitle');
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
      debugPrint('nextSubtitle - 没有字幕数据或播放器');
      return;
    }
    
    try {
      // 获取当前位置对应的字幕索引
      int currentIndex = -1;
      
      // 如果有当前字幕，直接使用其索引
      if (_currentSubtitle != null) {
        currentIndex = _currentSubtitle!.index;
      } else {
        // 如果没有当前字幕，找到最近的已播放字幕
        final currentPosition = _player!.state.position;
        final adjustedPosition = Duration(
          milliseconds: max(0, currentPosition.inMilliseconds - _subtitleTimeOffset)
        );
        
        for (int i = 0; i < _subtitleData!.entries.length; i++) {
          final entry = _subtitleData!.entries[i];
          if (entry.end <= adjustedPosition) {
            currentIndex = entry.index;
          } else {
            break;
          }
        }
      }
      
      // 计算下一个字幕的索引
      int nextIndex = currentIndex + 1;
      
      // 确保索引在有效范围内
      if (nextIndex >= 0 && nextIndex < _subtitleData!.entries.length) {
        // 获取下一个字幕
        final nextEntry = _subtitleData!.entries[nextIndex];
        
        // 跳转时需要考虑时间偏移
        final seekPosition = Duration(milliseconds: nextEntry.start.inMilliseconds + _subtitleTimeOffset);
        debugPrint('跳转到下一个字幕: #${nextEntry.index + 1}, 位置: ${seekPosition.inMilliseconds}ms');
        
        // 直接更新当前字幕
        _currentSubtitle = nextEntry;
        notifyListeners();
        
        // 执行跳转
        _player!.seek(seekPosition);
      } else {
        debugPrint('已经是最后一个字幕或没有找到下一个字幕');
      }
    } catch (e) {
      debugPrint('跳转到下一个字幕错误: $e');
    }
  }
  
  // 跳转到上一个字幕
  void previousSubtitle() {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty || _player == null) {
      debugPrint('previousSubtitle - 没有字幕数据或播放器');
      return;
    }
    
    try {
      // 获取当前位置对应的字幕索引
      int currentIndex = -1;
      
      // 如果有当前字幕，直接使用其索引
      if (_currentSubtitle != null) {
        currentIndex = _currentSubtitle!.index;
        
        // 如果当前位置靠近字幕开始位置（前1秒内），则跳到上一个字幕
        final currentPosition = _player!.state.position;
        final adjustedPosition = Duration(
          milliseconds: max(0, currentPosition.inMilliseconds - _subtitleTimeOffset)
        );
        
        bool nearStart = (adjustedPosition.inMilliseconds - _currentSubtitle!.start.inMilliseconds) < 1000;
        if (!nearStart) {
          // 如果不靠近开始位置，跳到当前字幕开始
          final seekPosition = Duration(milliseconds: _currentSubtitle!.start.inMilliseconds + _subtitleTimeOffset);
          _player!.seek(seekPosition);
          debugPrint('跳转到当前字幕开始位置: #${_currentSubtitle!.index + 1}');
          return;
        }
      } else {
        // 如果没有当前字幕，找到最近的已播放字幕
        final currentPosition = _player!.state.position;
        final adjustedPosition = Duration(
          milliseconds: max(0, currentPosition.inMilliseconds - _subtitleTimeOffset)
        );
        
        for (int i = 0; i < _subtitleData!.entries.length; i++) {
          final entry = _subtitleData!.entries[i];
          if (entry.end <= adjustedPosition) {
            currentIndex = entry.index;
          } else {
            break;
          }
        }
      }
      
      // 计算上一个字幕的索引
      int prevIndex = currentIndex - 1;
      
      // 确保索引在有效范围内
      if (prevIndex >= 0 && prevIndex < _subtitleData!.entries.length) {
        // 获取上一个字幕
        final prevEntry = _subtitleData!.entries[prevIndex];
        
        // 跳转时需要考虑时间偏移
        final seekPosition = Duration(milliseconds: prevEntry.start.inMilliseconds + _subtitleTimeOffset);
        debugPrint('跳转到上一个字幕: #${prevEntry.index + 1}, 位置: ${seekPosition.inMilliseconds}ms');
        
        // 直接更新当前字幕
        _currentSubtitle = prevEntry;
        notifyListeners();
        
        // 执行跳转
        _player!.seek(seekPosition);
      } else {
        debugPrint('已经是第一个字幕或没有找到上一个字幕');
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
  
  // 切换循环播放状态（别名方法，与toggleLooping功能相同）
  void toggleLoop() {
    toggleLooping();
  }
  
  // 切换循环播放状态
  void toggleLooping() {
    _isLooping = !_isLooping;
    
    if (_isLooping) {
      // 如果当前有字幕，设置为循环字幕
      if (_currentSubtitle != null) {
        _loopingSubtitle = _currentSubtitle;
        debugPrint('开始循环播放字幕: "${_loopingSubtitle!.text}" (${_loopingSubtitle!.start.inSeconds}s - ${_loopingSubtitle!.end.inSeconds}s)');
        
        // 如果不在当前字幕范围内，跳转到字幕开始位置
        final adjustedPosition = Duration(milliseconds: max(0, _currentPosition.inMilliseconds - _subtitleTimeOffset));
        if (_loopingSubtitle!.start > adjustedPosition || _loopingSubtitle!.end < adjustedPosition) {
          // 调整回字幕开始时间
          seek(_loopingSubtitle!.start + Duration(milliseconds: _subtitleTimeOffset));
        }
        
        // 开始循环计数
        _loopCount = 1;
      }
    } else {
      // 停止循环
      debugPrint('停止循环播放');
      _loopingSubtitle = null;
      _loopCount = 0;
      _isWaitingForLoop = false;
    }
    
    // 取消已有循环定时器
    _loopTimer?.cancel();
    _loopTimer = null;
    
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
  
  // 跳转到指定位置
  void seek(Duration position) {
    if (_player != null) {
      try {
        _player!.seek(position);
        
        // 立即更新当前位置，避免UI延迟
        _currentPosition = position;
        
        // 立即更新当前字幕
        _updateCurrentSubtitle(position);
        
        notifyListeners();
      } catch (e) {
        debugPrint('seek错误: $e');
      }
    } else if (_isYouTubeVideo && _youtubeController != null) {
      try {
        // 尝试调用YouTube播放器的seekTo方法
        _youtubeController.seekTo(position);
        
        // 更新当前位置
        _currentPosition = position;
        
        // 更新当前字幕
        _updateCurrentSubtitle(position);
        
        notifyListeners();
      } catch (e) {
        debugPrint('YouTube seek错误: $e');
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
  
  // 获取指定时间点的字幕（考虑时间偏移）
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
    
    // 检查字幕数据完整性
    if (_subtitleData!.entries.length < _lastKnownSubtitleCount) {
      debugPrint('警告: 字幕数据可能被截断! 当前条数: ${_subtitleData!.entries.length}, 之前条数: $_lastKnownSubtitleCount');
    }
    
    // 查找当前字幕
    for (final sub in _subtitleData!.entries) {
      if (positionMs >= sub.start.inMilliseconds && positionMs <= sub.end.inMilliseconds) {
        return sub;
      }
    }
    
    return null;
  }
  
  // 更新当前字幕
  void _updateCurrentSubtitle(Duration position) {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      return;
    }
    
    try {
      // 考虑字幕时间偏移
      final adjustedPosition = Duration(
        milliseconds: max(0, position.inMilliseconds - _subtitleTimeOffset)
      );
    
      // 找到当前时间对应的字幕
      SubtitleEntry? newSubtitle;
      
      for (final entry in _subtitleData!.entries) {
        if (entry.start <= adjustedPosition && entry.end > adjustedPosition) {
          newSubtitle = entry;
          break;
        }
      }
      
      // 如果找到了新的字幕，且与当前字幕不同，更新当前字幕
      if (newSubtitle != null && (_currentSubtitle == null || newSubtitle.index != _currentSubtitle!.index)) {
        _currentSubtitle = newSubtitle;
        debugPrint('更新当前字幕: #${newSubtitle.index + 1} - ${newSubtitle.text}');
      } else if (newSubtitle == null && _currentSubtitle != null) {
        // 如果当前没有字幕，清除当前字幕
        _currentSubtitle = null;
      }
    } catch (e) {
      debugPrint('更新当前字幕错误: $e');
    }
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
    _loopTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    
    // 取消播放位置监听
    _positionSubscription?.cancel();
    _positionSubscription = null;
    
    // 移除配置服务监听器
    if (_configService != null) {
      _configService!.removeListener(_onConfigChanged);
    }
    
    // 清理字幕数据
    if (_subtitleData != null) {
      debugPrint('清理字幕数据，原有条数: ${_subtitleData!.entries.length}');
      _subtitleData = null;
    }
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
    
    // 重置其他状态
    _isLoading = false;
    _errorMessage = null;
    _isLooping = false;
    _loopCount = 0;
    _lastPosition = null;
    _currentPosition = Duration.zero;
    _duration = Duration.zero;
    _isYouTubeVideo = false;
    _youtubeVideoId = null;
    _subtitleTimeOffset = 0;
    _lastKnownSubtitleCount = 0;
    
    // 通知监听器状态已重置
    notifyListeners();
    
    // 重新初始化播放器，准备下一次使用
    _initPlayer();
  }
  
  // 重新初始化视频服务
  Future<void> reinitialize() async {
    debugPrint('重新初始化VideoService');
    
    // 先清理现有资源
    _clearPreviousResources();
    
    // 如果播放器已销毁，重新创建
    if (_player == null) {
      _initPlayer();
      await Future.delayed(const Duration(milliseconds: 300)); // 等待初始化完成
    }
    
    notifyListeners();
  }
  
  // 从SRT格式的文本解析字幕
  SubtitleData? parseSrtSubtitle(String content) {
    try {
      // 首先对整个内容进行预处理，清理YouTube特有的标签
      content = _cleanYouTubeSubtitleContent(content);
      
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
  
  // 清理YouTube字幕内容中的特殊标签
  String _cleanYouTubeSubtitleContent(String content) {
    // 移除时间戳标签，如<00:00:31.359>
    content = content.replaceAll(RegExp(r'<\d+:\d+:\d+\.\d+>'), '');
    // 移除<c>和</c>标签
    content = content.replaceAll(RegExp(r'</?c>'), '');
    // 保留其他可能的HTML标签，因为它们可能是格式的一部分
    return content;
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
  
  // 将当前字幕保存到文件
  Future<bool> saveCurrentSubtitlesToFile() async {
    if (_subtitleData == null || _subtitleData!.entries.isEmpty) {
      debugPrint('没有可用的字幕数据可保存');
      return false;
    }
    
    if (_youtubeVideoId == null || _youtubeVideoId!.isEmpty) {
      debugPrint('没有YouTube视频ID，无法保存字幕');
      return false;
    }
    
    try {
      // 检查是否有自定义下载路径
      String? savePath;
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        final directory = Directory(_configService!.youtubeDownloadPath);
        
        // 首先尝试查找对应的视频文件并使用相同的命名方式
        if (await directory.exists()) {
          List<FileSystemEntity> files = await directory.list().toList();
          String? videoFileName;
          
          // 查找视频文件
          for (var file in files) {
            if (file is File) {
              String fileName = path.basename(file.path);
              if (fileName.startsWith('${_youtubeVideoId!}_') && 
                  (fileName.endsWith('.mp4') || fileName.endsWith('.webm') || fileName.endsWith('.mkv'))) {
                videoFileName = fileName;
                break;
              }
            }
          }
          
          // 如果找到了视频文件，使用相同的命名方式
          if (videoFileName != null) {
            final baseFileName = videoFileName.substring(0, videoFileName.lastIndexOf('.'));
            savePath = path.join(_configService!.youtubeDownloadPath, '$baseFileName.srt');
            debugPrint('使用与视频完全相同的命名: $savePath');
          }
        }
        
        // 如果没有找到视频文件，使用当前视频路径的信息
        if (savePath == null && _currentVideoPath != null && _currentVideoPath!.isNotEmpty && 
            !_currentVideoPath!.startsWith('watch?v=')) {
          // 使用视频文件同名但扩展名为.srt的文件路径，保持一致性
          final videoFileName = path.basename(_currentVideoPath!);
          final baseFileName = videoFileName.substring(0, videoFileName.lastIndexOf('.'));
          savePath = path.join(_configService!.youtubeDownloadPath, '$baseFileName.srt');
          debugPrint('使用当前视频路径生成字幕文件名: $savePath');
        }
        
        // 如果以上方法都无法确定文件名，使用视频ID
        if (savePath == null) {
          debugPrint('警告：无法找到对应的视频文件，将使用视频ID作为字幕文件名');
          savePath = path.join(_configService!.youtubeDownloadPath, '${_youtubeVideoId!}_subtitle.srt');
        }
        
        // 确保目录存在
        final directory2 = path.dirname(savePath);
        if (!await Directory(directory2).exists()) {
          await Directory(directory2).create(recursive: true);
        }
      } else {
        // 使用临时目录
        final tempDir = await getTemporaryDirectory();
        savePath = path.join(tempDir.path, '${_youtubeVideoId!}_subtitle.srt');
      }
      
      // 保存字幕
      final result = await _youtubeService.saveSubtitleToFile(_subtitleData!, savePath);
      
      if (result) {
        _currentSubtitlePath = savePath;
        debugPrint('字幕已保存到: $savePath');
        return true;
      } else {
        debugPrint('保存字幕失败');
        return false;
      }
    } catch (e) {
      debugPrint('保存字幕错误: $e');
      return false;
    }
  }
  
  // 清除视频缓存（仅用于测试）
  void clearVideoCache() {
    _youtubeService.clearDownloadCache();
    debugPrint('已清除视频缓存');
  }
  
  // 设置播放器位置监听
  void _setupPositionListener() {
    if (_player == null) return;
    
    // 取消之前的监听
    _positionSubscription?.cancel();
    
    // 设置新的监听
    _positionSubscription = _player!.stream.position.listen((position) {
      // 更新当前位置
      _currentPosition = position;
      
      // 根据当前位置更新字幕
      if (_subtitleData != null) {
        _updateCurrentSubtitle(position);
      }
      
      // 循环播放逻辑处理
      _handleLoopingLogic(position);
      
      // 通知监听器更新UI
      notifyListeners();
    });
    
    debugPrint('已设置播放器位置监听');
  }
  
  // 处理循环播放逻辑
  void _handleLoopingLogic(Duration position) {
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
      }
    }
  }
  
  // 播放视频
  void play() {
    if (_player != null) {
      _player!.play();
      debugPrint('播放视频');
      notifyListeners();
    }
  }
  
  // 暂停视频
  void pause() {
    if (_player != null) {
      _player!.pause();
      debugPrint('暂停视频');
      notifyListeners();
    }
  }
  
  // 重置视频服务状态，但不调用dispose
  void reset() {
    debugPrint('重置VideoService状态');
    
    // 取消所有定时器
    _loopTimer?.cancel();
    _loopTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    
    // 清理字幕相关数据
    if (_subtitleData != null) {
      debugPrint('清理字幕数据，原有条数: ${_subtitleData!.entries.length}');
      _subtitleData = null;
    }
    _currentSubtitle = null;
    _loopingSubtitle = null;
    _isLooping = false;
    _loopCount = 0;
    
    // 暂停当前播放
    if (_player != null && _player!.state.playing) {
      _player!.pause();
    }
    
    // 重置状态
    _currentPosition = Duration.zero;
    _duration = Duration.zero;
    _isYouTubeVideo = false;
    _youtubeVideoId = null;
    _lastKnownSubtitleCount = 0;
    _subtitleTimeOffset = 0;
    _currentVideoPath = null;
    _currentSubtitlePath = null;
    _isLoading = false;
    _errorMessage = null;
    
    notifyListeners();
  }
  
  // 获取当前时间的字幕
  SubtitleEntry? getCurrentSubtitle() {
    if (_subtitleData == null || _player == null) {
      return null;
    }
    
    return _currentSubtitle;
  }
  
  // 下载选中的字幕轨道
  Future<void> downloadSelectedSubtitle(String videoId, Map<String, dynamic> subtitleTrack) async {
    if (_downloadInfoService == null) {
      debugPrint('下载信息服务为空，无法下载字幕');
      return;
    }
    
    // 开始下载字幕
    _downloadInfoService!.startSubtitleDownload();
    
    // 下载字幕
    final subtitlePath = await _youtubeService.downloadSpecificSubtitle(
      videoId,
      subtitleTrack,
      onStatusUpdate: _downloadInfoService!.addMessage,
    );
    
    // 更新下载状态
    final success = subtitlePath != null;
    _downloadInfoService!.subtitleDownloadComplete(success);
    
    // 如果下载成功，加载字幕
    if (success) {
      // 加载字幕
      final loadSuccess = await loadSubtitle(subtitlePath!);
      if (loadSuccess) {
        _downloadInfoService!.addMessage('字幕已加载到视频');
      } else {
        _downloadInfoService!.addMessage('字幕加载失败');
      }
    }
  }
  
  // 从视频中提取字幕时间段的音频
  Future<String?> extractAudioFromSubtitle(SubtitleEntry subtitle) async {
    if (_currentVideoPath == null || subtitle == null) {
      debugPrint('无法提取音频：视频路径或字幕为空');
      return null;
    }

    try {
      // 创建音频文件存储目录
      final appDocDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory(path.join(appDocDir.path, 'vocabulary_audio'));
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      // 生成唯一的文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${path.basenameWithoutExtension(_currentVideoPath!)}_${subtitle.index}_$timestamp.mp3';
      final outputPath = path.join(audioDir.path, fileName);

      // 使用FFmpeg提取音频
      // 计算起始时间和持续时间（考虑字幕偏移）
      final startTime = subtitle.start.inMilliseconds + _subtitleTimeOffset;
      final duration = subtitle.duration.inMilliseconds;
      
      // 格式化时间为FFmpeg格式 (HH:MM:SS.mmm)
      final formattedStartTime = _formatDurationForFFmpeg(Duration(milliseconds: startTime));
      final formattedDuration = _formatDurationForFFmpeg(Duration(milliseconds: duration));
      
      debugPrint('提取音频：从 $formattedStartTime 开始，持续 $formattedDuration');
      
      // 构建FFmpeg命令
      final ffmpegArgs = [
        '-y',                      // 覆盖输出文件
        '-ss', formattedStartTime, // 起始时间
        '-i', _currentVideoPath!,  // 输入文件
        '-t', formattedDuration,   // 持续时间
        '-vn',                     // 不包含视频
        '-acodec', 'libmp3lame',   // 使用MP3编码器
        '-ar', '44100',            // 采样率
        '-ab', '192k',             // 比特率
        '-f', 'mp3',               // 输出格式
        outputPath                 // 输出文件
      ];
      
      debugPrint('FFmpeg命令: ffmpeg ${ffmpegArgs.join(' ')}');
      
      // 执行FFmpeg命令
      final process = await Process.start('ffmpeg', ffmpegArgs);
      
      // 监听输出
      process.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('FFmpeg: $data');
      });
      
      // 等待进程完成
      final exitCode = await process.exitCode;
      
      if (exitCode == 0) {
        debugPrint('音频提取成功: $outputPath');
        return outputPath;
      } else {
        debugPrint('音频提取失败，退出代码: $exitCode');
        return null;
      }
    } catch (e) {
      debugPrint('提取音频时出错: $e');
      return null;
    }
  }
  
  // 格式化时间为FFmpeg格式 (HH:MM:SS.mmm)
  String _formatDurationForFFmpeg(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds = (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }
  
  // 触发静默字幕分析
  void _triggerSilentAnalysis() {
    // 检查是否有必要的数据和服务
    if (_subtitleAnalysisService == null || 
        _currentVideoPath == null || 
        _subtitleData == null || 
        _subtitleData!.entries.isEmpty) {
      return;
    }
    
    // 异步触发分析，不阻塞UI
    Future.microtask(() async {
      await _subtitleAnalysisService!.analyzeSubtitlesSilently(
        videoPath: _currentVideoPath!,
        subtitlePath: _currentSubtitlePath,
        videoTitle: _videoTitle,
        subtitles: _subtitleData!.entries,
      );
    });
  }
} 