import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/history_service.dart';
import '../services/video_service.dart';
import '../services/message_service.dart';
import '../services/vocabulary_service.dart';
import '../models/history_model.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final historyService = Provider.of<HistoryService>(context);
    final videoHistory = historyService.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: () async {
              // 确认对话框
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认清空'),
                  content: const Text('确定要清空所有观看历史吗？此操作不可撤销。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ) ?? false;
              
              if (confirmed) {
                await historyService.clearHistory();
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: videoHistory.isEmpty
          ? const Center(child: Text('暂无观看历史'))
          : ListView.builder(
              itemCount: videoHistory.length,
              itemBuilder: (context, index) {
                final videoItem = videoHistory[index];
                final fileName = path.basename(videoItem.videoPath);
                
                return ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(fileName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('最后观看: ${videoItem.timestamp.toString().split('.')[0]}'),
                      Text(
                        '进度: ${_formatDuration(videoItem.lastPosition)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      await historyService.removeHistory(index);
                      setState(() {});
                    },
                  ),
                  onTap: () async {
                    // 在异步操作前缓存所有需要的服务引用
                    final videoService = Provider.of<VideoService>(context, listen: false);
                    final messageService = Provider.of<MessageService>(context, listen: false);
                    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
                    
                    // 设置当前历史记录
                    historyService.setCurrentHistory(videoItem);
                    
                    // 检查文件是否存在
                    if (!File(videoItem.videoPath).existsSync()) {
                      messageService.showMessage('视频文件不存在');
                      return;
                    }
                    
                    // 关闭历史记录页面
                    Navigator.pop(context);
                    
                    // 显示加载中消息
                    messageService.showMessage('加载视频中...');
                    
                    // 加载视频
                    bool videoSuccess = await videoService.loadVideo(videoItem.videoPath);
                    if (!videoSuccess) {
                      messageService.showMessage('视频加载失败');
                      return;
                    }
                    
                    // 等待视频加载完成
                    await Future.delayed(const Duration(milliseconds: 500));
                    
                    // 确保视频标题和路径正确更新
                    final videoName = path.basename(videoItem.videoPath);
                    debugPrint('从历史记录加载视频: $videoName, 路径: ${videoItem.videoPath}');
                    
                    // 加载该视频的生词本
                    vocabularyService.setCurrentVideo(videoName);
                    vocabularyService.loadVocabularyList(videoName);
                    
                    // 加载字幕
                    if (videoItem.subtitlePath.isNotEmpty && File(videoItem.subtitlePath).existsSync()) {
                      bool subtitleSuccess = await videoService.loadSubtitle(videoItem.subtitlePath);
                      
                      if (subtitleSuccess) {
                        messageService.showMessage('字幕加载成功');
                        
                        // 恢复字幕偏移
                        if (videoItem.subtitleTimeOffset != 0) {
                          final offsetSeconds = videoItem.subtitleTimeOffset ~/ 1000;
                          videoService.resetSubtitleTime();
                          videoService.adjustSubtitleTime(offsetSeconds);
                        }
                      } else {
                        messageService.showMessage('字幕加载失败');
                      }
                    }
                    
                    // 跳转到上次观看位置
                    await _seekToPositionWithRetry(
                      videoService, 
                      messageService, 
                      videoItem.lastPosition, 
                      videoItem.videoPath
                    );
                  },
                );
              },
            ),
    );
  }
  
  // 格式化时长
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }
  
  // 使用重试机制跳转到指定位置
  Future<void> _seekToPositionWithRetry(
    VideoService videoService, 
    MessageService messageService,
    Duration position, 
    String videoPath
  ) async {
    debugPrint('准备跳转到位置: ${position.inSeconds}秒');
    
    // 等待视频加载完成
    int attempts = 0;
    const maxAttempts = 8;  // 增加尝试次数
    const initialDelay = 800;  // 增加初始延迟
    
    while (attempts < maxAttempts) {
      // 计算当前尝试的延迟时间（逐渐增加）
      final delay = initialDelay + (attempts * 500);  // 增加每次延迟增量
      
      debugPrint('等待视频加载，尝试 ${attempts + 1}/$maxAttempts，延迟 ${delay}ms');
      await Future.delayed(Duration(milliseconds: delay));
      
      // 检查视频是否已加载
      if (videoService.player != null && videoService.duration.inMilliseconds > 0) {
        debugPrint('视频已加载，持续时间: ${videoService.duration.inSeconds}秒');
        
        // 确保位置在有效范围内
        final safePosition = Duration(
          milliseconds: position.inMilliseconds.clamp(0, videoService.duration.inMilliseconds)
        );
        
        // 执行跳转
        videoService.seek(safePosition);
        messageService.showMessage('已恢复到上次播放位置: ${_formatDuration(safePosition)}');
        return;
      }
      
      attempts++;
    }
    
    debugPrint('视频加载超时，无法跳转到指定位置');
    messageService.showMessage('无法恢复播放进度，请手动操作');
  }
} 