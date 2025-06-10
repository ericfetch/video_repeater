import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../services/download_info_service.dart';
import '../services/video_service.dart';

/// YouTube下载信息面板
/// 在屏幕中间显示下载进度和累加的信息
class DownloadInfoPanel extends StatefulWidget {
  const DownloadInfoPanel({Key? key}) : super(key: key);

  @override
  State<DownloadInfoPanel> createState() => _DownloadInfoPanelState();
}

class _DownloadInfoPanelState extends State<DownloadInfoPanel> {
  // 创建一个ScrollController来控制消息列表的滚动
  final ScrollController _scrollController = ScrollController();
  
  // 上一次消息列表的长度
  int _lastMessageCount = 0;
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  // 滚动到消息列表底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadInfoService>(
      builder: (context, downloadInfoService, child) {
        // 如果面板不可见，返回空容器
        if (!downloadInfoService.isVisible) {
          return const SizedBox.shrink();
        }

        // 检查消息数量是否变化，如果变化了，滚动到底部
        if (downloadInfoService.messages.length != _lastMessageCount) {
          _lastMessageCount = downloadInfoService.messages.length;
          // 使用addPostFrameCallback确保在布局完成后滚动
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 500,
              constraints: const BoxConstraints(
                maxHeight: 500,
                minHeight: 200,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                ],
                border: Border.all(
                  color: Colors.grey[800]!,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题和关闭按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.cloud_download,
                            color: Colors.blue,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'YouTube 视频下载',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: downloadInfoService.hidePanel,
                        tooltip: '关闭',
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  
                  const Divider(color: Colors.grey),
                  
                  // 进度条
                  if (downloadInfoService.isDownloading)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: downloadInfoService.progress,
                          backgroundColor: Colors.grey[800],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            downloadInfoService.progress > 0.95 
                                ? Colors.green 
                                : Colors.blue
                          ),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '下载进度: ${(downloadInfoService.progress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  
                  // 消息列表
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey[900]!,
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ListView.builder(
                        controller: _scrollController, // 使用类成员ScrollController
                        shrinkWrap: true,
                        itemCount: downloadInfoService.messages.length,
                        itemBuilder: (context, index) {
                          final message = downloadInfoService.messages[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              message,
                              style: TextStyle(
                                color: message.contains('错误') 
                                    ? Colors.red[300] 
                                    : Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // 字幕选择部分
                  if (downloadInfoService.availableSubtitleTracks.isNotEmpty && !downloadInfoService.isDownloading)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          '可用字幕:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.grey[800]!,
                              width: 1,
                            ),
                          ),
                          child: ListView.builder(
                            itemCount: downloadInfoService.availableSubtitleTracks.length,
                            itemBuilder: (context, index) {
                              final track = downloadInfoService.availableSubtitleTracks[index];
                              final isSelected = downloadInfoService.selectedSubtitleTrack == track;
                              
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                dense: true,
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        track['name'] as String,
                                        style: TextStyle(
                                          color: isSelected ? Colors.blue : Colors.white,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[800],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        track['languageCode'] as String,
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Wrap(
                                  spacing: 8,
                                  children: [
                                    Text(
                                      '来源: ${track['source'] ?? '未知'}',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '自动: ${track['isAutoGenerated'] == true ? '是' : '否'}',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (track['baseUrl'] != null)
                                      Text(
                                        'URL: ${(track['baseUrl'] as String).substring(0, min((track['baseUrl'] as String).length, 20))}...',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                isThreeLine: false,
                                selected: isSelected,
                                tileColor: isSelected ? Colors.blue.withOpacity(0.1) : null,
                                onTap: () {
                                  downloadInfoService.selectSubtitleTrack(track);
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 下载按钮
                            ElevatedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('下载所选字幕'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onPressed: downloadInfoService.selectedSubtitleTrack == null || 
                                          downloadInfoService.isSubtitleDownloading ? 
                                null : 
                                () {
                                  // 获取VideoService实例
                                  final videoService = Provider.of<VideoService>(context, listen: false);
                                  
                                  // 调用VideoService中的方法下载字幕
                                  videoService.downloadSelectedSubtitle(
                                    downloadInfoService.videoId!,
                                    downloadInfoService.selectedSubtitleTrack!,
                                  );
                                },
                            ),
                            
                            // 重试按钮
                            if (downloadInfoService.subtitleDownloadFailed)
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重试'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                  onPressed: downloadInfoService.isSubtitleDownloading ? 
                                    null : 
                                    () {
                                      // 获取VideoService实例
                                      final videoService = Provider.of<VideoService>(context, listen: false);
                                      
                                      // 调用VideoService中的方法下载字幕
                                      videoService.downloadSelectedSubtitle(
                                        downloadInfoService.videoId!,
                                        downloadInfoService.selectedSubtitleTrack!,
                                      );
                                    },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    
                  // 字幕下载中
                  if (downloadInfoService.isSubtitleDownloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '正在下载字幕...',
                            style: TextStyle(
                              color: Colors.blue[300],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
} 