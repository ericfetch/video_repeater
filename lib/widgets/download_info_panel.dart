import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/download_info_service.dart';

/// YouTube下载信息面板
/// 在屏幕中间显示下载进度和累加的信息
class DownloadInfoPanel extends StatelessWidget {
  const DownloadInfoPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadInfoService>(
      builder: (context, downloadInfoService, child) {
        // 如果面板不可见，返回空容器
        if (!downloadInfoService.isVisible) {
          return const SizedBox.shrink();
        }

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 500,
              constraints: const BoxConstraints(
                maxHeight: 400,
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
} 