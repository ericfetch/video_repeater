class VideoHistory {
  final String videoPath;
  final String subtitlePath;
  final String videoName;
  final Duration lastPosition;
  final DateTime timestamp;

  VideoHistory({
    required this.videoPath,
    required this.subtitlePath,
    required this.videoName,
    required this.lastPosition,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'videoPath': videoPath,
      'subtitlePath': subtitlePath,
      'videoName': videoName,
      'lastPosition': lastPosition.inMilliseconds,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory VideoHistory.fromJson(Map<String, dynamic> json) {
    return VideoHistory(
      videoPath: json['videoPath'],
      subtitlePath: json['subtitlePath'],
      videoName: json['videoName'],
      lastPosition: Duration(milliseconds: json['lastPosition']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    );
  }
} 