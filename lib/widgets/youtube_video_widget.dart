import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';
import '../services/video_service.dart';

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
  bool _isLoading = true;
  String? _errorMessage;
  VideoController? _videoController;

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
      
      // 使用VideoService加载YouTube视频
      bool success = await videoService.loadVideo('https://youtu.be/$videoId');
      
      if (success && videoService.player != null) {
        // 创建VideoController
        final controller = VideoController(videoService.player!);
        
        // 禁用视频内置字幕
        try {
          // 等待播放器初始化完成
          await Future.delayed(const Duration(milliseconds: 500));
          await videoService.player!.setSubtitleTrack(SubtitleTrack.no());
          debugPrint('已禁用视频区域内的字幕轨道');
          
          // 主动更新字幕显示
          final position = videoService.player!.state.position;
          debugPrint('YouTubeVideoWidget: 当前位置 ${position.inMilliseconds}ms');
        } catch (e) {
          debugPrint('禁用字幕轨道失败: $e');
        }
        
        if (mounted) {
          setState(() {
            _videoController = controller;
            _isLoading = false;
          });
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
    // 不在这里释放控制器，因为它由VideoService管理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videoController == null) {
      if (_isLoading) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      } else if (_errorMessage != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        );
      } else {
        return const Center(
          child: Text('正在初始化播放器...', style: TextStyle(color: Colors.white70)),
        );
      }
    }
    
    // 使用MediaKit视频播放器，字幕将在应用的字幕控制区域显示
    return Container(
      color: Colors.black,
      child: Video(
        controller: _videoController!,
        // 禁用视频内置字幕显示
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          style: TextStyle(fontSize: 0, color: Colors.transparent),
          visible: false, // 不显示字幕
          padding: EdgeInsets.zero,
        ),
        // 基本视频配置
        fit: BoxFit.contain,
      ),
    );
  }
} 