import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/config_service.dart';

/// 翻译服务类，用于调用Google Cloud Translation API
class TranslationService {
  final ConfigService _configService;
  
  // 缓存已翻译的文本，避免重复请求
  final Map<String, String> _translationCache = {};
  
  // 构造函数
  TranslationService({required ConfigService configService})
      : _configService = configService;
  
  /// 翻译文本到目标语言
  /// [text] 要翻译的文本
  /// [targetLanguage] 目标语言代码，如果未指定则使用配置中的目标语言
  /// [sourceLanguage] 源语言代码，默认为'auto'（自动检测）
  /// 返回翻译后的文本，如果翻译失败则返回原文本
  Future<String> translateText({
    required String text,
    String? targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    // 如果未指定目标语言，则使用配置中的目标语言
    final actualTargetLanguage = targetLanguage ?? _configService.translateTargetLanguage;
    
    // 检查缓存
    final cacheKey = '$text|$sourceLanguage|$actualTargetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      debugPrint('使用缓存的翻译结果');
      return _translationCache[cacheKey]!;
    }
    
    try {
      // 获取API凭据
      final apiKey = _configService.googleTranslateApiKey;
      
      // 检查API凭据是否已配置
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Google Cloud Translation API 密钥未配置，请在设置中配置');
      }
      
      // 构建请求URL和参数
      final url = Uri.parse('https://translation.googleapis.com/language/translate/v2');
      
      // 使用查询参数传递API密钥
      final queryParams = {
        'key': apiKey,
        'q': text,
        'target': actualTargetLanguage,
        'format': 'text',
      };
      
      // 如果指定了源语言且不是auto，添加到参数中
      if (sourceLanguage != 'auto') {
        queryParams['source'] = sourceLanguage;
      }
      
      final requestUrl = url.replace(queryParameters: queryParams);
      
      // 发送请求
      debugPrint('发送翻译请求: $text');
      final response = await http.post(
        requestUrl,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
        },
      ).timeout(const Duration(seconds: 10)); // 设置超时时间
      
      // 解析响应
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final translations = jsonResponse['data']['translations'] as List;
        if (translations.isNotEmpty) {
          final translatedText = translations[0]['translatedText'] as String;
          
          // 缓存翻译结果
          _translationCache[cacheKey] = translatedText;
          
          return translatedText;
        }
      }
      
      // 请求失败，返回原文本
      debugPrint('翻译请求失败: ${response.statusCode} - ${response.body}');
      return text;
    } catch (e) {
      debugPrint('翻译出错: $e');
      return text;
    }
  }
  
  /// 翻译长文本，通过分段翻译避免请求长度限制
  /// [text] 要翻译的长文本
  /// [targetLanguage] 目标语言代码，如果未指定则使用配置中的目标语言
  /// [sourceLanguage] 源语言代码，默认为'auto'（自动检测）
  /// 返回翻译后的合并文本
  Future<String> translateLongText({
    required String text,
    String? targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    // 如果未指定目标语言，则使用配置中的目标语言
    final actualTargetLanguage = targetLanguage ?? _configService.translateTargetLanguage;
    
    // 检查缓存
    final cacheKey = 'long|$text|$sourceLanguage|$actualTargetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      debugPrint('使用缓存的长文本翻译结果');
      return _translationCache[cacheKey]!;
    }
    
    try {
      // 将长文本分段，每段不超过1000个字符
      // 但要尽量按照段落或句子分割，避免破坏语义
      final segments = _splitTextIntoSegments(text);
      debugPrint('将长文本分成 ${segments.length} 段进行翻译');
      
      // 翻译每个段落
      final translatedSegments = <String>[];
      for (int i = 0; i < segments.length; i++) {
        debugPrint('翻译第 ${i + 1}/${segments.length} 段，长度: ${segments[i].length}');
        
        // 翻译当前段落
        final translatedSegment = await translateText(
          text: segments[i],
          targetLanguage: actualTargetLanguage,
          sourceLanguage: sourceLanguage,
        );
        
        translatedSegments.add(translatedSegment);
      }
      
      // 合并翻译结果
      final result = translatedSegments.join('\n\n');
      
      // 缓存结果
      _translationCache[cacheKey] = result;
      
      return result;
    } catch (e) {
      debugPrint('长文本翻译出错: $e');
      return text;
    }
  }
  
  /// 将长文本分割成适合翻译的段落
  List<String> _splitTextIntoSegments(String text) {
    // 最大段落长度（字符数）
    const int maxSegmentLength = 1000;
    
    // 结果段落列表
    final List<String> segments = [];
    
    // 首先按段落分割
    final paragraphs = text.split('\n\n');
    
    // 当前段落缓冲区
    StringBuffer currentSegment = StringBuffer();
    
    for (final paragraph in paragraphs) {
      // 如果当前段落加上新段落超过最大长度，则添加当前段落到结果，并重置缓冲区
      if (currentSegment.length + paragraph.length > maxSegmentLength) {
        if (currentSegment.isNotEmpty) {
          segments.add(currentSegment.toString());
          currentSegment = StringBuffer();
        }
        
        // 如果单个段落超过最大长度，需要进一步分割
        if (paragraph.length > maxSegmentLength) {
          // 按句子分割
          final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
          
          for (final sentence in sentences) {
            if (currentSegment.length + sentence.length > maxSegmentLength) {
              if (currentSegment.isNotEmpty) {
                segments.add(currentSegment.toString());
                currentSegment = StringBuffer();
              }
              
              // 如果单个句子仍然过长，按空格分割
              if (sentence.length > maxSegmentLength) {
                final words = sentence.split(' ');
                for (final word in words) {
                  if (currentSegment.length + word.length + 1 > maxSegmentLength) {
                    segments.add(currentSegment.toString());
                    currentSegment = StringBuffer(word);
                  } else {
                    if (currentSegment.isNotEmpty) {
                      currentSegment.write(' ');
                    }
                    currentSegment.write(word);
                  }
                }
              } else {
                currentSegment.write(sentence);
              }
            } else {
              if (currentSegment.isNotEmpty) {
                currentSegment.write(' ');
              }
              currentSegment.write(sentence);
            }
          }
        } else {
          // 直接添加这个段落作为新段落
          currentSegment.write(paragraph);
        }
      } else {
        // 如果当前段落不为空，添加换行符
        if (currentSegment.isNotEmpty) {
          currentSegment.write('\n\n');
        }
        currentSegment.write(paragraph);
      }
    }
    
    // 添加最后一个段落
    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment.toString());
    }
    
    return segments;
  }
  
  /// 清除翻译缓存
  void clearCache() {
    _translationCache.clear();
  }
} 