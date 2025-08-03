import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class BailianTranslationService {
  static const String _baseUrl = 'https://dashscope.aliyuncs.com/api/v1/apps';
  
  final ConfigService _configService;
  
  // 构造函数
  BailianTranslationService({required ConfigService configService})
      : _configService = configService;
  
  // 翻译文本
  Future<String> translateText(String text, {String targetLanguage = 'zh'}) async {
    try {
      // 从配置服务获取API密钥和应用ID
      final apiKey = _configService.bailianApiKey;
      final appId = _configService.bailianAppId;
      
      // 检查配置是否完整
      if (apiKey == null || apiKey.isEmpty) {
        return '百炼AI API密钥未配置，请在设置中配置';
      }
      
      if (appId == null || appId.isEmpty) {
        return '百炼AI应用ID未配置，请在设置中配置';
      }
      
      final url = Uri.parse('$_baseUrl/$appId/completion');
      
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'X-DashScope-SSE': 'disable',
      };
      
      final body = {
        'input': {
          'prompt': '请将以下英文翻译成中文，只返回翻译结果，不要添加任何解释：\n\n$text'
        },
        'parameters': {
          'result_format': 'message',
        },
        'debug': {}
      };
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        // 解析响应数据 - 根据实际API响应格式
        if (responseData['output'] != null) {
          // 尝试多种可能的响应格式
          
          // 格式1: choices数组格式
          if (responseData['output']['choices'] != null &&
              responseData['output']['choices'].isNotEmpty) {
            final message = responseData['output']['choices'][0]['message'];
            if (message != null && message['content'] != null) {
              return message['content'].toString().trim();
            }
          }
          
          // 格式2: 直接在output中的text字段
          if (responseData['output']['text'] != null) {
            return responseData['output']['text'].toString().trim();
          }
          
          // 格式3: 其他可能的text字段位置
          if (responseData['output']['finish_reason'] != null) {
            // 检查是否有text字段在output层级
            final outputKeys = responseData['output'].keys.toList();
            for (String key in outputKeys) {
              if (key.contains('text') && responseData['output'][key] is String) {
                final text = responseData['output'][key].toString().trim();
                if (text.isNotEmpty && !text.startsWith('{') && !text.startsWith('[')) {
                  return text;
                }
              }
            }
          }
        }
        
        // 如果以上都没找到，尝试在响应的根级别查找text
        if (responseData['text'] != null) {
          return responseData['text'].toString().trim();
        }
        
        // 打印完整响应以便调试
        print('完整API响应: ${response.body}');
        return '翻译响应格式异常，请检查控制台输出';
      } else {
        return '翻译请求失败: HTTP ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return '翻译服务异常: $e';
    }
  }
  
  // 批量翻译多个文本
  Future<List<String>> translateTexts(List<String> texts) async {
    List<String> results = [];
    
    for (String text in texts) {
      if (text.trim().isEmpty) {
        results.add('');
        continue;
      }
      
      try {
        final translated = await translateText(text);
        results.add(translated);
        
        // 添加小延迟避免API限流
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        results.add('翻译失败: $e');
      }
    }
    
    return results;
  }
  
  // 检查服务是否可用
  Future<bool> isServiceAvailable() async {
    try {
      final testResult = await translateText('Hello');
      return !testResult.startsWith('翻译');
    } catch (e) {
      return false;
    }
  }
} 