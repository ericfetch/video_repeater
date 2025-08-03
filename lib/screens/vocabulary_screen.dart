import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/vocabulary_service.dart';
import '../models/vocabulary_model.dart';
import '../services/dictionary_service.dart';
import '../models/dictionary_word.dart';
import '../services/translation_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  bool _isSelectionMode = false;
  Set<String> _selectedWords = {};
  TextEditingController _searchController = TextEditingController();
  List<String> _tags = [];
  String? _selectedTag;
  
  // 是否已显示复习提示
  bool _hasShownReviewTip = false;
  
  // 按天统计的单词数据
  Map<DateTime, int> _wordsByDate = {};
  
  // 创建AudioPlayer实例
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // 当前正在复习的单词列表和索引
  List<VocabularyWord> _reviewWords = [];
  int _currentReviewIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }
  
  Future<void> _loadVocabulary() async {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    if (!vocabularyService.isVocabularyLoaded()) {
      await vocabularyService.initialize();
      await vocabularyService.loadAllVocabularyLists();
    }
    
    // 加载按天统计的单词数据
    _calculateWordsByDate();
  }
  
  // 计算按天统计的单词数量
  void _calculateWordsByDate() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final allWords = vocabularyService.getAllWords();
    
    // 按天分组统计单词数量
    final wordsByDate = <DateTime, int>{};
    for (final word in allWords) {
      // 只保留日期部分，忽略时间
      final date = DateTime(
        word.addedTime.year,
        word.addedTime.month,
        word.addedTime.day,
      );
      
      wordsByDate[date] = (wordsByDate[date] ?? 0) + 1;
    }
    
    setState(() {
      _wordsByDate = wordsByDate;
    });
  }
  
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedWords.clear();
      }
    });
  }
  
  void _toggleWordSelection(String word) {
    setState(() {
      if (_selectedWords.contains(word)) {
        _selectedWords.remove(word);
      } else {
        _selectedWords.add(word);
      }
    });
  }
  
  Future<void> _deleteSelectedWords() async {
    if (_selectedWords.isEmpty) return;
    
    debugPrint('开始删除选中的单词，共 ${_selectedWords.length} 个');
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final allWords = vocabularyService.getAllWords();
    
    // 确认删除
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedWords.length} 个单词吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirmed) {
      debugPrint('用户取消删除');
      return;
    }
    
    debugPrint('用户确认删除');
    
    // 建立单词到视频的映射
    final wordToVideoMap = <String, String>{};
    for (final word in allWords) {
      if (_selectedWords.contains(word.word)) {
        wordToVideoMap[word.word] = word.videoName;
        debugPrint('将删除单词: ${word.word}, 视频: ${word.videoName}');
      }
    }
    
    if (wordToVideoMap.isEmpty) {
      debugPrint('没有找到要删除的单词');
      setState(() {
        _selectedWords.clear();
        _isSelectionMode = false;
      });
      return;
    }
    
    // 显示进度指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在删除单词...'),
          ],
        ),
      ),
    );
    
    try {
      // 删除选中的单词
      for (final entry in wordToVideoMap.entries) {
        final word = entry.key;
        final videoName = entry.value;
        debugPrint('删除单词: $word, 视频: $videoName');
        await vocabularyService.removeWord(videoName, word);
      }
      
      // 关闭进度指示器
      if (mounted) Navigator.of(context).pop();
      
      // 清空选择并退出选择模式
      setState(() {
        _selectedWords.clear();
        _isSelectionMode = false;
      });
      
      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 ${wordToVideoMap.length} 个单词'),
          backgroundColor: Colors.green,
        ),
      );
      
      debugPrint('删除完成');
    } catch (e) {
      // 关闭进度指示器
      if (mounted) Navigator.of(context).pop();
      
      // 显示错误消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除单词时出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
      
      debugPrint('删除失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  Future<void> _copySelectedWords() async {
    if (_selectedWords.isEmpty) return;
    
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final allWords = vocabularyService.getAllWords();
    
    // 构建要复制的文本
    final buffer = StringBuffer();
    for (final word in allWords) {
      if (_selectedWords.contains(word.word)) {
        buffer.writeln(word.word);
      }
    }
    
    // 复制到剪贴板
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    
    // 显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${_selectedWords.length} 个单词到剪贴板'),
        backgroundColor: Colors.green,
      ),
    );
    
    // 退出选择模式
    setState(() {
      _selectedWords.clear();
      _isSelectionMode = false;
    });
  }
  
  void _copyWord(String word) {
    Clipboard.setData(ClipboardData(text: word));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $word'),
        backgroundColor: Colors.blue,
      ),
    );
  }
  
  // 显示编辑单词对话框
  void _showEditWordDialog(BuildContext context, VocabularyWord word) {
    final TextEditingController wordController = TextEditingController(text: word.word);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑单词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wordController,
              decoration: const InputDecoration(
                labelText: '单词',
                hintText: '输入正确的单词形式',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '原始单词: ${word.word}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '上下文: ${word.context}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newWord = wordController.text.trim();
              if (newWord.isEmpty || newWord == word.word) {
                Navigator.of(context).pop();
                return;
              }
              
              final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
              
              // 创建新的单词对象
              final updatedWord = VocabularyWord(
                word: newWord,
                context: word.context,
                addedTime: word.addedTime,
                videoName: word.videoName,
                audioPath: word.audioPath, // 保留音频路径
              );
              
              // 删除旧单词并添加新单词
              await vocabularyService.removeWord(word.videoName, word.word);
              await vocabularyService.addWordDirectly(word.videoName, updatedWord);
              
              Navigator.of(context).pop();
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  // 保存文件到本地
  Future<void> _saveToFile(String content, String defaultFileName) async {
    try {
      // 让用户选择保存位置
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: defaultFileName,
      );
      
      if (outputPath == null) {
        // 用户取消了选择
        return;
      }
      
      // 保存文件
      final file = File(outputPath);
      await file.writeAsString(content);
      
      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('文件已保存到: $outputPath'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('保存文件失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      
      // 显示错误消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存文件失败: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 导出JSON备份
  Future<void> _exportJsonBackup() async {
    try {
      // 让用户选择保存位置
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存生词本备份',
        fileName: 'vocabulary_backup.json',
      );
      
      if (outputPath == null) {
        // 用户取消了选择
        return;
      }
      
      // 显示进度指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在导出数据...'),
            ],
          ),
        ),
      );
      
      try {
        final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
        final content = vocabularyService.exportVocabularyAsJSON();
        
        // 保存到用户选择的位置
        final file = File(outputPath);
        await file.writeAsString(content);
        
        // 关闭进度指示器
        if (mounted) Navigator.of(context).pop();
        
        // 显示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生词本已保存到: $outputPath'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        // 确保进度指示器被关闭
        if (mounted) Navigator.of(context).pop();
        
        debugPrint('导出JSON备份失败: $e');
        debugPrintStack(stackTrace: StackTrace.current);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出JSON备份失败: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('选择保存位置失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择保存位置失败: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 从文件导入数据
  Future<void> _importFromFile() async {
    try {
      // 让用户选择要导入的文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择生词本备份文件',
      );
      
      if (result == null || result.files.single.path == null) {
        // 用户取消了选择
        return;
      }
      
      final filePath = result.files.single.path!;
      
      // 显示进度指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在导入数据...'),
            ],
          ),
        ),
      );
      
      try {
        final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
        
        // 读取文件内容
        final file = File(filePath);
        final content = await file.readAsString();
        
        // 导入数据
        final results = await vocabularyService.importVocabularyFromJSON(content);
        
        // 关闭进度指示器
        if (mounted) Navigator.of(context).pop();
        
        // 显示结果
        if (results.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('导入失败: ${results['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功导入 ${results['lists']} 个生词本，共 ${results['words']} 个单词'),
              backgroundColor: Colors.green,
            ),
          );
          // 刷新界面
          setState(() {});
        }
      } catch (e) {
        // 确保进度指示器被关闭
        if (mounted) Navigator.of(context).pop();
        
        debugPrint('导入数据处理失败: $e');
        debugPrintStack(stackTrace: StackTrace.current);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入数据处理失败: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('选择导入文件失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择导入文件失败: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 修复数据库部分
  Future<void> _repairDatabase() async {
    // 显示进度指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检查和修复数据库...'),
          ],
        ),
      ),
    );
    
    try {
      final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
      final results = await vocabularyService.safeRepairVocabularyData();
      
      // 关闭进度指示器
      if (mounted) Navigator.of(context).pop();
      
      if (results['fixedLists']! > 0 || results['fixedWords']! > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据库修复完成，修复了 ${results['fixedLists']} 个生词本和 ${results['fixedWords']} 个单词'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('数据库检查完成，未发现问题'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      setState(() {});
    } catch (e) {
      // 关闭进度指示器
      if (mounted) Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('修复数据库时出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('修复数据库失败: $e');
      debugPrintStack(stackTrace: StackTrace.current);
    }
  }
  
  // 播放音频文件
  Future<void> _playAudio(String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可用的音频'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      // 检查文件是否存在
      final file = File(audioPath);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('音频文件不存在: $audioPath'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // 播放音频
      await _audioPlayer.stop(); // 停止当前播放
      await _audioPlayer.play(DeviceFileSource(audioPath));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在播放音频'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('播放音频失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('播放音频失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 检查是否有复习正在进行
  bool _isReviewInProgress() {
    return _reviewWords.isNotEmpty && _currentReviewIndex < _reviewWords.length;
  }
  
  // 开始自动复习
  void _startAutoReview() {
    // 始终重置复习状态，确保每次都是全新开始
    _reviewWords = [];
    _currentReviewIndex = 0;
    
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final allWords = vocabularyService.getAllWords();
    
    if (allWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('生词本为空，无法开始复习'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 随机打乱单词顺序
    _reviewWords = List.from(allWords)..shuffle();
    _currentReviewIndex = 0;
    
    // 显示第一个单词
    _showReviewDialog();
  }
  
  // 显示复习对话框
  void _showReviewDialog() {
    if (_reviewWords.isEmpty || _currentReviewIndex >= _reviewWords.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('复习完成！'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    
    final currentWord = _reviewWords[_currentReviewIndex];
    
    // 如果有音频，自动播放
    if (currentWord.audioPath != null && currentWord.audioPath!.isNotEmpty) {
      _playAudio(currentWord.audioPath);
    }
    
    // 标记正在导航到下一个单词，防止对话框关闭时错误地重置状态
    bool isNavigatingToNext = false;
    
    // 翻译相关的状态变量
    bool isTranslating = false;
    String? translatedText;
    
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        // 使用StatefulBuilder以便能够在对话框内更新状态
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '复习单词 (${_currentReviewIndex + 1}/${_reviewWords.length})',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            // 关闭按钮
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                // 中断复习，重置状态
                _reviewWords = [];
                _currentReviewIndex = 0;
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('复习已中断，下次将重新开始'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),
          ],
        ),
              content: SingleChildScrollView(
                child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  currentWord.word,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 复制按钮 - 无提示
                IconButton(
                  icon: const Icon(Icons.content_copy, size: 18),
                  tooltip: '复制单词',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: currentWord.word));
                    // 不显示提示
                  },
                ),
              ],
            ),
            // 显示记忆次数
            Text(
              '已记住: ${currentWord.rememberedCount}次',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '上下文: ${currentWord.context}',
              style: const TextStyle(fontSize: 16),
            ),
                    const SizedBox(height: 8),
                    
                    // 添加翻译按钮和翻译结果显示区域
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.translate),
                          label: Text(isTranslating ? '翻译中...' : '翻译上下文'),
                          onPressed: isTranslating ? null : () async {
                            // 设置翻译中状态
                            setState(() {
                              isTranslating = true;
                            });
                            
                            try {
                              // 获取翻译服务
                              final translationService = Provider.of<TranslationService>(dialogContext, listen: false);
                              // 翻译上下文文本
                              final translated = await translationService.translateText(
                                text: currentWord.context,
                              );
                              
                              // 更新翻译结果
                              setState(() {
                                translatedText = translated;
                                isTranslating = false;
                              });
                            } catch (e) {
                              // 翻译失败
                              setState(() {
                                translatedText = "翻译失败: $e";
                                isTranslating = false;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    
                    // 显示翻译结果
                    if (translatedText != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '翻译:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              translatedText!,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
            const SizedBox(height: 8),
            Text(
              '视频: ${currentWord.videoName}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (currentWord.audioPath != null && currentWord.audioPath!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.volume_up),
                label: const Text('重新播放音频'),
                onPressed: () => _playAudio(currentWord.audioPath),
              ),
            ],
          ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              isNavigatingToNext = true;
              Navigator.of(context).pop();
              _currentReviewIndex++;
              
              // 如果还有单词，继续复习
              if (_currentReviewIndex < _reviewWords.length) {
                _showReviewDialog();
              } else {
                // 复习完成，重置状态
                _reviewWords = [];
                _currentReviewIndex = 0;
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('复习完成！'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('不记得'),
          ),
          ElevatedButton(
            onPressed: () async {
              final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
              final currentWord = _reviewWords[_currentReviewIndex];
              
              // 增加记忆次数
              await vocabularyService.increaseRememberedCount(
                currentWord.videoName,
                currentWord.word,
              );
              
              // 标记正在导航到下一个单词
              isNavigatingToNext = true;
              Navigator.of(context).pop();
              _currentReviewIndex++;
              
              // 如果还有单词，继续复习
              if (_currentReviewIndex < _reviewWords.length) {
                _showReviewDialog();
              } else {
                // 复习完成，重置状态
                _reviewWords = [];
                _currentReviewIndex = 0;
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('复习完成！'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('记得'),
          ),
        ],
            );
          }
        );
      },
    ).then((_) {
      // 对话框关闭时（包括通过返回按钮关闭），重置状态
      // 但如果是正在导航到下一个单词，则不重置
      if (_reviewWords.isNotEmpty && !isNavigatingToNext) {
        _reviewWords = [];
        _currentReviewIndex = 0;
      }
    });
  }
  
  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    // 重置复习状态
    _reviewWords = [];
    _currentReviewIndex = 0;
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final vocabularyService = Provider.of<VocabularyService>(context);
    final allWords = vocabularyService.getAllWords(isActive: true);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本'),
        actions: [
          // 自动复习按钮
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.auto_stories),
              tooltip: '自动复习（随机显示单词，记住10次后自动标记为熟知）',
              onPressed: () {
                // 显示提示对话框，解释功能
                if (!_hasShownReviewTip) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('自动复习功能'),
                      content: const Text(
                        '自动复习将随机显示您的生词本中的单词和上下文，'
                        '如果有音频将自动播放。\n\n'
                        '每次您选择"记得"，系统会记录下来，当一个单词被记住10次后，'
                        '它将被标记为熟知并从生词本中移除。\n\n'
                        '您可以随时中断复习，下次将重新开始。'
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // 标记已显示提示
                            _hasShownReviewTip = true;
                            // 开始复习
                            _startAutoReview();
                          },
                          child: const Text('开始复习'),
                        ),
                      ],
                    ),
                  );
                } else {
                  // 直接开始复习
                  _startAutoReview();
                }
              },
            ),
          
          // 选择模式切换按钮
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            onPressed: _toggleSelectionMode,
          ),
          
          // 复制选中单词按钮
          if (_isSelectionMode && _selectedWords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copySelectedWords,
            ),
          
          // 导入按钮
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.file_upload),
              tooltip: '导入生词本备份',
              onPressed: _importFromFile,
            ),
            
          // 导出按钮
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '导出生词本备份',
              onPressed: _exportJsonBackup,
            ),
          
          // 更多操作按钮
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'export_txt') {
                // 导出为文本
                final content = vocabularyService.exportVocabularyAsText();
                await _saveToFile(content, 'vocabulary.txt');
              } else if (value == 'export_csv') {
                // 导出为CSV
                final content = vocabularyService.exportVocabularyAsCSV();
                await _saveToFile(content, 'vocabulary.csv');
              } else if (value == 'export_json') {
                // 导出JSON备份
                await _exportJsonBackup();
              } else if (value == 'import_json') {
                // 导入JSON备份
                await _importFromFile();
              } else if (value == 'clear') {
                // 清空生词本
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('确定要清空所有生词本吗？此操作不可撤销。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ) ?? false;
                
                if (confirmed) {
                  await vocabularyService.clearVocabulary();
                  setState(() {});
                }
              } else if (value == 'repair') {
                // 修复数据库
                await _repairDatabase();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'export_txt',
                child: Text('导出为文本'),
              ),
              const PopupMenuItem<String>(
                value: 'export_csv',
                child: Text('导出为CSV'),
              ),
              const PopupMenuItem<String>(
                value: 'export_json',
                child: Text('导出JSON备份'),
              ),
              const PopupMenuItem<String>(
                value: 'import_json',
                child: Text('导入JSON备份'),
              ),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Text('清空生词本'),
              ),
              const PopupMenuItem<String>(
                value: 'repair',
                child: Text('修复数据库'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 按天统计的单词数量曲线图
          if (_wordsByDate.isNotEmpty)
            Container(
              height: 150, // 控制图表高度不要太高
              padding: const EdgeInsets.all(8.0),
              child: _buildWordsChart(),
            ),
            
          // 选择工具栏
          if (_isSelectionMode && _selectedWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Text('已选择 ${_selectedWords.length} 个单词'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedWords.clear();
                      });
                    },
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
          
          // 单词列表
          Expanded(
            child: _buildWordList(allWords),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
        ? FloatingActionButton(
            onPressed: _selectedWords.isNotEmpty ? _deleteSelectedWords : null,
            backgroundColor: _selectedWords.isNotEmpty ? null : Colors.grey,
            child: const Icon(Icons.delete),
          )
        : null,
    );
  }
  
  // 构建单词数量曲线图
  Widget _buildWordsChart() {
    // 如果没有数据，显示提示
    if (_wordsByDate.isEmpty) {
      return const Center(child: Text('没有单词数据'));
    }
    
    // 获取最近30天的数据
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    // 按日期排序的数据点
    final sortedData = _wordsByDate.entries
        .where((entry) => entry.key.isAfter(thirtyDaysAgo))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    // 如果没有最近30天的数据，显示提示
    if (sortedData.isEmpty) {
      return const Center(child: Text('最近30天没有新增单词'));
    }
    
    // 准备曲线图数据
    final spots = <FlSpot>[];
    for (int i = 0; i < sortedData.length; i++) {
      spots.add(FlSpot(i.toDouble(), sortedData[i].value.toDouble()));
    }
    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white24,
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.white24,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value % 5 == 0 && value.toInt() < sortedData.length) {
                    final date = sortedData[value.toInt()].key;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '${date.day}/${date.month}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  );
                },
                reservedSize: 42,
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.white38),
          ),
          minX: 0,
          maxX: (sortedData.length - 1).toDouble(),
          minY: 0,
          maxY: sortedData.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() * 1.2,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.cyan,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
              ),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.cyan.withOpacity(0.3),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.x.toInt();
                  if (index >= 0 && index < sortedData.length) {
                    final date = sortedData[index].key;
                    return LineTooltipItem(
                      '${date.day}/${date.month}: ${spot.y.toInt()}个单词',
                      const TextStyle(color: Colors.white),
                    );
                  }
                  return null;
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildWordList(List<VocabularyWord> words) {
    if (words.isEmpty) {
      return const Center(child: Text('生词本为空'));
    }

    // 获取服务但不监听变化
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);

    return ListView.builder(
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        
        // 尝试从词典获取更多信息
        final dictionaryWord = dictionaryService.getWord(word.word);
        final isSelected = _selectedWords.contains(word.word);
        final isInDictionary = dictionaryWord != null;
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            title: Text(
              word.word,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (word.context.isNotEmpty)
                  Text(
                    '上下文: ${word.context}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text('来源: ${word.videoName}'),
                if (dictionaryWord != null) ...[
                  if (dictionaryWord.definition != null && dictionaryWord.definition!.isNotEmpty)
                    Text(
                      '释义: ${dictionaryWord.definition}',
                      style: const TextStyle(color: Colors.blue),
                    ),
                  if (dictionaryWord.phonetic != null && dictionaryWord.phonetic!.isNotEmpty)
                    Text(
                      '音标: [${dictionaryWord.phonetic}]',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ],
            ),
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedWords.add(word.word);
                        } else {
                          _selectedWords.remove(word.word);
                        }
                      });
                    },
                  )
                : isInDictionary
                    ? const Icon(Icons.star, color: Colors.amber)
                    : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 音频播放按钮
                if (word.audioPath != null && word.audioPath!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.volume_up, color: Colors.blue),
                    tooltip: '播放音频',
                    onPressed: () => _playAudio(word.audioPath),
                  ),
                IconButton(
                  icon: const Icon(Icons.content_copy),
                  tooltip: '复制单词',
                  onPressed: () => _copyWord(word.word),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditWordDialog(context, word),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除单词 "${word.word}" 吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ) ?? false;
                    
                    if (confirmed) {
                      await vocabularyService.removeWord(word.videoName, word.word);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            onTap: _isSelectionMode
                ? () {
                    setState(() {
                      if (isSelected) {
                        _selectedWords.remove(word.word);
                      } else {
                        _selectedWords.add(word.word);
                      }
                    });
                  }
                : () {
                    // 显示单词详情
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Row(
                          children: [
                            Expanded(child: Text(word.word)),
                            if (isInDictionary)
                              const Icon(Icons.star, color: Colors.amber),
                          ],
                        ),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (dictionaryWord != null) ...[
                                if (dictionaryWord.partOfSpeech != null)
                                  Text('词性: ${dictionaryWord.partOfSpeech}'),
                                if (dictionaryWord.definition != null)
                                  Text('释义: ${dictionaryWord.definition}'),
                                if (dictionaryWord.phonetic != null)
                                  Text('音标: ${dictionaryWord.phonetic}'),
                                if (dictionaryWord.cefr != null)
                                  Text('CEFR等级: ${dictionaryWord.cefr}'),
                                const SizedBox(height: 8),
                              ],
                              Text('上下文: ${word.context}'),
                              Text('视频: ${word.videoName}'),
                              Text('添加时间: ${word.addedTime.toString().split('.')[0]}'),
                              if (word.audioPath != null && word.audioPath!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.volume_up),
                                  label: const Text('播放音频'),
                                  onPressed: () => _playAudio(word.audioPath),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
            onLongPress: () {
              if (!_isSelectionMode) {
                setState(() {
                  _isSelectionMode = true;
                  _selectedWords.add(word.word);
                });
              }
            },
          ),
        );
      },
    );
  }
} 