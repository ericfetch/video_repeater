import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';
import '../models/vocabulary_model.dart';
import '../services/dictionary_service.dart';
import '../models/dictionary_word.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

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
  
  @override
  Widget build(BuildContext context) {
    // 获取服务但不监听变化
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    
    // 获取单词列表（现在有缓存，不会频繁触发数据库访问）
    final allWords = vocabularyService.getAllWords();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本'),
        actions: [
          if (_isSelectionMode) ...[
            // 选择模式下的操作按钮
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制选中单词',
              onPressed: _selectedWords.isNotEmpty ? _copySelectedWords : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: '删除选中单词',
              onPressed: _selectedWords.isNotEmpty ? _deleteSelectedWords : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            // 导入按钮
            IconButton(
              icon: const Icon(Icons.file_upload),
              tooltip: '导入生词本备份',
              onPressed: _importFromFile,
            ),
            // 导出按钮
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '导出生词本备份',
              onPressed: _exportJsonBackup,
            ),
            // 其他操作菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'export_txt') {
                  // 导出为文本
                  final content = vocabularyService.exportVocabularyAsText();
                  _saveToFile(content, 'vocabulary.txt');
                } else if (value == 'export_csv') {
                  // 导出为CSV
                  final content = vocabularyService.exportVocabularyAsCSV();
                  _saveToFile(content, 'vocabulary.csv');
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
        ],
      ),
      body: Column(
        children: [
          // 词典搜索栏
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '搜索单词',
                hintText: '输入要查询的单词',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          
          // 标签过滤器
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // 全部标签
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: FilterChip(
                        label: const Text('全部'),
                        selected: _selectedTag == null,
                        onSelected: (_) {
                          setState(() {
                            _selectedTag = null;
                          });
                        },
                      ),
                    ),
                    
                    // 视频标签
                    for (final tag in _tags)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: FilterChip(
                          label: Text(tag),
                          selected: _selectedTag == tag,
                          onSelected: (_) {
                            setState(() {
                              _selectedTag = tag;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
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