import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';
import '../services/video_service.dart';
import '../services/message_service.dart';
import '../models/vocabulary_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class VocabularyListWidget extends StatefulWidget {
  const VocabularyListWidget({super.key});

  @override
  State<VocabularyListWidget> createState() => _VocabularyListWidgetState();
}

class _VocabularyListWidgetState extends State<VocabularyListWidget> {
  // 当前展开的视频名称
  String? _expandedVideoName;
  // 是否为平铺模式
  bool _isTileMode = false;
  
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
  
  // 导出生词本为文本文件
  Future<void> _exportVocabulary() async {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final messageService = Provider.of<MessageService>(context, listen: false);
    
    try {
      // 显示导出格式选择对话框
      final format = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择导出格式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_format),
                title: const Text('文本格式 (TXT)'),
                subtitle: const Text('适合阅读和打印'),
                onTap: () => Navigator.of(context).pop('txt'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('表格格式 (CSV)'),
                subtitle: const Text('适合导入Excel或其他表格软件'),
                onTap: () => Navigator.of(context).pop('csv'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      
      if (format == null) return; // 用户取消
      
      // 准备导出内容
      String content;
      String fileExtension;
      
      if (format == 'txt') {
        content = vocabularyService.exportVocabularyAsText();
        fileExtension = 'txt';
      } else {
        content = vocabularyService.exportVocabularyAsCSV();
        fileExtension = 'csv';
      }
      
      // 选择保存路径
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出生词本',
        fileName: 'vocabulary_export_${DateTime.now().toString().split(' ')[0]}.$fileExtension',
        type: FileType.custom,
        allowedExtensions: [fileExtension],
      );
      
      if (savePath != null) {
        // 保存文件
        final result = await vocabularyService.saveVocabularyToFile(content, savePath);
        if (result != null) {
          messageService.showMessage('生词本已导出到: $savePath');
        } else {
          messageService.showMessage('导出失败');
        }
      }
    } catch (e) {
      messageService.showMessage('导出失败: $e');
      debugPrint('导出生词本失败: $e');
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
    
    return Column(
      children: [
        // 顶部控制栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              // 视图切换按钮
              ToggleButtons(
                isSelected: [!_isTileMode, _isTileMode],
                onPressed: (index) {
                  setState(() {
                    _isTileMode = index == 1;
                  });
                },
                borderRadius: BorderRadius.circular(8.0),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text('分组视图'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text('平铺视图'),
                  ),
                ],
              ),
              const Spacer(),
              // 导出按钮
              ElevatedButton.icon(
                onPressed: _exportVocabulary,
                icon: const Icon(Icons.download),
                label: const Text('导出'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        
        // 生词本内容
        Expanded(
          child: _isTileMode
              ? _buildTileView(vocabularyLists)
              : _buildGroupView(vocabularyLists, currentVideoName),
        ),
      ],
    );
  }
  
  // 构建分组视图
  Widget _buildGroupView(Map<String, VocabularyList> vocabularyLists, String? currentVideoName) {
    // 过滤掉没有生词的视频
    final filteredLists = vocabularyLists.entries
        .where((entry) => entry.value.words.isNotEmpty)
        .toList();
    
    if (filteredLists.isEmpty) {
      return const Center(
        child: Text('生词本为空', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return ListView.builder(
      itemCount: filteredLists.length,
      itemBuilder: (context, index) {
        final videoName = filteredLists[index].key;
        final vocabularyList = filteredLists[index].value;
        
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
                    title: SelectableText(
                      word.word, 
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      toolbarOptions: const ToolbarOptions(
                        copy: true,
                        selectAll: true,
                        cut: false,
                        paste: false,
                      ),
                    ),
                    subtitle: Text(
                      word.context,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: '复制单词',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: word.word));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已复制: ${word.word}'), duration: const Duration(seconds: 1))
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          tooltip: '删除',
                          onPressed: () {
                            final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
                            vocabularyService.removeWord(videoName, word.word);
                          },
                        ),
                      ],
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
  
  // 构建平铺视图
  Widget _buildTileView(Map<String, VocabularyList> vocabularyLists) {
    final vocabularyService = Provider.of<VocabularyService>(context);
    // 获取所有单词
    final allWords = vocabularyService.getAllWords();
    
    if (allWords.isEmpty) {
      return const Center(
        child: Text('生词本为空', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return ListView.builder(
      itemCount: allWords.length,
      itemBuilder: (context, index) {
        final word = allWords[index];
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: ListTile(
            title: SelectableText(
              word.word,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.context,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '来源: ${_getVideoNameForWord(vocabularyLists, word)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制单词',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: word.word));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制: ${word.word}'), duration: const Duration(seconds: 1))
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: '删除',
                  onPressed: () {
                    final videoName = _getVideoNameForWord(vocabularyLists, word);
                    if (videoName != null) {
                      final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
                      vocabularyService.removeWord(videoName, word.word);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // 获取单词所属的视频名称
  String? _getVideoNameForWord(Map<String, VocabularyList> vocabularyLists, VocabularyWord targetWord) {
    for (final videoName in vocabularyLists.keys) {
      final list = vocabularyLists[videoName]!;
      for (final word in list.words) {
        if (word.word == targetWord.word && word.context == targetWord.context) {
          return videoName;
        }
      }
    }
    return null;
  }
} 