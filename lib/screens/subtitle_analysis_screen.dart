import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/video_service.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../models/subtitle_model.dart';
import 'dart:collection';

// 排序方式枚举
enum SortMethod { alphabetical, frequency }

class SubtitleAnalysisScreen extends StatefulWidget {
  final VideoService videoService;
  final VocabularyService vocabularyService;
  final DictionaryService dictionaryService;

  const SubtitleAnalysisScreen({
    Key? key,
    required this.videoService,
    required this.vocabularyService,
    required this.dictionaryService,
  }) : super(key: key);

  @override
  State<SubtitleAnalysisScreen> createState() => _SubtitleAnalysisScreenState();
}

class _SubtitleAnalysisScreenState extends State<SubtitleAnalysisScreen> {
  // 分析结果
  Map<String, int> _wordFrequency = {};
  bool _isAnalyzing = false;
  bool _isAnalyzed = false;
  String _videoTitle = '';
  int _totalWords = 0;
  int _uniqueWords = 0;
  int _knownWords = 0;
  int _vocabularyWords = 0;
  int _unknownWords = 0;
  int _familiarWords = 0;
  int _needsLearningWords = 0;
  
  // 临时标记为需要学习的单词（不持久化）
  Set<String> _tempNeedsLearning = {};
  
  // 过滤设置
  bool _showKnownWords = true;
  bool _showVocabularyWords = true;
  bool _showUnknownWords = true;
  bool _showFamiliarWords = true;
  bool _showNeedsLearningWords = true;
  String _searchQuery = '';
  
  // 排序方式
  SortMethod _sortMethod = SortMethod.frequency;
  
  @override
  void initState() {
    super.initState();
    _videoTitle = widget.videoService.videoTitle;
    _analyzeSubtitles();
  }
  
  // 分析字幕中的单词
  Future<void> _analyzeSubtitles() async {
    setState(() {
      _isAnalyzing = true;
      _isAnalyzed = false;
      _tempNeedsLearning = {}; // 重置临时标记
    });
    
    try {
      // 获取当前视频的字幕
      final subtitles = widget.videoService.subtitleData?.entries;
      if (subtitles == null || subtitles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前视频没有字幕，无法进行分析'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }
      
      // 分析字幕中的单词频率
      final wordFrequency = <String, int>{};
      final regex = RegExp(r'\b[a-zA-Z]+\b');
      
      for (final subtitle in subtitles) {
        final matches = regex.allMatches(subtitle.text.toLowerCase());
        for (final match in matches) {
          final word = match.group(0)!;
          if (word.length > 1) { // 忽略单个字母
            wordFrequency[word] = (wordFrequency[word] ?? 0) + 1;
          }
        }
      }
      
      // 统计数据
      _totalWords = 0;
      wordFrequency.forEach((_, count) => _totalWords += count);
      _uniqueWords = wordFrequency.length;
      
      // 分类统计
      _knownWords = 0;
      _vocabularyWords = 0;
      _unknownWords = 0;
      _familiarWords = 0;
      _needsLearningWords = 0;
      
      final vocabularyWords = widget.vocabularyService.getAllWords();
      final vocabularyWordSet = vocabularyWords.map((w) => w.word.toLowerCase()).toSet();
      
      wordFrequency.forEach((word, _) {
        if (widget.dictionaryService.isFamiliar(word)) {
          _familiarWords++;
        } else {
          // 不熟悉的单词自动标记为需要学习
          _tempNeedsLearning.add(word);
          _needsLearningWords++;
          
        if (widget.dictionaryService.getWord(word) != null) {
          _knownWords++;
        } else if (vocabularyWordSet.contains(word.toLowerCase())) {
          _vocabularyWords++;
        } else {
          _unknownWords++;
          }
        }
      });
      
      setState(() {
        _wordFrequency = wordFrequency;
        _isAnalyzing = false;
        _isAnalyzed = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('分析字幕时出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isAnalyzing = false;
      });
    }
  }
  
  // 获取排序和过滤后的单词列表
  List<MapEntry<String, int>> _getSortedFilteredWords() {
    if (_wordFrequency.isEmpty) {
      return [];
    }
    
    // 过滤单词
    final filteredWords = _wordFrequency.entries.where((entry) {
      final word = entry.key;
      final isFamiliar = widget.dictionaryService.isFamiliar(word);
      final needsLearning = _tempNeedsLearning.contains(word);
      final isKnown = !isFamiliar && widget.dictionaryService.getWord(word) != null;
      final isInVocabulary = widget.vocabularyService.getAllWords()
          .any((w) => w.word.toLowerCase() == word.toLowerCase());
      
      // 应用过滤条件
      if (!_showFamiliarWords && isFamiliar) return false;
      if (!_showNeedsLearningWords && needsLearning) return false;
      if (!_showKnownWords && isKnown) return false;
      if (!_showVocabularyWords && isInVocabulary) return false;
      if (!_showUnknownWords && !isKnown && !isInVocabulary && !isFamiliar && !needsLearning) return false;
      
      // 应用搜索查询
      if (_searchQuery.isNotEmpty && 
          !word.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      
      return true;
    }).toList();
    
    // 排序
    if (_sortMethod == SortMethod.alphabetical) {
      filteredWords.sort((a, b) => a.key.compareTo(b.key));
    } else {
      // 如果是按频率排序，先排需要学习的，然后排其他的，熟知单词排在最后
      filteredWords.sort((a, b) {
        final aIsFamiliar = widget.dictionaryService.isFamiliar(a.key);
        final bIsFamiliar = widget.dictionaryService.isFamiliar(b.key);
        final aNeedsLearning = _tempNeedsLearning.contains(a.key);
        final bNeedsLearning = _tempNeedsLearning.contains(b.key);
        
        // 熟知的单词排在最后
        if (aIsFamiliar && !bIsFamiliar) return 1;
        if (!aIsFamiliar && bIsFamiliar) return -1;
        
        // 需要学习的单词排在前面
        if (aNeedsLearning && !bNeedsLearning) return -1;
        if (!aNeedsLearning && bNeedsLearning) return 1;
        
        // 最后按频率排序
        return b.value.compareTo(a.value);
      });
    }
    
    return filteredWords;
  }
  
  // 复制单词到剪贴板
  void _copyWord(String word) {
    Clipboard.setData(ClipboardData(text: word));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $word'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ),
    );
  }
  
  // 添加单词到生词本
  void _addToVocabulary(String word) {
    if (widget.videoService.currentSubtitle != null) {
      final context = widget.videoService.currentSubtitle!.text;
      final videoName = widget.videoService.videoTitle;
      
      widget.vocabularyService.addWord(videoName, word, context);
      
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('已添加到生词本: $word'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
      
      // 刷新状态以更新UI
      setState(() {
        _vocabularyWords++;
        _unknownWords--;
      });
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('无法添加到生词本：当前没有字幕上下文'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 标记单词为熟知
  void _markAsFamiliar(String word) {
    widget.dictionaryService.markAsFamiliar(word);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已标记为熟知单词: $word'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ),
    );
    
    // 刷新状态以更新UI
    setState(() {
      _familiarWords++;
      _tempNeedsLearning.remove(word); // 从需要学习的列表中移除
      _needsLearningWords--;
      
      if (widget.dictionaryService.getWord(word) != null) {
        _knownWords--;
      } else if (widget.vocabularyService.getAllWords().any((w) => w.word.toLowerCase() == word.toLowerCase())) {
        _vocabularyWords--;
      } else {
        _unknownWords--;
      }
    });
  }
  
  // 取消标记单词为熟知
  void _unmarkAsFamiliar(String word) {
    widget.dictionaryService.unmarkAsFamiliar(word);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已取消标记熟知单词: $word'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 1),
      ),
    );
    
    // 刷新状态以更新UI
    setState(() {
      _familiarWords--;
      _tempNeedsLearning.add(word); // 添加到需要学习的列表
      _needsLearningWords++;
      
      if (widget.dictionaryService.getWord(word) != null) {
        _knownWords++;
      } else if (widget.vocabularyService.getAllWords().any((w) => w.word.toLowerCase() == word.toLowerCase())) {
        _vocabularyWords++;
      } else {
        _unknownWords++;
      }
    });
  }
  
  // 标记/取消标记单词为需要学习
  void _toggleNeedsLearning(String word) {
    final wasMarked = _tempNeedsLearning.contains(word);
    
    setState(() {
      if (wasMarked) {
        _tempNeedsLearning.remove(word);
        _needsLearningWords--;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消标记为需要学习: $word'),
            backgroundColor: Colors.grey,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        _tempNeedsLearning.add(word);
        _needsLearningWords++;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已标记为需要学习: $word'),
            backgroundColor: Colors.purple,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final sortedWords = _getSortedFilteredWords();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('字幕单词分析 - $_videoTitle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新分析',
            onPressed: _isAnalyzing ? null : _analyzeSubtitles,
          ),
        ],
      ),
      body: _isAnalyzing 
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在分析字幕中的单词...'),
              ],
            ),
          )
        : Column(
            children: [
              // 统计信息和过滤选项的紧凑布局
              if (_isAnalyzed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      children: [
                      // 上部统计信息行
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 基本统计信息
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('总单词: $_totalWords', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('不同单词: $_uniqueWords'),
                              ],
                            ),
                            // 分类统计
                            Row(
                              children: [
                                _CompactStatItem(
                                  label: '需学',
                                  count: _needsLearningWords,
                                  color: Colors.purple,
                                ),
                                const SizedBox(width: 8),
                                _CompactStatItem(
                                  label: '熟知',
                                  count: _familiarWords,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                _CompactStatItem(
                                  label: '词典',
                                count: _knownWords,
                                color: Colors.green,
                              ),
                                const SizedBox(width: 8),
                                _CompactStatItem(
                                  label: '生词',
                                count: _vocabularyWords,
                                color: Colors.orange,
                              ),
                                const SizedBox(width: 8),
                                _CompactStatItem(
                                  label: '未知',
                                count: _unknownWords,
                                color: Colors.red,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                      
                      const SizedBox(height: 4),
              
                      // 搜索和过滤控件行
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      child: Column(
                        children: [
                            // 排序下拉框和过滤选项
                          Row(
                            children: [
                                // 排序下拉框
                              DropdownButton<SortMethod>(
                                value: _sortMethod,
                                items: [
                                  const DropdownMenuItem(
                                    value: SortMethod.frequency,
                                      child: Text('按频率'),
                                  ),
                                  const DropdownMenuItem(
                                    value: SortMethod.alphabetical,
                                      child: Text('按字母'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _sortMethod = value;
                                    });
                                  }
                                },
                              ),
                                const SizedBox(width: 16),
                              // 过滤选项
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _CompactFilterChip(
                                          label: '需学',
                                          selected: _showNeedsLearningWords,
                                          color: Colors.purple,
                                          onSelected: (selected) {
                                            setState(() {
                                              _showNeedsLearningWords = selected;
                                            });
                                          },
                                          icon: Icons.school,
                                        ),
                                        const SizedBox(width: 4),
                                        _CompactFilterChip(
                                          label: '熟知',
                                          selected: _showFamiliarWords,
                                          color: Colors.blue,
                                          onSelected: (selected) {
                                            setState(() {
                                              _showFamiliarWords = selected;
                                            });
                                          },
                                          icon: Icons.check_circle_outline,
                                        ),
                                        const SizedBox(width: 4),
                                        _CompactFilterChip(
                                          label: '词典',
                                selected: _showKnownWords,
                                          color: Colors.green,
                                onSelected: (selected) {
                                  setState(() {
                                    _showKnownWords = selected;
                                  });
                                },
                                          icon: Icons.check_circle,
                              ),
                                        const SizedBox(width: 4),
                                        _CompactFilterChip(
                                          label: '生词',
                                selected: _showVocabularyWords,
                                          color: Colors.orange,
                                onSelected: (selected) {
                                  setState(() {
                                    _showVocabularyWords = selected;
                                  });
                                },
                                          icon: Icons.book,
                              ),
                                        const SizedBox(width: 4),
                                        _CompactFilterChip(
                                          label: '未知',
                                selected: _showUnknownWords,
                                          color: Colors.red,
                                onSelected: (selected) {
                                  setState(() {
                                    _showUnknownWords = selected;
                                  });
                                },
                                          icon: Icons.help_outline,
                                        ),
                                      ],
                                    ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
              
              // 单词列表
              if (_isAnalyzed)
                Expanded(
                  child: sortedWords.isEmpty
                    ? const Center(child: Text('没有符合条件的单词'))
                    : ListView.builder(
                        itemCount: sortedWords.length,
                        itemBuilder: (context, index) {
                          final entry = sortedWords[index];
                          final word = entry.key;
                          final count = entry.value;
                          final isFamiliar = widget.dictionaryService.isFamiliar(word);
                          final needsLearning = _tempNeedsLearning.contains(word);
                          final isKnown = !isFamiliar && widget.dictionaryService.getWord(word) != null;
                          final isInVocabulary = widget.vocabularyService.getAllWords()
                              .any((w) => w.word.toLowerCase() == word.toLowerCase());
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            // 标记需要学习的单词有紫色边框
                            shape: needsLearning 
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  side: const BorderSide(color: Colors.purple, width: 2),
                                )
                              : null,
                            child: ListTile(
                              visualDensity: VisualDensity.compact,
                              title: Text(
                                word,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('出现 $count 次'),
                              leading: isFamiliar 
                                ? const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20)
                                : needsLearning
                                  ? const Icon(Icons.school, color: Colors.purple, size: 20)
                                  : isKnown
                                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                : isInVocabulary
                                      ? const Icon(Icons.book, color: Colors.orange, size: 20)
                                      : const Icon(Icons.help_outline, color: Colors.red, size: 20),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 标记为需要学习的按钮
                                  if (!isFamiliar)
                                    IconButton(
                                      icon: Icon(
                                        needsLearning ? Icons.school : Icons.school_outlined,
                                        color: needsLearning ? Colors.purple : null,
                                        size: 20,
                                      ),
                                      tooltip: needsLearning ? '取消标记为需要学习' : '标记为需要学习',
                                      onPressed: () => _toggleNeedsLearning(word),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  
                                  IconButton(
                                    icon: const Icon(Icons.content_copy, size: 20),
                                    tooltip: '复制单词',
                                    onPressed: () => _copyWord(word),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                  
                                  if (!isKnown && !isInVocabulary && !isFamiliar)
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 20),
                                      tooltip: '添加到生词本',
                                      onPressed: () => _addToVocabulary(word),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  
                                  if (isFamiliar)
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      tooltip: '取消标记为熟知',
                                      onPressed: () => _unmarkAsFamiliar(word),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, size: 20),
                                      tooltip: '标记为熟知',
                                      onPressed: () => _markAsFamiliar(word),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
            ],
          ),
    );
  }
}

// 紧凑型统计项目组件
class _CompactStatItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  
  const _CompactStatItem({
    required this.label,
    required this.count,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}

// 紧凑型过滤芯片组件
class _CompactFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final Function(bool) onSelected;
  final IconData icon;
  
  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onSelected,
    required this.icon,
  });
  
  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: onSelected,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? color : Colors.grey,
      ),
      visualDensity: VisualDensity.compact,
      labelStyle: const TextStyle(fontSize: 12),
    );
  }
}

// 统计项目组件
class _StatisticItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  
  const _StatisticItem({
    required this.label,
    required this.count,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
          ),
        ),
      ],
    );
  }
} 