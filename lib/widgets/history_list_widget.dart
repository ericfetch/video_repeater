import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/history_service.dart';
import '../services/video_service.dart';
import '../services/message_service.dart';
import '../services/vocabulary_service.dart';
import '../models/history_model.dart';
import '../screens/home_screen.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

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
            
            // 检查文件是否存在
            if (!File(item.videoPath).existsSync()) {
              final messageService = Provider.of<MessageService>(context, listen: false);
              messageService.showMessage('视频文件不存在');
              return;
            }
            
            // 关闭抽屉
            Navigator.pop(context);
            
            // 显示加载中消息
            final messageService = Provider.of<MessageService>(context, listen: false);
            messageService.showMessage('加载视频中...');
            
            // 加载视频
            bool videoSuccess = await videoService.loadVideo(item.videoPath);
            if (!videoSuccess) {
              messageService.showMessage('视频加载失败');
              return;
            }
            
            // 等待视频加载完成
            await Future.delayed(const Duration(milliseconds: 500));
            
            // 加载字幕
            if (item.subtitlePath.isNotEmpty && File(item.subtitlePath).existsSync()) {
              // 直接读取字幕文件内容
              final subtitleFile = File(item.subtitlePath);
              final content = await subtitleFile.readAsString();
              final lineCount = content.split('\n').length;
              debugPrint('字幕文件行数: $lineCount');
              
              // 加载字幕
              bool subtitleSuccess = await videoService.loadSubtitle(item.subtitlePath);
              
              // 检查字幕是否加载完整
              if (subtitleSuccess) {
                final loadedCount = videoService.subtitleData?.entries.length ?? 0;
                debugPrint('加载了 $loadedCount 条字幕');
                
                // 如果字幕数量恰好是48条，可能存在问题，尝试重新加载
                if (loadedCount == 48 && lineCount > 200) {
                  debugPrint('检测到可能的字幕截断问题，尝试重新加载');
                  
                  // 重新加载字幕
                  await Future.delayed(const Duration(milliseconds: 300));
                  subtitleSuccess = await videoService.loadSubtitle(item.subtitlePath);
                  
                  final reloadedCount = videoService.subtitleData?.entries.length ?? 0;
                  debugPrint('重新加载后字幕数: $reloadedCount');
                }
                
                messageService.showMessage('字幕加载成功');
                
                // 恢复字幕偏移
                if (item.subtitleTimeOffset != 0) {
                  final offsetSeconds = item.subtitleTimeOffset ~/ 1000;
                  videoService.resetSubtitleTime();
                  videoService.adjustSubtitleTime(offsetSeconds);
                }
              } else {
                messageService.showMessage('字幕加载失败');
              }
            }
            
            // 等待字幕加载完成
            await Future.delayed(const Duration(milliseconds: 500));
            
            // 跳转到上次观看位置
            if (videoService.player != null && videoService.duration.inMilliseconds > 0) {
              final safePosition = Duration(
                milliseconds: item.lastPosition.inMilliseconds.clamp(0, videoService.duration.inMilliseconds)
              );
              videoService.seek(safePosition);
              messageService.showMessage('已恢复到上次播放位置: ${_formatDuration(safePosition)}');
            }
          },
          onDelete: () => historyService.removeHistory(index),
        );
      },
    );
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
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