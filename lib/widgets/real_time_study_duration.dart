import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/daily_video_service.dart';
import 'dart:async';

/// 实时学习时长显示组件
/// 使用独立的Timer避免影响父级Consumer重建
class RealTimeStudyDuration extends StatefulWidget {
  const RealTimeStudyDuration({super.key});

  @override
  State<RealTimeStudyDuration> createState() => _RealTimeStudyDurationState();
}

class _RealTimeStudyDurationState extends State<RealTimeStudyDuration> {
  Timer? _timer;
  int _displaySeconds = 0;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    // 每秒更新显示，但不影响父级Consumer
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateDuration();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateDuration() {
    final service = Provider.of<DailyVideoService>(context, listen: false);
    final newSeconds = service.currentStudyDurationSeconds;
    if (newSeconds != _displaySeconds) {
      setState(() {
        _displaySeconds = newSeconds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_displaySeconds / 60.0).round();
    return Text('学习时长: ${minutes}分钟');
  }
} 