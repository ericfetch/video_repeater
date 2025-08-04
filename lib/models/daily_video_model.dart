/// 视频加载状态
enum VideoLoadStatus {
  pending,    // 待加载
  loading,    // 加载中
  loaded,     // 已加载
  error,      // 加载失败
}

/// 视频学习状态
enum VideoStudyStatus {
  notStarted, // 未开始
  studying,   // 学习中
  completed,  // 已完成
}

/// 字幕分析状态
enum SubtitleAnalysisStatus { 
  pending,    // 待分析
  analyzing,  // 分析中
  completed,  // 已完成
  error       // 分析失败
}

/// 今日视频条目
class DailyVideoItem {
  /// 视频路径
  final String videoPath;
  
  /// 字幕路径（可选）
  final String? subtitlePath;
  
  /// 视频标题
  final String title;
  
  /// 视频加载状态
  final VideoLoadStatus loadStatus;
  
  /// 视频学习状态
  final VideoStudyStatus studyStatus;
  
  /// 添加时间
  final DateTime addedTime;
  
  /// 开始学习时间（可选）
  final DateTime? startedTime;
  
  /// 完成学习时间（可选）
  final DateTime? completedTime;
  
  /// 学习时长（秒）
  final int studyDuration;
  
  /// 错误信息（如果加载失败）
  final String? errorMessage;
  
  /// 字幕分析状态
  final SubtitleAnalysisStatus analysisStatus;

  DailyVideoItem({
    required this.videoPath,
    this.subtitlePath,
    required this.title,
    this.loadStatus = VideoLoadStatus.pending,
    this.studyStatus = VideoStudyStatus.notStarted,
    required this.addedTime,
    this.startedTime,
    this.completedTime,
    this.studyDuration = 0,
    this.errorMessage,
    this.analysisStatus = SubtitleAnalysisStatus.pending,
  });

  /// 复制并修改部分属性
  DailyVideoItem copyWith({
    String? videoPath,
    String? subtitlePath,
    String? title,
    VideoLoadStatus? loadStatus,
    VideoStudyStatus? studyStatus,
    DateTime? addedTime,
    DateTime? startedTime,
    DateTime? completedTime,
    int? studyDuration,
    String? errorMessage,
    SubtitleAnalysisStatus? analysisStatus,
  }) {
    return DailyVideoItem(
      videoPath: videoPath ?? this.videoPath,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      title: title ?? this.title,
      loadStatus: loadStatus ?? this.loadStatus,
      studyStatus: studyStatus ?? this.studyStatus,
      addedTime: addedTime ?? this.addedTime,
      startedTime: startedTime ?? this.startedTime,
      completedTime: completedTime ?? this.completedTime,
      studyDuration: studyDuration ?? this.studyDuration,
      errorMessage: errorMessage ?? this.errorMessage,
      analysisStatus: analysisStatus ?? this.analysisStatus,
    );
  }

  /// 获取显示名称
  String get displayName {
    if (title.isNotEmpty) return title;
    
    // 从路径中提取文件名
    final segments = videoPath.split(RegExp(r'[/\\]'));
    return segments.isNotEmpty ? segments.last : 'Unknown Video';
  }

  /// 是否正在学习中
  bool get isStudying => studyStatus == VideoStudyStatus.studying;
  
  /// 是否已完成学习
  bool get isCompleted => studyStatus == VideoStudyStatus.completed;
  
  /// 是否已加载
  bool get isLoaded => loadStatus == VideoLoadStatus.loaded;
  
  /// 是否加载出错
  bool get hasLoadError => loadStatus == VideoLoadStatus.error;
  
  /// 是否有分析结果
  bool get hasAnalysisResult => analysisStatus == SubtitleAnalysisStatus.completed;
  
  /// 是否正在分析
  bool get isAnalyzing => analysisStatus == SubtitleAnalysisStatus.analyzing;
  
  /// 分析是否出错
  bool get hasAnalysisError => analysisStatus == SubtitleAnalysisStatus.error;

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'videoPath': videoPath,
      'subtitlePath': subtitlePath,
      'title': title,
      'loadStatus': loadStatus.index,
      'studyStatus': studyStatus.index,
      'addedTime': addedTime.millisecondsSinceEpoch,
      'startedTime': startedTime?.millisecondsSinceEpoch,
      'completedTime': completedTime?.millisecondsSinceEpoch,
      'studyDuration': studyDuration,
      'errorMessage': errorMessage,
      'analysisStatus': analysisStatus.index,
    };
  }

  /// 从JSON创建
  factory DailyVideoItem.fromJson(Map<String, dynamic> json) {
    return DailyVideoItem(
      videoPath: json['videoPath'],
      subtitlePath: json['subtitlePath'],
      title: json['title'],
      loadStatus: VideoLoadStatus.values[json['loadStatus'] ?? 0],
      studyStatus: VideoStudyStatus.values[json['studyStatus'] ?? 0],
      addedTime: DateTime.fromMillisecondsSinceEpoch(json['addedTime']),
      startedTime: json['startedTime'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['startedTime'])
          : null,
      completedTime: json['completedTime'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['completedTime'])
          : null,
      studyDuration: json['studyDuration'] ?? 0,
      errorMessage: json['errorMessage'],
      analysisStatus: SubtitleAnalysisStatus.values[json['analysisStatus'] ?? 0],
    );
  }
}

/// 今日视频列表
class DailyVideoList {
  /// 日期（YYYY-MM-DD格式）
  final String date;
  
  /// 视频列表
  final List<DailyVideoItem> videos;
  
  /// 创建时间
  final DateTime createdTime;
  
  /// 最后更新时间
  final DateTime lastUpdatedTime;

  DailyVideoList({
    required this.date,
    this.videos = const [],
    required this.createdTime,
    required this.lastUpdatedTime,
  });

  /// 复制并修改部分属性
  DailyVideoList copyWith({
    String? date,
    List<DailyVideoItem>? videos,
    DateTime? createdTime,
    DateTime? lastUpdatedTime,
  }) {
    return DailyVideoList(
      date: date ?? this.date,
      videos: videos ?? this.videos,
      createdTime: createdTime ?? this.createdTime,
      lastUpdatedTime: lastUpdatedTime ?? this.lastUpdatedTime,
    );
  }

  /// 添加视频
  DailyVideoList addVideo(DailyVideoItem video) {
    final updatedVideos = [...videos, video];
    return copyWith(
      videos: updatedVideos,
      lastUpdatedTime: DateTime.now(),
    );
  }

  /// 删除视频
  DailyVideoList removeVideo(String videoPath) {
    final updatedVideos = videos.where((v) => v.videoPath != videoPath).toList();
    return copyWith(
      videos: updatedVideos,
      lastUpdatedTime: DateTime.now(),
    );
  }

  /// 更新视频
  DailyVideoList updateVideo(String videoPath, DailyVideoItem updatedVideo) {
    final updatedVideos = videos.map((v) => 
      v.videoPath == videoPath ? updatedVideo : v
    ).toList();
    return copyWith(
      videos: updatedVideos,
      lastUpdatedTime: DateTime.now(),
    );
  }

  /// 获取统计信息
  DailyVideoStats get stats {
    final totalVideos = videos.length;
    final completedVideos = videos.where((v) => v.isCompleted).length;
    final studyingVideos = videos.where((v) => v.isStudying).length;
    final loadedVideos = videos.where((v) => v.isLoaded).length;
    final totalStudyDuration = videos.fold<int>(0, (sum, v) => sum + v.studyDuration);
    final videosWithAnalysis = videos.where((v) => v.analysisStatus == SubtitleAnalysisStatus.completed).length;
    
    return DailyVideoStats(
      totalVideos: totalVideos,
      completedVideos: completedVideos,
      studyingVideos: studyingVideos,
      loadedVideos: loadedVideos,
      totalStudyDuration: totalStudyDuration,
      videosWithAnalysis: videosWithAnalysis,
    );
  }
}

/// 今日视频学习统计
class DailyVideoStats {
  final int totalVideos;
  final int completedVideos;
  final int studyingVideos;
  final int loadedVideos;
  final int totalStudyDuration; // 秒
  final int videosWithAnalysis;

  DailyVideoStats({
    required this.totalVideos,
    required this.completedVideos,
    required this.studyingVideos,
    required this.loadedVideos,
    required this.totalStudyDuration,
    required this.videosWithAnalysis,
  });

  /// 完成率（0-1）
  double get completionRate => totalVideos > 0 ? completedVideos / totalVideos : 0.0;

  /// 学习时长（分钟）
  double get studyDurationMinutes => totalStudyDuration / 60.0;

  /// 分析覆盖率（0-1）
  double get analysisRate => totalVideos > 0 ? videosWithAnalysis / totalVideos : 0.0;
} 