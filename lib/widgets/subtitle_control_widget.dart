import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/video_service.dart';
import '../services/vocabulary_service.dart';
import '../services/message_service.dart';
import '../services/config_service.dart';
import '../models/subtitle_model.dart';
import 'subtitle_selection_area.dart';
import 'package:path/path.dart' as path;

class SubtitleControlWidget extends StatefulWidget {
  final VideoService? videoService;
  
  const SubtitleControlWidget({
    super.key,
    this.videoService,
  });
  
  @override
  SubtitleControlWidgetState createState() => SubtitleControlWidgetState();
}

class SubtitleControlWidgetState extends State<SubtitleControlWidget> {
  // 当前音量
  double _currentVolume = 100;
  // 当前播放速度
  double _currentRate = 1.0;
  // 是否模糊字幕
  bool _isSubtitleBlurred = false;
  // 用于保存上次的音量
  double _lastVolume = 100;
  
  // 获取字幕模糊状态
  bool get isSubtitleBlurred => _isSubtitleBlurred;
  
  // 切换字幕模糊状态
  void toggleSubtitleBlur() {
    setState(() {
      _isSubtitleBlurred = !_isSubtitleBlurred;
    });
  }
  
  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeValues();
      }
    });
  }
  
  void _initializeValues() {
    if (!mounted) return;
    
    final videoService = widget.videoService ?? Provider.of<VideoService>(context, listen: false);
    final configService = Provider.of<ConfigService>(context, listen: false);
    final player = videoService.player;
    if (player != null) {
      setState(() {
        _currentVolume = player.state.volume;
        _currentRate = player.state.rate;
        
        // 如果播放速度是默认的1.0，则应用配置的默认播放速度
        if (_currentRate == 1.0) {
          _currentRate = configService.defaultPlaybackRate;
          player.setRate(_currentRate);
        }
      });
      
      // 监听音量变化
      player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() {
            _currentVolume = volume;
          });
        }
      });
      
      // 监听播放速度变化
      player.stream.rate.listen((rate) {
        if (mounted) {
          setState(() {
            _currentRate = rate;
          });
        }
      });
    }
  }
  
  // 清理YouTube字幕文本中的特殊标签
  String _cleanSubtitleText(String text) {
    // 移除时间戳标签，如<00:00:31.359>
    text = text.replaceAll(RegExp(r'<\d+:\d+:\d+\.\d+>'), '');
    // 移除<c>和</c>标签
    text = text.replaceAll(RegExp(r'</?c>'), '');
    // 移除其他可能的HTML标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    // 完全移除换行符
    text = text.replaceAll('\n', '');
    return text;
  }
  
  // 添加单词到生词本
  void _addToVocabulary(BuildContext context, String word) {
    if (word.isEmpty) return;
    
    // 获取视频服务
    final videoService = widget.videoService ?? Provider.of<VideoService>(context, listen: false);
    
    // 获取当前字幕文本
    final currentSubtitle = videoService.currentSubtitle;
    if (currentSubtitle == null) return;
    
    // 获取生词本服务
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    
    // 添加单词到生词本
    vocabularyService.addWordToVocabulary(
      word, 
      _cleanSubtitleText(currentSubtitle.text),
      videoService.currentVideoPath,
    );
    
    // 使用通用消息服务显示提示
    final messageService = Provider.of<MessageService>(context, listen: false);
    messageService.showSuccess('已添加 "$word" 到生词本');
  }
  
  @override
  Widget build(BuildContext context) {
    final videoService = widget.videoService ?? Provider.of<VideoService>(context);
    final vocabularyService = Provider.of<VocabularyService>(context);
    final currentSubtitle = videoService.currentSubtitle;
    final player = videoService.player;
    
    // 如果Player实例变化，重新初始化值
    if (player != null && (player != videoService.player)) {
      _initializeValues();
    }
    
    // 如果没有加载视频，显示提示
    if (player == null) {
      return const Center(
        child: Text('请先加载视频和字幕', style: TextStyle(color: Colors.grey)),
      );
    }
    
    // 计算字幕序号和总数
    int currentIndex = -1;
    int totalCount = 0;
    int passedSubtitles = 0;
    
    if (videoService.subtitleData != null) {
      totalCount = videoService.subtitleData!.entries.length;
      
      if (currentSubtitle != null) {
        currentIndex = currentSubtitle.index + 1; // 从0开始的索引转为从1开始的编号
        passedSubtitles = currentIndex; // 已播放的字幕数量就是当前字幕的索引
      } else {
        // 在没有当前字幕的间隙，根据当前播放位置找到最近的已播放字幕
        final currentPosition = videoService.currentPosition;
        int lastIndex = 0;
        
        for (var i = 0; i < videoService.subtitleData!.entries.length; i++) {
          final entry = videoService.subtitleData!.entries[i];
          if (entry.end <= currentPosition) {
            lastIndex = i + 1; // 从0开始的索引转为从1开始的编号
          } else {
            break;
          }
        }
        
        passedSubtitles = lastIndex > 0 ? lastIndex : 0;
      }
    }
    
    return Container(
      color: Colors.grey[900],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 视频播放进度条
          SizedBox(
            height: 4,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.red,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
                thumbColor: Colors.red,
                overlayColor: Colors.red.withOpacity(0.3),
                trackShape: CustomTrackShape(),
              ),
              child: Slider(
                value: videoService.currentPosition.inMilliseconds.toDouble().clamp(
                  0,
                  videoService.duration.inMilliseconds > 0 
                    ? videoService.duration.inMilliseconds.toDouble()
                    : 1.0
                ),
                min: 0,
                max: videoService.duration.inMilliseconds > 0 
                  ? videoService.duration.inMilliseconds.toDouble()
                  : 1.0, // 防止除以零错误
                onChanged: (value) {
                  final position = Duration(milliseconds: value.toInt());
                  if (videoService.isYouTubeVideo) {
                    videoService.seek(position);
                  } else {
                    videoService.player?.seek(position);
                  }
                },
              ),
            ),
          ),
          
          // 字幕操作区域
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
            child: Row(
              children: [
                // 左侧：播放/暂停和控制按钮
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 播放/暂停按钮
                    IconButton(
                      onPressed: () {
                        videoService.togglePlay();
                        final messageService = Provider.of<MessageService>(context, listen: false);
                        messageService.showMessage(
                          player.state.playing ? '暂停' : '播放'
                        );
                      },
                      icon: Icon(
                        player.state.playing ? Icons.pause : Icons.play_arrow, 
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: player.state.playing ? '暂停' : '播放',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    
                    // 音量图标和滑块
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 可点击的音量图标，用于快速静音/恢复
                        InkWell(
                          onTap: () {
                            // 如果当前音量大于0，则静音；否则恢复到上次的音量
                            if (_currentVolume > 0) {
                              // 保存当前音量，用于恢复
                              setState(() {
                                _lastVolume = _currentVolume;
                                _currentVolume = 0;
                              });
                              if (videoService.isYouTubeVideo) {
                                videoService.setVolume(0);
                              } else {
                                player.setVolume(0);
                              }
                              final messageService = Provider.of<MessageService>(context, listen: false);
                              messageService.showMessage('静音');
                            } else {
                              // 恢复到上次的音量，如果没有上次音量，则设为50
                              final volumeToRestore = _lastVolume > 0 ? _lastVolume : 50.0;
                              setState(() {
                                _currentVolume = volumeToRestore;
                              });
                              if (videoService.isYouTubeVideo) {
                                videoService.setVolume(volumeToRestore);
                              } else {
                                player.setVolume(volumeToRestore);
                              }
                              final messageService = Provider.of<MessageService>(context, listen: false);
                              messageService.showMessage('音量: ${volumeToRestore.toInt()}%');
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              _currentVolume > 0 ? Icons.volume_up : Icons.volume_off,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _currentVolume,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            activeColor: Colors.blue,
                            inactiveColor: Colors.grey[700],
                            onChanged: (value) {
                              setState(() {
                                _currentVolume = value;
                                if (value > 0) {
                                  _lastVolume = value; // 更新上次音量
                                }
                              });
                              if (videoService.isYouTubeVideo) {
                                videoService.setVolume(value);
                              } else {
                                player.setVolume(value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    
                    // 倍速控制按钮组
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer<ConfigService>(
                          builder: (context, configService, child) {
                            final allRates = configService.playbackRates;
                            // 最多显示5个按钮
                            final maxButtonsToShow = 5;
                            final showMoreButton = allRates.length > maxButtonsToShow;
                            final displayRates = showMoreButton 
                                ? allRates.sublist(0, maxButtonsToShow - 1) 
                                : allRates;
                            
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 显示有限数量的按钮
                                for (var rate in displayRates)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _currentRate = rate;
                                        });
                                        if (videoService.isYouTubeVideo) {
                                          videoService.setRate(rate);
                                        } else {
                                          player.setRate(rate);
                                        }
                                        final messageService = Provider.of<MessageService>(context, listen: false);
                                        messageService.showMessage('播放速度: ${rate}x');
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _currentRate == rate ? Colors.blue : Colors.grey[800],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${rate}x',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                // 如果需要，添加"更多"按钮
                                if (showMoreButton)
                                  PopupMenuButton<double>(
                                    tooltip: '更多速度选项',
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      Icons.more_horiz,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onSelected: (rate) {
                                      setState(() {
                                        _currentRate = rate;
                                      });
                                      if (videoService.isYouTubeVideo) {
                                        videoService.setRate(rate);
                                      } else {
                                        player.setRate(rate);
                                      }
                                      final messageService = Provider.of<MessageService>(context, listen: false);
                                      messageService.showMessage('播放速度: ${rate}x');
                                    },
                                    itemBuilder: (context) {
                                      return allRates.sublist(maxButtonsToShow - 1).map((rate) {
                                        return PopupMenuItem<double>(
                                          value: rate,
                                          child: Text('${rate}x'),
                                        );
                                      }).toList();
                                    },
                                  ),
                              ],
                            );
                          }
                        ),
                      ],
                    ),
                    
                    const SizedBox(width: 8),
                    
                    IconButton(
                      onPressed: () {
                        videoService.previousSubtitle();
                        final messageService = Provider.of<MessageService>(context, listen: false);
                        messageService.showMessage('上一句');
                      },
                      icon: const Icon(Icons.skip_previous, color: Colors.white, size: 20),
                      tooltip: '上一句',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    IconButton(
                      onPressed: () {
                        videoService.toggleLoop();
                        final messageService = Provider.of<MessageService>(context, listen: false);
                        messageService.showMessage(
                          videoService.isLooping ? '开始循环' : '停止循环'
                        );
                      },
                      icon: Icon(
                        videoService.isLooping ? Icons.repeat_one : Icons.repeat, 
                        color: videoService.isLooping ? Colors.orange : Colors.white,
                        size: 20,
                      ),
                      tooltip: videoService.isLooping ? '停止循环' : '循环播放',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    IconButton(
                      onPressed: () {
                        videoService.nextSubtitle();
                        final messageService = Provider.of<MessageService>(context, listen: false);
                        messageService.showMessage('下一句');
                      },
                      icon: const Icon(Icons.skip_next, color: Colors.white, size: 20),
                      tooltip: '下一句',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    
                    // 字幕模糊按钮
                    IconButton(
                      onPressed: () {
                        toggleSubtitleBlur();
                        final messageService = Provider.of<MessageService>(context, listen: false);
                        messageService.showMessage(
                          _isSubtitleBlurred ? '字幕已模糊' : '字幕已显示'
                        );
                      },
                      icon: Icon(
                        _isSubtitleBlurred ? Icons.visibility_off : Icons.visibility, 
                        color: _isSubtitleBlurred ? Colors.orange : Colors.white,
                        size: 20,
                      ),
                      tooltip: _isSubtitleBlurred ? '显示字幕' : '模糊字幕',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(8),
                    ),
                    
                    // 字幕时间校正按钮组
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: videoService.subtitleTimeOffset != 0 
                              ? Colors.amber 
                              : Colors.grey[600]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 字幕时间后退按钮
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.white, size: 20),
                            tooltip: '字幕时间 -1秒',
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              videoService.adjustSubtitleTime(-1);
                              final messageService = Provider.of<MessageService>(context, listen: false);
                              messageService.showMessage('字幕时间 -1秒 (总偏移: ${videoService.subtitleTimeOffset / 1000}秒)');
                            },
                          ),
                          
                          // 字幕时间偏移显示
                          GestureDetector(
                            onTap: () {
                              videoService.resetSubtitleTime();
                              final messageService = Provider.of<MessageService>(context, listen: false);
                              messageService.showMessage('字幕时间偏移已重置');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    color: Colors.white70,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(videoService.subtitleTimeOffset / 1000).toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      color: videoService.subtitleTimeOffset == 0 
                                          ? Colors.white70 
                                          : Colors.amber,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // 字幕时间前进按钮
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.white, size: 20),
                            tooltip: '字幕时间 +1秒',
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              videoService.adjustSubtitleTime(1);
                              final messageService = Provider.of<MessageService>(context, listen: false);
                              messageService.showMessage('字幕时间 +1秒 (总偏移: ${videoService.subtitleTimeOffset / 1000}秒)');
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // 中间：字幕文本 (占用最大空间)
                Expanded(
                  child: Consumer<ConfigService>(
                    builder: (context, configService, child) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          color: configService.subtitleBackgroundColor,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Row(
                          children: [
                            // 循环等待指示器
                            if (videoService.isLooping && videoService.isWaitingForLoop)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(right: 4),
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const Text(
                                      '等待...',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            // 字幕文本 - 使用带右键菜单的文本区域
                            Expanded(
                              child: Container(
                                alignment: Alignment.centerLeft, // 垂直居中，水平左对齐
                                child: currentSubtitle != null
                                  ? SubtitleSelectionArea(
                                      subtitle: SubtitleEntry(
                                        index: currentSubtitle.index,
                                        start: currentSubtitle.start,
                                        end: currentSubtitle.end,
                                        text: _cleanSubtitleText(currentSubtitle.text), // 直接在这里清理文本
                                      ),
                                      onSaveWord: (word) {
                                        _addToVocabulary(context, word);
                                      },
                                      isBlurred: _isSubtitleBlurred,
                                      fontSize: configService.subtitleFontSize,
                                      fontWeight: configService.subtitleFontWeight,
                                      textColor: configService.subtitleColor,
                                    )
                                  : Center(
                                      child: Text(
                                        passedSubtitles > 0 
                                          ? '已播放 $passedSubtitles 条字幕'
                                          : '等待字幕...',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  ),
                ),
                
                // 右侧：字幕序号和时间信息
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 字幕索引/总数
                    Text(
                      videoService.subtitleData != null 
                        ? '${passedSubtitles} / ${totalCount}'
                        : '-- / --',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    // 循环次数
                    if (videoService.isLooping && videoService.loopCount > 0)
                      Text(
                        '循环: ${videoService.loopCount}',
                        style: const TextStyle(color: Colors.orange, fontSize: 10),
                      )
                    else
                      const SizedBox(height: 10),
                    
                    // 时间信息
                    Text(
                      '${_formatDuration(videoService.currentPosition)} / ${_formatDuration(videoService.duration)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 格式化时间，精简版
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

// 自定义进度条轨道形状，移除默认的边距
class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
} 