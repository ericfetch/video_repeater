import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Added for jsonEncode and jsonDecode
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';

import '../models/dictionary_word.dart';
import '../services/dictionary_service.dart';

// 添加一个新的点阵图可视化组件
class VocabularyVisualizerWidget extends StatefulWidget {
  final List<DictionaryWord> allWords;
  final Set<String> reviewedWords;
  final int pointSize;
  final int pointsPerRow;
  
  const VocabularyVisualizerWidget({
    super.key,
    required this.allWords,
    required this.reviewedWords,
    this.pointSize = 4,
    this.pointsPerRow = 50,
  });
  
  @override
  State<VocabularyVisualizerWidget> createState() => _VocabularyVisualizerWidgetState();
}

class _VocabularyVisualizerWidgetState extends State<VocabularyVisualizerWidget> {
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
            AssetSource('audio/tick.mp3'), // 使用完整的资源相对路径
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
          int totalRows = (widget.allWords.length / calculatedPointsPerRow).ceil();
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
                  row >= 0 && row * pointsPerRow + col < widget.allWords.length) {
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
                  if (index < widget.allWords.length) {
                    _showWordTooltip(context, event.position, widget.allWords[index]);
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
                painter: VocabularyPainter(
                  allWords: widget.allWords,
                  reviewedWords: widget.reviewedWords,
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

// 自定义绘制器，用于绘制点阵图
class VocabularyPainter extends CustomPainter {
  final List<DictionaryWord> allWords;
  final Set<String> reviewedWords;
  final int pointSize;
  final int pointsPerRow;
  final int? hoverIndex;  // 添加悬停索引
  final int pointSpacing; // 点之间的间距
  
  VocabularyPainter({
    required this.allWords,
    required this.reviewedWords,
    required this.pointSize,
    required this.pointsPerRow,
    this.hoverIndex,
    this.pointSpacing = 2, // 默认间距为2像素
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
      
      // 设置颜色：未熟知为柔和的颜色，熟知为绿色，复习过的深绿色
      if (word.isFamiliar) {
        // 判断是否复习过
        if (reviewedWords.contains(word.word)) {
          // 已复习过的熟知单词，使用深绿色
          paint.color = const Color(0xFF196127);
        } else {
          // 未复习过的熟知单词，使用浅绿色
          paint.color = const Color(0xFF40C463);
        }
      } else {
        // 未熟知的单词，使用柔和的深灰色
        paint.color = const Color.fromARGB(255, 252, 251, 251); // 深灰色，柔和但可见
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
  bool shouldRepaint(VocabularyPainter oldDelegate) {
    return oldDelegate.allWords != allWords || 
           oldDelegate.reviewedWords != reviewedWords ||
           oldDelegate.hoverIndex != hoverIndex ||
           oldDelegate.pointSize != pointSize ||
           oldDelegate.pointSpacing != pointSpacing ||
           oldDelegate.pointsPerRow != pointsPerRow;
  }
}

class DictionaryManagementScreen extends StatefulWidget {
  const DictionaryManagementScreen({super.key});

  @override
  State<DictionaryManagementScreen> createState() => _DictionaryManagementScreenState();
}

class _DictionaryManagementScreenState extends State<DictionaryManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<DictionaryWord> _selectedWords = [];
  List<DictionaryWord> _filteredWords = [];
  bool _isLoading = false;
  String _statusMessage = '';
  
  // 进度指示器相关变量
  bool _showProgressIndicator = false;
  double _progressValue = 0.0;
  
  // 过滤选项
  bool? _showFamiliarFilter = null; // null表示显示全部，true只显示熟知，false只显示未熟知
  
  // 熟知单词复习相关变量
  List<DictionaryWord> _reviewWords = [];
  int _currentReviewIndex = 0;
  int _correctCount = 0;
  bool _isReviewing = false;
  
  // 添加变量，用于记录上次复习的日期和成绩
  DateTime? _lastReviewDate;
  String? _lastReviewScore;
  
  // 添加变量，用于记录累计复习进度
  int _totalReviewSessions = 0; // 总复习次数
  int _totalReviewWords = 0;    // 总复习词量
  int _totalCorrectWords = 0;   // 总正确词数
  
  // 跟踪已复习过的熟知单词
  Set<String> _reviewedFamiliarWords = {}; // 存储已复习过的熟知单词ID
  
  @override
  void initState() {
    super.initState();
    _loadDictionary(); // 加载词典数据
    // 从SharedPreferences加载累计复习数据
    _loadReviewStats();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 加载词典
  Future<void> _loadDictionary() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '加载词典数据...';
    });
    
    // 确保词典服务已初始化
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    if (!dictionaryService.isInitialized) {
      await dictionaryService.initialize();
    }
    
    _filterWords();
    
    setState(() {
      _isLoading = false;
      _statusMessage = '词典加载完成，共 ${dictionaryService.allWords.length} 个单词';
    });
  }
  
  // 清洗词典，将词汇还原并合并重复项
  Future<void> _cleanDictionary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清洗词典'),
        content: const Text(
          '此操作将使用最新的词形还原算法清洗词典：\n\n'
          '• 将单词还原到词根形式\n'
          '• 合并相同词根的重复单词\n'
          '• 保留最完整的单词信息\n\n'
          '清洗过程中会自动备份数据。\n'
          '确定要继续吗？'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始清洗'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isLoading = true;
      _statusMessage = '正在清洗词典...';
      _showProgressIndicator = true;
      _progressValue = 0.0;
    });
    
    try {
      final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
      final result = await dictionaryService.cleanDictionary();
      
      if (result['success'] == true) {
        setState(() {
          _statusMessage = '词典清洗完成！\n'
              '原始单词: ${result['originalCount']} 个\n'
              '合并后: ${result['finalCount']} 个\n'
              '减少了: ${result['merged']} 个重复单词';
        });
        
        // 重新加载词典数据
        await _loadDictionary();
        
        // 显示成功对话框
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('清洗完成'),
              ],
            ),
            content: Text(
              '词典清洗成功完成！\n\n'
              '原始单词数量: ${result['originalCount']}\n'
              '清洗后数量: ${result['finalCount']}\n'
              '合并的重复词: ${result['merged']}\n'
              '词根分组数: ${result['groups']}\n\n'
              '现在您的词典更加整洁，相同词根的变形已经合并。'
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        setState(() {
          _statusMessage = '清洗失败: ${result['message']}';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清洗失败: ${result['message']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = '清洗过程中发生错误: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清洗失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _showProgressIndicator = false;
      });
    }
  }
  
  void _filterWords() {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final query = _searchController.text.trim();
    
    setState(() {
      if (_showFamiliarFilter != null) {
        _filteredWords = dictionaryService.searchDictionaryWithFamiliar(query, _showFamiliarFilter);
      } else {
        _filteredWords = dictionaryService.searchDictionary(query);
      }
    });
  }
  
  Future<void> _importDictionary(String fileType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [fileType],
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          _isLoading = true;
          _statusMessage = '导入词典中...';
        });
        
        final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
        int count = 0;
        
        if (fileType == 'json') {
          count = await dictionaryService.importDictionaryFromJson(result.files.single.path!);
        } else if (fileType == 'csv') {
          count = await dictionaryService.importDictionaryFromCsv(result.files.single.path!);
        }
        
        _filterWords();
        
        setState(() {
          _isLoading = false;
          _statusMessage = '导入完成，共导入 $count 个单词';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '导入失败: $e';
      });
    }
  }
  
  Future<void> _exportDictionary(String fileType) async {
    try {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存词典文件',
        fileName: 'dictionary.$fileType',
      );
      
      if (outputPath != null) {
        setState(() {
          _isLoading = true;
          _statusMessage = '导出词典中...';
        });
        
        final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
        bool success = false;
        
        if (fileType == 'json') {
          success = await dictionaryService.exportDictionaryToJson(outputPath);
        } else if (fileType == 'csv') {
          success = await dictionaryService.exportDictionaryToCsv(outputPath);
        }
        
        setState(() {
          _isLoading = false;
          _statusMessage = success ? '导出成功' : '导出失败';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '导出失败: $e';
      });
    }
  }
  
  void _toggleWordSelection(DictionaryWord word) {
    setState(() {
      if (_selectedWords.contains(word)) {
        _selectedWords.remove(word);
      } else {
        _selectedWords.add(word);
      }
    });
  }
  
  void _selectAllWords() {
    setState(() {
      if (_selectedWords.length == _filteredWords.length) {
        // 如果已经全选，则取消全选
        _selectedWords.clear();
      } else {
        // 否则全选
        _selectedWords.clear();
        _selectedWords.addAll(_filteredWords);
      }
    });
  }
  
  void _deleteSelectedWords() {
    if (_selectedWords.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedWords.length} 个单词吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              setState(() {
                _isLoading = true;
                _statusMessage = '删除单词中...';
              });
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.removeWords(_selectedWords.map((w) => w.word).toList());
              
              _selectedWords.clear();
              _filterWords();
              
              setState(() {
                _isLoading = false;
                _statusMessage = '删除完成';
              });
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
  
  void _clearDictionary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空整个词典吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              setState(() {
                _isLoading = true;
                _statusMessage = '清空词典中...';
              });
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.clearDictionary();
              
              _selectedWords.clear();
              _filterWords();
              
              setState(() {
                _isLoading = false;
                _statusMessage = '词典已清空';
              });
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
  
  void _addNewWord() {
    final wordController = TextEditingController();
    final partOfSpeechController = TextEditingController();
    final definitionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加新单词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                decoration: const InputDecoration(
                  labelText: '单词',
                  hintText: '输入单词',
                ),
              ),
              TextField(
                controller: partOfSpeechController,
                decoration: const InputDecoration(
                  labelText: '词性',
                  hintText: '例如: n., v., adj.',
                ),
              ),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(
                  labelText: '释义',
                  hintText: '输入单词释义',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final word = wordController.text.trim();
              if (word.isEmpty) {
                return;
              }
              
              Navigator.of(context).pop();
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.addWord(DictionaryWord(
                word: word,
                partOfSpeech: partOfSpeechController.text.trim(),
                definition: definitionController.text.trim(),
                rank: 0,
              ));
              
              _filterWords();
              setState(() {
                _statusMessage = '添加单词成功';
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
  
  void _editWord(DictionaryWord word) {
    final wordController = TextEditingController(text: word.word);
    final partOfSpeechController = TextEditingController(text: word.partOfSpeech);
    final definitionController = TextEditingController(text: word.definition);
    final phoneticController = TextEditingController(text: word.phonetic);
    final cefrController = TextEditingController(text: word.cefr);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑单词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                decoration: const InputDecoration(
                  labelText: '单词',
                  hintText: '输入单词',
                ),
                readOnly: true, // 不允许修改单词本身
              ),
              TextField(
                controller: partOfSpeechController,
                decoration: const InputDecoration(
                  labelText: '词性',
                  hintText: '例如: n., v., adj.',
                ),
              ),
              TextField(
                controller: phoneticController,
                decoration: const InputDecoration(
                  labelText: '音标',
                  hintText: '例如: əˈbaʊt',
                ),
              ),
              TextField(
                controller: cefrController,
                decoration: const InputDecoration(
                  labelText: 'CEFR等级',
                  hintText: '例如: A1, B2, C1',
                ),
              ),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(
                  labelText: '释义',
                  hintText: '输入单词释义',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              word.partOfSpeech = partOfSpeechController.text.trim();
              word.definition = definitionController.text.trim();
              word.phonetic = phoneticController.text.trim();
              word.cefr = cefrController.text.trim();
              
              // 根据CEFR等级更新rank
              if (word.cefr != null && word.cefr!.isNotEmpty) {
                switch (word.cefr!.toUpperCase()) {
                  case 'A1': word.rank = 1; break;
                  case 'A2': word.rank = 2; break;
                  case 'B1': word.rank = 3; break;
                  case 'B2': word.rank = 4; break;
                  case 'C1': word.rank = 5; break;
                  case 'C2': word.rank = 6; break;
                }
              }
              
              await dictionaryService.updateWord(word);
              
              _filterWords();
              setState(() {
                _statusMessage = '更新单词成功';
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  // 批量查询单词信息
  Future<void> _enrichSelectedWords() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要查询的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认查询'),
        content: Text('确定要查询选中的 ${_selectedWords.length} 个单词的详细信息吗？这将通过网络API查询单词的释义和词性。'),
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
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在查询单词信息...';
    });
    
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final wordList = _selectedWords.map((w) => w.word).toList();
    
    try {
      final results = await dictionaryService.enrichWordsWithAPI(
        wordList,
        batchSize: 5,
        onProgress: (current, total) {
          setState(() {
            _progressValue = current / total;
          });
        },
      );
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询完成: 成功 ${results['success']}，跳过 ${results['skipped']}，失败 ${results['failed']}';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询失败: $e';
      });
    }
  }
  
  // 批量查询所有无释义单词
  Future<void> _enrichAllIncompleteWords() async {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final incompleteWords = dictionaryService.allWords
        .where((word) => word.definition == null || word.partOfSpeech == null)
        .map((word) => word.word)
        .toList();
    
    if (incompleteWords.isEmpty) {
      setState(() {
        _statusMessage = '没有找到需要补充信息的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认查询'),
        content: Text('找到 ${incompleteWords.length} 个缺少释义或词性的单词，确定要查询它们的详细信息吗？'),
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
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在查询单词信息...';
    });
    
    try {
      final results = await dictionaryService.enrichWordsWithAPI(
        incompleteWords,
        batchSize: 5,
        onProgress: (current, total) {
          setState(() {
            _progressValue = current / total;
          });
        },
      );
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询完成: 成功 ${results['success']}，跳过 ${results['skipped']}，失败 ${results['failed']}';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询失败: $e';
      });
    }
  }
  
  // 将数字排名转换为CEFR等级
  String _getCefrFromRank(int rank) {
    switch (rank) {
      case 1: return 'A1';
      case 2: return 'A2';
      case 3: return 'B1';
      case 4: return 'B2';
      case 5: return 'C1';
      case 6: return 'C2';
      default: return rank.toString();
    }
  }
  
  void _showWordDetails(DictionaryWord word) {
    // Implementation of _showWordDetails method
  }
  
  // 批量标记选中的单词为熟知
  Future<void> _markSelectedWordsAsFamiliar() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要标记的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认标记'),
        content: Text('确定要将选中的 ${_selectedWords.length} 个单词标记为熟知吗？'),
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
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在标记单词...';
    });
    
    try {
      final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
      int count = 0;
      
      for (int i = 0; i < _selectedWords.length; i++) {
        await dictionaryService.markAsFamiliar(_selectedWords[i].word);
        count++;
        
        setState(() {
          _progressValue = i / _selectedWords.length;
        });
      }
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '成功标记 $count 个单词为熟知';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '标记失败: $e';
      });
    }
  }
  
  // 批量取消标记选中的单词为熟知
  Future<void> _unmarkSelectedWordsAsFamiliar() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要取消标记的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认取消标记'),
        content: Text('确定要取消选中的 ${_selectedWords.length} 个单词的熟知标记吗？'),
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
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在取消标记单词...';
    });
    
    try {
      final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
      int count = 0;
      
      for (int i = 0; i < _selectedWords.length; i++) {
        await dictionaryService.unmarkAsFamiliar(_selectedWords[i].word);
        count++;
        
        setState(() {
          _progressValue = i / _selectedWords.length;
        });
      }
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '成功取消 $count 个单词的熟知标记';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '取消标记失败: $e';
      });
    }
  }
  
  // 开始熟知单词复习
  Future<void> _startFamiliarWordsReview() async {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final familiarWords = dictionaryService.familiarWords;
    
    if (familiarWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无熟知单词可供复习'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 优先选择未复习过的熟知单词
    List<DictionaryWord> unreviewed = [];
    List<DictionaryWord> reviewed = [];
    
    for (var word in familiarWords) {
      if (_reviewedFamiliarWords.contains(word.word)) {
        reviewed.add(word);
      } else {
        unreviewed.add(word);
      }
    }
    
    // 如果未复习过的单词不足20个，则从已复习过的单词中补充
    if (unreviewed.length < 20) {
      reviewed.shuffle();
      unreviewed.addAll(reviewed.take(20 - unreviewed.length));
    }
    
    // 打乱顺序，最多取20个单词
    unreviewed.shuffle();
    final wordsToReview = unreviewed.take(20).toList();
    
    setState(() {
      _reviewWords = wordsToReview;
      _currentReviewIndex = 0;
      _correctCount = 0;
      _isReviewing = true;
    });
    
    _showReviewDialog();
  }
  
  // 加载累计复习统计数据
  Future<void> _loadReviewStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalReviewSessions = prefs.getInt('totalReviewSessions') ?? 0;
      _totalReviewWords = prefs.getInt('totalReviewWords') ?? 0;
      _totalCorrectWords = prefs.getInt('totalCorrectWords') ?? 0;
      
      // 加载已复习过的熟知单词ID集合
      final reviewedWordsJson = prefs.getString('reviewedFamiliarWords');
      if (reviewedWordsJson != null) {
        final List<dynamic> wordsList = jsonDecode(reviewedWordsJson);
        _reviewedFamiliarWords = wordsList.map((e) => e.toString()).toSet();
      }
      
      // 也加载上次复习记录
      final lastReviewDateStr = prefs.getString('lastReviewDate');
      if (lastReviewDateStr != null) {
        _lastReviewDate = DateTime.parse(lastReviewDateStr);
        _lastReviewScore = prefs.getString('lastReviewScore');
      }
    });
  }
  
  // 保存累计复习统计数据
  Future<void> _saveReviewStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('totalReviewSessions', _totalReviewSessions);
    await prefs.setInt('totalReviewWords', _totalReviewWords);
    await prefs.setInt('totalCorrectWords', _totalCorrectWords);
    
    // 保存已复习过的熟知单词ID集合
    await prefs.setString('reviewedFamiliarWords', jsonEncode(_reviewedFamiliarWords.toList()));
    
    // 也保存上次复习记录
    if (_lastReviewDate != null) {
      await prefs.setString('lastReviewDate', _lastReviewDate!.toIso8601String());
      await prefs.setString('lastReviewScore', _lastReviewScore ?? '');
    }
  }
  
  // 显示复习对话框
  void _showReviewDialog() {
    if (_reviewWords.isEmpty || _currentReviewIndex >= _reviewWords.length) {
      // 复习完成，更新累计统计数据
      setState(() {
        _isReviewing = false;
        _lastReviewDate = DateTime.now();
        _lastReviewScore = '$_correctCount/${_reviewWords.length}';
        
        // 更新累计数据
        _totalReviewSessions++;
        _totalReviewWords += _reviewWords.length;
        _totalCorrectWords += _correctCount;
        
        // 更新已复习单词集合
        for (var word in _reviewWords) {
          _reviewedFamiliarWords.add(word.word);
        }
        
        // 保存统计数据
        _saveReviewStats();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('复习完成! 共 $_correctCount/${_reviewWords.length} 个单词答对'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    
    final currentWord = _reviewWords[_currentReviewIndex];
    bool isDefinitionVisible = false;
    bool isLoadingDefinition = false;
    
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '复习熟知单词 (${_currentReviewIndex + 1}/${_reviewWords.length})',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _isReviewing = false;
                      _reviewWords = [];
                      _currentReviewIndex = 0;
                    });
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('复习已中断'),
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
                crossAxisAlignment: CrossAxisAlignment.start, // 确保所有内容靠左对齐
                children: [
                  Text(
                    currentWord.word,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (currentWord.phonetic != null && currentWord.phonetic!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '[${currentWord.phonetic!}]',
                        style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  if (currentWord.partOfSpeech != null && currentWord.partOfSpeech!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '词性: ${currentWord.partOfSpeech!}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  
                  const Divider(height: 24),
                  
                  // 显示/隐藏释义按钮 - 改为靠左对齐
                  Align(
                    alignment: Alignment.centerLeft,
                    child: isLoadingDefinition
                        ? const Column(
                            crossAxisAlignment: CrossAxisAlignment.start, // 靠左对齐
                            children: [
                              SizedBox(
                                width: 24, // 设置较小的宽度
                                height: 24, // 设置较小的高度
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(height: 8),
                              Text('正在查询释义...', style: TextStyle(fontSize: 14))
                            ],
                          )
                        : ElevatedButton(
                            onPressed: () async {
                              // 检查是否有释义
                              bool hasDefinition = currentWord.definition != null && 
                                                  currentWord.definition!.isNotEmpty;
                              
                              // 如果没有释义，调用API查询
                              if (!hasDefinition && !isDefinitionVisible) {
                                // 显示加载状态
                                setDialogState(() {
                                  isLoadingDefinition = true;
                                });
                                
                                // 使用页面中已有的API查询方法
                                final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
                                // 创建临时选中单词列表
                                _selectedWords.clear();
                                _selectedWords.add(currentWord);
                                
                                // 使用现有的批量查询方法
                                await _enrichSelectedWords();
                                
                                // 查询完成后更新状态
                                if (mounted && dialogContext.mounted) {
                                  // 获取更新后的单词
                                  final updatedWord = dictionaryService.getWord(currentWord.word);
                                  if (updatedWord != null) {
                                    // 更新复习单词列表
                                    final index = _currentReviewIndex;
                                    if (index >= 0 && index < _reviewWords.length) {
                                      _reviewWords[index] = updatedWord;
                                    }
                                  }
                                  // 清空临时选中列表
                                  _selectedWords.clear();
                                  
                                  // 更新UI状态
                                  setDialogState(() {
                                    isLoadingDefinition = false;
                                    isDefinitionVisible = true;
                                  });
                                }
                              } else {
                                // 如果已有释义，直接切换显示状态
                                setDialogState(() {
                                  isDefinitionVisible = !isDefinitionVisible;
                                });
                              }
                            },
                            child: Text(isDefinitionVisible ? '隐藏释义' : '查看释义'),
                          ),
                  ),
                  
                  // 释义内容
                  if (isDefinitionVisible && !isLoadingDefinition) ...[
                    if (currentWord.definition != null && currentWord.definition!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currentWord.definition!,
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '未找到释义',
                          style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start, // 按钮靠左对齐
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      setState(() {
                        _currentReviewIndex++;
                      });
                      _showReviewDialog(); // 显示下一个单词
                    },
                    child: const Text('不记得'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      setState(() {
                        _correctCount++;
                        _currentReviewIndex++;
                      });
                      _showReviewDialog(); // 显示下一个单词
                    },
                    child: const Text('记得'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
  
  // 显示重置复习进度对话框
  void _showResetReviewProgressDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置复习进度'),
        content: const Text('确定要重置复习进度吗？这将清空已复习单词记录，但不会影响您的熟知单词标记。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _resetReviewProgress();
              Navigator.of(context).pop();
            },
            child: const Text('确定重置'),
          ),
        ],
      ),
    );
  }
  
  // 重置复习进度
  Future<void> _resetReviewProgress() async {
    setState(() {
      _reviewedFamiliarWords.clear();
      // 保留总复习次数、总词量和总正确数的统计
    });
    
    await _saveReviewStats();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('复习进度已重置'),
        backgroundColor: Colors.blue,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词典管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewWord,
            tooltip: '添加新单词',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _selectedWords.isNotEmpty ? _deleteSelectedWords : null,
            tooltip: '删除选中的单词',
          ),
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _filteredWords.isNotEmpty ? _selectAllWords : null,
            tooltip: '全选/取消全选',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _selectedWords.isNotEmpty ? _enrichSelectedWords : null,
            tooltip: '查询选中单词的详细信息',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'import_json':
                  _importDictionary('json');
                  break;
                case 'import_csv':
                  _importDictionary('csv');
                  break;
                case 'export_json':
                  _exportDictionary('json');
                  break;
                case 'export_csv':
                  _exportDictionary('csv');
                  break;
                case 'enrich_all':
                  _enrichAllIncompleteWords();
                  break;
                case 'mark_familiar':
                  _markSelectedWordsAsFamiliar();
                  break;
                case 'unmark_familiar':
                  _unmarkSelectedWordsAsFamiliar();
                  break;
                case 'clear':
                  _clearDictionary();
                  break;
                case 'review_familiar':
                  _startFamiliarWordsReview();
                  break;
                case 'reset_review_progress':
                  _showResetReviewProgressDialog();
                  break;
                case 'clean_dictionary':
                  _cleanDictionary();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import_json',
                child: Text('导入JSON词典'),
              ),
              const PopupMenuItem(
                value: 'import_csv',
                child: Text('导入CSV词典'),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: Text('导出为JSON'),
              ),
              const PopupMenuItem(
                value: 'export_csv',
                child: Text('导出为CSV'),
              ),
              const PopupMenuItem(
                value: 'enrich_all',
                child: Text('查询所有缺失信息的单词'),
              ),
              const PopupMenuItem(
                value: 'clean_dictionary',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services, size: 18),
                    SizedBox(width: 8),
                    Text('清洗词典（词形还原）'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mark_familiar',
                child: Text('标记选中单词为熟知'),
              ),
              const PopupMenuItem(
                value: 'unmark_familiar',
                child: Text('取消选中单词的熟知标记'),
              ),
              const PopupMenuItem(
                value: 'review_familiar',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('复习熟知单词'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空词典'),
              ),
              const PopupMenuItem(
                value: 'reset_review_progress',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 18),
                    SizedBox(width: 8),
                    Text('重置复习进度'),
                  ],
                ),
          ),
        ],
      ),
          const PopupMenuItem(
            value: 'review_familiar',
            child: Row(
        children: [
                Icon(Icons.refresh, size: 18),
                SizedBox(width: 8),
                Text('复习熟知单词'),
              ],
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：复习记录和点阵图（垂直布局）
          Expanded(
            flex: 4, // 左侧占整体宽度的40%
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // 状态信息和进度条
          if (_isLoading || _statusMessage.isNotEmpty || _showProgressIndicator)
            Container(
              width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_statusMessage.isNotEmpty)
                    Text(_statusMessage),
                  if (_isLoading)
                    const LinearProgressIndicator(),
                  if (_showProgressIndicator)
                    LinearProgressIndicator(value: _progressValue),
                ],
              ),
            ),
          
                  // 复习记录部分
                  Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 4.0),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Consumer<DictionaryService>(
                  builder: (context, dictionaryService, child) {
                    final totalWords = dictionaryService.allWords.length;
                    final familiarWords = dictionaryService.familiarWords.length;
                    final percentage = totalWords > 0 
                        ? (familiarWords / totalWords * 100).toStringAsFixed(1) 
                        : '0';
                        
                          // 格式化上次复习信息
                          String lastReviewInfo = '';
                          if (_lastReviewDate != null && _lastReviewScore != null) {
                            final dateStr = '${_lastReviewDate!.month}/${_lastReviewDate!.day} ${_lastReviewDate!.hour}:${_lastReviewDate!.minute.toString().padLeft(2, '0')}';
                            lastReviewInfo = ' | 上次复习: $dateStr ($_lastReviewScore)';
                          }
                          
                          // 计算总复习正确率
                          final overallPercentage = _totalReviewWords > 0 
                              ? (_totalCorrectWords / _totalReviewWords * 100).toStringAsFixed(1) 
                              : '0';
                          
                          // 计算已复习的熟知单词比例
                          final totalFamiliarCount = familiarWords;
                          final reviewedFamiliarCount = _reviewedFamiliarWords.length;
                          final reviewedPercentage = totalFamiliarCount > 0
                              ? (reviewedFamiliarCount / totalFamiliarCount * 100).toStringAsFixed(1)
                              : '0';
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                      '总单词: $totalWords  |  熟知单词: $familiarWords ($percentage%)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                textAlign: TextAlign.left,
                              ),
                              if (_lastReviewDate != null)
                                Text(
                                  lastReviewInfo,
                                  style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                                  textAlign: TextAlign.left,
                                ),
                              // 添加累计复习统计信息
                              if (_totalReviewSessions > 0)
                                Text(
                                  '复习总进度: $_totalReviewSessions 次 | $_totalCorrectWords/$_totalReviewWords 词 (${overallPercentage}%)',
                                  style: TextStyle(fontSize: 11, color: Colors.green[700]),
                                  textAlign: TextAlign.left,
                                ),
                              // 添加熟知单词复习进度
                              if (familiarWords > 0)
                                Text(
                                  '熟知单词复习: $reviewedFamiliarCount/$familiarWords 词 (${reviewedPercentage}%)',
                                  style: TextStyle(fontSize: 11, color: Colors.purple[700]),
                                  textAlign: TextAlign.left,
                                ),
                            ],
                    );
                  },
                ),
                    ),
                  ),
                  
                  // 点阵图
                  Expanded(
                    child: Card(
                      elevation: 1,
                      margin: EdgeInsets.zero, // 移除卡片边距
                      child: Padding(
                        padding: const EdgeInsets.all(2.0), // 进一步减少内边距
                        child: Consumer<DictionaryService>(
                          builder: (context, dictionaryService, child) {
                            return VocabularyVisualizerWidget(
                              allWords: dictionaryService.allWords,
                              reviewedWords: _reviewedFamiliarWords,
                              pointSize: 8, // 进一步增大点的大小
                              pointsPerRow: 0, // 设为0让组件自动计算每行点数
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 右侧：单词搜索和列表（垂直布局）
          Expanded(
            flex: 6, // 右侧占整体宽度的60%
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // 搜索框和过滤选项
                  Row(
                    children: [
                      // 搜索框
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: '搜索单词',
                            hintText: '输入关键词搜索',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterWords();
                                  },
                                )
                              : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => _filterWords(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 过滤下拉框
                      DropdownButton<bool?>(
                        value: _showFamiliarFilter,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('全部单词')),
                          DropdownMenuItem(value: true, child: Text('熟知单词')),
                          DropdownMenuItem(value: false, child: Text('未熟知单词')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _showFamiliarFilter = value;
                      _filterWords();
                    });
                  },
                  hint: const Text('过滤'),
                ),
                ],
            ),
          
          // 选中单词信息
          if (_selectedWords.isNotEmpty)
            Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
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
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _filteredWords.length,
                  itemBuilder: (context, index) {
                    final word = _filteredWords[index];
                    final isSelected = _selectedWords.contains(word);
                    
                    return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 选择框
                            Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                _toggleWordSelection(word);
                              },
                            ),
                            
                            // 单词内容
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 单词、词性和CEFR等级
                                  Row(
                                    children: [
                                      // 单词
                                      Text(
                                        word.word,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      
                                      // 词性
                                      if (word.partOfSpeech != null && word.partOfSpeech!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            word.partOfSpeech!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.secondary,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      
                                      // 音标
                                      if (word.phonetic != null && word.phonetic!.isNotEmpty)
                                        Text(
                                          '[${word.phonetic!}]',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      
                                      // CEFR等级
                                      if (word.cefr != null || word.rank != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            word.getCefrString() ?? _getCefrFromRank(word.rank ?? 0),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      
                                      // 熟知标签
                                      if (word.isFamiliar)
                                        Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            '熟知',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  // 定义
                                  if (word.definition != null && word.definition!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        word.definition!,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            // 编辑按钮
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _editWord(word),
                              tooltip: '编辑单词',
                            ),
                            
                            // 熟知切换按钮
                            IconButton(
                              icon: Icon(
                                word.isFamiliar 
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                                size: 20,
                                color: word.isFamiliar ? Colors.blue : null,
                              ),
                              onPressed: () async {
                                final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
                                if (word.isFamiliar) {
                                  await dictionaryService.unmarkAsFamiliar(word.word);
                                } else {
                                  await dictionaryService.markAsFamiliar(word.word);
                                }
                                _filterWords();
                              },
                              tooltip: word.isFamiliar ? '取消标记为熟知' : '标记为熟知',
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
        ],
      ),
    );
  }
} 