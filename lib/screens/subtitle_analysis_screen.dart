import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';

import '../services/video_service.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../services/bailian_translation_service.dart';
import '../models/subtitle_model.dart';
import '../models/dictionary_word.dart';
import '../utils/word_lemmatizer.dart';



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
  // 添加单词到字幕的映射
  Map<String, String> _wordToSubtitle = {};
  // 添加单词到字幕条目的映射，这样我们可以获取时间戳
  Map<String, SubtitleEntry> _wordToSubtitleEntry = {};
  // 词根到原始单词形式的映射（显示原始变形）
  Map<String, Set<String>> _lemmaToOriginalWords = {};
  
  // 直接使用最先进的词形还原模式
  final LemmatizationMode _lemmatizationMode = LemmatizationMode.precise;
  
  bool _isAnalyzing = false;
  bool _isAnalyzed = false;
  String _videoTitle = '';
  int _totalWords = 0;
  int _uniqueWords = 0;
  int _knownWords = 0;
  int _vocabularyWords = 0;
  int _unknownWords = 0;
  int _familiarWords = 0;
  int _needsLearningWords = 0; // 需要学习的单词数量（所有不熟知的单词）
  
  // 保存原始排序后的单词列表，确保顺序稳定
  List<MapEntry<String, int>> _originalSortedWords = [];
  
  // 添加变量来存储字幕中的所有单词
  Set<String> _subtitleWords = {};
  
  // 翻译服务
  final BailianTranslationService _translationService = BailianTranslationService();
  
  // 翻译相关状态
  Map<String, String> _translations = {}; // 存储翻译结果
  Set<String> _translatingWords = {}; // 正在翻译的单词
  Map<String, bool> _showTranslations = {}; // 控制是否显示翻译结果
  
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

      _wordToSubtitle = {}; // 重置单词到字幕的映射
      _wordToSubtitleEntry = {}; // 重置单词到字幕条目的映射
      _subtitleWords = {}; // 重置字幕单词集合
      _lemmaToOriginalWords = {}; // 重置词根到原始单词的映射
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
      
      // 使用新的逻辑进行分析：先拆句子，再拆单词
      final List<String> sentences = []; // 所有句子列表
      final Map<String, SubtitleEntry> sentenceToEntry = {}; // 句子到字幕条目的映射
      
      // 1. 将所有字幕收集为句子，并建立句子到字幕条目的映射
      for (final subtitle in subtitles) {
        sentences.add(subtitle.text);
        sentenceToEntry[subtitle.text] = subtitle; // 记录句子与字幕条目的对应关系
      }
      
      // 2. 从句子中提取单词并建立映射关系
      final wordFrequency = <String, int>{};
      final wordToSubtitle = <String, String>{};
      final wordToSubtitleEntry = <String, SubtitleEntry>{}; // 单词到字幕条目的映射
      final subtitleWords = <String>{}; // 字幕中出现的所有单词（词根形式）
      final lemmaToOriginalWords = <String, Set<String>>{}; // 词根到原始单词的映射
      final regex = RegExp(r'\b[a-zA-Z]+\b');
      
      for (final sentence in sentences) {
        final matches = regex.allMatches(sentence.toLowerCase());
        for (final match in matches) {
          final originalWord = match.group(0)!;
          if (originalWord.length > 1) { // 忽略单个字母
            // 使用改进的词形还原获取词根
            final lemma = ImprovedWordLemmatizer.lemmatize(originalWord, _lemmatizationMode);
            
            // 添加词根到字幕单词集合
            subtitleWords.add(lemma);
            
            // 记录词根到原始单词的映射
            if (!lemmaToOriginalWords.containsKey(lemma)) {
              lemmaToOriginalWords[lemma] = <String>{};
            }
            lemmaToOriginalWords[lemma]!.add(originalWord);
            
            // 使用词根更新频率
            wordFrequency[lemma] = (wordFrequency[lemma] ?? 0) + 1;
            
            // 如果这个词根第一次出现，记录它所在的句子
            if (!wordToSubtitle.containsKey(lemma)) {
              wordToSubtitle[lemma] = sentence;
              // 同时记录词根与字幕条目的对应关系
              final entry = sentenceToEntry[sentence];
              if (entry != null) {
                wordToSubtitleEntry[lemma] = entry;
              }
            }
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
          // 所有不熟知的单词都算作需要学习
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
      
      // 创建并排序原始单词列表（按频率排序）
      final originalWords = wordFrequency.entries.toList();
        originalWords.sort((a, b) => b.value.compareTo(a.value));
      
      setState(() {
        _wordFrequency = wordFrequency;
        _wordToSubtitle = wordToSubtitle;
        _wordToSubtitleEntry = wordToSubtitleEntry; // 更新单词到字幕条目的映射
        _subtitleWords = subtitleWords; // 更新字幕单词集合（词根形式）
        _lemmaToOriginalWords = lemmaToOriginalWords; // 更新词根到原始单词的映射
        _isAnalyzing = false;
        _isAnalyzed = true;
        _originalSortedWords = originalWords;
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
  
  // 获取排序后的单词列表（为了性能，只显示非熟知单词）
  List<MapEntry<String, int>> _getSortedFilteredWords() {
    if (_wordFrequency.isEmpty) {
      return [];
    }
    
    // 只保留非熟知的单词，提升性能
    final List<MapEntry<String, int>> unfamiliarWords = [];
    
    // 遍历原始排序列表，只添加非熟知的单词
    for (final entry in _originalSortedWords) {
      final word = entry.key;
      final isFamiliar = widget.dictionaryService.isFamiliar(word);
      
      // 只添加非熟知的单词
      if (!isFamiliar) {
        unfamiliarWords.add(entry);
      }
    }
    
    return unfamiliarWords;
  }
  
  // 获取单词所在的字幕（缩短版本）
  String _getShortSubtitleText(String word) {
    final subtitle = _wordToSubtitle[word.toLowerCase()];
    if (subtitle == null) return '';
    
    // 将字幕限制在一个合理的长度，避免UI过长
    const maxLength = 50;
    if (subtitle.length <= maxLength) {
      return subtitle;
    }
    
    // 找到单词在字幕中的位置
    final wordPosition = subtitle.toLowerCase().indexOf(word.toLowerCase());
      
    // 如果找不到单词位置，就从开头截取
    if (wordPosition < 0) {
      return '${subtitle.substring(0, maxLength)}...';
    }
    
    // 计算截取的开始位置，尽量保持单词在中间
    int startPos = wordPosition - (maxLength ~/ 2);
    if (startPos < 0) startPos = 0;
    
    // 确保截取长度不超过字幕长度
    int endPos = startPos + maxLength;
    if (endPos > subtitle.length) {
      endPos = subtitle.length;
      startPos = endPos - maxLength;
      if (startPos < 0) startPos = 0;
      }
      
    // 返回截取的字幕，添加省略号表示有省略
    final result = subtitle.substring(startPos, endPos);
    return (startPos > 0 ? '...' : '') + result + (endPos < subtitle.length ? '...' : '');
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
      _needsLearningWords--; // 从需要学习中移除
      
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
      _needsLearningWords++; // 添加到需要学习中
      
      if (widget.dictionaryService.getWord(word) != null) {
        _knownWords++;
      } else if (widget.vocabularyService.getAllWords().any((w) => w.word.toLowerCase() == word.toLowerCase())) {
        _vocabularyWords++;
      } else {
        _unknownWords++;
      }
    });
  }
  

  
  // 播放单词对应的字幕
  void _playWordSubtitle(String word) {
    final entry = _wordToSubtitleEntry[word.toLowerCase()];
    if (entry != null) {
      // 使用视频服务跳转到该字幕的开始时间
      widget.videoService.seekToSubtitle(entry);
      
      // 确保视频开始播放
      if (!widget.videoService.isPlaying) {
        widget.videoService.togglePlay();
      }
      
      // 如果当前不是循环模式，启动循环模式
      if (!widget.videoService.isLooping) {
        widget.videoService.toggleLooping();
      }
      
      // 显示提示消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在循环播放: "${entry.text}"'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // 未找到对应字幕
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法找到单词 "$word" 对应的字幕'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  // 翻译单词对应的字幕
  Future<void> _translateWordSubtitle(String word) async {
    final subtitleText = _wordToSubtitle[word.toLowerCase()];
    if (subtitleText == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法找到单词 "$word" 对应的字幕'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // 如果已经有翻译结果，切换显示状态
    if (_translations.containsKey(subtitleText)) {
    setState(() {
        _showTranslations[word] = !(_showTranslations[word] ?? false);
      });
      return;
    }
    
    // 开始翻译
    setState(() {
      _translatingWords.add(word);
    });
    
    try {
      final translation = await _translationService.translateText(subtitleText);
      
      setState(() {
        _translations[subtitleText] = translation;
        _translatingWords.remove(word);
        _showTranslations[word] = true; // 翻译完成后显示结果
      });
    } catch (e) {
      setState(() {
        _translatingWords.remove(word);
    });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('翻译失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  @override
  void dispose() {
    super.dispose();
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
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：统计信息和词典覆盖可视化（垂直布局）
              if (_isAnalyzed)
                Expanded(
                  flex: 4, // 左侧占整体宽度的40%
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 统计信息
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
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                _CompactStatItem(
                                  label: '熟知',
                                  count: _familiarWords,
                                  color: Colors.blue,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                      
                        const SizedBox(height: 8),
              
                        // 词典覆盖可视化
                        Expanded(
                      child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                              // 小标题
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  '词典覆盖情况 (紫色:字幕中熟知单词 红色:字幕中未熟知单词 浅灰色:其他熟知单词 灰色:其他词典单词)', 
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                              ),
                              // 覆盖度统计
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _buildCoverageStats(),
                              ),
                              // 可视化组件
                                Expanded(
                                child: SubtitleDictionaryCoverageVisualizer(
                                  allDictionaryWords: widget.dictionaryService.allWords,
                                  subtitleWords: _subtitleWords,
                                  pointSize: 6,
                                  pointsPerRow: 0, // 0表示自动计算
                                ),
                                        ),
                                      ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              
              // 右侧：单词列表（垂直布局）
              if (_isAnalyzed)
                Expanded(
                  flex: 6, // 右侧占整体宽度的60%
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                  child: sortedWords.isEmpty
                    ? const Center(child: Text('没有符合条件的单词'))
                    : ListView.builder(
                        itemCount: sortedWords.length,
                        itemBuilder: (context, index) {
                          final entry = sortedWords[index];
                          final lemma = entry.key;  // 现在这是词根
                          final count = entry.value;
                          final isFamiliar = widget.dictionaryService.isFamiliar(lemma);
                          final isKnown = !isFamiliar && widget.dictionaryService.getWord(lemma) != null;
                          final isInVocabulary = widget.vocabularyService.getAllWords()
                              .any((w) => w.word.toLowerCase() == lemma.toLowerCase());
                          
                          // 获取这个词根对应的所有原始单词形式
                          final originalForms = _lemmaToOriginalWords[lemma] ?? {lemma};
                          
                            // 获取字幕文本（如果非熟知单词）
                            final showSubtitle = !isFamiliar && _wordToSubtitle.containsKey(lemma.toLowerCase());
                            final subtitleText = showSubtitle ? _getShortSubtitleText(lemma) : null;
                            
                            // 获取翻译结果
                            final fullSubtitle = _wordToSubtitle[lemma.toLowerCase()];
                            final translationText = fullSubtitle != null ? _translations[fullSubtitle] : null;
                            final showTranslation = _showTranslations[lemma] ?? false;
                            
                            // 确定边框颜色，简单逻辑：词典内红色，词典外黄色
                            Color borderColor;
                            
                            // 检查单词是否在词典中
                            final isInDictionary = widget.dictionaryService.allWords
                                .any((dictionaryWord) => dictionaryWord.word.toLowerCase() == lemma.toLowerCase());
                            
                            if (isInDictionary) {
                              // 词典中的未熟知单词，使用红色（对应左边红色格子）
                              borderColor = const Color(0xFFF44336); // Red
                            } else {
                              // 词典外的单词，使用黄色
                              borderColor = const Color(0xFFFFB84D); // Yellow
                            }
                            
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              // 边框颜色对应左边格子的颜色
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                side: BorderSide(
                                  color: borderColor, 
                                  width: isInDictionary ? 2 : 1, // 词典内的单词边框更粗
                                ),
                              ),
                            child: ListTile(
                              visualDensity: VisualDensity.compact,
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 单词和字幕行
                                    Row(
                                      children: [
                                        // 单词（显示词根和原始形式）
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              lemma,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            if (originalForms.length > 1 || !originalForms.contains(lemma))
                                              Text(
                                                '(${originalForms.join(', ')})',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                          ],
                                        ),
                                        // 如果有字幕且非熟知单词，显示字幕
                                        if (subtitleText != null) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              subtitleText,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black87, // 使用更深的颜色提高可读性
                                                fontStyle: FontStyle.italic,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    // 翻译结果
                                    if (showTranslation && translationText != null) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                translationText,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black87,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: translationText));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('翻译已复制'),
                                                    backgroundColor: Colors.green,
                                                    duration: Duration(seconds: 1),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                child: const Icon(
                                                  Icons.copy,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                              ),
                              subtitle: Text('出现 $count 次'),
                              leading: isFamiliar 
                                ? const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20)
                                : isKnown
                                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                  : isInVocabulary
                                    ? const Icon(Icons.book, color: Colors.orange, size: 20)
                                    : const Icon(Icons.help_outline, color: Colors.red, size: 20),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [

                                  IconButton(
                                    icon: const Icon(Icons.content_copy, size: 20),
                                    tooltip: '复制单词',
                                    onPressed: () => _copyWord(lemma),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                    
                                    // 添加播放按钮，如果单词有对应的字幕条目
                                    if (_wordToSubtitleEntry.containsKey(lemma.toLowerCase()))
                                      IconButton(
                                        icon: const Icon(Icons.play_circle_outline, size: 20),
                                        tooltip: '播放此单词的字幕',
                                        onPressed: () => _playWordSubtitle(lemma),
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        padding: EdgeInsets.zero,
                                      ),
                                    
                                    // 添加翻译按钮，如果单词有对应的字幕
                                    if (_wordToSubtitle.containsKey(lemma.toLowerCase()))
                                      IconButton(
                                        icon: _translatingWords.contains(lemma)
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                              ),
                                            )
                                          : Icon(
                                              showTranslation ? Icons.translate_outlined : Icons.translate,
                                              size: 20,
                                              color: showTranslation ? Colors.blue : null,
                                            ),
                                        tooltip: showTranslation ? '隐藏翻译' : '翻译此单词的字幕',
                                        onPressed: _translatingWords.contains(lemma) 
                                          ? null 
                                          : () => _translateWordSubtitle(lemma),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                  
                                  if (!isKnown && !isInVocabulary && !isFamiliar)
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 20),
                                      tooltip: '添加到生词本',
                                      onPressed: () => _addToVocabulary(lemma),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  
                                  if (isFamiliar)
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      tooltip: '取消标记为熟知',
                                      onPressed: () => _unmarkAsFamiliar(lemma),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, size: 20),
                                      tooltip: '标记为熟知',
                                      onPressed: () => _markAsFamiliar(lemma),
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
                ),
            ],
          ),
    );
  }
  
  // 构建覆盖度统计信息
  Widget _buildCoverageStats() {
    // 计算覆盖度
    final totalDictionaryWords = widget.dictionaryService.allWords.length;
    final totalSubtitleWords = _subtitleWords.length;
    
    // 字幕中出现的词典单词数量
    int dictionaryWordsInSubtitle = 0;
    
    // 熟知单词在字幕中的数量（紫色单词）
    int familiarWordsInSubtitle = 0;
    
    // 未熟知单词在字幕中的数量（红色单词）
    int unfamiliarWordsInSubtitle = 0;
    
    // 统计计算
    for (String word in _subtitleWords) {
      if (widget.dictionaryService.getWord(word) != null) {
        dictionaryWordsInSubtitle++;
        if (widget.dictionaryService.isFamiliar(word)) {
          familiarWordsInSubtitle++;
        } else {
          unfamiliarWordsInSubtitle++;
        }
      }
    }
    
    // 计算百分比
    double dictionaryCoverage = totalDictionaryWords > 0 
      ? (dictionaryWordsInSubtitle / totalDictionaryWords * 100)
      : 0.0;
    
    double subtitleCoverage = totalSubtitleWords > 0
      ? (dictionaryWordsInSubtitle / totalSubtitleWords * 100)
      : 0.0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '字幕覆盖词典: $dictionaryWordsInSubtitle/$totalDictionaryWords (${dictionaryCoverage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                '词典覆盖字幕: $dictionaryWordsInSubtitle/$totalSubtitleWords (${subtitleCoverage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '紫色单词: $familiarWordsInSubtitle (字幕中熟知单词)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9C27B0)),
              ),
            ),
            Expanded(
              child: Text(
                '红色单词: $unfamiliarWordsInSubtitle (字幕中未熟知单词)',
                style: const TextStyle(fontSize: 12, color: Color(0xFFF44336)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 添加一个新的组件用于可视化字幕单词对词典的覆盖情况
class SubtitleDictionaryCoverageVisualizer extends StatefulWidget {
  final List<DictionaryWord> allDictionaryWords; // 词典中的所有单词
  final Set<String> subtitleWords; // 字幕中出现的所有单词
  final int pointSize;
  final int pointsPerRow;
  
  const SubtitleDictionaryCoverageVisualizer({
    super.key,
    required this.allDictionaryWords,
    required this.subtitleWords,
    this.pointSize = 4,
    this.pointsPerRow = 50,
  });
  
  @override
  State<SubtitleDictionaryCoverageVisualizer> createState() => _SubtitleDictionaryCoverageVisualizerState();
}

class _SubtitleDictionaryCoverageVisualizerState extends State<SubtitleDictionaryCoverageVisualizer> {
  // 当前鼠标位置
  Offset? _mousePosition;
  // 当前悬停的单词索引
  int? _hoverWordIndex;
  // 屏幕坐标到本地坐标的转换
  final LayerLink _layerLink = LayerLink();
  // 是否显示悬停信息
  bool _showTooltip = false;
  // OverlayEntry用于显示悬停信息
  OverlayEntry? _overlayEntry;
  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();
  // 上次播放音效的时间戳，用于避免过于频繁播放
  DateTime? _lastPlayTime;
  
  @override
  void initState() {
    super.initState();
    _audioPlayer.setVolume(0.2); // 设置适当的音量
  }
  
  @override
  void dispose() {
    _removeOverlay();
    _audioPlayer.dispose();
    super.dispose();
  }
  
  // 播放悬停音效
  void _playHoverSound() {
    // 节流控制：限制触发频率
    final now = DateTime.now();
    if (_lastPlayTime == null || now.difference(_lastPlayTime!).inMilliseconds > 150) {
      // 确保在主线程上执行音频播放，避免平台线程错误
      Future.microtask(() async {
        try {
          // 使用AudioPlayer播放内置音效
          await _audioPlayer.play(
            AssetSource('audio/tick.mp3'),
            volume: 0.2,
            mode: PlayerMode.lowLatency,
          );
        } catch (e) {
          // 如果无法播放音效，静默失败，不影响用户体验
          debugPrint('无法播放音效: $e');
        }
      });
      
      _lastPlayTime = now;
    }
  }
  
  // 移除悬停信息
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  
  // 显示悬停信息
  void _showWordTooltip(BuildContext context, Offset position, DictionaryWord word) {
    _removeOverlay();
    
    // 创建悬停信息
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy - 40, // 显示在鼠标上方
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, -40),
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(4),
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    word.word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (word.phonetic != null && word.phonetic!.isNotEmpty)
                    Text(
                      '[${word.phonetic!}]',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (word.definition != null && word.definition!.isNotEmpty)
                    SizedBox(
                      width: 200,
                      child: Text(
                        word.definition!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    // 显示悬停信息
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  @override
  Widget build(BuildContext context) {
    int pointsPerRow = widget.pointsPerRow;
    int pointSize = widget.pointSize;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 调整每行点数，使其适应可用宽度，同时确保点足够大
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        
        // 点之间的间距，保持较小以便更紧密地排列
        final pointSpacing = 1;
        
        // 动态计算点的大小，优先填满可用宽度
        // 如果用户没有设置pointsPerRow，则自动计算，尽量填满空间
        int calculatedPointsPerRow;
        int effectivePointSize;
        
        if (widget.pointsPerRow <= 0) {
          // 自动计算模式，优先考虑较大的点
          
          // 首先尝试使用8像素的点大小
          effectivePointSize = 8;
          calculatedPointsPerRow = availableWidth ~/ (effectivePointSize + pointSpacing);
          
          // 检查总行数
          int totalRows = (widget.allDictionaryWords.length / calculatedPointsPerRow).ceil();
          int totalHeight = totalRows * (effectivePointSize + pointSpacing);
          
          // 如果预估高度超出可用高度，减小点的大小
          if (totalHeight > availableHeight && availableHeight > 100) {
            // 计算能填满可用高度的点大小
            double heightRatio = availableHeight / totalHeight;
            effectivePointSize = math.max(4, (effectivePointSize * heightRatio).floor());
            calculatedPointsPerRow = availableWidth ~/ (effectivePointSize + pointSpacing);
          }
          
          // 确保点不会太小或太大
          effectivePointSize = math.max(4, math.min(12, effectivePointSize));
          calculatedPointsPerRow = math.max(10, calculatedPointsPerRow);
        } else {
          // 使用用户指定的每行点数
          calculatedPointsPerRow = widget.pointsPerRow;
          
          // 计算能填满整个宽度的点大小
          effectivePointSize = math.max(4, (availableWidth / calculatedPointsPerRow - pointSpacing).floor());
        }
        
        pointsPerRow = calculatedPointsPerRow;
        
        return CompositedTransformTarget(
          link: _layerLink,
          child: MouseRegion(
            onHover: (event) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPosition = box.globalToLocal(event.position);
              
              // 计算鼠标悬停的点索引
              final col = localPosition.dx ~/ (effectivePointSize + pointSpacing);
              final row = localPosition.dy ~/ (effectivePointSize + pointSpacing);
              
              if (col >= 0 && col < pointsPerRow && 
                  row >= 0 && row * pointsPerRow + col < widget.allDictionaryWords.length) {
                final index = row * pointsPerRow + col;
                
                // 如果悬停到新的点上
                if (_hoverWordIndex != index) {
                  // 播放悬停音效
                  _playHoverSound();
                  
                  setState(() {
                    _mousePosition = event.position;
                    _hoverWordIndex = index;
                    _showTooltip = true;
                  });
                  
                  // 显示悬停信息
                  if (index < widget.allDictionaryWords.length) {
                    _showWordTooltip(context, event.position, widget.allDictionaryWords[index]);
                  }
                }
              } else {
                if (_showTooltip) {
                  setState(() {
                    _showTooltip = false;
                    _hoverWordIndex = null;
                  });
                  _removeOverlay();
                }
              }
            },
            onExit: (_) {
              setState(() {
                _mousePosition = null;
                _hoverWordIndex = null;
                _showTooltip = false;
              });
              _removeOverlay();
            },
            child: Container(
              width: availableWidth,
              height: availableHeight,
              child: CustomPaint(
                painter: SubtitleCoveragePainter(
                  allWords: widget.allDictionaryWords,
                  subtitleWords: widget.subtitleWords,
                  pointSize: effectivePointSize,
                  pointsPerRow: pointsPerRow,
                  pointSpacing: pointSpacing,
                  hoverIndex: _hoverWordIndex,
                ),
                isComplex: true,
                willChange: _hoverWordIndex != null,
              ),
            ),
          ),
        );
      }
    );
  }
}

// 自定义绘制器，用于绘制字幕覆盖的点阵图
class SubtitleCoveragePainter extends CustomPainter {
  final List<DictionaryWord> allWords;
  final Set<String> subtitleWords; // 字幕中出现的所有单词
  final int pointSize;
  final int pointsPerRow;
  final int? hoverIndex;  // 添加悬停索引
  final int pointSpacing; // 点之间的间距
  
  SubtitleCoveragePainter({
    required this.allWords,
    required this.subtitleWords,
    required this.pointSize,
    required this.pointsPerRow,
    this.hoverIndex,
    this.pointSpacing = 1, // 默认间距为1像素
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    for (int i = 0; i < allWords.length; i++) {
      final word = allWords[i];
      final row = i ~/ pointsPerRow;
      final col = i % pointsPerRow;
      
      final x = col * (pointSize + pointSpacing).toDouble();
      final y = row * (pointSize + pointSpacing).toDouble();
      
      // 设置颜色：判断这个单词是否在字幕中出现
      if (subtitleWords.contains(word.word.toLowerCase())) {
        // 该单词在字幕中出现
        if (word.isFamiliar) {
          // 字幕中出现的熟知单词，使用紫色
          paint.color = const Color(0xFF9C27B0); // Purple
        } else {
          // 字幕中出现的未熟知单词，使用红色（重点学习目标）
          paint.color = const Color(0xFFF44336); // Red
        }
                        } else if (word.isFamiliar) {
                    // 熟知但未出现在字幕中的单词，使用浅灰色
                    paint.color = const Color(0xFFD3D3D3); // Light gray
      } else {
        // 其他单词（在词典中但不在字幕中），使用灰色
        paint.color = const Color.fromARGB(255, 200, 200, 200); // Light grey
      }
      
      // 如果当前点是鼠标悬停的点，使用高亮颜色
      if (i == hoverIndex) {
        // 高亮颜色
        paint.color = Colors.yellow;
      }
      
      canvas.drawRect(
        Rect.fromLTWH(x, y, pointSize.toDouble(), pointSize.toDouble()),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(SubtitleCoveragePainter oldDelegate) {
    return oldDelegate.allWords != allWords || 
           oldDelegate.subtitleWords != subtitleWords ||
           oldDelegate.hoverIndex != hoverIndex ||
           oldDelegate.pointSize != pointSize ||
           oldDelegate.pointSpacing != pointSpacing ||
           oldDelegate.pointsPerRow != pointsPerRow;
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