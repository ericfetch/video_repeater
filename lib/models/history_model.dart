import 'package:hive/hive.dart';

part 'history_model.g.dart';

@HiveType(typeId: 21)
class VideoHistory {
  @HiveField(0)
  final String videoPath;
  
  @HiveField(1)
  final String subtitlePath;
  
  @HiveField(2)
  final String videoName;
  
  @HiveField(3)
  final Duration lastPosition;
  
  @HiveField(4)
  final DateTime timestamp;
  
  @HiveField(5)
  final int subtitleTimeOffset; // 字幕时间偏移（毫秒）

  VideoHistory({
    required this.videoPath,
    required this.subtitlePath,
    required this.videoName,
    required this.lastPosition,
    required this.timestamp,
    this.subtitleTimeOffset = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'videoPath': videoPath,
      'subtitlePath': subtitlePath,
      'videoName': videoName,
      'lastPositionMs': lastPosition.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'subtitleTimeOffset': subtitleTimeOffset,
    };
  }

  factory VideoHistory.fromJson(Map<String, dynamic> json) {
    return VideoHistory(
      videoPath: json['videoPath'] as String,
      subtitlePath: json['subtitlePath'] as String? ?? '',
      videoName: json['videoName'] as String,
      lastPosition: Duration(milliseconds: json['lastPositionMs'] as int? ?? 0),
      timestamp: DateTime.parse(json['timestamp'] as String),
      subtitleTimeOffset: json['subtitleTimeOffset'] as int? ?? 0,
    );
  }
} 