import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';
import '../services/video_service.dart';
import '../models/vocabulary_model.dart';

class VocabularyListWidget extends StatefulWidget {
  const VocabularyListWidget({super.key});

  @override
  State<VocabularyListWidget> createState() => _VocabularyListWidgetState();
}

class _VocabularyListWidgetState extends State<VocabularyListWidget> {
  // 当前展开的视频名称
  String? _expandedVideoName;
  
  @override
  void initState() {
    super.initState();
    // 在初始化时获取当前视频
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateExpandedVideo();
    });
  }
  
  // 更新当前展开的视频
  void _updateExpandedVideo() {
    final videoService = Provider.of<VideoService>(context, listen: false);
    if (videoService.currentVideoPath != null) {
      final currentVideoName = videoService.currentVideoPath!.split('/').last;
      setState(() {
        _expandedVideoName = currentVideoName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vocabularyService = Provider.of<VocabularyService>(context);
    final videoService = Provider.of<VideoService>(context);
    final currentVideoPath = videoService.currentVideoPath;
    final currentVideoName = currentVideoPath != null ? 
        currentVideoPath.split('/').last : null;
    
    // 每次打开生词本时更新展开的视频
    if (currentVideoName != null && _expandedVideoName != currentVideoName) {
      _expandedVideoName = currentVideoName;
    }
    
    final vocabularyLists = vocabularyService.vocabularyLists;
    
    if (vocabularyLists.isEmpty) {
      return const Center(
        child: Text('生词本为空', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return ListView.builder(
      itemCount: vocabularyLists.length,
      itemBuilder: (context, index) {
        final videoName = vocabularyLists.keys.elementAt(index);
        final vocabularyList = vocabularyLists[videoName]!;
        
        // 当前视频高亮显示
        final isCurrentVideo = videoName == currentVideoName;
        
        // 为当前视频的ExpansionTile生成一个新的Key，强制重建并展开
        final key = isCurrentVideo ? UniqueKey() : ValueKey(videoName);
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: isCurrentVideo ? Colors.blue.withOpacity(0.1) : null,
          child: ExpansionTile(
            key: key,
            initiallyExpanded: videoName == _expandedVideoName,
            title: Text(
              videoName,
              style: TextStyle(
                fontWeight: isCurrentVideo ? FontWeight.bold : FontWeight.normal,
                color: isCurrentVideo ? Colors.blue : null,
              ),
            ),
            subtitle: Text('${vocabularyList.words.length} 个单词'),
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: vocabularyList.words.length,
                itemBuilder: (context, wordIndex) {
                  final word = vocabularyList.words[wordIndex];
                  
                  return ListTile(
                    dense: true,
                    title: Text(word.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      word.context,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      onPressed: () {
                        vocabularyService.removeWord(videoName, word.word);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
} 