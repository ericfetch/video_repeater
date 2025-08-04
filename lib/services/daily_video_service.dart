import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../models/daily_video_model.dart';
import '../models/subtitle_model.dart';
import 'video_service.dart';
import 'subtitle_analysis_service.dart';

/// 今日视频列表服务
/// 负责管理今日学习视频列表，包括添加、删除、加载视频等功能
class DailyVideoService extends ChangeNotifier {
  final VideoService _videoService;
  final SubtitleAnalysisService _subtitleAnalysisService;
  
  DailyVideoList? _currentDayList;
  String? _currentVideoPath; // 当前正在播放的视频路径
  
  // 视频加载状态追踪
  final Set<String> _loadingVideos = {};
  
  // 学习时长计时器
  Timer? _studyTimer;
  DateTime? _currentVideoStartTime;

  // 防抖保存定时器
  Timer? _saveDebounceTimer;
  static const Duration _saveDebounceDelay = Duration(seconds: 5);

  DailyVideoService({
    required VideoService videoService,
    required SubtitleAnalysisService subtitleAnalysisService,
  }) : _videoService = videoService,
       _subtitleAnalysisService = subtitleAnalysisService {
    _initializeToday();
    _listenToVideoService();
  }

  /// 获取当前日期的视频列表
  DailyVideoList? get currentDayList => _currentDayList;
  
  /// 获取今日视频列表
  List<DailyVideoItem> get todayVideos => _currentDayList?.videos ?? [];
  
  /// 获取今日学习统计
  DailyVideoStats get todayStats => _currentDayList?.stats ?? DailyVideoStats(
    totalVideos: 0,
    completedVideos: 0,
    studyingVideos: 0,
    loadedVideos: 0,
    totalStudyDuration: 0,
    videosWithAnalysis: 0,
  );
  
  /// 获取当前正在播放的视频
  DailyVideoItem? get currentVideo {
    if (_currentVideoPath == null || _currentDayList == null) return null;
    
    try {
      return _currentDayList!.videos.firstWhere(
        (v) => v.videoPath == _currentVideoPath,
      );
    } catch (e) {
      return null;
    }
  }
  
  /// 检查是否正在加载视频
  bool isVideoLoading(String videoPath) => _loadingVideos.contains(videoPath);

  /// 初始化今日列表
  Future<void> _initializeToday() async {
    final today = _getTodayDateString();
    await _loadDayList(today);
  }

  /// 监听VideoService状态变化
  void _listenToVideoService() {
    _videoService.addListener(_onVideoServiceChanged);
  }

  /// VideoService状态变化处理
  void _onVideoServiceChanged() {
    final currentVideoPath = _videoService.currentVideoPath;
    
    // 如果当前视频改变了
    if (currentVideoPath != _currentVideoPath) {
      _onCurrentVideoChanged(currentVideoPath);
    }
    
    // 更新视频加载状态
    _updateVideoLoadStatus();
  }

  /// 当前视频改变处理
  void _onCurrentVideoChanged(String? newVideoPath) {
    // 停止之前视频的学习计时
    _stopStudyTimer();
    
    final oldVideoPath = _currentVideoPath;
    _currentVideoPath = newVideoPath;
    
    if (oldVideoPath != null && _currentDayList != null) {
      _updateVideoStudyStatus(oldVideoPath, VideoStudyStatus.notStarted);
    }
    
    if (newVideoPath != null && _currentDayList != null) {
      // 检查新视频是否在今日列表中
      final videoInList = _currentDayList!.videos.any((v) => v.videoPath == newVideoPath);
      
      if (videoInList) {
        _updateVideoStudyStatus(newVideoPath, VideoStudyStatus.studying);
        _startStudyTimer();
      }
    }
    
    notifyListeners();
  }

  /// 更新视频加载状态
  void _updateVideoLoadStatus() {
    if (_currentDayList == null || _currentVideoPath == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == _currentVideoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      VideoLoadStatus newStatus;
      
      if (_videoService.errorMessage != null) {
        newStatus = VideoLoadStatus.error;
      } else if (_videoService.currentVideoPath != null && 
                 _videoService.currentVideoPath == videoItem.videoPath) {
        newStatus = VideoLoadStatus.loaded;
      } else {
        newStatus = VideoLoadStatus.pending;
      }
      
      if (videoItem.loadStatus != newStatus) {
        final updatedVideo = videoItem.copyWith(
          loadStatus: newStatus,
          errorMessage: _videoService.errorMessage,
        );
        _updateVideoInList(videoItem.videoPath, updatedVideo);
      }
    }
  }

  /// 开始学习计时
  void _startStudyTimer() {
    _currentVideoStartTime = DateTime.now();
    // 只记录开始时间，不需要定时通知UI
    // 学习时长会在停止时保存，UI显示时计算即可
  }

  /// 停止学习计时
  void _stopStudyTimer() {
    _studyTimer?.cancel();
    _studyTimer = null;
    if (_currentVideoStartTime != null) {
      _updateStudyDuration(); // 最终保存到数据库
    }
    _currentVideoStartTime = null;
  }

  /// 获取当前学习时长（秒）- 包含正在进行的时长
  int get currentStudyDurationSeconds {
    int savedDuration = todayStats.totalStudyDuration;
    
    // 如果正在学习，加上当前会话的时长
    if (_currentVideoStartTime != null) {
      final currentSessionDuration = DateTime.now().difference(_currentVideoStartTime!).inSeconds;
      savedDuration += currentSessionDuration;
    }
    
    return savedDuration;
  }

  /// 更新学习时长（保存到数据库）
  void _updateStudyDuration() {
    if (_currentVideoPath == null || 
        _currentVideoStartTime == null || 
        _currentDayList == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == _currentVideoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      // 计算本次会话的时长
      final sessionDuration = DateTime.now().difference(_currentVideoStartTime!).inSeconds;
      // 累加到已有的学习时长
      final totalDuration = videoItem.studyDuration + sessionDuration;
      
      final updatedVideo = videoItem.copyWith(studyDuration: totalDuration);
      _updateVideoInList(videoItem.videoPath, updatedVideo);
      
      debugPrint('学习时长更新: 本次会话 ${sessionDuration}秒, 总时长 ${totalDuration}秒');
    }
  }

  /// 获取当前视频的实时学习时长（用于显示）
  int getCurrentVideoStudyDuration(String videoPath) {
    if (_currentDayList == null) return 0;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem == null) return 0;
    
    // 如果是当前正在学习的视频，加上当前会话时长
    if (_currentVideoPath == videoPath && _currentVideoStartTime != null) {
      final currentSessionDuration = DateTime.now().difference(_currentVideoStartTime!).inSeconds;
      return videoItem.studyDuration + currentSessionDuration;
    }
    
    return videoItem.studyDuration;
  }

  /// 添加视频到今日列表
  Future<bool> addVideo({String? videoPath, bool autoLoad = false}) async {
    try {
      // 如果没有提供路径，则让用户选择
      if (videoPath == null) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
        );
        
        if (result == null || result.files.isEmpty) {
          return false;
        }
        
        videoPath = result.files.single.path!;
      }
      
      // 检查是否已经存在
      if (_currentDayList != null && 
          _currentDayList!.videos.any((v) => v.videoPath == videoPath)) {
        debugPrint('视频已存在于今日列表中: $videoPath');
        return false;
      }
      
      // 创建新的视频项目
      final fileName = path.basename(videoPath);
      final video = DailyVideoItem(
        videoPath: videoPath,
        title: fileName,
        addedTime: DateTime.now(),
        analysisStatus: SubtitleAnalysisStatus.pending, // 初始状态为待分析
      );
      
      // 添加到列表
      final today = _getTodayDateString();
      if (_currentDayList == null) {
        _currentDayList = DailyVideoList(
          date: today,
          videos: [video],
          createdTime: DateTime.now(),
          lastUpdatedTime: DateTime.now(),
        );
      } else {
        _currentDayList = _currentDayList!.addVideo(video);
      }
      
      await _saveDayList();
      notifyListeners();
      
      // 自动开始字幕分析
      _startVideoAnalysis(videoPath);
      
      // 如果设置了自动加载，则加载视频
      if (autoLoad) {
        await loadVideo(videoPath);
      }
      
      return true;
    } catch (e) {
      debugPrint('添加视频失败: $e');
      return false;
    }
  }

  /// 从今日列表删除视频
  Future<bool> removeVideo(String videoPath) async {
    if (_currentDayList == null) return false;
    
    try {
      // 如果正在播放这个视频，先停止
      if (_currentVideoPath == videoPath) {
        _stopStudyTimer();
        _currentVideoPath = null;
      }
      
      // 从列表中移除
      final updatedList = _currentDayList!.removeVideo(videoPath);
      _currentDayList = updatedList;
      
      await _saveDayList();
      notifyListeners();
      
      debugPrint('从今日列表删除视频: $videoPath');
      return true;
    } catch (e) {
      debugPrint('删除视频失败: $e');
      return false;
    }
  }

  /// 播放视频（简化版，移除复杂的加载状态）
  Future<bool> loadVideo(String videoPath) async {
    try {
      // 直接使用VideoService播放视频
      final success = await _videoService.loadVideo(videoPath);
      
      if (success) {
        debugPrint('视频播放成功: $videoPath');
        // 标记为已加载状态
        _setVideoLoadStatus(videoPath, VideoLoadStatus.loaded);
        
        // 异步触发字幕分析（不阻塞播放）
        Future.microtask(() {
          _triggerSubtitleAnalysis(videoPath, _videoService.currentSubtitlePath);
        });
        
        return true;
      } else {
        debugPrint('视频播放失败: $videoPath');
        _setVideoLoadStatus(
          videoPath, 
          VideoLoadStatus.error,
          errorMessage: _videoService.errorMessage,
        );
        return false;
      }
    } catch (e) {
      debugPrint('播放视频异常: $e');
      _setVideoLoadStatus(
        videoPath, 
        VideoLoadStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// 批量加载所有视频
  Future<void> loadAllVideos() async {
    if (_currentDayList == null) return;
    
    final videosToLoad = _currentDayList!.videos
        .where((v) => v.loadStatus == VideoLoadStatus.pending)
        .toList();
    
    for (final video in videosToLoad) {
      await loadVideo(video.videoPath);
      // 添加小延迟避免同时加载太多视频
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 标记视频为已完成
  Future<void> markVideoCompleted(String videoPath) async {
    await _updateVideoStudyStatus(videoPath, VideoStudyStatus.completed);
  }

  /// 重置视频学习状态
  Future<void> resetVideoStudyStatus(String videoPath) async {
    await _updateVideoStudyStatus(videoPath, VideoStudyStatus.notStarted);
  }

  /// 清空今日列表
  Future<void> clearTodayList() async {
    if (_currentDayList == null) return;
    
    _stopStudyTimer();
    _currentVideoPath = null;
    
    final today = _getTodayDateString();
    _currentDayList = DailyVideoList(
      date: today,
      videos: [],
      createdTime: DateTime.now(),
      lastUpdatedTime: DateTime.now(),
    );
    
    await _saveDayList();
    notifyListeners();
  }

  /// 获取今日字幕分析汇总
  Future<Map<String, dynamic>?> getTodayAnalysisSummary() async {
    if (_currentDayList == null) return null;
    
    final videosWithAnalysis = _currentDayList!.videos
        .where((v) => v.hasAnalysisResult)
        .toList();
    
    if (videosWithAnalysis.isEmpty) return null;
    
    // 获取视频路径和字幕路径列表
    final videoPaths = videosWithAnalysis.map((v) => v.videoPath).toList();
    final subtitlePaths = videosWithAnalysis.map((v) => v.subtitlePath).toList();
    
    // 使用字幕分析服务获取多视频分析结果
    final multiAnalysis = _subtitleAnalysisService.getTodayAnalysisSummary(videoPaths, subtitlePaths);
    
    if (multiAnalysis == null) {
      return {
        'videosAnalyzed': videosWithAnalysis.length,
        'totalVideos': _currentDayList!.videos.length,
        'error': '无法获取分析数据',
      };
    }
    
    // 计算学习统计
    final stats = _currentDayList!.stats;
    
    return {
      'videosAnalyzed': videosWithAnalysis.length,
      'totalVideos': _currentDayList!.videos.length,
      'completedVideos': stats.completedVideos,
      'totalStudyMinutes': stats.studyDurationMinutes.round(),
      
      // 词汇统计
      'totalWords': multiAnalysis.totalWords,
      'uniqueWords': multiAnalysis.uniqueWords,
      'familiarWords': multiAnalysis.uniqueFamiliarWords,
      'needsLearningWords': multiAnalysis.uniqueNeedsLearningWords,
      'vocabularyMasteryRate': (multiAnalysis.vocabularyMasteryRate * 100).round(),
      
      // 学习潜力
      'learningPotential': multiAnalysis.learningPotential,
      'topNeedsLearningWords': multiAnalysis.topNeedsLearningWords.take(10).map((e) => {
        'word': e.key,
        'frequency': e.value,
      }).toList(),
      
      // 分析时间
      'analysisTime': multiAnalysis.analysisTime.toIso8601String(),
    };
  }

  // 私有方法

  /// 添加视频到列表
  Future<void> _addVideoToList(DailyVideoItem video) async {
    if (_currentDayList == null) {
      final today = _getTodayDateString();
      _currentDayList = DailyVideoList(
        date: today,
        videos: [video],
        createdTime: DateTime.now(),
        lastUpdatedTime: DateTime.now(),
      );
    } else {
      _currentDayList = _currentDayList!.addVideo(video);
    }
    
    await _saveDayList();
    notifyListeners();
  }

  /// 更新列表中的视频
  void _updateVideoInList(String videoPath, DailyVideoItem updatedVideo) {
    if (_currentDayList == null) return;
    
    _currentDayList = _currentDayList!.updateVideo(videoPath, updatedVideo);
    _scheduleDebouncedSave(); // 使用防抖保存
    notifyListeners();
  }

  /// 计划防抖保存
  void _scheduleDebouncedSave() {
    // 取消之前的保存计时器
    _saveDebounceTimer?.cancel();
    
    // 设置新的保存计时器
    _saveDebounceTimer = Timer(_saveDebounceDelay, () {
      _saveDayList();
    });
  }

  /// 立即保存（用于重要操作）
  void _saveImmediately() {
    // 取消防抖计时器
    _saveDebounceTimer?.cancel();
    // 立即保存
    _saveDayList();
  }

  /// 更新视频加载状态
  void _setVideoLoadStatus(String videoPath, VideoLoadStatus status, {String? errorMessage}) {
    if (_currentDayList == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      final updatedVideo = videoItem.copyWith(
        loadStatus: status,
        errorMessage: errorMessage,
      );
      _updateVideoInList(videoPath, updatedVideo);
    }
  }

  /// 更新视频学习状态
  Future<void> _updateVideoStudyStatus(String videoPath, VideoStudyStatus status) async {
    if (_currentDayList == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      final now = DateTime.now();
      final updatedVideo = videoItem.copyWith(
        studyStatus: status,
        startedTime: status == VideoStudyStatus.studying ? now : videoItem.startedTime,
        completedTime: status == VideoStudyStatus.completed ? now : null,
      );
      
      // 状态变更是重要操作，使用立即保存
      _currentDayList = _currentDayList!.updateVideo(videoPath, updatedVideo);
      await _saveDayList(); // 立即保存
      notifyListeners();
    }
  }

  /// 触发字幕分析
  void _triggerSubtitleAnalysis(String videoPath, String? subtitlePath) {
    debugPrint('=== 触发字幕分析 ===');
    debugPrint('视频路径: $videoPath');
    debugPrint('字幕路径: $subtitlePath');
    
    if (_subtitleAnalysisService == null || subtitlePath == null) {
      debugPrint('分析服务为空或字幕路径为空，跳过分析');
      return;
    }
    
    // 延迟执行，确保视频和字幕都已加载
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        debugPrint('开始解析字幕文件: $subtitlePath');
        
        // 读取字幕文件
        final subtitleFile = File(subtitlePath);
        if (!await subtitleFile.exists()) {
          debugPrint('字幕文件不存在: $subtitlePath');
          _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
          return;
        }

        final content = await subtitleFile.readAsString();
        debugPrint('字幕文件内容长度: ${content.length}');
        
        // 检测字幕格式并解析
        final entries = <SubtitleEntry>[];
        
        if (subtitlePath.toLowerCase().endsWith('.srt')) {
          debugPrint('使用SRT格式解析');
          await _parseSrtSubtitles(content, entries);
        } else {
          debugPrint('使用VTT格式解析');
          await _parseVttSubtitles(content, entries);
        }

        debugPrint('解析出字幕条目数: ${entries.length}');

        if (entries.isEmpty) {
          debugPrint('字幕解析失败或为空: $subtitlePath');
          _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
          return;
        }

        debugPrint('开始调用分析服务分析字幕...');
        
        // 触发分析
        await _subtitleAnalysisService!.analyzeSubtitlesSilently(
          videoPath: videoPath,
          subtitlePath: subtitlePath,
          videoTitle: path.basename(videoPath),
          subtitles: entries,
        );
        
        debugPrint('分析服务调用完成');
        
        // 验证分析结果是否保存成功
        final hasResult = _subtitleAnalysisService!.hasAnalysisResult(videoPath, subtitlePath);
        debugPrint('验证分析结果: $hasResult');
        
        if (hasResult) {
          // 分析完成，更新状态
          _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.completed);
          
          // 同时更新字幕路径，确保汇总时能找到分析结果
          _updateVideoSubtitlePath(videoPath, subtitlePath);
          
          debugPrint('字幕分析完成: $videoPath');
        } else {
          debugPrint('分析结果验证失败，可能未正确保存');
          _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
        }
        
      } catch (e) {
        debugPrint('字幕分析失败: $e');
        _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
      }
    });
  }

  /// 解析VTT时间格式
  Duration? _parseVttTime(String timeStr) {
    try {
      // 格式: 00:01:23.456 or 01:23.456 or 00:01:23,456 (SRT格式)
      // 先统一替换逗号为点号
      final normalizedTimeStr = timeStr.replaceAll(',', '.');
      
      final parts = normalizedTimeStr.split(':');
      if (parts.length == 2) {
        // mm:ss.fff
        final minutes = int.parse(parts[0]);
        final secondsParts = parts[1].split('.');
        final seconds = int.parse(secondsParts[0]);
        final milliseconds = secondsParts.length > 1 
            ? int.parse(secondsParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds);
      } else if (parts.length == 3) {
        // hh:mm:ss.fff
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secondsParts = parts[2].split('.');
        final seconds = int.parse(secondsParts[0]);
        final milliseconds = secondsParts.length > 1 
            ? int.parse(secondsParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
      }
    } catch (e) {
      debugPrint('时间解析失败: $timeStr - $e');
    }
    return null;
  }

  /// 解析SRT时间格式
  Duration? _parseSrtTime(String timeStr) {
    try {
      // 格式: hh:mm:ss,ms
      final parts = timeStr.split(',');
      if (parts.length == 2) {
        final timeParts = parts[0].split(':');
        if (timeParts.length == 3) {
          final hours = int.parse(timeParts[0]);
          final minutes = int.parse(timeParts[1]);
          final seconds = int.parse(timeParts[2]);
          final milliseconds = int.parse(parts[1]);
          return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
        }
      }
    } catch (e) {
      debugPrint('SRT时间解析失败: $timeStr - $e');
    }
    return null;
  }

  /// 解析VTT字幕
  Future<void> _parseVttSubtitles(String content, List<SubtitleEntry> entries) async {
    final lines = content.split('\n');
    int entryIndex = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.contains('-->')) {
        // 时间行
        final parts = line.split('-->');
        if (parts.length == 2 && i + 1 < lines.length) {
          final startTime = _parseVttTime(parts[0].trim());
          final endTime = _parseVttTime(parts[1].trim());
          final text = lines[i + 1].trim();
          
          if (startTime != null && endTime != null && text.isNotEmpty) {
            entries.add(SubtitleEntry(
              index: entryIndex++,
              start: startTime,
              end: endTime,
              text: text,
            ));
          }
          i++; // 跳过文本行
        }
      }
    }
  }

  /// 解析SRT字幕
  Future<void> _parseSrtSubtitles(String content, List<SubtitleEntry> entries) async {
    final lines = content.split('\n');
    int entryIndex = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      // 跳过空行
      if (line.isEmpty) continue;
      
      // 检查是否是序号行（纯数字）
      if (RegExp(r'^\d+$').hasMatch(line)) {
        // 下一行应该是时间行
        if (i + 1 < lines.length) {
          final timeLine = lines[i + 1].trim();
          if (timeLine.contains('-->')) {
            // 解析时间
            final parts = timeLine.split('-->');
            if (parts.length == 2) {
              final startTime = _parseSrtTime(parts[0].trim());
              final endTime = _parseSrtTime(parts[1].trim());
              
              // 收集文本行（可能多行）
              final textLines = <String>[];
              int textIndex = i + 2;
              while (textIndex < lines.length && 
                     lines[textIndex].trim().isNotEmpty &&
                     !RegExp(r'^\d+$').hasMatch(lines[textIndex].trim())) {
                textLines.add(lines[textIndex].trim());
                textIndex++;
              }
              
              if (startTime != null && endTime != null && textLines.isNotEmpty) {
                final text = textLines.join(' ');
                entries.add(SubtitleEntry(
                  index: entryIndex++,
                  start: startTime,
                  end: endTime,
                  text: text,
                ));
              }
              
              // 跳过已处理的行
              i = textIndex - 1;
            }
          }
        }
      }
    }
  }

  /// 获取今日日期字符串
  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 加载指定日期的列表
  Future<void> _loadDayList(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'daily_video_list_$date';
      final jsonString = prefs.getString(key);
      
      if (jsonString != null) {
        final jsonData = json.decode(jsonString);
        _currentDayList = _parseDailyVideoList(jsonData);
        debugPrint('加载今日视频列表: ${_currentDayList?.videos.length ?? 0} 个视频');
      } else {
        // 创建新的今日列表
        _currentDayList = DailyVideoList(
          date: date,
          videos: [],
          createdTime: DateTime.now(),
          lastUpdatedTime: DateTime.now(),
        );
        debugPrint('创建新的今日视频列表');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('加载今日视频列表失败: $e');
      // 创建空列表作为后备
      _currentDayList = DailyVideoList(
        date: date,
        videos: [],
        createdTime: DateTime.now(),
        lastUpdatedTime: DateTime.now(),
      );
      notifyListeners();
    }
  }

  /// 保存当前日期的列表
  Future<void> _saveDayList() async {
    if (_currentDayList == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'daily_video_list_${_currentDayList!.date}';
      final jsonString = json.encode(_serializeDailyVideoList(_currentDayList!));
      await prefs.setString(key, jsonString);
      // 降低日志输出频率，只在调试时使用
      // debugPrint('保存今日视频列表成功');
    } catch (e) {
      debugPrint('保存今日视频列表失败: $e');
    }
  }

  /// 序列化DailyVideoList
  Map<String, dynamic> _serializeDailyVideoList(DailyVideoList list) {
    return {
      'date': list.date,
      'videos': list.videos.map(_serializeDailyVideoItem).toList(),
      'createdTime': list.createdTime.toIso8601String(),
      'lastUpdatedTime': list.lastUpdatedTime.toIso8601String(),
    };
  }

  /// 序列化DailyVideoItem
  Map<String, dynamic> _serializeDailyVideoItem(DailyVideoItem item) {
    return {
      'videoPath': item.videoPath,
      'subtitlePath': item.subtitlePath,
      'title': item.title,
      'loadStatus': item.loadStatus.index,
      'studyStatus': item.studyStatus.index,
      'addedTime': item.addedTime.millisecondsSinceEpoch,
      'startedTime': item.startedTime?.millisecondsSinceEpoch,
      'completedTime': item.completedTime?.millisecondsSinceEpoch,
      'studyDuration': item.studyDuration,
      'errorMessage': item.errorMessage,
      'analysisStatus': item.analysisStatus.index,
    };
  }

  /// 解析DailyVideoList
  DailyVideoList _parseDailyVideoList(Map<String, dynamic> json) {
    return DailyVideoList(
      date: json['date'],
      videos: (json['videos'] as List)
          .map((v) => _parseDailyVideoItem(v))
          .toList(),
      createdTime: DateTime.parse(json['createdTime']),
      lastUpdatedTime: DateTime.parse(json['lastUpdatedTime']),
    );
  }

  /// 解析DailyVideoItem
  DailyVideoItem _parseDailyVideoItem(Map<String, dynamic> json) {
    return DailyVideoItem(
      videoPath: json['videoPath'],
      subtitlePath: json['subtitlePath'],
      title: json['title'],
      loadStatus: VideoLoadStatus.values[json['loadStatus']],
      studyStatus: VideoStudyStatus.values[json['studyStatus']],
      addedTime: DateTime.fromMillisecondsSinceEpoch(json['addedTime']),
      startedTime: json['startedTime'] != null ? DateTime.fromMillisecondsSinceEpoch(json['startedTime']) : null,
      completedTime: json['completedTime'] != null ? DateTime.fromMillisecondsSinceEpoch(json['completedTime']) : null,
      studyDuration: json['studyDuration'] ?? 0,
      errorMessage: json['errorMessage'],
      analysisStatus: SubtitleAnalysisStatus.values[json['analysisStatus'] ?? 0],
    );
  }

  @override
  void dispose() {
    _stopStudyTimer();
    _saveDebounceTimer?.cancel(); // 清理防抖计时器
    _videoService.removeListener(_onVideoServiceChanged);
    super.dispose();
  }

  /// 手动触发视频字幕分析
  void analyzeSubtitles(String videoPath) {
    debugPrint('手动触发字幕分析: $videoPath');
    _startVideoAnalysis(videoPath);
  }

  /// 修复视频的字幕路径（用于已存在的视频）
  void fixVideoSubtitlePath(String videoPath) {
    if (_currentDayList == null) return;
    
    final video = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (video == null) return;
    
    // 如果字幕路径为空，尝试查找
    if (video.subtitlePath == null) {
      debugPrint('修复字幕路径: $videoPath');
      _tryAutoLoadSubtitle(videoPath);
    }
  }

  /// 开始视频字幕分析
  void _startVideoAnalysis(String videoPath) {
    debugPrint('=== 开始视频分析: $videoPath ===');
    
    // 更新状态为分析中
    _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.analyzing);
    
    // 检查是否已经有字幕加载
    if (_videoService.currentVideoPath == videoPath && 
        _videoService.subtitleData != null) {
      debugPrint('当前视频已有字幕，直接分析');
      // 如果当前视频已加载字幕，直接分析
      _triggerSubtitleAnalysis(videoPath, _videoService.currentSubtitlePath);
    } else {
      debugPrint('尝试自动加载字幕文件');
      // 否则尝试自动加载字幕
      _tryAutoLoadSubtitle(videoPath);
    }
  }

  /// 尝试自动加载字幕并分析
  Future<void> _tryAutoLoadSubtitle(String videoPath) async {
    try {
      debugPrint('自动查找字幕: $videoPath');
      
      // 基于视频路径查找字幕文件
      final videoDir = path.dirname(videoPath);
      final videoName = path.basenameWithoutExtension(videoPath);
      
      debugPrint('视频目录: $videoDir');
      debugPrint('视频文件名: $videoName');
      
      // 常见字幕扩展名
      const subtitleExtensions = ['.srt', '.vtt', '.ass', '.ssa'];
      
      String? subtitlePath;
      for (final ext in subtitleExtensions) {
        final candidatePath = path.join(videoDir, '$videoName$ext');
        debugPrint('检查字幕文件: $candidatePath');
        final file = File(candidatePath);
        if (await file.exists()) {
          subtitlePath = candidatePath;
          debugPrint('找到字幕文件: $subtitlePath');
          break;
        }
      }
      
      if (subtitlePath != null) {
        // 更新视频项目的字幕路径
        _updateVideoSubtitlePath(videoPath, subtitlePath);
        
        // 触发字幕分析
        _triggerSubtitleAnalysis(videoPath, subtitlePath);
      } else {
        // 没有找到字幕文件，标记为错误
        debugPrint('未找到任何字幕文件');
        _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
      }
    } catch (e) {
      debugPrint('自动加载字幕失败: $e');
      _updateVideoAnalysisStatus(videoPath, SubtitleAnalysisStatus.error);
    }
  }

  /// 更新视频分析状态
  void _updateVideoAnalysisStatus(String videoPath, SubtitleAnalysisStatus status) {
    if (_currentDayList == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      final updatedVideo = videoItem.copyWith(analysisStatus: status);
      _updateVideoInList(videoPath, updatedVideo);
      debugPrint('视频分析状态更新: $videoPath -> $status');
    }
  }

  /// 更新视频字幕路径
  void _updateVideoSubtitlePath(String videoPath, String subtitlePath) {
    if (_currentDayList == null) return;
    
    final videoItem = _currentDayList!.videos.firstWhere(
      (v) => v.videoPath == videoPath,
      orElse: () => null as DailyVideoItem,
    );
    
    if (videoItem != null) {
      final updatedVideo = videoItem.copyWith(subtitlePath: subtitlePath);
      _updateVideoInList(videoPath, updatedVideo);
    }
  }
} 