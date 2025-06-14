import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'video_service.dart';
import 'history_service.dart';
import 'vocabulary_service.dart' as vocabService;
import 'message_service.dart';
import 'config_service.dart';

/// 全局服务引用，便于在应用的任何地方访问
class AppServices {
  static VideoService? videoService;
  static HistoryService? historyService;
  static vocabService.VocabularyService? vocabularyService;
  static MessageService? messageService;
  static ConfigService? configService;
  
  /// 初始化所有服务引用
  static void initServices(BuildContext context) {
    videoService = Provider.of<VideoService>(context, listen: false);
    historyService = Provider.of<HistoryService>(context, listen: false);
    vocabularyService = Provider.of<vocabService.VocabularyService>(context, listen: false);
    messageService = Provider.of<MessageService>(context, listen: false);
    configService = Provider.of<ConfigService>(context, listen: false);
    
    debugPrint('全局服务引用初始化完成');
  }
} 