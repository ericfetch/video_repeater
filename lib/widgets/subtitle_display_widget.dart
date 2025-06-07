import 'package:flutter/material.dart';
import '../services/video_service.dart';

class SubtitleDisplayWidget extends StatelessWidget {
  final VideoService videoService;
  
  const SubtitleDisplayWidget({
    super.key,
    required this.videoService,
  });

  @override
  Widget build(BuildContext context) {
    final currentSubtitle = videoService.currentSubtitle;
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 字幕索引和时间信息
          if (currentSubtitle != null) ...[
            Row(
              children: [
                Text(
                  '字幕 #${currentSubtitle.index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${_formatDuration(currentSubtitle.start)} → ${_formatDuration(currentSubtitle.end)}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // 字幕文本
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  currentSubtitle.text,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ] else ...[
            const Center(
              child: Text(
                '当前没有字幕',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // 格式化时间显示
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
} 