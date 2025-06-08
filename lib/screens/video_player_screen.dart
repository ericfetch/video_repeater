import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/video_service.dart';
import '../services/config_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/subtitle_control_widget.dart';
import '../widgets/youtube_video_widget.dart';
import 'package:webview_flutter/webview_flutter.dart';

class VideoPlayerScreen extends StatelessWidget {
  const VideoPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final videoService = Provider.of<VideoService>(context);
    final configService = Provider.of<ConfigService>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频播放器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '打开视频文件',
            onPressed: () => videoService.openVideoFile(),
          ),
          IconButton(
            icon: const Icon(Icons.subtitles),
            tooltip: '加载字幕文件',
            onPressed: () => videoService.openSubtitleFile(),
          ),
          IconButton(
            icon: const Icon(Icons.youtube_searched_for),
            tooltip: '打开YouTube视频',
            onPressed: () => _showYouTubeUrlDialog(context, videoService),
          ),
          IconButton(
            icon: const Icon(Icons.web),
            tooltip: '使用WebView打开YouTube视频',
            onPressed: () => _showYouTubeWebViewDialog(context, videoService),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              // 显示设置对话框
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('设置'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('默认播放速度'),
                        subtitle: Slider(
                          value: configService.defaultPlaybackRate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: configService.defaultPlaybackRate.toStringAsFixed(2),
                          onChanged: (value) {
                            configService.setDefaultPlaybackRate(value);
                          },
                        ),
                      ),
                      ListTile(
                        title: const Text('YouTube视频质量'),
                        subtitle: DropdownButton<String>(
                          value: configService.youtubeVideoQuality,
                          items: const [
                            DropdownMenuItem(value: '1080p', child: Text('1080p')),
                            DropdownMenuItem(value: '720p', child: Text('720p')),
                            DropdownMenuItem(value: '480p', child: Text('480p')),
                            DropdownMenuItem(value: '360p', child: Text('360p')),
                            DropdownMenuItem(value: '320p', child: Text('320p')),
                            DropdownMenuItem(value: '240p', child: Text('240p')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              configService.setYouTubeVideoQuality(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 视频播放区域
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: videoService.isYouTubeVideo
                  ? (videoService.isUsingWebView 
                      ? YouTubeWebViewPlayer(videoId: videoService.youtubeVideoId)
                      : const YouTubeVideoWidget())
                  : const VideoPlayerWidget(),
            ),
          ),
          
          // 字幕控制区域
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              child: const SubtitleControlWidget(),
            ),
          ),
        ],
      ),
    );
  }
  
  // 显示YouTube URL输入对话框
  void _showYouTubeUrlDialog(BuildContext context, VideoService videoService) {
    final textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入YouTube视频链接'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=...',
            labelText: 'YouTube URL',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final url = textController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(context);
                // 使用PodPlayer播放YouTube视频
                videoService.playYouTubeWithPodPlayer(url);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  
  // 显示WebView YouTube URL输入对话框
  void _showYouTubeWebViewDialog(BuildContext context, VideoService videoService) {
    final textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用WebView打开YouTube视频'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                labelText: 'YouTube URL',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('使用WebView直接加载YouTube视频，可获得最佳视频质量，但无法使用字幕功能。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final url = textController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(context);
                // 使用WebView播放YouTube视频
                videoService.playYouTubeWithWebView(url);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// YouTube WebView播放器
class YouTubeWebViewPlayer extends StatefulWidget {
  final String? videoId;
  
  const YouTubeWebViewPlayer({
    super.key,
    this.videoId,
  });
  
  @override
  State<YouTubeWebViewPlayer> createState() => _YouTubeWebViewPlayerState();
}

class _YouTubeWebViewPlayerState extends State<YouTubeWebViewPlayer> {
  late WebViewController _controller;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initWebView();
  }
  
  void _initWebView() {
    if (widget.videoId == null) {
      return;
    }
    
    // 创建WebView控制器
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView错误: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.youtube.com/embed/${widget.videoId}?autoplay=1&fs=1'));
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.videoId == null) {
      return const Center(
        child: Text('未提供YouTube视频ID', style: TextStyle(color: Colors.white70)),
      );
    }
    
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
} 