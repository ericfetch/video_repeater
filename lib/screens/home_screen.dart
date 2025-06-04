import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
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
import '../screens/config_screen.dart';

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
  
  // 控制栏显示状态
  bool _showAppBar = true;
  Timer? _hideAppBarTimer;
  
  // 视频播放状态
  bool _isVideoPlaying = false;
  
  // 防止应用从后台切回前台时误触发空格键
  bool _isJustResumed = false;
  Timer? _resumeDebounceTimer;
  
  @override
  void initState() {
    super.initState();
    debugPrint('HomeScreen初始化');
    _loadHistory();
    _loadVocabulary();
    _focusNode = FocusNode();
    
    // 添加窗口焦点变化的监听
    WidgetsBinding.instance.addObserver(this);
    
    // 确保初始获得焦点并恢复最后的播放状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      
      debugPrint('准备恢复最后播放状态');
      // 在应用启动时恢复最后的播放状态
      _restoreLastPlayState();
    });
    
    // 监听历史服务变化
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.addListener(_onHistoryServiceChanged);
  }
  
  @override
  void dispose() {
    // 保存当前播放状态
    _saveLastPlayState();
    
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.removeListener(_onHistoryServiceChanged);
    _focusNode.dispose();
    _hideAppBarTimer?.cancel();
    _resumeDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用恢复到前台时，请求焦点
    if (state == AppLifecycleState.resumed) {
      _focusNode.requestFocus();
      
      // 应用从后台切回前台时，不显示AppBar
      setState(() {
        _showAppBar = false;
        _isJustResumed = true; // 标记应用刚刚恢复
      });
      
      // 延迟重置恢复状态，防止误触发
      _resumeDebounceTimer?.cancel();
      _resumeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _isJustResumed = false;
      });
      
      // 刷新字幕状态
      final videoService = Provider.of<VideoService>(context, listen: false);
      if (videoService.player != null) {
        // 获取当前播放位置
        final position = videoService.currentPosition;
        
        // 延迟一点执行，确保UI已经更新
        Future.delayed(const Duration(milliseconds: 100), () {
          // 小幅度前进后退，刷新字幕状态
          videoService.seek(Duration(milliseconds: position.inMilliseconds + 10));
          Future.delayed(const Duration(milliseconds: 50), () {
            videoService.seek(position);
          });
        });
      }
    } else if (state == AppLifecycleState.inactive || 
               state == AppLifecycleState.paused) {
      // 当应用切换到后台时，隐藏AppBar并保存当前状态
      setState(() {
        _showAppBar = false;
      });
      
      // 保存当前播放状态
      _saveLastPlayState();
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
  
  // 提取播放状态切换逻辑到单独方法
  void _togglePlayState(VideoService videoService) {
    try {
      // 获取当前状态
      bool isPlaying = videoService.player!.state.playing;
      // 切换播放状态
      videoService.togglePlay();
      // 切换后状态相反
      _showSnackBar(isPlaying ? '暂停' : '播放');
      
      // 如果暂停，隐藏AppBar
      if (isPlaying) { // 原来是播放状态，现在是暂停状态
        setState(() {
          _showAppBar = false;
        });
      }
    } catch (e) {
      debugPrint('切换播放状态错误: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final videoService = Provider.of<VideoService>(context);
    final isPlaying = videoService.player?.state.playing ?? false;
    
    // 在播放状态变化时更新AppBar显示逻辑
    if (isPlaying != _isVideoPlaying) {
      _isVideoPlaying = isPlaying;
      
      // 如果暂停，隐藏AppBar
      if (!isPlaying) {
        setState(() {
          _showAppBar = false;
        });
      }
      // 播放状态下不自动显示AppBar，只依靠鼠标移动触发
    }
    
    // 确保焦点在主视频区域
    if (!_focusNode.hasFocus && !_isJustResumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }
    
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      // 确保该Focus节点始终获得键盘事件的优先处理权
      onKeyEvent: (_, KeyEvent event) {
        // 处理空格键和方向键
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            if (!_isJustResumed) {
              _togglePlayState(videoService);
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            videoService.seek(Duration(milliseconds: 
              (videoService.currentPosition.inMilliseconds - 5000).clamp(0, videoService.duration.inMilliseconds)
            ));
            _showSnackBar('回退5秒');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            videoService.seek(Duration(milliseconds: 
              (videoService.currentPosition.inMilliseconds + 5000).clamp(0, videoService.duration.inMilliseconds)
            ));
            _showSnackBar('前进5秒');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            videoService.previousSubtitle();
            _showSnackBar('上一句');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            videoService.nextSubtitle();
            _showSnackBar('下一句');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
            videoService.toggleLoop();
            _showSnackBar(videoService.isLooping ? '开始循环' : '停止循环');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
            final subtitleControlWidget = _subtitleControlKey.currentState;
            if (subtitleControlWidget != null) {
              subtitleControlWidget.toggleSubtitleBlur();
              _showSnackBar(subtitleControlWidget.isSubtitleBlurred ? '字幕已模糊' : '字幕已显示');
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // 点击任何区域都重新获取焦点
        onTap: () => _focusNode.requestFocus(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          key: _scaffoldKey,
          appBar: null, // 不使用标准AppBar
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
          body: MouseRegion(
            onHover: _handleMouseMove,
            onEnter: _handleMouseMove,
            child: Stack(
              children: [
                // 主内容
                Column(
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
                
                // 顶部触发区指示条，只在AppBar隐藏时显示
                if (!_showAppBar)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onHover: (event) {
                        // 立即显示AppBar
                        setState(() {
                          _showAppBar = true;
                        });
                      },
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.grey.withOpacity(0.1),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // 自定义覆盖式AppBar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  top: _showAppBar ? 0 : -kToolbarHeight,
                  left: 0,
                  right: 0,
                  height: kToolbarHeight,
                  child: Material(
                    color: Colors.black.withOpacity(0.6),
                    elevation: 4,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _appTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // 选择视频按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.video_library, color: Colors.white),
                            tooltip: '选择视频',
                            onPressed: () async {
                              final videoService = Provider.of<VideoService>(context, listen: false);
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
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 选择字幕按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.subtitles, color: Colors.white),
                            tooltip: '选择字幕',
                            onPressed: () async {
                              final videoService = Provider.of<VideoService>(context, listen: false);
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
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 帮助按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.help_outline, color: Colors.white),
                            tooltip: '帮助',
                            onPressed: () {
                              _showHelpDialog(context);
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 保存进度按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.save, color: Colors.white),
                            tooltip: '保存进度',
                            onPressed: () {
                              _saveCurrentProgress();
                              _showSnackBar('已保存当前进度');
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 设置按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.settings, color: Colors.white),
                            tooltip: '设置',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const ConfigScreen()),
                              );
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 历史记录按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.history, color: Colors.white),
                            tooltip: '查看历史记录',
                            onPressed: () {
                              setState(() {
                                _showVocabulary = false;
                              });
                              _scaffoldKey.currentState?.openEndDrawer();
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          // 生词本按钮
                          _SafeIconButton(
                            icon: const Icon(Icons.book, color: Colors.white),
                            tooltip: '查看生词本',
                            onPressed: () {
                              setState(() {
                                _showVocabulary = true;
                              });
                              _scaffoldKey.currentState?.openEndDrawer();
                              // 操作完成后重新获取主焦点
                              _focusNode.requestFocus();
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
              description: '上一句字幕',
            ),
            _KeyboardShortcutItem(
              keyName: '↓',
              description: '下一句字幕',
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
  Future<void> _loadHistory() async {
    debugPrint('开始加载历史记录');
    final historyService = Provider.of<HistoryService>(context, listen: false);
    await historyService.loadHistory();
    debugPrint('历史记录加载完成');
  }
  
  // 加载生词本
  void _loadVocabulary() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    vocabularyService.loadAllVocabularyLists();
  }
  
  // 恢复最后的播放状态
  Future<void> _restoreLastPlayState() async {
    try {
      debugPrint('开始恢复最后播放状态');
      final historyService = Provider.of<HistoryService>(context, listen: false);
      await historyService.loadLastPlayState(); // 确保最新状态已加载
      final lastState = historyService.lastPlayState;
      
      debugPrint('尝试恢复最后播放状态...');
      
      if (lastState != null) {
        debugPrint('找到最后的播放状态: ${lastState.videoName}, 路径: ${lastState.videoPath}, 位置: ${lastState.lastPosition.inSeconds}秒');
        
        // 检查视频文件是否存在
        final videoFile = File(lastState.videoPath);
        if (!videoFile.existsSync()) {
          debugPrint('视频文件不存在: ${lastState.videoPath}');
          return;
        }
        
        // 更新当前路径
        _currentVideoPath = lastState.videoPath;
        _updateAppTitle(lastState.videoPath);
        
        // 加载视频
        final videoService = Provider.of<VideoService>(context, listen: false);
        debugPrint('开始加载视频: ${lastState.videoPath}');
        final videoSuccess = await videoService.loadVideo(lastState.videoPath);
        
        if (videoSuccess) {
          // 检查是否有字幕文件
          if (lastState.subtitlePath.isNotEmpty) {
            final subtitleFile = File(lastState.subtitlePath);
            if (subtitleFile.existsSync()) {
              debugPrint('字幕文件存在，开始加载字幕: ${lastState.subtitlePath}');
              _currentSubtitlePath = lastState.subtitlePath;
              final subtitleSuccess = await videoService.loadSubtitle(lastState.subtitlePath);
              
              if (!subtitleSuccess) {
                debugPrint('字幕加载失败');
              }
            } else {
              debugPrint('字幕文件不存在: ${lastState.subtitlePath}');
            }
          } else {
            debugPrint('没有字幕文件路径');
          }
          
          // 无论字幕是否加载成功，都跳转到上次播放位置
          debugPrint('准备跳转到位置: ${lastState.lastPosition.inSeconds}秒');
          Future.delayed(const Duration(milliseconds: 800), () {
            debugPrint('跳转到上次播放位置: ${lastState.lastPosition.inSeconds}秒');
            videoService.seek(lastState.lastPosition);
            _showSnackBar('已恢复上次播放进度: ${path.basename(lastState.videoPath)}');
          });
          
          // 加载该视频的生词本
          final videoName = path.basename(lastState.videoPath);
          final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
          vocabularyService.setCurrentVideo(videoName);
          vocabularyService.loadVocabularyList(videoName);
        } else {
          debugPrint('视频加载失败');
        }
      } else {
        debugPrint('没有找到最后播放状态');
      }
    } catch (e) {
      debugPrint('恢复最后播放状态时发生错误: $e');
    }
  }
  
  // 保存当前播放状态
  void _saveLastPlayState() {
    final videoService = Provider.of<VideoService>(context, listen: false);
    final historyService = Provider.of<HistoryService>(context, listen: false);
    
    if (_currentVideoPath != null && videoService.player != null) {
      final videoName = path.basename(_currentVideoPath!);
      final position = videoService.currentPosition;
      final subtitlePath = _currentSubtitlePath ?? '';
      
      final lastState = VideoHistory(
        videoPath: _currentVideoPath!,
        subtitlePath: subtitlePath,
        videoName: videoName,
        lastPosition: position,
        timestamp: DateTime.now(),
      );
      
      historyService.saveLastPlayState(lastState);
      debugPrint('保存当前播放状态: $videoName - ${position.inSeconds}秒');
    }
  }
  
  // 启动隐藏AppBar的定时器
  void _startHideAppBarTimer() {
    _hideAppBarTimer?.cancel();
    _hideAppBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showAppBar = false;
        });
      }
    });
  }
  
  // 显示AppBar
  void _showAppBarNow() {
    _hideAppBarTimer?.cancel();
    if (mounted && !_showAppBar) {
      // 添加短暂延迟，使显示更加自然
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showAppBar = true;
          });
        }
      });
    } else {
      // 如果已经显示，只需重置隐藏定时器
      _startHideAppBarTimer();
    }
  }
  
  // 鼠标移动处理
  void _handleMouseMove(PointerEvent event) {
    // 只有当鼠标在屏幕上方20像素区域内时才显示AppBar
    if (event.position.dy < 20) {
      // 显示AppBar
      if (!_showAppBar) {
        _showAppBarNow();
      }
      // 重置隐藏定时器
      _startHideAppBarTimer();
    }
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

class _SafeIconButton extends StatelessWidget {
  final Icon icon;
  final String tooltip;
  final VoidCallback onPressed;
  
  const _SafeIconButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Focus(
      // 完全禁用键盘焦点
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      // 拦截所有键盘事件
      onKeyEvent: (_, KeyEvent event) {
        // 阻止所有键盘事件
        return KeyEventResult.skipRemainingHandlers;
      },
      child: IconButton(
        icon: icon,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40),
        focusColor: Colors.transparent,
        onPressed: onPressed,
      ),
    );
  }
} 