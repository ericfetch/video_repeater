import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/config_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _playbackRatesController = TextEditingController();
  final _loopWaitIntervalController = TextEditingController();
  final _subtitleFontSizeController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    
    // 延迟初始化，确保Provider已经准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initControllers();
    });
  }
  
  void _initControllers() {
    final configService = Provider.of<ConfigService>(context, listen: false);
    
    _playbackRatesController.text = configService.playbackRates.join(', ');
    _loopWaitIntervalController.text = configService.loopWaitInterval.toString();
    _subtitleFontSizeController.text = configService.subtitleFontSize.toString();
  }
  
  @override
  void dispose() {
    // 保存所有更改
    _saveAllChanges();
    
    _playbackRatesController.dispose();
    _loopWaitIntervalController.dispose();
    _subtitleFontSizeController.dispose();
    super.dispose();
  }
  
  // 保存所有更改
  void _saveAllChanges() {
    final configService = Provider.of<ConfigService>(context, listen: false);
    
    // 保存播放速度选项
    try {
      final rates = _playbackRatesController.text.split(',')
          .map((e) => double.parse(e.trim()))
          .toList();
      configService.updatePlaybackRates(rates);
    } catch (e) {
      // 如果格式错误，保持原值
    }
    
    // 保存循环等待间隔
    try {
      final interval = int.parse(_loopWaitIntervalController.text);
      configService.updateLoopWaitInterval(interval);
    } catch (e) {
      // 如果格式错误，保持原值
    }
    
    // 保存字幕字体大小
    try {
      final size = double.parse(_subtitleFontSizeController.text);
      if (size >= 12.0 && size <= 30.0) {
        configService.updateSubtitleFontSize(size);
      }
    } catch (e) {
      // 如果格式错误，保持原值
    }
  }

  @override
  Widget build(BuildContext context) {
    final configService = Provider.of<ConfigService>(context);
    
    return WillPopScope(
      onWillPop: () async {
        _saveAllChanges();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          actions: [
            // 保存按钮
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存设置',
              onPressed: () {
                _saveAllChanges();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置已保存')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: '恢复默认设置',
              onPressed: () {
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
                          configService.resetToDefault();
                          _initControllers();
                          Navigator.of(context).pop();
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 播放速度设置
            const _SectionHeader(title: '播放设置'),
            
            // 播放速度选项
            _SettingItem(
              title: '播放速度选项',
              subtitle: '可选的播放速度列表，用逗号分隔',
              child: TextField(
                controller: _playbackRatesController,
                decoration: const InputDecoration(
                  hintText: '例如: 0.5, 0.75, 1.0, 1.25, 1.5, 2.0',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
                onChanged: (value) {
                  // 实时更新，但不保存
                },
                onSubmitted: (value) {
                  try {
                    final rates = value.split(',')
                        .map((e) => double.parse(e.trim()))
                        .toList();
                    configService.updatePlaybackRates(rates);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('格式错误，请使用逗号分隔的数字')),
                    );
                  }
                },
              ),
            ),
            
            // 默认播放速度
            _SettingItem(
              title: '默认播放速度',
              subtitle: '视频加载后的初始播放速度',
              child: DropdownButton<double>(
                value: configService.defaultPlaybackRate,
                items: configService.playbackRates.map((rate) {
                  return DropdownMenuItem<double>(
                    value: rate,
                    child: Text('${rate}x'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    configService.updateDefaultPlaybackRate(value);
                  }
                },
              ),
            ),
            
            // 循环设置
            const _SectionHeader(title: '循环设置'),
            
            // 循环等待间隔
            _SettingItem(
              title: '循环等待间隔',
              subtitle: '字幕循环播放时的等待时间（毫秒）',
              child: TextField(
                controller: _loopWaitIntervalController,
                decoration: const InputDecoration(
                  hintText: '例如: 2000',
                  border: OutlineInputBorder(),
                  suffixText: '毫秒',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  // 实时更新，但不保存
                },
                onSubmitted: (value) {
                  try {
                    final interval = int.parse(value);
                    configService.updateLoopWaitInterval(interval);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入有效的数字')),
                    );
                  }
                },
              ),
            ),
            
            // 字幕设置
            const _SectionHeader(title: '字幕设置'),
            
            // 字幕字体大小
            _SettingItem(
              title: '字幕字体大小',
              subtitle: '调整字幕文本的大小',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: configService.subtitleFontSize,
                      min: 12.0,
                      max: 30.0,
                      divisions: 18,
                      label: configService.subtitleFontSize.toStringAsFixed(1),
                      onChanged: (value) {
                        configService.updateSubtitleFontSize(value);
                        _subtitleFontSizeController.text = value.toStringAsFixed(1);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _subtitleFontSizeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onSubmitted: (value) {
                        try {
                          final size = double.parse(value);
                          if (size >= 12.0 && size <= 30.0) {
                            configService.updateSubtitleFontSize(size);
                          }
                        } catch (e) {
                          // 恢复为当前值
                          _subtitleFontSizeController.text = 
                              configService.subtitleFontSize.toStringAsFixed(1);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // 字幕字体粗细
            _SettingItem(
              title: '字幕字体粗细',
              subtitle: '设置字幕文本是否加粗',
              child: Switch(
                value: configService.subtitleFontWeight == FontWeight.bold,
                onChanged: (value) {
                  configService.updateSubtitleFontWeight(value);
                },
              ),
            ),
            
            // 字幕颜色
            _SettingItem(
              title: '字幕颜色',
              subtitle: '设置字幕文本的颜色',
              child: InkWell(
                onTap: () {
                  _showColorPicker(
                    context, 
                    configService.subtitleColor,
                    (color) => configService.updateSubtitleColor(color),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: configService.subtitleColor,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            
            // 字幕背景颜色
            _SettingItem(
              title: '字幕背景颜色',
              subtitle: '设置字幕背景的颜色',
              child: InkWell(
                onTap: () {
                  _showColorPicker(
                    context, 
                    configService.subtitleBackgroundColor,
                    (color) => configService.updateSubtitleBackgroundColor(color),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: configService.subtitleBackgroundColor,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            
            // 界面设置
            const _SectionHeader(title: '界面设置'),
            
            // 暗黑模式
            _SettingItem(
              title: '暗黑模式',
              subtitle: '切换应用的明暗主题',
              child: Switch(
                value: configService.darkMode,
                onChanged: (value) {
                  configService.updateDarkMode(value);
                },
              ),
            ),
            
            // 预览区域
            const SizedBox(height: 20),
            const _SectionHeader(title: '字幕预览'),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: configService.subtitleBackgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '这是字幕预览文本',
                    style: TextStyle(
                      color: configService.subtitleColor,
                      fontSize: configService.subtitleFontSize,
                      fontWeight: configService.subtitleFontWeight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showColorPicker(BuildContext context, Color currentColor, Function(Color) onColorChanged) {
    showDialog(
      context: context,
      builder: (context) {
        Color pickerColor = currentColor;
        
        return AlertDialog(
          title: const Text('选择颜色'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha: true,
              displayThumbColor: true,
              showLabel: true,
              paletteType: PaletteType.hsv,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                onColorChanged(pickerColor);
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}

// 设置分组标题
class _SectionHeader extends StatelessWidget {
  final String title;
  
  const _SectionHeader({required this.title});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

// 设置项
class _SettingItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  
  const _SettingItem({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: child,
          ),
        ],
      ),
    );
  }
} 