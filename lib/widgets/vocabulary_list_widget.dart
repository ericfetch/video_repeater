import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../models/vocabulary_model.dart';

class VocabularyListWidget extends StatefulWidget {
  final Function(String)? onWordSelected;
  final bool showControls;
  
  const VocabularyListWidget({
    super.key,
    this.onWordSelected,
    this.showControls = true,
  });

  @override
  State<VocabularyListWidget> createState() => _VocabularyListWidgetState();
}

class _VocabularyListWidgetState extends State<VocabularyListWidget> {
  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  // 选中的单词
  final Set<String> _selectedWords = {};
  // 当前显示的字母
  String? _currentLetter;
  // 是否显示删除确认对话框
  bool _showDeleteConfirmation = false;
  // 缓存单词列表，避免频繁重建
  List<VocabularyWord> _allWords = [];
  
  @override
  void initState() {
    super.initState();
    _loadWords();
  }
  
  // 在初始化时加载单词列表
  void _loadWords() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    _allWords = vocabularyService.getAllWords(isActive: true);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // 根据搜索关键词筛选单词
    final filteredWords = _filterWords(_allWords);
    
    // 如果没有单词，显示空状态
    if (filteredWords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.book, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                ? '生词本为空'
                : '没有找到匹配的单词',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_searchController.text.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: const Text('清除搜索'),
              ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        if (widget.showControls) ...[
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '搜索单词',
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
          
          // 字母筛选器
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 全部按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: const Text('全部'),
                    selected: _currentLetter == null,
                    onSelected: (_) {
                      setState(() {
                        _currentLetter = null;
                      });
                    },
                  ),
                ),
                
                // 字母按钮
                for (int i = 0; i < 26; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: FilterChip(
                      label: Text(String.fromCharCode(65 + i)),
                      selected: _currentLetter == String.fromCharCode(97 + i),
                      onSelected: (_) {
                        setState(() {
                          _currentLetter = String.fromCharCode(97 + i);
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          
          // 操作按钮
          if (_selectedWords.isNotEmpty)
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
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showDeleteConfirmation = true;
                      });
                    },
                    child: const Text('删除选中'),
                  ),
                ],
              ),
            ),
          
          const Divider(),
        ],
        
        // 单词列表
        Expanded(
          child: ListView.builder(
            itemCount: filteredWords.length,
            itemBuilder: (context, index) {
              final word = filteredWords[index];
              final isSelected = _selectedWords.contains(word.word);
              
              return ListTile(
                title: _buildWordDisplay(word.word, context),
                subtitle: word.context.isNotEmpty ? Text(word.context) : null,
                trailing: widget.showControls
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
                  : null,
                onTap: widget.onWordSelected != null
                  ? () => widget.onWordSelected!(word.word)
                  : null,
                onLongPress: widget.showControls
                  ? () {
                      setState(() {
                        if (isSelected) {
                          _selectedWords.remove(word.word);
                        } else {
                          _selectedWords.add(word.word);
                        }
                      });
                    }
                  : null,
              );
            },
          ),
        ),
        
        // 删除确认对话框
        if (_showDeleteConfirmation)
          _buildDeleteConfirmationDialog(),
      ],
    );
  }
  
  // 筛选单词
  List<VocabularyWord> _filterWords(List<VocabularyWord> words) {
    // 首先按字母筛选
    List<VocabularyWord> filtered = words;
    
    if (_currentLetter != null) {
      filtered = filtered.where((word) => 
        word.word.toLowerCase().startsWith(_currentLetter!)
      ).toList();
    }
    
    // 然后按搜索关键词筛选
    if (_searchController.text.isNotEmpty) {
      final searchText = _searchController.text.toLowerCase();
      filtered = filtered.where((word) => 
        word.word.toLowerCase().contains(searchText) ||
        word.context.toLowerCase().contains(searchText)
      ).toList();
    }
    
    // 按字母顺序排序
    filtered.sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
    
    return filtered;
  }
  
  // 构建删除确认对话框
  Widget _buildDeleteConfirmationDialog() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    
    return AlertDialog(
      title: const Text('确认删除'),
      content: Text('确定要删除选中的 ${_selectedWords.length} 个单词吗？'),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _showDeleteConfirmation = false;
            });
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            debugPrint('开始删除选中的单词，共 ${_selectedWords.length} 个');
            
            // 获取所有单词及其所属的视频
            final wordToVideoMap = <String, String>{};
            
            // 建立单词到视频的映射
            for (final word in _allWords) {
              if (_selectedWords.contains(word.word)) {
                wordToVideoMap[word.word] = word.videoName;
              }
            }
            
            // 关闭对话框
            setState(() {
              _showDeleteConfirmation = false;
            });
            
            // 删除单词
            for (final entry in wordToVideoMap.entries) {
              final word = entry.key;
              final videoName = entry.value;
              debugPrint('尝试从生词本"$videoName"中删除单词: $word');
              await vocabularyService.removeWord(videoName, word);
            }
            
            // 重新加载单词列表
            setState(() {
              _selectedWords.clear();
              _allWords = vocabularyService.getAllWords(isActive: true);
            });
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
  
  // 构建单词显示
  Widget _buildWordDisplay(String word, BuildContext context) {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final dictWord = dictionaryService.getWord(word);
    final isInDictionary = dictWord != null;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        // 单词本身
        SelectableText(
          word,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        
        // 如果单词在词典库中，显示五角星标识
        if (isInDictionary)
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Icon(
              Icons.star,
              size: 16,
              color: Colors.amber,
            ),
          ),
        
        // 如果有词典释义，显示在单词后面
        if (dictWord != null) ...[
          const SizedBox(width: 8),
          const Text('·', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(width: 8),
          
          // 词性标签（如果有）
          if (dictWord.partOfSpeech != null && dictWord.partOfSpeech!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.blueGrey[700] : Colors.blueGrey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                dictWord.partOfSpeech!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          
          // 简短释义
          Expanded(
            child: Text(
              dictWord.definition ?? '',
              style: TextStyle(
                color: isDarkMode ? Colors.blue[200] : Colors.blue[800],
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
  
  // 刷新单词列表
  void refreshWordList() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    setState(() {
      _allWords = vocabularyService.getAllWords(isActive: true);
    });
  }
} 