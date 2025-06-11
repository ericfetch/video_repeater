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
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) {
        _initializeController();
      }
    });
  }
  
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
  
  void _initializeController() {
    if (!mounted) return;
    
    final videoService = Provider.of<VideoService>(context, listen: false);
    if (videoService.player != null) {
      if (mounted) {
        setState(() {
          _videoController = VideoController(videoService.player!);
        });
      }
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
      if (mounted) {
        _videoController = VideoController(player);
      }
    }
    
    // 显示错误信息
    if (errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red[300], size: 64),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: videoService.clearError,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // 显示加载状态
    if (isLoading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '正在加载视频...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // 视频播放 (本地和YouTube视频都使用本地播放器)
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