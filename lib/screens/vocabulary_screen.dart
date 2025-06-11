import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';
import '../models/vocabulary_model.dart';
import '../services/dictionary_service.dart';
import '../models/dictionary_word.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  bool _isSelectionMode = false;
  Set<String> _selectedWords = {};
  
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
    
    if (!confirmed) return;
    
    // 删除选中的单词
    for (final word in allWords) {
      if (_selectedWords.contains(word.word)) {
        await vocabularyService.removeWord(word.videoName, word.word);
      }
    }
    
    // 清空选择并退出选择模式
    setState(() {
      _selectedWords.clear();
      _isSelectionMode = false;
    });
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
        duration: const Duration(seconds: 2),
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
        duration: const Duration(seconds: 1),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final vocabularyService = Provider.of<VocabularyService>(context);
    final dictionaryService = Provider.of<DictionaryService>(context);
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
            // 正常模式下的菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'export_txt') {
                  // 导出为文本
                  final content = vocabularyService.exportVocabularyAsText();
                  // 保存文件逻辑
                } else if (value == 'export_csv') {
                  // 导出为CSV
                  final content = vocabularyService.exportVocabularyAsCSV();
                  // 保存文件逻辑
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
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 功能区域
          if (!_isSelectionMode)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.select_all, size: 18),
                    label: const Text('选择模式'),
                    onPressed: _toggleSelectionMode,
                  ),
                  const SizedBox(width: 12),
                  ActionChip(
                    avatar: const Icon(Icons.copy, size: 18),
                    label: const Text('复制全部'),
                    onPressed: () {
                      final words = allWords.map((w) => w.word).join('\n');
                      Clipboard.setData(ClipboardData(text: words));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制所有单词到剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          
          // 单词列表
          Expanded(
            child: allWords.isEmpty
                ? const Center(child: Text('生词本为空'))
                : ListView.builder(
                    itemCount: allWords.length,
                    itemBuilder: (context, index) {
                      final word = allWords[index];
                      
                      // 尝试从词典获取更多信息
                      DictionaryWord? dictWord;
                      bool isInDictionary = false;
                      if (dictionaryService.isInitialized) {
                        dictWord = dictionaryService.getWord(word.word);
                        isInDictionary = dictWord != null;
                      }
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: _selectedWords.contains(word.word),
                                  onChanged: (_) => _toggleWordSelection(word.word),
                                )
                              : isInDictionary
                                  ? const Icon(Icons.star, color: Colors.amber)
                                  : null,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  word.word,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (!_isSelectionMode) ...[
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  tooltip: '复制单词',
                                  onPressed: () => _copyWord(word.word),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  tooltip: '删除单词',
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
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dictWord != null && dictWord.definition != null)
                                Text(
                                  dictWord.definition!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                '来源: ${word.context}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '视频: ${word.videoName}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '添加时间: ${word.addedTime.toString().split('.')[0]}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: _isSelectionMode
                              ? () => _toggleWordSelection(word.word)
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
                                          IconButton(
                                            icon: const Icon(Icons.copy),
                                            tooltip: '复制单词',
                                            onPressed: () {
                                              _copyWord(word.word);
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ],
                                      ),
                                      content: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (dictWord != null) ...[
                                              if (dictWord.partOfSpeech != null)
                                                Text('词性: ${dictWord.partOfSpeech}'),
                                              if (dictWord.definition != null)
                                                Text('释义: ${dictWord.definition}'),
                                              if (dictWord.phonetic != null)
                                                Text('音标: ${dictWord.phonetic}'),
                                              if (dictWord.cefr != null)
                                                Text('CEFR等级: ${dictWord.cefr}'),
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode && _selectedWords.isNotEmpty
          ? FloatingActionButton(
              onPressed: _deleteSelectedWords,
              tooltip: '删除选中',
              child: const Icon(Icons.delete),
            )
          : null,
    );
  }
} 