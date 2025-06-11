import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/history_service.dart';
import '../services/video_service.dart';
import '../services/message_service.dart';
import '../services/vocabulary_service.dart';
import '../models/history_model.dart';
import '../screens/home_screen.dart';

class HistoryListWidget extends StatelessWidget {
  const HistoryListWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final historyService = Provider.of<HistoryService>(context);
    final videoService = Provider.of<VideoService>(context);
    final history = historyService.history;
    
    if (history.isEmpty) {
      return const Center(
        child: Text('暂无观看历史', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return HistoryListItem(
          history: item,
          onTap: () async {
            // 在异步操作前缓存所有需要的服务引用
            final cachedHistoryService = historyService;
            final cachedVideoService = videoService;
            final cachedMessageService = Provider.of<MessageService>(context, listen: false);
            final cachedVocabularyService = Provider.of<VocabularyService>(context, listen: false);
            
            // 设置当前历史记录
            cachedHistoryService.setCurrentHistory(item);
            
            // 检查文件是否存在
            if (!File(item.videoPath).existsSync()) {
              cachedMessageService.showMessage('视频文件不存在');
              return;
            }
            
            // 关闭抽屉
            Navigator.pop(context);
            
            // 显示加载中消息
            cachedMessageService.showMessage('加载视频中...');
            
            // 加载视频
            bool videoSuccess = await cachedVideoService.loadVideo(item.videoPath);
            if (!videoSuccess) {
              cachedMessageService.showMessage('视频加载失败');
              return;
            }
            
            // 等待视频加载完成
            await Future.delayed(const Duration(milliseconds: 500));
            
            // 确保视频标题和路径正确更新
            final videoName = path.basename(item.videoPath);
            debugPrint('从历史记录加载视频: $videoName, 路径: ${item.videoPath}');
            
            // 加载该视频的生词本
            cachedVocabularyService.setCurrentVideo(videoName);
            cachedVocabularyService.loadVocabularyList(videoName);
            
            // 加载字幕
            if (item.subtitlePath.isNotEmpty && File(item.subtitlePath).existsSync()) {
              // 验证字幕文件是否与视频匹配
              final videoFileName = path.basenameWithoutExtension(item.videoPath).toLowerCase();
              final subtitleFileName = path.basenameWithoutExtension(item.subtitlePath).toLowerCase();
              
              // 检查字幕文件名是否包含视频文件名的一部分，或者视频文件名是否包含字幕文件名的一部分
              bool isMatched = false;
              
              // 如果是YouTube视频，检查视频ID是否匹配
              if (videoFileName.contains('_') && videoFileName.split('_').first.length == 11) {
                // 可能是YouTube视频，提取视频ID
                final videoId = videoFileName.split('_').first;
                isMatched = subtitleFileName.contains(videoId);
                debugPrint('YouTube视频ID检查: $videoId, 匹配结果: $isMatched');
              }
              
              // 如果不是YouTube视频或ID不匹配，检查文件名相似度
              if (!isMatched) {
                // 简单比较：检查文件名是否有相似部分
                if (videoFileName.length > 5 && subtitleFileName.length > 5) {
                  // 检查前5个字符是否匹配
                  isMatched = videoFileName.substring(0, 5) == subtitleFileName.substring(0, 5);
                  
                  // 如果不匹配，检查字幕文件名是否包含视频文件名的一部分
                  if (!isMatched && videoFileName.length > 8) {
                    isMatched = subtitleFileName.contains(videoFileName.substring(0, 8));
                  }
                  
                  // 如果还不匹配，检查视频文件名是否包含字幕文件名的一部分
                  if (!isMatched && subtitleFileName.length > 8) {
                    isMatched = videoFileName.contains(subtitleFileName.substring(0, 8));
                  }
                }
              }
              
              debugPrint('字幕文件匹配检查: 视频=$videoFileName, 字幕=$subtitleFileName, 匹配结果=$isMatched');
              
              if (!isMatched) {
                cachedMessageService.showMessage('字幕文件可能与视频不匹配，跳过加载');
                debugPrint('字幕文件可能与视频不匹配，跳过加载');
                return;
              }
              
              // 直接读取字幕文件内容
              final subtitleFile = File(item.subtitlePath);
              final content = await subtitleFile.readAsString();
              final lineCount = content.split('\n').length;
              debugPrint('字幕文件行数: $lineCount');
              
              // 加载字幕
              bool subtitleSuccess = await cachedVideoService.loadSubtitle(item.subtitlePath);
              
              // 检查字幕是否加载完整
              if (subtitleSuccess) {
                final loadedCount = cachedVideoService.subtitleData?.entries.length ?? 0;
                debugPrint('加载了 $loadedCount 条字幕');
                
                // 如果字幕数量恰好是48条，可能存在问题，尝试重新加载
                if (loadedCount == 48 && lineCount > 200) {
                  debugPrint('检测到可能的字幕截断问题，尝试重新加载');
                  
                  // 重新加载字幕
                  await Future.delayed(const Duration(milliseconds: 300));
                  subtitleSuccess = await cachedVideoService.loadSubtitle(item.subtitlePath);
                  
                  final reloadedCount = cachedVideoService.subtitleData?.entries.length ?? 0;
                  debugPrint('重新加载后字幕数: $reloadedCount');
                }
                
                cachedMessageService.showMessage('字幕加载成功');
                
                // 恢复字幕偏移
                if (item.subtitleTimeOffset != 0) {
                  final offsetSeconds = item.subtitleTimeOffset ~/ 1000;
                  cachedVideoService.resetSubtitleTime();
                  cachedVideoService.adjustSubtitleTime(offsetSeconds);
                }
              } else {
                cachedMessageService.showMessage('字幕加载失败');
              }
            }
            
            // 使用延迟和重试机制跳转到上次观看位置
            await _seekToPositionWithRetry(
              cachedVideoService, 
              cachedMessageService, 
              item.lastPosition, 
              item.videoPath
            );
          },
          onDelete: () => historyService.removeHistory(index),
        );
      },
    );
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
        
        // 再次延迟一点并检查位置是否正确设置
        await Future.delayed(const Duration(milliseconds: 300));
        final actualPosition = videoService.currentPosition;
        final difference = (actualPosition.inMilliseconds - safePosition.inMilliseconds).abs();
        
        if (difference > 1000) {  // 如果差异超过1秒
          debugPrint('位置设置不正确，再次尝试跳转。目标: ${safePosition.inSeconds}秒，实际: ${actualPosition.inSeconds}秒');
          videoService.seek(safePosition);
        } else {
          debugPrint('位置设置正确，跳转成功');
        }
        
        return;
      }
      
      attempts++;
    }
    
    debugPrint('视频加载超时，无法跳转到指定位置');
    messageService.showMessage('无法恢复播放进度，请手动操作');
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