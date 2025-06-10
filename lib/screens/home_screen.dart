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
import '../widgets/download_info_panel.dart';
import '../models/history_model.dart';
import '../screens/config_screen.dart';
import '../screens/youtube_video_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _currentVideoPath;
  String? _currentSubtitlePath;
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
  
  // 保留变量声明但不使用它进行定期检查
  Timer? _focusCheckTimer;
  
  // 添加一个标志，用于控制是否允许从历史记录加载视频
  bool _allowHistoryLoading = true;
  
  // 添加一个标志，用于控制是否应该自动请求焦点
  bool _shouldAutoFocus = true;
  
  @override
  void initState() {
    super.initState();
    debugPrint('HomeScreen初始化');
    _focusNode = FocusNode(debugLabel: 'HomeScreenFocus');
    
    // 添加窗口焦点变化的监听
    WidgetsBinding.instance.addObserver(this);
    
    // 确保焦点节点在初始化后立即获取焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode != null) {
        try {
          FocusScope.of(context).requestFocus(_focusNode);
          debugPrint('初始化后请求焦点');
        } catch (e) {
          debugPrint('初始化后请求焦点出错: $e');
        }
      }
    });
    
    // 添加定期检查焦点的计时器，如果焦点丢失则重新请求
    _focusCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        // 如果组件已经被销毁，取消计时器
        timer.cancel();
        return;
      }
      
      try {
        // 只在组件挂载且应该自动获取焦点且当前没有焦点时重新请求焦点
        if (mounted && _shouldAutoFocus && _focusNode != null && !_focusNode.hasFocus) {
          debugPrint('检测到焦点丢失，重新请求焦点');
          // 使用安全的方式请求焦点
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _focusNode != null && !_focusNode.hasFocus) {
              try {
                FocusScope.of(context).requestFocus(_focusNode);
              } catch (e) {
                // 忽略错误，只记录日志
                debugPrint('重新请求焦点时发生可忽略的错误: $e');
              }
            }
          });
        }
      } catch (e) {
        // 捕获并忽略所有错误，确保计时器不会因错误而停止
        debugPrint('焦点检查时发生可忽略的错误: $e');
      }
    });
    
    // 先加载历史记录和生词本
    _loadHistory();
    _loadVocabulary();
    
    // 监听历史服务变化
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.addListener(_onHistoryServiceChanged);
  }
  
  @override
  void dispose() {
    final historyService = Provider.of<HistoryService>(context, listen: false);
    historyService.removeListener(_onHistoryServiceChanged);
    _focusNode.dispose();
    _hideAppBarTimer?.cancel();
    _resumeDebounceTimer?.cancel();
    _focusCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用恢复到前台时，请求焦点
    if (state == AppLifecycleState.resumed) {
      // 使用安全的方式请求焦点
      if (mounted && _focusNode != null) {
        try {
          _focusNode.requestFocus();
        } catch (e) {
          debugPrint('应用恢复时请求焦点出错: $e');
        }
      }
      
      // 应用从后台切回前台时，不显示AppBar
      if (mounted) {
        setState(() {
          _showAppBar = false;
          _isJustResumed = true; // 标记应用刚刚恢复
        });
      }
      
      // 延迟重置恢复状态，防止误触发
      _resumeDebounceTimer?.cancel();
      _resumeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _isJustResumed = false;
      });
      
      // 刷新字幕状态
      if (mounted) {  // 确保组件仍然挂载
        try {
          final videoService = Provider.of<VideoService>(context, listen: false);
          if (videoService.player != null) {
            // 获取当前播放位置
            final position = videoService.currentPosition;
            
            // 延迟一点执行，确保UI已经更新
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {  // 再次检查以确保安全
                // 小幅度前进后退，刷新字幕状态
                videoService.seek(Duration(milliseconds: position.inMilliseconds + 10));
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted) {  // 再次检查以确保安全
                    videoService.seek(position);
                  }
                });
              }
            });
          }
        } catch (e) {
          debugPrint('刷新字幕状态时出错: $e');
        }
      }
    } else if (state == AppLifecycleState.inactive || 
               state == AppLifecycleState.paused) {
      // 当应用切换到后台时，隐藏AppBar
      if (mounted) {
        setState(() {
          _showAppBar = false;
        });
      }
    }
  }
  
  // 当历史记录服务状态变化时
  void _onHistoryServiceChanged() {
    // 如果组件已经被销毁，直接返回
    if (!mounted) {
      return;
    }
    
    // 如果不允许从历史记录加载视频，直接返回
    if (!_allowHistoryLoading) {
      debugPrint('历史记录服务状态变化，但当前不允许加载视频');
      return;
    }
    
    try {
      final historyService = Provider.of<HistoryService>(context, listen: false);
      final currentHistory = historyService.currentHistory;
      
      debugPrint('历史记录服务状态变化: currentHistory=${currentHistory?.videoName}');
      debugPrint('当前视频路径: $_currentVideoPath');
      
      // 如果从历史记录加载了视频，更新路径但不更新标题
      if (currentHistory != null && 
          _currentVideoPath != currentHistory.videoPath) {
        debugPrint('更新视频路径: ${currentHistory.videoName}');
        _currentVideoPath = currentHistory.videoPath;
        _currentSubtitlePath = currentHistory.subtitlePath;
        
        // 同时加载该视频的生词本
        if (_currentVideoPath != null && mounted) {
          final videoName = path.basename(_currentVideoPath!);
          final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
          vocabularyService.setCurrentVideo(videoName);
          vocabularyService.loadVocabularyList(videoName);
        }
      } else if (currentHistory != null) {
        debugPrint('历史记录变化但视频路径未变: ${currentHistory.videoName}');
      }
    } catch (e) {
      debugPrint('处理历史记录变化时出错: $e');
    }
  }
  
  // 保存当前进度到历史记录
  void _saveCurrentProgress() {
    if (!mounted) {
      return;
    }
    
    try {
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
    } catch (e) {
      debugPrint('保存播放进度时出错: $e');
    }
  }
  
  // 显示提示消息 (公开方法，供其他组件调用)
  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    
    try {
      final messageService = Provider.of<MessageService>(context, listen: false);
      messageService.showMessage(message);
    } catch (e) {
      debugPrint('显示提示消息时出错: $e');
    }
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
  
  // 更新视频标题 - 只在视频加载成功后调用此方法
  void updateVideoTitle(String videoPath) {
    // 不再需要此方法，视频标题由VideoService管理
  }
  
  @override
  Widget build(BuildContext context) {
    debugPrint('焦点节点状态: ${_focusNode.hasFocus ? "有焦点" : "无焦点"}');
    return Consumer3<VideoService, HistoryService, VocabularyService>(
      builder: (context, videoService, historyService, vocabularyService, child) {
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            debugPrint('Focus接收到键盘事件: ${event.logicalKey.keyLabel}, 类型: ${event.runtimeType}');
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.space) {
                debugPrint('空格键按下，切换播放状态');
                if (!_isJustResumed) {
                  _togglePlayState(videoService);
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                debugPrint('左箭头按下，回退5秒');
                videoService.seek(Duration(milliseconds: 
                  (videoService.currentPosition.inMilliseconds - 5000).clamp(0, videoService.duration.inMilliseconds)
                ));
                _showSnackBar('回退5秒');
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                debugPrint('右箭头按下，前进5秒');
                videoService.seek(Duration(milliseconds: 
                  (videoService.currentPosition.inMilliseconds + 5000).clamp(0, videoService.duration.inMilliseconds)
                ));
                _showSnackBar('前进5秒');
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                debugPrint('上箭头按下，跳转到上一句字幕');
                videoService.previousSubtitle();
                _showSnackBar('上一句');
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                debugPrint('下箭头按下，跳转到下一句字幕');
                videoService.nextSubtitle();
                _showSnackBar('下一句');
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
                debugPrint('R键按下，切换循环模式');
                videoService.toggleLooping();
                _showSnackBar(videoService.isLooping ? '开始循环' : '停止循环');
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
                debugPrint('S键按下，切换字幕模糊');
                final subtitleControlWidget = _subtitleControlKey.currentState;
                if (subtitleControlWidget != null) {
                  subtitleControlWidget.toggleSubtitleBlur();
                  _showSnackBar(subtitleControlWidget.isSubtitleBlurred ? '字幕已模糊' : '字幕已显示');
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
                debugPrint('L键按下，切换循环模式');
                videoService.toggleLooping();
                _showSnackBar(videoService.isLooping ? '开始循环' : '停止循环');
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showAppBar = !_showAppBar;
              });
            },
            child: ScaffoldMessenger(
              key: _scaffoldMessengerKey,
              child: Scaffold(
                key: _scaffoldKey,
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
                              // 使用Future.microtask延迟恢复自动焦点
                              Future.microtask(() {
                                if (mounted) {
                                  setState(() {
                                    _shouldAutoFocus = true;
                                  });
                                }
                              });
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
                                // 启动隐藏定时器
                                _startHideAppBarTimer();
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
                      
                      // 下载信息面板
                      const DownloadInfoPanel(),
                      
                      // 自定义覆盖式AppBar
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        top: _showAppBar ? 0 : -kToolbarHeight,
                        left: 0,
                        right: 0,
                        height: kToolbarHeight,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.9),
                                  Colors.black.withOpacity(0.7),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: SafeArea(
                              bottom: false,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.video_library,
                                          color: Colors.blue,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          constraints: const BoxConstraints(maxWidth: 500),
                                          child: Text(
                                            videoService.videoTitle,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  // 设置按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.settings, color: Colors.white),
                                    tooltip: '设置',
                                    onPressed: () {
                                      _navigateToConfigScreen(context);
                                    },
                                  ),
                                  // 选择视频按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.video_library, color: Colors.white),
                                    tooltip: '选择视频',
                                    onPressed: () async {
                                      final videoService = Provider.of<VideoService>(context, listen: false);
                                      final videoPath = await videoService.pickVideoFile();
                                      if (videoPath != null) {
                                        _currentVideoPath = videoPath;
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
                                    },
                                  ),
                                  // 帮助按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.help_outline, color: Colors.white),
                                    tooltip: '帮助',
                                    onPressed: () {
                                      _showHelpDialog(context);
                                    },
                                  ),
                                  // 保存进度按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.save, color: Colors.white),
                                    tooltip: '保存进度',
                                    onPressed: () {
                                      _saveCurrentProgress();
                                      _showSnackBar('已保存当前进度');
                                    },
                                  ),
                                  // 历史记录按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.history, color: Colors.white),
                                    tooltip: '查看历史记录',
                                    onPressed: () {
                                      setState(() {
                                        _showVocabulary = false;
                                        _shouldAutoFocus = false; // 禁用自动焦点
                                      });
                                      _scaffoldKey.currentState?.openEndDrawer();
                                    },
                                  ),
                                  // 生词本按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.book, color: Colors.white),
                                    tooltip: '查看生词本',
                                    onPressed: () {
                                      setState(() {
                                        _showVocabulary = true;
                                        _shouldAutoFocus = false; // 禁用自动焦点
                                      });
                                      _scaffoldKey.currentState?.openEndDrawer();
                                    },
                                  ),
                                  // YouTube按钮
                                  _SafeIconButton(
                                    icon: const Icon(Icons.play_circle_outline, color: Colors.white),
                                    tooltip: '打开YouTube视频',
                                    onPressed: () {
                                      _showYouTubeUrlDialog(context);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  // 显示键盘快捷键帮助对话框
  void _showHelpDialog(BuildContext context) {
    // 禁用自动焦点
    setState(() {
      _shouldAutoFocus = false;
    });
    
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
    ).then((_) {
      // 使用Future.microtask延迟恢复自动焦点
      Future.microtask(() {
        if (mounted && _focusNode != null) {
          setState(() {
            _shouldAutoFocus = true;
          });
          
          // 对话框关闭后，重新请求主界面焦点
          try {
            FocusScope.of(context).requestFocus(_focusNode);
          } catch (e) {
            debugPrint('对话框关闭后请求焦点出错: $e');
          }
        }
      });
    });
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
  
  // 保存当前播放状态
  void _saveLastPlayState() {
    final videoService = Provider.of<VideoService>(context, listen: false);
    final historyService = Provider.of<HistoryService>(context, listen: false);
    
    // 使用VideoService中的路径，确保是最新的
    final currentVideoPath = videoService.currentVideoPath;
    if (currentVideoPath != null && videoService.player != null) {
      // 使用VideoService中的数据
      final videoName = path.basename(currentVideoPath);
      final position = videoService.currentPosition;
      final subtitlePath = videoService.currentSubtitlePath ?? '';
      final subtitleTimeOffset = videoService.subtitleTimeOffset;
      
      debugPrint('保存播放状态 - 使用VideoService中的数据:');
      debugPrint('- 视频路径: $currentVideoPath');
      debugPrint('- 字幕路径: $subtitlePath');
      
      final lastState = VideoHistory(
        videoPath: currentVideoPath,
        subtitlePath: subtitlePath,
        videoName: videoName,
        lastPosition: position,
        timestamp: DateTime.now(),
        subtitleTimeOffset: subtitleTimeOffset,
      );
      
      // 保存状态
      historyService.saveLastPlayState(lastState);
      debugPrint('保存当前播放状态: $videoName - ${position.inSeconds}秒, 字幕偏移: ${subtitleTimeOffset/1000}秒');
      
      // 更新本地路径变量，确保与VideoService同步
      _currentVideoPath = currentVideoPath;
      _currentSubtitlePath = subtitlePath;
    }
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
        debugPrint('找到最后的播放状态: ${lastState.videoName}, 路径: ${lastState.videoPath}, 位置: ${lastState.lastPosition.inSeconds}秒, 字幕偏移: ${lastState.subtitleTimeOffset/1000}秒');
        
        // 检查视频文件是否存在
        final videoFile = File(lastState.videoPath);
        if (!videoFile.existsSync()) {
          debugPrint('视频文件不存在: ${lastState.videoPath}');
          return;
        }
        
        // 更新当前路径，但不更新标题
        _currentVideoPath = lastState.videoPath;
        
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
              
              // 验证字幕文件是否与视频匹配
              final videoFileName = path.basenameWithoutExtension(lastState.videoPath).toLowerCase();
              final subtitleFileName = path.basenameWithoutExtension(lastState.subtitlePath).toLowerCase();
              
              // 检查字幕文件名是否包含视频文件名的一部分，或者视频文件名是否包含字幕文件名的一部分
              bool isMatched = false;
              
              // 如果是YouTube视频，检查视频ID是否匹配
              if (videoFileName.contains('_') && videoFileName.split('_').first.length == 11) {
                // 可能是YouTube视频，提取视频ID
                final videoId = videoFileName.split('_').first;
                isMatched = subtitleFileName.contains(videoId);
                debugPrint('YouTube视频ID检查: $videoId, 匹配结果: $isMatched');
              }
              
              // 如果不是YouTube视频或ID不匹配，检查文件名相似度
              if (!isMatched) {
                // 简单比较：检查文件名是否有相似部分
                if (videoFileName.length > 5 && subtitleFileName.length > 5) {
                  // 检查前5个字符是否匹配
                  isMatched = videoFileName.substring(0, 5) == subtitleFileName.substring(0, 5);
                  
                  // 如果不匹配，检查字幕文件名是否包含视频文件名的一部分
                  if (!isMatched && videoFileName.length > 8) {
                    isMatched = subtitleFileName.contains(videoFileName.substring(0, 8));
                  }
                  
                  // 如果还不匹配，检查视频文件名是否包含字幕文件名的一部分
                  if (!isMatched && subtitleFileName.length > 8) {
                    isMatched = videoFileName.contains(subtitleFileName.substring(0, 8));
                  }
                }
              }
              
              debugPrint('字幕文件匹配检查: 视频=$videoFileName, 字幕=$subtitleFileName, 匹配结果=$isMatched');
              
              if (!isMatched) {
                debugPrint('字幕文件可能与视频不匹配，跳过加载');
              } else {
                _currentSubtitlePath = lastState.subtitlePath;
                final subtitleSuccess = await videoService.loadSubtitle(lastState.subtitlePath);
                
                if (subtitleSuccess) {
                  // 恢复字幕时间偏移
                  if (lastState.subtitleTimeOffset != 0) {
                    // 计算需要调整的秒数
                    final offsetSeconds = lastState.subtitleTimeOffset / 1000;
                    debugPrint('恢复字幕时间偏移: ${offsetSeconds}秒');
                    
                    // 重置后设置正确的偏移值
                    videoService.resetSubtitleTime();
                    videoService.adjustSubtitleTime(offsetSeconds.toInt());
                  }
                } else {
                  debugPrint('字幕加载失败');
                }
              }
            } else {
              debugPrint('字幕文件不存在: ${lastState.subtitlePath}');
            }
          } else {
            debugPrint('没有字幕文件路径');
          }
          
          // 使用更智能的方式等待视频加载并跳转
          await _seekToPositionWithRetry(videoService, lastState.lastPosition, lastState.videoPath);
          
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
  
  // 使用重试机制跳转到指定位置
  Future<void> _seekToPositionWithRetry(VideoService videoService, Duration position, String videoPath) async {
    debugPrint('准备跳转到位置: ${position.inSeconds}秒');
    
    // 等待视频加载完成
    int attempts = 0;
    const maxAttempts = 5;
    const initialDelay = 500; // 初始延迟毫秒
    
    while (attempts < maxAttempts) {
      // 计算当前尝试的延迟时间（逐渐增加）
      final delay = initialDelay + (attempts * 300);
      
      debugPrint('等待视频加载，尝试 ${attempts + 1}/$maxAttempts，延迟 ${delay}ms');
      await Future.delayed(Duration(milliseconds: delay));
      
      // 检查视频是否已加载
      if (videoService.player != null && videoService.duration.inMilliseconds > 0) {
        debugPrint('视频已加载，持续时间: ${videoService.duration.inSeconds}秒');
        
        // 确保位置在有效范围内
        final safePosition = Duration(
          milliseconds: position.inMilliseconds.clamp(0, videoService.duration.inMilliseconds)
        );
        
        // 执行跳转
        videoService.seek(safePosition);
        _showSnackBar('已恢复上次播放进度: ${path.basename(videoPath)}');
        return;
      }
      
      attempts++;
    }
    
    debugPrint('视频加载超时，无法跳转到指定位置');
    _showSnackBar('无法恢复播放进度，请手动操作');
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
  
  // 导航到配置页面
  void _navigateToConfigScreen(BuildContext context) async {
    // 在打开设置页面前禁用历史记录加载
    _allowHistoryLoading = false;
    
    // 禁用自动焦点
    setState(() {
      _shouldAutoFocus = false;
    });
    
    // 使用await等待设置页面关闭
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ConfigScreen()),
    );
    
    // 设置页面关闭后，重新获取焦点，但不重新加载视频
    if (mounted) {
      // 使用Future.microtask延迟恢复自动焦点
      Future.microtask(() {
        if (mounted && _focusNode != null) {
          setState(() {
            _shouldAutoFocus = true;
          });
          
          try {
            _focusNode.requestFocus();
          } catch (e) {
            debugPrint('设置页面关闭后请求焦点出错: $e');
          }
        }
      });
      
      // 延迟一段时间后再允许历史记录加载，确保不会立即触发
      Future.delayed(const Duration(milliseconds: 500), () {
        _allowHistoryLoading = true;
      });
    }
  }
  
  // 显示YouTube URL输入对话框
  void _showYouTubeUrlDialog(BuildContext context) {
    final TextEditingController urlController = TextEditingController();
    
    // 创建一个专用的焦点节点，用于输入框
    final inputFocusNode = FocusNode();
    
    // 禁用自动焦点
    setState(() {
      _shouldAutoFocus = false;
    });
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入YouTube视频链接'),
        content: TextField(
          controller: urlController,
          focusNode: inputFocusNode,
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/watch?v=...',
            labelText: 'YouTube URL',
          ),
          autofocus: true,
          onSubmitted: (value) {
            Navigator.of(dialogContext).pop();
            _loadYouTubeVideo(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _loadYouTubeVideo(urlController.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) {
      // 对话框关闭后，释放焦点节点
      inputFocusNode.dispose();
      
      // 使用Future.microtask延迟恢复自动焦点
      Future.microtask(() {
        if (mounted && _focusNode != null) {
          setState(() {
            _shouldAutoFocus = true;
          });
          
          // 对话框关闭后，重新请求主界面焦点
          try {
            FocusScope.of(context).requestFocus(_focusNode);
          } catch (e) {
            debugPrint('YouTube对话框关闭后请求焦点出错: $e');
          }
        }
      });
    });
  }
  
  // 加载YouTube视频
  void _loadYouTubeVideo(String url) async {
    if (url.isEmpty) return;
    
    final videoService = Provider.of<VideoService>(context, listen: false);
    
    if (videoService.isYouTubeLink(url)) {
      // 显示加载消息
      _showSnackBar('正在加载YouTube视频...');
      
      // 直接加载YouTube视频
      final success = await videoService.loadVideo(url);
      
      if (success) {
        _showSnackBar('YouTube视频加载成功');
      } else {
        _showSnackBar('YouTube视频加载失败: ${videoService.errorMessage ?? "未知错误"}');
      }
      
      // 操作完成后重新获取主焦点
      _focusNode.requestFocus();
    } else {
      _showSnackBar('无效的YouTube链接');
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
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40),
      focusColor: Colors.transparent,
      focusNode: AlwaysDisabledFocusNode(), // 使用自定义FocusNode，永远不获取焦点
      onPressed: () {
        // 执行点击操作
        onPressed();
      },
    );
  }
}

// 永远不获取焦点的FocusNode
class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
  
  @override
  bool canRequestFocus = false;
} 