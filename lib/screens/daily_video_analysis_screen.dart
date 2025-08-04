import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../services/daily_video_service.dart';
import '../services/subtitle_analysis_service.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../services/bailian_translation_service.dart';
import '../models/daily_video_model.dart';
import '../models/subtitle_model.dart';
import '../models/dictionary_word.dart'; // 添加DictionaryWord导入
import '../widgets/subtitle_selection_area.dart';
import '../widgets/real_time_study_duration.dart';

/// 今日视频汇总分析页面
class DailyVideoAnalysisScreen extends StatefulWidget {
  const DailyVideoAnalysisScreen({super.key});

  @override
  State<DailyVideoAnalysisScreen> createState() => _DailyVideoAnalysisScreenState();
}

class _DailyVideoAnalysisScreenState extends State<DailyVideoAnalysisScreen> {
  bool _isAnalyzing = false;
  bool _isAnalyzed = false;
  
  // 多视频分析结果
  MultiVideoAnalysisResult? _analysisResult;
  
  // 翻译相关
  final Map<String, String> _translations = {};
  final Map<String, bool> _showTranslations = {};
  final Set<String> _translatingWords = {};

  @override
  void initState() {
    super.initState();
    // 不在initState中直接调用_loadTodayAnalysis，而是延迟到didChangeDependencies中
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在第一次调用时执行分析
    if (!_isAnalyzing && !_isAnalyzed) {
      // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在下一帧执行
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTodayAnalysis();
      });
    }
  }

  /// 加载今日分析结果
  Future<void> _loadTodayAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _isAnalyzed = false;
    });

    try {
      final dailyVideoService = Provider.of<DailyVideoService>(context, listen: false);
      final analysisService = Provider.of<SubtitleAnalysisService>(context, listen: false);
      
      final todayList = dailyVideoService.currentDayList;
      debugPrint('今日分析: 获取今日列表, 列表为空: ${todayList == null}, 视频数量: ${todayList?.videos.length ?? 0}');
      
      if (todayList == null || todayList.videos.isEmpty) {
        _showMessage('今日视频列表为空，请先在左侧添加视频');
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }

      // 统计各种状态的视频
      final totalVideos = todayList.videos.length;
      final pendingVideos = todayList.videos.where((v) => v.analysisStatus == SubtitleAnalysisStatus.pending).length;
      final analyzingVideos = todayList.videos.where((v) => v.analysisStatus == SubtitleAnalysisStatus.analyzing).length;
      final completedVideos = todayList.videos.where((v) => v.analysisStatus == SubtitleAnalysisStatus.completed).length;
      final errorVideos = todayList.videos.where((v) => v.analysisStatus == SubtitleAnalysisStatus.error).length;
      
      debugPrint('今日分析状态: 总数=$totalVideos, 待分析=$pendingVideos, 分析中=$analyzingVideos, 已完成=$completedVideos, 错误=$errorVideos');

      // 直接从所有视频中尝试获取分析结果，不管状态标记
      final allVideoPaths = todayList.videos.map((v) => v.videoPath).toList();
      final allSubtitlePaths = todayList.videos.map((v) => v.subtitlePath).toList();
      
      debugPrint('今日视频路径和字幕路径：');
      for (int i = 0; i < todayList.videos.length; i++) {
        debugPrint('视频 ${i + 1}: ${todayList.videos[i].videoPath}');
        debugPrint('字幕 ${i + 1}: ${todayList.videos[i].subtitlePath ?? "null"}');
        debugPrint('分析状态: ${todayList.videos[i].analysisStatus}');
      }

      // 检查哪些视频实际有分析结果
      final actualAnalyzedPaths = <String>[];
      final actualSubtitlePaths = <String?>[];
      
      debugPrint('=== 检查分析结果 ===');
      // 显示当前缓存状态
      analysisService.debugCacheStatus();
      
      for (int i = 0; i < allVideoPaths.length; i++) {
        final videoPath = allVideoPaths[i];
        final subtitlePath = allSubtitlePaths[i];
        
        debugPrint('检查视频: $videoPath');
        debugPrint('字幕路径: $subtitlePath');
        
        final hasResult = analysisService.hasAnalysisResult(videoPath, subtitlePath);
        debugPrint('是否有分析结果: $hasResult');
        
        if (hasResult) {
          actualAnalyzedPaths.add(videoPath);
          actualSubtitlePaths.add(subtitlePath);
          debugPrint('✅ 找到分析结果: $videoPath');
        } else {
          debugPrint('❌ 未找到分析结果: $videoPath');
          // 尝试检查缓存的所有key
          final analysisServiceDebug = analysisService;
          debugPrint('当前缓存的分析结果数量: ${analysisServiceDebug.runtimeType}');
        }
      }
      
      if (actualAnalyzedPaths.isEmpty) {
        // 真的没有任何分析结果
        _showMessage('共有 $totalVideos 个视频，但内存中没有找到任何分析结果\n请确保视频已加载字幕并完成分析');
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }

      // 有分析结果，获取汇总
      debugPrint('今日分析: 从内存中找到 ${actualAnalyzedPaths.length} 个分析结果');
      final result = analysisService.getTodayAnalysisSummary(actualAnalyzedPaths, actualSubtitlePaths);
      
      if (result == null) {
        _showMessage('无法获取分析结果，分析服务返回null');
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
        _isAnalyzed = true;
      });
      
      debugPrint('今日分析: 汇总完成, 总单词: ${result.totalWords}, 需学习: ${result.uniqueNeedsLearningWords}');

      // 显示实际分析情况
      if (actualAnalyzedPaths.length < totalVideos) {
        final missingCount = totalVideos - actualAnalyzedPaths.length;
        _showMessage('汇总显示 ${actualAnalyzedPaths.length} 个视频的分析结果\n${missingCount} 个视频暂无分析结果');
      } else {
        _showMessage('汇总显示所有 ${actualAnalyzedPaths.length} 个视频的分析结果');
      }

    } catch (e) {
      debugPrint('今日分析错误: $e');
      _showMessage('分析失败: $e');
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  /// 显示消息
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// 重新分析
  Future<void> _reanalyze() async {
    await _loadTodayAnalysis();
  }

  /// 获取排序后的单词列表（只显示需要学习的单词）
  List<MapEntry<String, int>> _getSortedFilteredWords() {
    if (_analysisResult == null) return [];
    
    return _analysisResult!.needsLearningWords;
  }

  /// 获取简短的字幕文本用于显示
  String _getShortSubtitleText(String word) {
    if (_analysisResult == null) return '';
    
    final fullText = _analysisResult!.combinedWordToSubtitle[word.toLowerCase()] ?? '';
    if (fullText.length <= 100) return fullText;
    
    // 找到单词在句子中的位置
    final lowerText = fullText.toLowerCase();
    final wordIndex = lowerText.indexOf(word.toLowerCase());
    
    if (wordIndex == -1) return fullText.substring(0, 100) + '...';
    
    // 尝试获取单词前后各50个字符
    int start = (wordIndex - 50).clamp(0, fullText.length);
    int end = (wordIndex + word.length + 50).clamp(0, fullText.length);
    
    String result = fullText.substring(start, end);
    if (start > 0) result = '...$result';
    if (end < fullText.length) result = '$result...';
    
    return result;
  }

  /// 构建统计项目
  Widget _buildCompactStatItem({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }



  /// 构建基础的可视化组件
  Widget _buildBasicVisualization(List<DictionaryWord> allWords, Set<String> subtitleWords) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 格子可视化
        Expanded(
          child: MultiVideoSubtitleDictionaryCoverageVisualizer(
            allDictionaryWords: allWords,
            subtitleWords: subtitleWords,
          ),
        ),
      ],
    );
  }
  
  /// 构建统计项
  Widget _buildStatItem(String label, int count, Color color, int total) {
    final percentage = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $count ($percentage%)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortedWords = _getSortedFilteredWords();
    final dailyVideoService = Provider.of<DailyVideoService>(context);
    final todayStats = dailyVideoService.todayStats;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日视频汇总分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新分析',
            onPressed: _isAnalyzing ? null : _reanalyze,
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
                Text('正在汇总分析今日视频...'),
              ],
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：统计信息和词典覆盖可视化
              if (_isAnalyzed && _analysisResult != null)
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 今日学习统计
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📅 今日学习统计',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('视频数量: ${_analysisResult!.videoCount}'),
                                      Text('完成数量: ${todayStats.completedVideos}'),
                                      const RealTimeStudyDuration(),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('完成率: ${(todayStats.completionRate * 100).round()}%'),
                                      Text('分析率: ${(todayStats.analysisRate * 100).round()}%'),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // 词汇统计
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
                                  Text(
                                    '总单词: ${_analysisResult!.totalWords}', 
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('不同单词: ${_analysisResult!.uniqueWords}'),
                                ],
                              ),
                              // 分类统计
                              Row(
                                children: [
                                  _buildCompactStatItem(
                                    label: '需学',
                                    count: _analysisResult!.uniqueNeedsLearningWords,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildCompactStatItem(
                                    label: '熟知',
                                    count: _analysisResult!.uniqueFamiliarWords,
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
                              // 可视化组件
                              Expanded(
                                child: Consumer<DictionaryService>(
                                  builder: (context, dictionaryService, child) {
                                    // 获取所有词典单词
                                    final allDictionaryWords = dictionaryService.allWords;
                                    
                                    // 获取字幕中的所有单词（合并的）
                                    final subtitleWords = _analysisResult!.combinedWordFrequency.keys.toSet();
                                    
                                    if (allDictionaryWords.isEmpty || subtitleWords.isEmpty) {
                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.analytics, size: 48, color: Colors.grey.shade600),
                                            const SizedBox(height: 8),
                                            Text(
                                              '词典覆盖可视化',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '等待加载词典数据...',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    
                                    return _buildBasicVisualization(allDictionaryWords, subtitleWords);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // 右侧：单词列表
              if (_isAnalyzed && _analysisResult != null)
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 单词列表标题
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.list_alt, color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '需要学习的单词 (${sortedWords.length}个)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '按出现频率排序',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // 单词列表
                        Expanded(
                          child: sortedWords.isEmpty
                            ? const Center(child: Text('没有需要学习的单词，恭喜！'))
                            : ListView.builder(
                                itemCount: sortedWords.length,
                                itemBuilder: (context, index) {
                                  final entry = sortedWords[index];
                                  final lemma = entry.key;
                                  final count = entry.value;
                                  
                                  // 获取这个词根对应的所有原始单词形式
                                  final originalForms = _analysisResult!.combinedLemmaToOriginalWords[lemma] ?? {lemma};
                                  
                                  // 获取字幕文本
                                  final subtitleText = _getShortSubtitleText(lemma);
                                  
                                  // 获取翻译结果
                                  final fullSubtitle = _analysisResult!.combinedWordToSubtitle[lemma.toLowerCase()];
                                  final translationText = fullSubtitle != null ? _translations[fullSubtitle] : null;
                                  final showTranslation = _showTranslations[lemma] ?? false;
                                  
                                  // 确定边框颜色
                                  final dictionaryService = Provider.of<DictionaryService>(context);
                                  final isInDictionary = dictionaryService.allWords
                                      .any((dictionaryWord) => dictionaryWord.word.toLowerCase() == lemma.toLowerCase());
                                  
                                  final borderColor = isInDictionary 
                                      ? const Color(0xFFF44336) // Red - 词典中的未熟知单词
                                      : const Color(0xFFFFB84D); // Orange - 词典外的单词
                                  
                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      side: BorderSide(
                                        color: borderColor, 
                                        width: isInDictionary ? 2 : 1,
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
                                              // 如果有字幕，显示字幕
                                              if (subtitleText.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    subtitleText,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black87,
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
                                              child: Text(
                                                translationText,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black87,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text('出现 $count 次'),
                                      leading: Icon(
                                        isInDictionary 
                                          ? Icons.help_outline 
                                          : Icons.book,
                                        color: isInDictionary 
                                          ? Colors.red 
                                          : Colors.orange,
                                        size: 20,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 翻译按钮
                                          if (fullSubtitle != null)
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
                                                : () => _translateSubtitle(fullSubtitle, lemma),
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
                  ),
                ),
              
              // 如果没有分析结果，显示提示信息
              if (!_isAnalyzed || _analysisResult == null)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '还没有可用的分析数据',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '请先在今日视频列表中添加视频并完成加载',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  /// 翻译字幕
  Future<void> _translateSubtitle(String subtitleText, String word) async {
    setState(() {
      _showTranslations[word] = !(_showTranslations[word] ?? false);
    });

    // 如果是隐藏翻译，直接返回
    if (!(_showTranslations[word] ?? false)) {
      return;
    }

    // 如果已经有翻译结果，直接显示
    if (_translations.containsKey(subtitleText)) {
      return;
    }

    // 开始翻译
    setState(() {
      _translatingWords.add(word);
    });

    try {
      final translationText = await Provider.of<BailianTranslationService>(context, listen: false)
          .translateText(subtitleText);
      
      setState(() {
        _translations[subtitleText] = translationText;
        _translatingWords.remove(word);
      });
    } catch (e) {
      setState(() {
        _translations[subtitleText] = '翻译失败: $e';
        _translatingWords.remove(word);
      });
    }
  }
}

// 多视频字幕词典覆盖可视化组件
class MultiVideoSubtitleDictionaryCoverageVisualizer extends StatefulWidget {
  final List<DictionaryWord> allDictionaryWords; // 词典中的所有单词
  final Set<String> subtitleWords; // 字幕中出现的所有单词（多视频合并）
  final int pointSize;
  final int pointsPerRow;
  
  const MultiVideoSubtitleDictionaryCoverageVisualizer({
    super.key,
    required this.allDictionaryWords,
    required this.subtitleWords,
    this.pointSize = 4,
    this.pointsPerRow = 50,
  });
  
  @override
  State<MultiVideoSubtitleDictionaryCoverageVisualizer> createState() => _MultiVideoSubtitleDictionaryCoverageVisualizerState();
}

class _MultiVideoSubtitleDictionaryCoverageVisualizerState extends State<MultiVideoSubtitleDictionaryCoverageVisualizer> {
  // 当前悬停的单词索引
  int? _hoverWordIndex;
  bool _showTooltip = false;
  Offset _mousePosition = Offset.zero;
  // OverlayEntry用于显示悬停信息
  OverlayEntry? _overlayEntry;
  // 屏幕坐标到本地坐标的转换
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
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
        top: position.dy - 50, // 显示在鼠标上方
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
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // 插入到Overlay中
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    int pointsPerRow = widget.pointsPerRow;
    int pointSize = widget.pointSize;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 调整每行点数，使其适应可用宽度
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        
        // 点之间的间距
        final pointSpacing = 1;
        
        // 动态计算点的大小和每行点数
        int calculatedPointsPerRow;
        int effectivePointSize;
        
        if (widget.pointsPerRow <= 0) {
          // 自动计算模式 - 找到最优的格子大小充分利用空间
          
          // 尝试不同的格子大小，找到最佳的利用率
          int bestPointSize = 4;
          int bestPointsPerRow = 5;
          double bestUtilization = 0.0;
          
          // 从较大的格子开始尝试
          for (int testPointSize = 20; testPointSize >= 4; testPointSize--) {
            int testPointsPerRow = availableWidth ~/ (testPointSize + pointSpacing);
            if (testPointsPerRow < 5) continue; // 至少5列
            
            int testTotalRows = (widget.allDictionaryWords.length / testPointsPerRow).ceil();
            int testTotalHeight = testTotalRows * (testPointSize + pointSpacing);
            
            // 检查是否能放下所有格子
            if (testTotalHeight <= availableHeight) {
              // 计算空间利用率
              double utilization = (testTotalHeight.toDouble() / availableHeight) * 
                                  ((testPointsPerRow * testPointSize).toDouble() / availableWidth);
              
              if (utilization > bestUtilization) {
                bestUtilization = utilization;
                bestPointSize = testPointSize;
                bestPointsPerRow = testPointsPerRow;
              }
              
              // 如果找到一个能充分利用空间的方案，就使用它
              if (utilization > 0.7) { // 70%以上的利用率就很好了
                break;
              }
            }
          }
          
          effectivePointSize = bestPointSize;
          calculatedPointsPerRow = bestPointsPerRow;
          

        } else {
          // 使用用户指定的每行点数
          calculatedPointsPerRow = widget.pointsPerRow;
          effectivePointSize = math.max(3, (availableWidth / calculatedPointsPerRow - pointSpacing).floor());
        }
        
        pointsPerRow = calculatedPointsPerRow;
        
        return MouseRegion(
          onHover: (event) {
            final RenderBox? box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            
            final localPosition = box.globalToLocal(event.position);
            
            // 保存鼠标位置用于tooltip定位
            _mousePosition = localPosition;
            
            // 计算鼠标悬停的点索引
            final col = localPosition.dx ~/ (effectivePointSize + pointSpacing);
            final row = localPosition.dy ~/ (effectivePointSize + pointSpacing);
            
            if (col >= 0 && col < pointsPerRow && 
                row >= 0 && row * pointsPerRow + col < widget.allDictionaryWords.length) {
              final index = row * pointsPerRow + col;
              
              if (_hoverWordIndex != index) {
                setState(() {
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
              _showTooltip = false;
              _hoverWordIndex = null;
            });
            _removeOverlay();
          },
          child: Container(
            width: availableWidth,
            height: availableHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: MultiVideoSubtitleCoveragePainter(
                  allWords: widget.allDictionaryWords,
                  subtitleWords: widget.subtitleWords,
                  pointSize: effectivePointSize,
                  pointsPerRow: pointsPerRow,
                  pointSpacing: pointSpacing,
                  hoverIndex: _hoverWordIndex,
                ),
                size: Size(availableWidth, availableHeight),
              ),
            ),
          ),
        );
      }
    );
  }
}

// 自定义绘制器，用于绘制多视频字幕覆盖的点阵图
class MultiVideoSubtitleCoveragePainter extends CustomPainter {
  final List<DictionaryWord> allWords;
  final Set<String> subtitleWords; // 字幕中出现的所有单词（多视频合并）
  final int pointSize;
  final int pointsPerRow;
  final int? hoverIndex;
  final int pointSpacing;
  
  MultiVideoSubtitleCoveragePainter({
    required this.allWords,
    required this.subtitleWords,
    required this.pointSize,
    required this.pointsPerRow,
    this.hoverIndex,
    this.pointSpacing = 1,
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
        paint.color = const Color(0xFFE0E0E0); // Light gray
      } else {
        // 其他单词（在词典中但不在字幕中），使用灰色
        paint.color = const Color(0xFFBDBDBD); // Gray
      }
      
      // 如果当前点是鼠标悬停的点，使用高亮颜色
      if (i == hoverIndex) {
        paint.color = Colors.yellow;
      }
      
      canvas.drawRect(
        Rect.fromLTWH(x, y, pointSize.toDouble(), pointSize.toDouble()),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 总是重绘以支持悬停效果
  }
} 