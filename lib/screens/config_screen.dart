import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/config_service.dart';
import '../services/video_service.dart';
import '../services/message_service.dart';

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 在打开设置页面时暂停视频
    final videoService = Provider.of<VideoService>(context, listen: false);
    final wasPlaying = videoService.player?.state.playing ?? false;
    if (wasPlaying) {
      videoService.player?.pause();
    }
    
    // 使用StatelessWidget和Builder模式，避免整个界面随Provider状态变化而重建
    return _ConfigScreenContent(wasPlaying: wasPlaying);
  }
}

class _ConfigScreenContent extends StatefulWidget {
  final bool wasPlaying;
  
  const _ConfigScreenContent({required this.wasPlaying});
  
  @override
  _ConfigScreenContentState createState() => _ConfigScreenContentState();
}

class _ConfigScreenContentState extends State<_ConfigScreenContent> {
  // 文本编辑控制器
  final _playbackRatesController = TextEditingController();
  final _loopWaitIntervalController = TextEditingController();
  final _subtitleFontSizeController = TextEditingController();
  final _subtitleSuffixesController = TextEditingController();
  final _youtubeDownloadPathController = TextEditingController();
  
  // 设置值
  bool _isDarkMode = false;
  bool _isBoldFont = false;
  bool _autoMatchSubtitle = true;
  String _subtitleMatchMode = 'same';
  
  // 确保只初始化一次
  bool _initialized = false;
  
  @override
  void initState() {
    super.initState();
    
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConfig();
    });
  }
  
  void _loadConfig() {
    if (_initialized) return;
    
    final configService = Provider.of<ConfigService>(context, listen: false);
    
    // 更新控制器
    _playbackRatesController.text = configService.playbackRates.join(', ');
    _loopWaitIntervalController.text = configService.loopWaitInterval.toString();
    _subtitleFontSizeController.text = configService.subtitleFontSize.toString();
    _subtitleSuffixesController.text = configService.subtitleSuffixes.join(', ');
    _youtubeDownloadPathController.text = configService.youtubeDownloadPath;
    
    // 更新设置值
    setState(() {
      _isDarkMode = configService.darkMode;
      _isBoldFont = configService.subtitleFontWeight == FontWeight.bold;
      _autoMatchSubtitle = configService.autoMatchSubtitle;
      _subtitleMatchMode = configService.subtitleMatchMode;
      _initialized = true;
    });
  }
  
  @override
  void dispose() {
    _playbackRatesController.dispose();
    _loopWaitIntervalController.dispose();
    _subtitleFontSizeController.dispose();
    _subtitleSuffixesController.dispose();
    _youtubeDownloadPathController.dispose();
    
    // 恢复视频播放状态
    if (widget.wasPlaying) {
      final videoService = Provider.of<VideoService>(context, listen: false);
      videoService.player?.play();
    }
    
    super.dispose();
  }
  
  // 保存配置
  void _saveConfig() {
    final configService = Provider.of<ConfigService>(context, listen: false);
    
    // 解析播放速度
    try {
      final rates = _playbackRatesController.text.split(',')
          .map((e) => double.parse(e.trim()))
          .toList();
      configService.updatePlaybackRates(rates);
    } catch (e) {
      debugPrint('解析播放速度失败: $e');
    }
    
    // 解析循环等待间隔
    try {
      final interval = int.parse(_loopWaitIntervalController.text);
      configService.updateLoopWaitInterval(interval);
    } catch (e) {
      debugPrint('解析循环等待间隔失败: $e');
    }
    
    // 解析字幕字体大小
    try {
      final size = double.parse(_subtitleFontSizeController.text);
      if (size >= 12.0 && size <= 30.0) {
        configService.updateSubtitleFontSize(size);
      }
    } catch (e) {
      debugPrint('解析字幕字体大小失败: $e');
    }
    
    // 解析字幕后缀
    try {
      final suffixes = _subtitleSuffixesController.text.split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      configService.updateSubtitleSuffixes(suffixes);
    } catch (e) {
      debugPrint('解析字幕后缀失败: $e');
    }
    
    // 保存YouTube下载路径
    configService.updateYoutubeDownloadPath(_youtubeDownloadPathController.text);
    
    // 保存其他设置
    configService.updateSubtitleFontWeight(_isBoldFont);
    configService.updateAutoMatchSubtitle(_autoMatchSubtitle);
    configService.updateSubtitleMatchMode(_subtitleMatchMode);
    configService.updateDarkMode(_isDarkMode);
    
    final messageService = Provider.of<MessageService>(context, listen: false);
    messageService.showSuccess('设置已保存');
  }
  
  // 重置为默认设置
  void _resetToDefault() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要恢复所有设置为默认值吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final configService = Provider.of<ConfigService>(context, listen: false);
              configService.resetToDefault();
              Navigator.of(context).pop();
              _loadConfig(); // 重新加载配置
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 选择YouTube下载目录
  Future<void> _selectYoutubeDownloadDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _youtubeDownloadPathController.text = selectedDirectory;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 保存设置
        _saveConfig();
        
        // 恢复视频播放状态
        if (widget.wasPlaying) {
          final videoService = Provider.of<VideoService>(context, listen: false);
          videoService.player?.play();
        }
        
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存设置',
              onPressed: _saveConfig,
            ),
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: '恢复默认设置',
              onPressed: _resetToDefault,
            ),
          ],
        ),
        // 使用NotificationListener拦截滚动事件，避免不必要的重建
        body: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // 播放设置
              const Text(
                '播放设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // 播放速度选项 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('播放速度选项'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _playbackRatesController,
                        decoration: const InputDecoration(
                          hintText: '例如: 0.5, 0.75, 1.0, 1.25, 1.5, 2.0',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '用逗号分隔的数字列表',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              
              // 循环等待间隔 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('循环等待间隔(毫秒)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _loopWaitIntervalController,
                        decoration: const InputDecoration(
                          hintText: '例如: 2000',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '循环播放时在字幕结束后等待的时间',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 字幕设置
              const Text(
                '字幕设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // 字幕字体大小 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('字幕字体大小'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _subtitleFontSizeController,
                        decoration: const InputDecoration(
                          hintText: '例如: 16',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '字幕文本的字体大小(12-30)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              
              // 字幕字体粗细 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: const Text('字幕粗体显示'),
                  subtitle: const Text('使用粗体显示字幕文本'),
                  value: _isBoldFont,
                  onChanged: (value) {
                    setState(() {
                      _isBoldFont = value;
                    });
                  },
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 字幕自动匹配设置
              const Text(
                '字幕自动匹配设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // 启用自动匹配 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: const Text('自动匹配字幕'),
                  subtitle: const Text('加载视频时自动尝试匹配字幕文件'),
                  value: _autoMatchSubtitle,
                  onChanged: (value) {
                    setState(() {
                      _autoMatchSubtitle = value;
                    });
                  },
                ),
              ),
              
              // 字幕匹配模式 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('字幕匹配模式'),
                            SizedBox(height: 4),
                            Text(
                              '选择字幕文件的匹配方式',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<String>(
                        value: _subtitleMatchMode,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _subtitleMatchMode = value;
                            });
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                            value: 'same',
                            child: Text('与视频同名'),
                          ),
                          DropdownMenuItem(
                            value: 'suffix',
                            child: Text('添加后缀'),
                          ),
                          DropdownMenuItem(
                            value: 'both',
                            child: Text('两者都尝试'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // 字幕后缀列表 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('字幕后缀列表'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _subtitleSuffixesController,
                        decoration: const InputDecoration(
                          hintText: '例如: _en, .en, -en, _chs',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '用逗号分隔的后缀列表',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // YouTube设置
              const Text(
                'YouTube设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // YouTube下载路径
              StatefulBuilder(
                builder: (context, setState) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('YouTube视频下载路径'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _youtubeDownloadPathController,
                              decoration: const InputDecoration(
                                hintText: '留空使用临时目录',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _selectYoutubeDownloadDirectory,
                            child: const Text('选择'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '选择保存YouTube视频的目录，留空则保存到临时目录',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              

              
              const SizedBox(height: 24),
              
              // 界面设置
              const Text(
                '界面设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              
              // 暗黑模式 - 使用StatefulBuilder隔离重建范围
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: const Text('暗黑模式'),
                  subtitle: const Text('使用暗色主题'),
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 