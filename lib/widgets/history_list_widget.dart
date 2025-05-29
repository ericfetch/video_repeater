import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/history_service.dart';
import '../services/video_service.dart';
import '../models/history_model.dart';

class HistoryListWidget extends StatelessWidget {
  const HistoryListWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final historyService = Provider.of<HistoryService>(context);
    final videoService = Provider.of<VideoService>(context);
    final history = historyService.history;
    
    if (history.isEmpty) {
      return const Center(
        child: Text('暂无观看历史记录', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return HistoryListItem(
          history: item,
          onTap: () async {
            // 设置当前历史记录
            historyService.setCurrentHistory(item);
            
            // 加载视频和字幕
            await videoService.loadVideo(item.videoPath);
            await videoService.loadSubtitle(item.subtitlePath);
            
            // 跳转到上次观看位置
            if (videoService.player != null) {
              videoService.player!.seek(item.lastPosition);
            }
            
            // 关闭抽屉
            Navigator.pop(context);
          },
          onDelete: () => historyService.removeHistory(index),
        );
      },
    );
  }
}

class HistoryListItem extends StatelessWidget {
  final VideoHistory history;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  
  const HistoryListItem({
    Key? key,
    required this.history,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // 格式化时间
    final formattedTime = _formatDuration(history.lastPosition);
    final formattedDate = _formatDate(history.timestamp);
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: ListTile(
        leading: const Icon(Icons.movie, color: Colors.blue),
        title: Text(
          history.videoName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('上次位置: $formattedTime\n$formattedDate'),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
} 