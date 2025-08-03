import 'package:flutter/material.dart';
import '../services/video_service.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../services/translation_service.dart';
import '../models/subtitle_model.dart';
import '../models/dictionary_word.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

class SubtitleArticleScreen extends StatefulWidget {
  final VideoService videoService;
  final VocabularyService vocabularyService;
  final DictionaryService dictionaryService;

  const SubtitleArticleScreen({
    Key? key,
    required this.videoService,
    required this.vocabularyService,
    required this.dictionaryService,
  }) : super(key: key);

  @override
  State<SubtitleArticleScreen> createState() => _SubtitleArticleScreenState();
}

class _SubtitleArticleScreenState extends State<SubtitleArticleScreen> {
  List<String> _paragraphs = [];
  List<String?> _translatedParagraphs = [];
  Set<int> _translatingParagraphs = {};
  bool _isTranslatingFullText = false;
  String? _fullTextTranslation;
  
  bool _isLoading = true;
  bool _isProcessingHighlights = false;
  Map<String, WordStatus> _wordStatusMap = {};
  Map<String, String> _wordDefinitions = {};
  List<String> _orderedUniqueWords = [];
  
  TextSpan? _processedTextSpan;
  
  double _fontSize = 20.0;
  
  final Set<String> _commonWords = {
    'i', 'me', 'my', 'mine', 'myself',
    'you', 'your', 'yours', 'yourself',
    'he', 'him', 'his', 'himself',
    'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself',
    'we', 'us', 'our', 'ours', 'ourselves',
    'they', 'them', 'their', 'theirs', 'themselves',
    'this', 'that', 'these', 'those',
    'a', 'an', 'the',
    'and', 'but', 'or', 'nor', 'for', 'so', 'yet',
    'in', 'on', 'at', 'to', 'from', 'by', 'with', 'about',
    'is', 'am', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did',
    'can', 'could', 'will', 'would', 'shall', 'should', 'may', 'might', 'must',
    'not', 'no', 'yes',
    'of', 'as', 'if', 'then', 'than', 'when', 'where', 'why', 'how',
    'all', 'any', 'both', 'each', 'few', 'many', 'some',
    'what', 'who', 'whom', 'which',
    'there', 'here',
  };
  
  @override
  void initState() {
    super.initState();
    _processSubtitles();
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  // 处理字幕，转换为文章格式
  Future<void> _processSubtitles() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 获取当前视频的字幕
      final subtitles = widget.videoService.subtitleData?.entries.toList();
      if (subtitles == null || subtitles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前视频没有字幕，无法显示文章'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // 打印字幕总数
      debugPrint('字幕总数: ${subtitles.length}');
      
      // 按时间排序字幕
      subtitles.sort((a, b) => a.start.compareTo(b.start));
      
      // 将字幕分段处理
      final List<String> paragraphs = [];
      StringBuffer currentParagraph = StringBuffer();
      
      // 定义判断段落的参数
      final int maxCharsPerParagraph = 300; // 每个段落最多300个字符
      bool isFirstSubtitle = true;
      int newParagraphCount = 0; // 统计创建的新段落数
      
      for (int i = 0; i < subtitles.length; i++) {
        final subtitle = subtitles[i];
        // 移除字幕中的HTML标签和多余空格
        String cleanText = subtitle.text.replaceAll(RegExp(r'<[^>]*>'), '');
        cleanText = cleanText.trim();
        
        if (cleanText.isNotEmpty) {
          // 检查是否需要开始新段落
          bool startNewParagraph = false;
          
          // 第一个字幕总是新段落的开始
          if (isFirstSubtitle) {
            isFirstSubtitle = false;
            startNewParagraph = false;
            debugPrint('第一个字幕: $cleanText');
          } 
          // 检查当前段落长度是否已经达到最大字符数
          else if (currentParagraph.length + cleanText.length > maxCharsPerParagraph) {
            startNewParagraph = true;
            debugPrint('段落长度达到上限，创建新段落');
            debugPrint('新段落开始: $cleanText');
            newParagraphCount++;
          }
          
          // 如果需要开始新段落且当前段落不为空
          if (startNewParagraph && currentParagraph.isNotEmpty) {
            paragraphs.add(currentParagraph.toString().trim());
            currentParagraph = StringBuffer();
          }
          
          // 添加当前字幕文本
          if (currentParagraph.isNotEmpty) {
            // 如果当前段落不为空，添加空格
            currentParagraph.write(' ');
          }
          currentParagraph.write(cleanText);
        }
      }
      
      // 添加最后一个段落（如果有内容）
      if (currentParagraph.isNotEmpty) {
        paragraphs.add(currentParagraph.toString().trim());
      }
      
      // 打印分段结果
      debugPrint('总共创建了 ${newParagraphCount} 个新段落');
      debugPrint('最终段落数: ${paragraphs.length}');
      for (int i = 0; i < paragraphs.length; i++) {
        debugPrint('段落 ${i + 1}: ${paragraphs[i].substring(0, paragraphs[i].length > 50 ? 50 : paragraphs[i].length)}...');
      }
      
      setState(() {
        _paragraphs = paragraphs;
        _translatedParagraphs = List.filled(paragraphs.length, null);
        _isLoading = false;
        _isProcessingHighlights = true;
      });
      
      // 异步处理单词分析和高亮
      _processHighlightsAsync(paragraphs.join(' '));
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('处理字幕时出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // 异步处理单词高亮
  Future<void> _processHighlightsAsync(String text) async {
    try {
      // 分析文章中的单词状态
      await _analyzeWords(text);
      
      // 为每个段落构建高亮文本
      List<TextSpan> paragraphSpans = [];
      for (String paragraph in _paragraphs) {
        paragraphSpans.add(_buildTextSpanWithHighlightedWords(paragraph));
      }
      
      // 更新UI
      setState(() {
        _processedTextSpan = TextSpan(children: paragraphSpans);
        _isProcessingHighlights = false;
      });
    } catch (e) {
      debugPrint('处理单词高亮时出错: $e');
      setState(() {
        _isProcessingHighlights = false;
      });
    }
  }
  
  // 分析文章中的单词状态
  Future<void> _analyzeWords(String text) async {
    final Map<String, WordStatus> statusMap = {};
    final regex = RegExp(r'\b[a-zA-Z]+\b');
    
    // 创建一个有序集合来保存单词的原始顺序
    final Set<String> orderedUniqueWords = <String>{};
    
    final matches = regex.allMatches(text.toLowerCase());
    for (final match in matches) {
      final word = match.group(0)!;
      if (word.length > 1 && !_commonWords.contains(word.toLowerCase())) { // 忽略单个字母和常用词
        // 保存单词的原始顺序
        orderedUniqueWords.add(word);
        
        // 检查单词状态
        if (widget.dictionaryService.containsWord(word)) {
          statusMap[word] = WordStatus.inDictionary;
        } else if (widget.dictionaryService.isInVocabulary(word)) {
          statusMap[word] = WordStatus.inVocabulary;
        } else {
          statusMap[word] = WordStatus.unknown;
        }
      }
    }
    
    setState(() {
      _wordStatusMap = statusMap;
      _orderedUniqueWords = orderedUniqueWords.toList();
    });
  }
  
  // 查询单词定义
  Future<void> _lookupWordDefinition(String word) async {
    try {
      // 首先检查本地词典
      final dictWord = widget.dictionaryService.getWord(word);
      if (dictWord != null && dictWord.definition != null) {
        setState(() {
          _wordDefinitions[word] = dictWord.definition!;
        });
        return;
      }
      
      // 使用在线API查询
      final response = await http.get(
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final wordData = data[0];
          final meanings = wordData['meanings'] as List<dynamic>;
          
          if (meanings.isNotEmpty) {
            final firstMeaning = meanings[0];
            final definitions = firstMeaning['definitions'] as List<dynamic>;
            
            if (definitions.isNotEmpty) {
              final definition = definitions[0]['definition'] as String;
              setState(() {
                _wordDefinitions[word] = definition;
              });
              
              // 可选：将查询到的单词添加到词典
              final partOfSpeech = firstMeaning['partOfSpeech'] as String?;
              final phonetic = wordData['phonetic'] as String?;
              
              if (definition.isNotEmpty) {
                final newWord = DictionaryWord(
                  word: word,
                  partOfSpeech: partOfSpeech,
                  definition: definition,
                  phonetic: phonetic,
                );
                
                await widget.dictionaryService.addWord(newWord);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('查询单词 $word 失败: $e');
    }
  }
  
  // 复制全文
  void _copyFullText() {
    final String fullText = _paragraphs.join('\n\n');
    Clipboard.setData(ClipboardData(text: fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制全文到剪贴板'),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  // 翻译段落
  Future<void> _translateParagraph(int index) async {
    // 如果已经翻译过或正在翻译，则不重复翻译
    if (_translatedParagraphs[index] != null || _translatingParagraphs.contains(index)) {
      return;
    }
    
    setState(() {
      _translatingParagraphs.add(index);
    });
    
    try {
      // 获取翻译服务
      final translationService = Provider.of<TranslationService>(context, listen: false);
      
      // 翻译文本
      final translatedText = await translationService.translateText(
        text: _paragraphs[index],
      );
      
      // 更新UI
      setState(() {
        _translatedParagraphs[index] = translatedText;
        _translatingParagraphs.remove(index);
      });
    } catch (e) {
      debugPrint('翻译段落失败: $e');
      setState(() {
        _translatingParagraphs.remove(index);
      });
      
      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('翻译失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 翻译全文
  Future<void> _translateFullText() async {
    if (_isTranslatingFullText) return;
    
    setState(() {
      _isTranslatingFullText = true;
    });
    
    try {
      // 获取翻译服务
      final translationService = Provider.of<TranslationService>(context, listen: false);
      
      // 合并所有段落为一个文本
      final fullText = _paragraphs.join('\n\n');
      
      // 翻译文本 - 使用长文本翻译方法
      final translatedText = await translationService.translateLongText(
        text: fullText,
      );
      
      // 更新UI
      setState(() {
        _fullTextTranslation = translatedText;
        _isTranslatingFullText = false;
      });
      
      // 滚动到底部显示翻译结果
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_fullTextTranslationKey.currentContext != null) {
          Scrollable.ensureVisible(
            _fullTextTranslationKey.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    } catch (e) {
      debugPrint('翻译全文失败: $e');
      setState(() {
        _isTranslatingFullText = false;
      });
      
      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('翻译全文失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 创建一个GlobalKey用于定位全文翻译结果
  final GlobalKey _fullTextTranslationKey = GlobalKey();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('字幕文章 - ${widget.videoService.videoTitle}'),
        actions: [
          // 添加字体大小调整按钮
          IconButton(
            icon: const Icon(Icons.text_fields),
            tooltip: '调整字体大小',
            onPressed: _isLoading ? null : _showFontSizeDialog,
          ),
          // 添加全文翻译按钮
          IconButton(
            icon: _isTranslatingFullText 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.translate),
            tooltip: '翻译全文',
            onPressed: _isLoading || _isTranslatingFullText ? null : _translateFullText,
          ),
          // 添加复制全文按钮
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: '复制全文',
            onPressed: _isLoading ? null : () => _copyFullText(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 文章标题
                              Text(
                                widget.videoService.videoTitle ?? '字幕文章',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // 处理中提示
                              if (_isProcessingHighlights)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 16, 
                                        height: 16, 
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('正在处理单词高亮，请稍候...'),
                                    ],
                                  ),
                                ),
                              
                              // 文章内容 - 根据处理状态显示不同内容
                              _isProcessingHighlights || _processedTextSpan == null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _buildParagraphsWithTranslation(),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _buildHighlightedParagraphsWithTranslation(),
                                  ),
                                  
                              // 全文翻译结果
                              if (_fullTextTranslation != null) ...[
                                const SizedBox(height: 32),
                                const Divider(thickness: 2),
                                Container(
                                  key: _fullTextTranslationKey,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.translate, color: Colors.blue),
                                          const SizedBox(width: 8),
                                          const Text(
                                            '全文翻译',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            icon: const Icon(Icons.copy, size: 20),
                                            tooltip: '复制翻译结果',
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(
                                                text: _fullTextTranslation!,
                                              ));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('已复制翻译结果到剪贴板'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SelectableText(
                                        _fullTextTranslation!,
                                        style: TextStyle(
                                          fontSize: _fontSize,
                                          height: 1.8,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 单词定义
                if (_wordDefinitions.isNotEmpty)
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(top: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '单词定义',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView(
                            children: _wordDefinitions.entries.map((entry) => 
                              _buildDefinitionCard(entry.key, entry.value)
                            ).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
  
  // 构建带翻译功能的段落列表
  List<Widget> _buildParagraphsWithTranslation() {
    return List.generate(_paragraphs.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原文
            SelectableText(
              _paragraphs[index],
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.8,
                color: Colors.black87,
              ),
            ),
            
            // 翻译按钮和翻译结果
            Row(
              children: [
                // 翻译按钮
                IconButton(
                  icon: _translatingParagraphs.contains(index)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate, size: 16),
                  tooltip: '翻译',
                  onPressed: _translatingParagraphs.contains(index)
                      ? null
                      : () => _translateParagraph(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                ),
                const SizedBox(width: 8),
                
                // 翻译结果
                if (_translatedParagraphs[index] != null)
                  Expanded(
                    child: SelectableText(
                      _translatedParagraphs[index]!,
                      style: TextStyle(
                        fontSize: _fontSize - 1,
                        height: 1.6,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
  
  // 构建带高亮和翻译功能的段落列表
  List<Widget> _buildHighlightedParagraphsWithTranslation() {
    return List.generate(_paragraphs.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 带高亮的原文
            SelectableText.rich(
              _processedTextSpan!.children![index] as TextSpan,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.8,
                color: Colors.black87,
              ),
            ),
            
            // 翻译按钮和翻译结果
            Row(
              children: [
                // 翻译按钮
                IconButton(
                  icon: _translatingParagraphs.contains(index)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate, size: 16),
                  tooltip: '翻译',
                  onPressed: _translatingParagraphs.contains(index)
                      ? null
                      : () => _translateParagraph(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                ),
                const SizedBox(width: 8),
                
                // 翻译结果
                if (_translatedParagraphs[index] != null)
                  Expanded(
                    child: SelectableText(
                      _translatedParagraphs[index]!,
                      style: TextStyle(
                        fontSize: _fontSize - 1,
                        height: 1.6,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
  
  // 构建单词定义卡片
  Widget _buildDefinitionCard(String word, String definition) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              word,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(definition),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // 添加到生词本
                    final dictWord = widget.dictionaryService.getWord(word);
                    if (dictWord != null) {
                      widget.dictionaryService.addToVocabulary(dictWord);
                      setState(() {
                        _wordStatusMap[word] = WordStatus.inVocabulary;
                        // 保持定义列表不变，只更新状态
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已添加到生词本: $word'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: const Text('添加到生词本'),
                ),
                TextButton(
                  onPressed: () {
                    // 移除定义
                    setState(() {
                      _wordDefinitions.remove(word);
                    });
                  },
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // 显示字体大小调整对话框
  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        double tempFontSize = _fontSize;
        return AlertDialog(
          title: const Text('调整字体大小'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '预览文本',
                    style: TextStyle(fontSize: tempFontSize),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          if (tempFontSize > 12) {
                            setState(() {
                              tempFontSize -= 1;
                            });
                          }
                        },
                      ),
                      Text('${tempFontSize.toInt()}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          if (tempFontSize < 24) {
                            setState(() {
                              tempFontSize += 1;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _fontSize = tempFontSize;
                });
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
  
  // 构建带有高亮单词的TextSpan
  TextSpan _buildTextSpanWithHighlightedWords(String text) {
    // 正则表达式匹配单词（英文单词）
    final RegExp wordRegex = RegExp(r'\b[a-zA-Z]+\b');
    
    // 存储所有TextSpan
    List<TextSpan> spans = [];
    
    // 上一个匹配结束位置
    int lastEnd = 0;
    
    // 查找所有单词
    final matches = wordRegex.allMatches(text);
    
    for (final match in matches) {
      // 添加匹配前的文本
      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start);
        spans.add(TextSpan(text: beforeText));
      }
      
      // 获取单词
      final word = match.group(0)!.toLowerCase();
      
      // 判断是否需要高亮（非常用单词且不在词典中）
      bool shouldHighlight = false;
      if (word.length > 1 && !_commonWords.contains(word)) {
        // 检查是否在词典中
        if (!widget.dictionaryService.containsWord(word)) {
          shouldHighlight = true;
        }
      }
      
      // 添加单词（高亮或普通）
      spans.add(
        TextSpan(
          text: match.group(0),
          style: shouldHighlight 
              ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
              : null,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (shouldHighlight) {
                _lookupWordDefinition(word);
              }
            },
        ),
      );
      
      // 更新上一个匹配结束位置
      lastEnd = match.end;
    }
    
    // 添加最后一部分文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    
    return TextSpan(children: spans);
  }
}

// 单词状态枚举
enum WordStatus {
  inDictionary,
  inVocabulary,
  unknown,
} 