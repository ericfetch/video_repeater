import 'package:flutter/material.dart';
import 'package:pod_player/pod_player.dart';
import 'package:provider/provider.dart';
import '../services/video_service.dart';
import '../services/youtube_service.dart';

class YouTubeVideoWidget extends StatefulWidget {
  final VideoService? videoService;
  final String? videoId;
  
  const YouTubeVideoWidget({
    super.key,
    this.videoService,
    this.videoId,
  });

  @override
  State<YouTubeVideoWidget> createState() => _YouTubeVideoWidgetState();
}

class _YouTubeVideoWidgetState extends State<YouTubeVideoWidget> {
  PodPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeController();
    });
  }

  Future<void> _initializeController() async {
    final videoService = widget.videoService ?? Provider.of<VideoService>(context, listen: false);
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // 如果提供了视频ID，直接使用它
      String? videoId = widget.videoId;
      
      // 否则，从视频服务获取
      if (videoId == null && videoService.youtubeVideoId != null) {
        videoId = videoService.youtubeVideoId;
      }
      
      if (videoId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '未提供YouTube视频ID';
        });
        return;
      }
      
      // 直接使用视频服务的方法播放YouTube视频
      final success = await videoService.playYouTubeWithPodPlayer('https://youtu.be/$videoId');
      
      if (success) {
        // 从YouTubeService获取控制器
        final controller = videoService.youtubeService?.getPodPlayerController();
        
        if (controller != null) {
          if (mounted) {
            setState(() {
              _controller = controller;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = '无法获取播放器控制器';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '无法加载YouTube视频';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载YouTube视频失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    // 不在这里释放控制器，因为它由YouTubeService管理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeController,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_controller == null) {
      return const Center(
        child: Text('未初始化播放器', style: TextStyle(color: Colors.white70)),
      );
    }
    
    return PodVideoPlayer(controller: _controller!);
  }
} 