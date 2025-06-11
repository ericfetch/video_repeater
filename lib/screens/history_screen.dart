import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/history_service.dart';
import '../models/history_model.dart';
import 'package:path/path.dart' as path;

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
                  onTap: () {
                    // 打开视频
                    Navigator.of(context).pop(videoItem);
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
} 