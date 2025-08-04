import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ConfigService extends ChangeNotifier {
  // 默认配置
  static const Map<String, dynamic> _defaultConfig = {
    // 播放速度选项
    'playbackRates': [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
    'defaultPlaybackRate': 1.0,
    
    // 循环设置
    'loopWaitInterval': 2000, // 毫秒
    
    // 字幕设置
    'subtitleFontSize': 16.0,
    'subtitleColor': 0xFFFFFFFF, // 白色
    'subtitleBackgroundColor': 0x80000000, // 半透明黑色
    'subtitleFontWeight': 'normal', // normal, bold
    
    // 字幕自动匹配设置
    'autoMatchSubtitle': true, // 是否自动尝试匹配字幕
    'subtitleMatchMode': 'same', // 字幕匹配模式: same(与视频同名), suffix(添加后缀)
    'subtitleSuffixes': ['_en', '.en', '-en', '_chs', '.chs', '-chs'], // 字幕后缀列表
    
    // YouTube设置
    'youtubeDownloadPath': '', // YouTube视频下载路径，空表示使用临时目录
    'youtubeVideoQuality': '480p', // YouTube视频质量
    
    // Google Cloud Translation API设置
    'googleTranslateApiKey': '', // Google Cloud Translation API密钥
    'googleProjectId': '', // Google Cloud项目ID
    'translateTargetLanguage': 'zh-CN', // 翻译目标语言，默认为中文简体
    
    // 百炼AI翻译设置
    'bailianApiKey': '', // 百炼AI API密钥
    'bailianAppId': '', // 百炼AI应用ID
    
    // 界面设置
    'darkMode': false,
    'showDailyVideoList': true, // 是否显示今日视频列表
  };
  
  // 当前配置
  Map<String, dynamic> _config = Map.from(_defaultConfig);
  
  // 获取配置
  Map<String, dynamic> get config => _config;
  
  // 获取播放速度选项
  List<double> get playbackRates => List<double>.from(_config['playbackRates']);
  
  // 获取默认播放速度
  double get defaultPlaybackRate => _config['defaultPlaybackRate'];
  
  // 获取循环等待间隔
  int get loopWaitInterval => _config['loopWaitInterval'];
  
  // 获取字幕字体大小
  double get subtitleFontSize => _config['subtitleFontSize'];
  
  // 获取字幕颜色
  Color get subtitleColor => Color(_config['subtitleColor']);
  
  // 获取字幕背景颜色
  Color get subtitleBackgroundColor => Color(_config['subtitleBackgroundColor']);
  
  // 获取字幕字体粗细
  FontWeight get subtitleFontWeight => 
      _config['subtitleFontWeight'] == 'bold' ? FontWeight.bold : FontWeight.normal;
      
  // 获取是否自动匹配字幕
  bool get autoMatchSubtitle => _config['autoMatchSubtitle'] ?? true;
  
  // 获取字幕匹配模式
  String get subtitleMatchMode => _config['subtitleMatchMode'] ?? 'same';
  
  // 获取字幕后缀列表
  List<String> get subtitleSuffixes => 
      List<String>.from(_config['subtitleSuffixes'] ?? ['_en', '.en', '-en', '_chs', '.chs', '-chs']);
  
  // 获取YouTube视频下载路径
  String get youtubeDownloadPath => _config['youtubeDownloadPath'] ?? '';
  
  // 获取YouTube视频质量
  String get youtubeVideoQuality => _config['youtubeVideoQuality'] ?? '480p';
  
  // 获取Google Cloud Translation API密钥
  String? get googleTranslateApiKey => _config['googleTranslateApiKey'];
  
  // 获取Google Cloud项目ID
  String? get googleProjectId => _config['googleProjectId'];
  
  // 获取翻译目标语言
  String get translateTargetLanguage => _config['translateTargetLanguage'] ?? 'zh-CN';
  
  // 获取百炼AI API密钥
  String? get bailianApiKey => _config['bailianApiKey'];
  
  // 获取百炼AI应用ID
  String? get bailianAppId => _config['bailianAppId'];
  
  // 获取暗黑模式
  bool get darkMode => _config['darkMode'];
  
  // 获取是否显示今日视频列表
  bool get showDailyVideoList => _config['showDailyVideoList'] ?? true;
  
  // 构造函数
  ConfigService() {
    loadConfig();
  }
  
  // 加载配置
  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configString = prefs.getString('app_config');
      
      if (configString != null) {
        final loadedConfig = json.decode(configString);
        _config = Map.from(_defaultConfig); // 先加载默认配置
        _config.addAll(loadedConfig); // 再覆盖已保存的配置
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('加载配置失败: $e');
      // 使用默认配置
      _config = Map.from(_defaultConfig);
    }
  }
  
  // 保存配置
  Future<void> saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configString = json.encode(_config);
      await prefs.setString('app_config', configString);
    } catch (e) {
      debugPrint('保存配置失败: $e');
    }
  }
  
  // 更新播放速度选项
  Future<void> updatePlaybackRates(List<double> rates) async {
    _config['playbackRates'] = rates;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新默认播放速度
  Future<void> updateDefaultPlaybackRate(double rate) async {
    _config['defaultPlaybackRate'] = rate;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新循环等待间隔
  Future<void> updateLoopWaitInterval(int milliseconds) async {
    _config['loopWaitInterval'] = milliseconds;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕字体大小
  Future<void> updateSubtitleFontSize(double size) async {
    _config['subtitleFontSize'] = size;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕颜色
  Future<void> updateSubtitleColor(Color color) async {
    _config['subtitleColor'] = color.value;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕背景颜色
  Future<void> updateSubtitleBackgroundColor(Color color) async {
    _config['subtitleBackgroundColor'] = color.value;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕字体粗细
  Future<void> updateSubtitleFontWeight(bool isBold) async {
    _config['subtitleFontWeight'] = isBold ? 'bold' : 'normal';
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕自动匹配设置
  Future<void> updateAutoMatchSubtitle(bool autoMatch) async {
    _config['autoMatchSubtitle'] = autoMatch;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕匹配模式
  Future<void> updateSubtitleMatchMode(String mode) async {
    _config['subtitleMatchMode'] = mode;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新字幕后缀列表
  Future<void> updateSubtitleSuffixes(List<String> suffixes) async {
    _config['subtitleSuffixes'] = suffixes;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新YouTube视频下载路径
  Future<void> updateYoutubeDownloadPath(String path) async {
    _config['youtubeDownloadPath'] = path;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新YouTube视频质量
  Future<void> setYouTubeVideoQuality(String quality) async {
    _config['youtubeVideoQuality'] = quality;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新Google Cloud Translation API密钥
  Future<void> updateGoogleTranslateApiKey(String apiKey) async {
    _config['googleTranslateApiKey'] = apiKey;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新Google Cloud项目ID
  Future<void> updateGoogleProjectId(String projectId) async {
    _config['googleProjectId'] = projectId;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新翻译目标语言
  Future<void> updateTranslateTargetLanguage(String languageCode) async {
    _config['translateTargetLanguage'] = languageCode;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新百炼AI API密钥
  Future<void> updateBailianApiKey(String apiKey) async {
    _config['bailianApiKey'] = apiKey;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新百炼AI应用ID
  Future<void> updateBailianAppId(String appId) async {
    _config['bailianAppId'] = appId;
    await saveConfig();
    notifyListeners();
  }
  
  // 更新暗黑模式
  Future<void> updateDarkMode(bool isDark) async {
    _config['darkMode'] = isDark;
    await saveConfig();
    notifyListeners();
  }

  // 更新是否显示今日视频列表
  Future<void> updateShowDailyVideoList(bool show) async {
    _config['showDailyVideoList'] = show;
    await saveConfig();
    notifyListeners();
  }
  
  // 重置为默认配置
  Future<void> resetToDefault() async {
    _config = Map.from(_defaultConfig);
    await saveConfig();
    notifyListeners();
  }
} 