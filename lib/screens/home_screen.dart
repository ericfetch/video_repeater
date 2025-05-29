import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../services/video_service.dart';
import '../services/history_service.dart';
import '../services/vocabulary_service.dart';
import '../services/message_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/subtitle_control_widget.dart';
import '../widgets/history_list_widget.dart';
import '../widgets/vocabulary_list_widget.dart';
import '../models/history_model.dart';
import 'config_screen.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _currentVideoPath;
  String? _currentSubtitlePath;
  String _appTitle = '视频复读机';
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // 用于访问SubtitleControlWidget的状态
  final _subtitleControlKey = GlobalKey<SubtitleControlWidgetState>();
  
  // 侧边栏显示内容
  bool _showVocabulary = false; // true表示显示生词本，false表示显示历史记录
  
  late FocusNode _focusNode;
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadVocabulary();
    _focusNode = FocusNode();
    
    // 添加窗口焦点变化的监听
    WidgetsBinding.instance.addObserver(this);
    
    // 确保初始获得焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    
    // 监听历史服务变化
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.addListener(_onHistoryServiceChanged);
  }
  
  @override
  void dispose() {
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.removeListener(_onHistoryServiceChanged);
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用恢复到前台时，请求焦点
    if (state == AppLifecycleState.resumed) {
      _focusNode.requestFocus();
    }
  }
  
  // 当历史记录服务状态变化时
  void _onHistoryServiceChanged() {
    final historyService = Provider.of<HistoryService>(context, listen: false);
    final currentHistory = historyService.currentHistory;
    
    // 如果从历史记录加载了视频，更新标题
    if (currentHistory != null && 
        _currentVideoPath != currentHistory.videoPath) {
      _currentVideoPath = currentHistory.videoPath;
      _currentSubtitlePath = currentHistory.subtitlePath;
      _updateAppTitle(currentHistory.videoPath);
      
      // 同时加载该视频的生词本
      if (_currentVideoPath != null) {
        final videoName = path.basename(_currentVideoPath!);
        final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
        vocabularyService.setCurrentVideo(videoName);
        vocabularyService.loadVocabularyList(videoName);
      }
    }
  }
  
  // 保存当前进度到历史记录
  void _saveCurrentProgress() {
    final videoService = Provider.of<VideoService>(context, listen: false);
    final historyService = Provider.of<HistoryService>(context, listen: false);
    
    if (_currentVideoPath != null && 
        _currentSubtitlePath != null && 
        videoService.player != null) {
      
      final videoName = path.basename(_currentVideoPath!);
      final position = videoService.currentPosition;
      
      final history = VideoHistory(
        videoPath: _currentVideoPath!,
        subtitlePath: _currentSubtitlePath!,
        videoName: videoName,
        lastPosition: position,
        timestamp: DateTime.now(),
      );
      
      historyService.addHistory(history);
    }
  }
  
  // 显示提示消息 (公开方法，供其他组件调用)
  void _showSnackBar(String message) {
    final messageService = Provider.of<MessageService>(context, listen: false);
    messageService.showMessage(message);
  }
  
  // 更新应用标题
  void _updateAppTitle(String videoPath) {
    setState(() {
      _appTitle = path.basename(videoPath);
    });
  }
  
  // 处理键盘快捷键
  void _handleKeyEvent(RawKeyEvent event, BuildContext context) {
    if (event is RawKeyDownEvent) {
      final videoService = Provider.of<VideoService>(context, listen: false);
      
      // 检查播放器是否已初始化
      if (videoService.player == null) {
        return;
      }
      
      // 如果按下空格键，切换播放/暂停
      if (event.logicalKey == LogicalKeyboardKey.space) {
        videoService.togglePlay();
        _showSnackBar(videoService.player!.state.playing ? '播放' : '暂停');
      }
      // 如果按下左箭头键，回退5秒
      else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        videoService.seek(Duration(milliseconds: 
          (videoService.currentPosition.inMilliseconds - 5000).clamp(0, videoService.duration.inMilliseconds)
        ));
        _showSnackBar('回退5秒');
      }
      // 如果按下右箭头键，前进5秒
      else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        videoService.seek(Duration(milliseconds: 
          (videoService.currentPosition.inMilliseconds + 5000).clamp(0, videoService.duration.inMilliseconds)
        ));
        _showSnackBar('前进5秒');
      }
      // 如果按下上箭头键，前进到下一个字幕
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
           videoService.previousSubtitle();
        _showSnackBar('上一句');
      }
      // 如果按下下箭头键，回退到上一个字幕
      else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
         videoService.nextSubtitle();
        _showSnackBar('下一句');
    
      }
      // 如果按下 'r' 键，切换循环模式
      else if (event.logicalKey == LogicalKeyboardKey.keyR) {
        videoService.toggleLoop();
        _showSnackBar(videoService.isLooping ? '开始循环' : '停止循环');
      }
      // 如果按下 's' 键，切换字幕模糊
      else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        final subtitleControlWidget = _subtitleControlKey.currentState;
        if (subtitleControlWidget != null) {
          subtitleControlWidget.toggleSubtitleBlur();
          _showSnackBar(subtitleControlWidget.isSubtitleBlurred ? '字幕已模糊' : '字幕已显示');
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final videoService = Provider.of<VideoService>(context);
    
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (event) => _handleKeyEvent(event, context),
      autofocus: true,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(_appTitle),
          actions: [
            // 帮助按钮
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: '帮助',
              onPressed: () => _showHelpDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.video_library),
              onPressed: () async {
                final videoPath = await videoService.pickVideoFile();
                if (videoPath != null) {
                  _currentVideoPath = videoPath;
                  _updateAppTitle(videoPath);
                  _showSnackBar('正在加载视频: ${path.basename(videoPath)}');
                  final success = await videoService.loadVideo(videoPath);
                  if (success) {
                    _showSnackBar('视频加载成功');
                    
                    // 加载该视频的生词本
                    final videoName = path.basename(videoPath);
                    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
                    vocabularyService.setCurrentVideo(videoName);
                    vocabularyService.loadVocabularyList(videoName);
                  }
                }
              },
              tooltip: '选择视频',
            ),
            IconButton(
              icon: const Icon(Icons.subtitles),
              onPressed: () async {
                if (videoService.player == null) {
                  _showSnackBar('请先选择视频文件');
                  return;
                }
                
                final subtitlePath = await videoService.pickSubtitleFile();
                if (subtitlePath != null) {
                  _currentSubtitlePath = subtitlePath;
                  _showSnackBar('正在加载字幕: ${path.basename(subtitlePath)}');
                  final success = await videoService.loadSubtitle(subtitlePath);
                  if (success) {
                    _showSnackBar('字幕加载成功');
                  }
                }
              },
              tooltip: '选择字幕',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () {
                _saveCurrentProgress();
                _showSnackBar('已保存当前进度');
              },
              tooltip: '保存进度',
            ),
            // 历史记录按钮
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '查看历史记录',
              onPressed: () {
                setState(() {
                  _showVocabulary = false;
                });
                _scaffoldKey.currentState?.openEndDrawer();
              },
            ),
            // 生词本按钮
            IconButton(
              icon: const Icon(Icons.book),
              tooltip: '查看生词本',
              onPressed: () {
                setState(() {
                  _showVocabulary = true;
                });
                _scaffoldKey.currentState?.openEndDrawer();
              },
            ),
            // 设置按钮
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ConfigScreen()),
                );
              },
            ),
          ],
        ),
        // 使用EndDrawer显示历史记录或生词本
        endDrawer: Drawer(
          width: 350,
          child: Column(
            children: [
              AppBar(
                title: Text(_showVocabulary ? '生词本' : '观看历史'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              // 切换按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('历史记录'),
                    style: TextButton.styleFrom(
                      foregroundColor: !_showVocabulary ? Colors.blue : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _showVocabulary = false;
                      });
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.book),
                    label: const Text('生词本'),
                    style: TextButton.styleFrom(
                      foregroundColor: _showVocabulary ? Colors.blue : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _showVocabulary = true;
                      });
                    },
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: _showVocabulary
                    ? const VocabularyListWidget()
                    : const HistoryListWidget(),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // 视频播放区域
            Expanded(
              child: Column(
                children: [
                  // 视频播放器
                  Expanded(
                    child: VideoPlayerWidget(
                      videoService: videoService,
                    ),
                  ),
                  
                  // 字幕控制区域
                  SubtitleControlWidget(
                    key: _subtitleControlKey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 显示键盘快捷键帮助对话框
  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('键盘快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _KeyboardShortcutItem(
              keyName: 'Space',
              description: '播放/暂停',
            ),
            _KeyboardShortcutItem(
              keyName: '←',
              description: '回退5秒',
            ),
            _KeyboardShortcutItem(
              keyName: '→',
              description: '前进5秒',
            ),
            _KeyboardShortcutItem(
              keyName: '↑',
              description: '下一句字幕',
            ),
            _KeyboardShortcutItem(
              keyName: '↓',
              description: '上一句字幕',
            ),
            _KeyboardShortcutItem(
              keyName: 'R',
              description: '切换循环模式',
            ),
            _KeyboardShortcutItem(
              keyName: 'S',
              description: '切换字幕模糊',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  // 加载历史记录
  void _loadHistory() {
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.loadHistory();
  }
  
  // 加载生词本
  void _loadVocabulary() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    vocabularyService.loadAllVocabularyLists();
  }
}

// 快捷键帮助项组件
class _KeyboardShortcutItem extends StatelessWidget {
  final String keyName;
  final String description;
  
  const _KeyboardShortcutItem({
    Key? key,
    required this.keyName,
    required this.description,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4.0),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Text(
              keyName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16.0),
          Text(description),
        ],
      ),
    );
  }
} 