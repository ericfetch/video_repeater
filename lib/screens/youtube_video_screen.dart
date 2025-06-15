import 'package:flutter/material.dart';

class YouTubeVideoScreen extends StatefulWidget {
  final String? initialVideoUrl;
  
  const YouTubeVideoScreen({Key? key, this.initialVideoUrl}) : super(key: key);

  @override
  State<YouTubeVideoScreen> createState() => _YouTubeVideoScreenState();
}

class _YouTubeVideoScreenState extends State<YouTubeVideoScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube视频 (已弃用)'),
      ),
      body: const Center(
        child: Text('YouTube视频现在直接在主界面播放'),
      ),
    );
  }
} 