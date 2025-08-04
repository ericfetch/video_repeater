import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/daily_video_service.dart';
import '../services/subtitle_analysis_service.dart';
import '../services/dictionary_service.dart';
import '../models/dictionary_word.dart';
import 'daily_video_list_widget.dart';
import '../screens/daily_video_analysis_screen.dart';
import 'real_time_study_duration.dart';

/// 今日视频仪表板组件
/// 左侧：视频列表，右侧：分析数据
class DailyVideoDashboardWidget extends StatelessWidget {
  final VoidCallback? onHide;
  
  const DailyVideoDashboardWidget({super.key, this.onHide});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧：视频列表
        SizedBox(
          width: 320,
          child: DailyVideoListWidget(
            onHide: onHide,
          ),
        ),
        
        // 分隔线
        Container(
          width: 1,
          color: Colors.grey.shade300,
        ),
        
        // 右侧：分析数据
        Expanded(
          child: _buildAnalysisPanel(),
        ),
      ],
    );
  }

  Widget _buildAnalysisPanel() {
    return Consumer2<DailyVideoService, SubtitleAnalysisService>(
      builder: (context, dailyVideoService, subtitleAnalysisService, child) {
        final todayVideos = dailyVideoService.todayVideos;
        final stats = dailyVideoService.todayStats;
        
        // 检查是否有视频需要分析
        if (todayVideos.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '还没有添加视频',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  '添加视频后将显示学习分析',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // 获取分析结果
        final videoPaths = todayVideos.map((video) => video.videoPath).toList();
        final subtitlePaths = todayVideos.map((video) => video.subtitlePath).toList();
        
        final analysisResult = subtitleAnalysisService.getTodayAnalysisSummary(videoPaths, subtitlePaths);
        
        if (analysisResult == null) {
          // 检查是否有视频有字幕路径
          final videosWithSubtitles = subtitlePaths.where((path) => path != null).length;
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('正在分析视频字幕...'),
                const SizedBox(height: 8),
                Text(
                  '共 ${videoPaths.length} 个视频，其中 $videosWithSubtitles 个有字幕',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (videosWithSubtitles == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '请先加载视频以自动匹配字幕',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
              ],
            ),
          );
        }

        // 获取需要学习的单词（排序后）
        final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
        final sortedWords = _getSortedFilteredWords(analysisResult, dictionaryService);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：统计信息和词典覆盖可视化
            Expanded(
              flex: 7,
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
                                  Text('视频数量: ${analysisResult.videoCount}'),
                                  Text('完成数量: ${stats.completedVideos}'),
                                  const RealTimeStudyDuration(),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('完成率: ${(stats.completionRate * 100).round()}%'),
                                  Text('分析率: ${(stats.analysisRate * 100).round()}%'),
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
                                '总单词: ${analysisResult.totalWords}', 
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('不同单词: ${analysisResult.uniqueWords}'),
                            ],
                          ),
                          // 分类统计
                          Row(
                            children: [
                              _buildCompactStatItem(
                                label: '需学',
                                count: analysisResult.uniqueNeedsLearningWords,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              _buildCompactStatItem(
                                label: '熟知',
                                count: analysisResult.uniqueFamiliarWords,
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
                                
                                // 获取字幕中的所有单词（合并的，已去重）
                                final subtitleWords = analysisResult.combinedSubtitleWords;
                                

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
                                
                                return MultiVideoSubtitleDictionaryCoverageVisualizer(
                                  allDictionaryWords: allDictionaryWords,
                                  subtitleWords: subtitleWords,
                                  pointSize: 8, // 自动模式下会被覆盖，但设置一个合理的默认值
                                  pointsPerRow: 0, // 0表示自动计算，充分利用空间
                                );
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
            Expanded(
              flex: 3,
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
                              final originalForms = analysisResult.combinedLemmaToOriginalWords[lemma] ?? {lemma};
                              
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
                                      // 单词
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
                                        ],
                                      ),
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
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 获取排序和过滤后的单词列表
  List<MapEntry<String, int>> _getSortedFilteredWords(dynamic analysisResult, DictionaryService dictionaryService) {
    return analysisResult.needsLearningWords;
  }

  /// 构建紧凑的统计项
  Widget _buildCompactStatItem({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 