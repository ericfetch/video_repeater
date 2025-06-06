import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../services/video_service.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoService? videoService;
  
  const VideoPlayerWidget({
    super.key,
    this.videoService,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  // 视频控制器
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeController();
    });
  }
  
  void _initializeController() {
    final player = Provider.of<VideoService>(context, listen: false).player;
    if (player != null) {
      setState(() {
        _videoController = VideoController(player);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoService = widget.videoService ?? Provider.of<VideoService>(context);
    final player = videoService.player;
    final isLoading = videoService.isLoading;
    final errorMessage = videoService.errorMessage;
    
    // 如果Player实例变化，重新初始化控制器
    if (player != null && (_videoController == null || _videoController!.player != player)) {
      _videoController = VideoController(player);
    }
    
    // 显示错误信息
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: videoService.clearError,
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
    
    // 显示加载状态
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在加载视频...',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    
    if (player == null || player.state.duration == Duration.zero) {
      return const Center(
        child: Text(
          '请选择视频文件',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    // 确保视频控制器已初始化
    if (_videoController == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 使用Video组件显示视频，但隐藏控制UI
    return Video(
      controller: _videoController!,
      controls: null, // 隐藏控制界面
      fill: Colors.black, // 填充颜色
    );
  }
} 