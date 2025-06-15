import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:process_run/process_run.dart';

/// YouTube字幕下载器
/// 封装所有与YouTube字幕下载相关的功能
class YouTubeSubtitleDownloader {
  // 视频ID
  final String videoId;
  
  // 语言代码
  final String languageCode;
  
  // 重试次数
  final int maxRetries;
  
  // 重试延迟
  final Duration retryDelay;
  
  // HTTP客户端
  final Dio _dio;
  
  // 用户代理
  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
  
  // 状态更新回调
  final Function(String)? onStatusUpdate;
  
  // 构造函数
  YouTubeSubtitleDownloader({
    required this.videoId,
    this.languageCode = 'zh-CN',
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.onStatusUpdate,
  }) : _dio = Dio(BaseOptions(
         connectTimeout: const Duration(seconds: 15),
         receiveTimeout: const Duration(seconds: 15),
         headers: {'User-Agent': _userAgent},
       ));
  
  /// 下载字幕
  Future<String> downloadSubtitles() async {
    // 方法优先级列表（按成功率排序）
    final strategies = [
      _tryYtDlpCommand,   // yt-dlp 命令行工具 (最可靠)
      _tryYtDlpApi,       // yt-dlp API (备用)
      _tryYouTubeTimedText, // YouTube TimedText API
      _tryYouTubeTranscript, // YouTube Transcript API
      _tryScrapingWebPage,   // 网页抓取
    ];
    
    // 记录错误
    final errors = <String>[];
    
    // 依次尝试所有方法
    for (final strategy in strategies) {
      int attempts = 0;
      while (attempts < maxRetries) {
        try {
          _updateStatus('尝试下载字幕 (方法: ${strategy.toString().split('.').last})...');
          final result = await strategy();
          if (result.isNotEmpty) {
            _updateStatus('字幕下载成功');
            return result;
          }
          break; // 如果返回空字符串但没有异常，跳到下一个策略
        } catch (e) {
          attempts++;
          final errorMsg = '方法 ${strategy.toString().split('.').last} 失败 ($attempts/$maxRetries): $e';
          _debug(errorMsg);
          errors.add(errorMsg);
          
          if (attempts >= maxRetries) {
            _updateStatus('方法失败，尝试下一种方法...');
            break;
          }
          
          _updateStatus('重试中...');
          await Future.delayed(retryDelay * attempts);
        }
      }
    }
    
    // 所有方法都失败
    final errorMessage = '所有字幕下载方法均失败:\n${errors.join('\n')}';
    _debug(errorMessage);
    throw Exception(errorMessage);
  }
  
  /// 获取可用字幕轨道列表
  Future<List<Map<String, dynamic>>> getAvailableSubtitleTracks() async {
    try {
      _updateStatus('获取可用字幕轨道...');
      
      // 首先尝试使用yt-dlp命令行获取字幕轨道
      final tracksFromCommand = await _getSubtitleTracksFromYtDlpCommand();
      if (tracksFromCommand.isNotEmpty) {
        _updateStatus('找到 ${tracksFromCommand.length} 个字幕轨道');
        return tracksFromCommand;
      }
      
      // 然后尝试使用yt-dlp API获取字幕轨道
      final tracks = await _getSubtitleTracksFromYtDlp();
      if (tracks.isNotEmpty) {
        _updateStatus('找到 ${tracks.length} 个字幕轨道');
        return tracks;
      }
      
      // 如果yt-dlp失败，尝试从网页获取
      final webTracks = await _getSubtitleTracksFromWebPage();
      if (webTracks.isNotEmpty) {
        _updateStatus('找到 ${webTracks.length} 个字幕轨道');
        return webTracks;
      }
      
      _updateStatus('未找到字幕轨道');
      return [];
    } catch (e) {
      _debug('获取字幕轨道失败: $e');
      return [];
    }
  }
  
  /// 下载特定字幕轨道
  Future<String> downloadSpecificTrack(Map<String, dynamic> track) async {
    try {
      final trackLang = track['languageCode'] as String? ?? languageCode;
      final trackName = track['name'] as String? ?? trackLang;
      
      _updateStatus('下载字幕: $trackName');
      
      if (track['source'] == 'yt-dlp-command') {
        // 从yt-dlp命令行下载
        final code = track['code'] as String?;
        if (code != null) {
          return await _downloadSubtitleWithYtDlpCommand(code);
        }
      } else if (track['source'] == 'yt-dlp') {
        // 从yt-dlp API下载
        final url = track['url'] as String?;
        if (url != null) {
          final response = await _dio.get(url);
          if (response.statusCode == 200 && response.data != null) {
            return _convertToSrt(response.data);
          }
        }
      } else if (track['source'] == 'web') {
        // 从网页下载
        final baseUrl = track['baseUrl'] as String?;
        if (baseUrl != null) {
          final response = await _dio.get('$baseUrl&fmt=json3');
          if (response.statusCode == 200 && response.data != null) {
            return _convertJson3ToSrt(response.data);
          }
        }
      }
      
      // 如果特定轨道下载失败，回退到通用下载方法
      _updateStatus('特定轨道下载失败，尝试通用方法...');
      return await downloadSubtitles();
    } catch (e) {
      _debug('下载特定字幕轨道失败: $e');
      // 回退到通用下载方法
      return await downloadSubtitles();
    }
  }
  
  /// 保存字幕到文件
  Future<File> saveSubtitlesToFile(String subtitles, String filePath) async {
    try {
      _updateStatus('保存字幕到文件...');
      
      // 确保目录存在
      final directory = path.dirname(filePath);
      if (!Directory(directory).existsSync()) {
        await Directory(directory).create(recursive: true);
      }
      
      // 保存文件
      final file = File(filePath);
      await file.writeAsString(subtitles);
      
      _updateStatus('字幕已保存: ${path.basename(filePath)}');
      return file;
    } catch (e) {
      _debug('保存字幕文件失败: $e');
      rethrow;
    }
  }
  
  /// 检查yt-dlp是否已安装，如果未安装则返回安装指南
  static Future<Map<String, dynamic>> checkYtDlpInstallation() async {
    try {
      final result = await Process.run('python', ['-m', 'yt_dlp', '--version']);
      if (result.exitCode == 0) {
        final version = (result.stdout as String).trim();
        return {
          'installed': true,
          'version': version,
          'message': 'yt-dlp已安装，版本: $version',
        };
      } else {
        return {
          'installed': false,
          'message': '未检测到yt-dlp',
          'installationGuide': _getYtDlpInstallationGuide(),
        };
      }
    } catch (e) {
      return {
        'installed': false,
        'message': '未检测到yt-dlp',
        'error': e.toString(),
        'installationGuide': _getYtDlpInstallationGuide(),
      };
    }
  }
  
  /// 获取yt-dlp安装指南
  static String _getYtDlpInstallationGuide() {
    final isWindows = Platform.isWindows;
    final isMacOS = Platform.isMacOS;
    final isLinux = Platform.isLinux;
    
    final buffer = StringBuffer();
    buffer.writeln('yt-dlp安装指南:');
    buffer.writeln('');
    
    buffer.writeln('使用pip安装 (推荐):');
    buffer.writeln('```');
    buffer.writeln('python -m pip install -U yt-dlp');
    buffer.writeln('```');
    buffer.writeln('');
    
    if (isWindows) {
      buffer.writeln('Windows其他安装方法:');
      buffer.writeln('1. 使用Chocolatey:');
      buffer.writeln('```');
      buffer.writeln('choco install yt-dlp');
      buffer.writeln('```');
      buffer.writeln('');
      buffer.writeln('2. 使用Scoop:');
      buffer.writeln('```');
      buffer.writeln('scoop install yt-dlp');
      buffer.writeln('```');
    } else if (isMacOS) {
      buffer.writeln('macOS其他安装方法:');
      buffer.writeln('1. 使用Homebrew:');
      buffer.writeln('```');
      buffer.writeln('brew install yt-dlp');
      buffer.writeln('```');
    } else if (isLinux) {
      buffer.writeln('Linux其他安装方法:');
      buffer.writeln('1. 使用apt (Debian/Ubuntu):');
      buffer.writeln('```');
      buffer.writeln('sudo apt install yt-dlp');
      buffer.writeln('```');
      buffer.writeln('');
      buffer.writeln('2. 使用dnf (Fedora):');
      buffer.writeln('```');
      buffer.writeln('sudo dnf install yt-dlp');
      buffer.writeln('```');
    }
    
    buffer.writeln('');
    buffer.writeln('安装后，请重启应用以使更改生效。');
    
    return buffer.toString();
  }
  
  //==== 私有方法 ====//
  
  // 检查yt-dlp是否已安装
  Future<bool> _isYtDlpInstalled() async {
    try {
      final result = await Process.run('python', ['-m', 'yt_dlp', '--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
  
  // 方法0: 使用yt-dlp命令行工具 (最可靠)
  Future<String> _tryYtDlpCommand() async {
    if (!await _isYtDlpInstalled()) {
      _debug('yt-dlp未安装，跳过命令行方法');
      return '';
    }
    
    try {
      return await _downloadSubtitleWithYtDlpCommand(languageCode);
    } catch (e) {
      _debug('yt-dlp命令行方法失败: $e');
      rethrow;
    }
  }
  
  // 使用yt-dlp命令行工具下载字幕
  Future<String> _downloadSubtitleWithYtDlpCommand(String lang) async {
    final tempDir = Directory.systemTemp.createTempSync('yt_subtitles_');
    
    try {
      _updateStatus('使用yt-dlp命令行工具下载字幕...');
      
      // 构建yt-dlp命令
      final command = 'python';
      final args = [
        '-m',
        'yt_dlp',
        'https://www.youtube.com/watch?v=$videoId',
        '--write-sub',
        '--write-auto-sub',
        '--sub-lang', lang,
        '--skip-download',
        '--sub-format', 'srt',
        '-o', path.join(tempDir.path, videoId),
      ];
      
      // 执行命令
      final shell = Shell();
      final result = await shell.run('$command ${args.join(' ')}');
      
      if (result.first.exitCode != 0) {
        throw Exception('yt-dlp命令执行失败: ${result.first.stderr}');
      }
      
      // 查找生成的字幕文件
      final files = tempDir.listSync().where((f) => 
        f is File && 
        path.basename(f.path).contains(videoId) && 
        path.basename(f.path).endsWith('.srt')
      ).toList();
      
      if (files.isEmpty) {
        throw Exception('未找到生成的字幕文件');
      }
      
      // 读取字幕内容
      final subtitleFile = files.first as File;
      final content = await subtitleFile.readAsString();
      
      // 清理临时文件
      await tempDir.delete(recursive: true);
      
      if (content.isEmpty) {
        throw Exception('字幕文件内容为空');
      }
      
      return content;
    } catch (e) {
      // 清理临时文件
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      _debug('yt-dlp命令行下载失败: $e');
      rethrow;
    }
  }
  
  // 从yt-dlp命令行获取字幕轨道
  Future<List<Map<String, dynamic>>> _getSubtitleTracksFromYtDlpCommand() async {
    if (!await _isYtDlpInstalled()) {
      _debug('yt-dlp未安装，跳过获取字幕轨道');
      return [];
    }
    
    try {
      _updateStatus('使用yt-dlp命令行获取字幕轨道...');
      
      // 构建yt-dlp命令，获取可用字幕列表
      final command = 'python';
      final args = [
        '-m',
        'yt_dlp',
        'https://www.youtube.com/watch?v=$videoId',
        '--list-subs',
        '--skip-download',
      ];
      
      // 执行命令
      final shell = Shell();
      final result = await shell.run('$command ${args.join(' ')}');
      
      if (result.first.exitCode != 0) {
        throw Exception('yt-dlp命令执行失败: ${result.first.stderr}');
      }
      
      // 解析输出
      final output = result.first.stdout as String;
      final tracks = <Map<String, dynamic>>[];
      
      // 解析字幕轨道
      final languageRegex = RegExp(r'(\w+(?:-\w+)?) +([^(]+)(?:\(([^)]+)\))?');
      final matches = languageRegex.allMatches(output);
      
      for (final match in matches) {
        if (match.groupCount >= 2) {
          final code = match.group(1)?.trim() ?? '';
          final name = match.group(2)?.trim() ?? '';
          final isAuto = output.contains('auto-generated') || 
                        (match.groupCount >= 3 && match.group(3) != null && 
                         match.group(3)?.contains('auto') == true);
          
          tracks.add({
            'source': 'yt-dlp-command',
            'languageCode': code,
            'languageName': name,
            'isAutoGenerated': isAuto,
            'name': '$name${isAuto ? " (自动生成)" : ""}',
            'code': code,
          });
        }
      }
      
      return tracks;
    } catch (e) {
      _debug('从yt-dlp命令行获取字幕轨道失败: $e');
      return [];
    }
  }
  
  // 方法1: 使用yt-dlp API (备用)
  Future<String> _tryYtDlpApi() async {
    try {
      final response = await _dio.get(
        'https://yt.lemnoslife.com/videos',
        queryParameters: {
          'part': 'subtitles',
          'id': videoId,
        },
      );
      
      if (response.statusCode != 200 || response.data == null) {
        return '';
      }
      
      final items = response.data['items'] as List?;
      if (items == null || items.isEmpty) {
        return '';
      }
      
      final subtitles = items[0]['subtitles'];
      if (subtitles == null) {
        return '';
      }
      
      // 尝试获取指定语言的字幕
      String? subUrl;
      
      // 首先精确匹配语言代码
      if (subtitles[languageCode] != null) {
        subUrl = subtitles[languageCode].last['url'];
      } 
      // 然后尝试匹配语言代码前缀 (例如 'zh-CN' -> 'zh')
      else {
        final prefix = languageCode.split('-')[0];
        for (final key in subtitles.keys) {
          if (key.startsWith(prefix)) {
            subUrl = subtitles[key].last['url'];
            break;
          }
        }
      }
      
      // 如果没有找到匹配的语言，使用第一个可用的字幕
      if (subUrl == null && subtitles.isNotEmpty) {
        final firstLang = subtitles.keys.first;
        subUrl = subtitles[firstLang].last['url'];
      }
      
      if (subUrl == null) {
        return '';
      }
      
      // 下载字幕内容
      final subResponse = await _dio.get(subUrl);
      if (subResponse.statusCode != 200 || subResponse.data == null) {
        return '';
      }
      
      return _convertToSrt(subResponse.data);
    } catch (e) {
      _debug('yt-dlp API方法失败: $e');
      rethrow;
    }
  }
  
  // 方法2: 使用YouTube TimedText API
  Future<String> _tryYouTubeTimedText() async {
    try {
      // 构建请求URL
      final url = 'https://www.youtube.com/api/timedtext?v=$videoId&lang=$languageCode';
      
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      
      if (response.statusCode != 200 || response.data == null || response.data.toString().isEmpty) {
        return '';
      }
      
      // 检查是否是XML格式
      final content = response.data.toString();
      if (content.contains('<transcript>')) {
        return _convertXmlToSrt(content);
      }
      
      return '';
    } catch (e) {
      _debug('YouTube TimedText API方法失败: $e');
      rethrow;
    }
  }
  
  // 方法3: 使用YouTube Transcript API
  Future<String> _tryYouTubeTranscript() async {
    try {
      final url = 'https://youtubetranscript.com/';
      
      // 发送POST请求获取字幕
      final response = await _dio.post(
        url,
        data: {'videoId': videoId, 'lang': languageCode},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      
      if (response.statusCode != 200 || response.data == null) {
        return '';
      }
      
      // 解析JSON响应
      final data = response.data;
      if (data is Map && data['transcript'] != null) {
        final transcript = data['transcript'] as List?;
        if (transcript != null && transcript.isNotEmpty) {
          return _convertTranscriptToSrt(transcript);
        }
      }
      
      return '';
    } catch (e) {
      _debug('YouTube Transcript API方法失败: $e');
      rethrow;
    }
  }
  
  // 方法4: 网页抓取
  Future<String> _tryScrapingWebPage() async {
    try {
      final response = await _dio.get(
        'https://www.youtube.com/watch?v=$videoId',
        options: Options(responseType: ResponseType.plain),
      );
      
      if (response.statusCode != 200 || response.data == null) {
        return '';
      }
      
      final html = response.data.toString();
      
      // 从HTML中提取字幕数据
      final regex = RegExp(r'"captionTracks":(\[.*?\])');
      final match = regex.firstMatch(html);
      if (match == null || match.groupCount < 1) {
        return '';
      }
      
      final captionsJson = match.group(1)!;
      final captions = jsonDecode(captionsJson) as List;
      
      if (captions.isEmpty) {
        return '';
      }
      
      // 查找匹配语言的字幕
      Map<String, dynamic>? targetCaption;
      
      // 首先精确匹配
      targetCaption = captions.cast<Map<String, dynamic>>().firstWhere(
        (c) => c['languageCode'] == languageCode,
        orElse: () => <String, dynamic>{},
      );
      
      // 然后尝试匹配前缀
      if (targetCaption.isEmpty) {
        final prefix = languageCode.split('-')[0];
        targetCaption = captions.cast<Map<String, dynamic>>().firstWhere(
          (c) => (c['languageCode'] as String).startsWith(prefix),
          orElse: () => <String, dynamic>{},
        );
      }
      
      // 如果还是没找到，使用第一个
      if (targetCaption.isEmpty && captions.isNotEmpty) {
        targetCaption = captions.first as Map<String, dynamic>;
      }
      
      if (targetCaption.isEmpty || targetCaption['baseUrl'] == null) {
        return '';
      }
      
      final subUrl = targetCaption['baseUrl'];
      final subResponse = await _dio.get('$subUrl&fmt=json3');
      
      if (subResponse.statusCode != 200 || subResponse.data == null) {
        return '';
      }
      
      return _convertJson3ToSrt(subResponse.data);
    } catch (e) {
      _debug('网页抓取方法失败: $e');
      rethrow;
    }
  }
  
  // 从yt-dlp获取字幕轨道
  Future<List<Map<String, dynamic>>> _getSubtitleTracksFromYtDlp() async {
    try {
      final response = await _dio.get(
        'https://yt.lemnoslife.com/videos',
        queryParameters: {
          'part': 'subtitles',
          'id': videoId,
        },
      );
      
      if (response.statusCode != 200 || response.data == null) {
        return [];
      }
      
      final items = response.data['items'] as List?;
      if (items == null || items.isEmpty) {
        return [];
      }
      
      final subtitles = items[0]['subtitles'];
      if (subtitles == null) {
        return [];
      }
      
      final result = <Map<String, dynamic>>[];
      
      // 为每种语言添加一个轨道
      subtitles.forEach((lang, tracks) {
        final track = tracks.last;
        final name = track['name'] ?? lang;
        final isAuto = name.toString().toLowerCase().contains('auto');
        
        result.add({
          'source': 'yt-dlp',
          'languageCode': lang,
          'languageName': name,
          'isAutoGenerated': isAuto,
          'name': '$name${isAuto ? " (自动生成)" : ""}',
          'url': track['url'],
        });
      });
      
      return result;
    } catch (e) {
      _debug('从yt-dlp获取字幕轨道失败: $e');
      return [];
    }
  }
  
  // 从网页获取字幕轨道
  Future<List<Map<String, dynamic>>> _getSubtitleTracksFromWebPage() async {
    try {
      final response = await _dio.get(
        'https://www.youtube.com/watch?v=$videoId',
        options: Options(responseType: ResponseType.plain),
      );
      
      if (response.statusCode != 200 || response.data == null) {
        return [];
      }
      
      final html = response.data.toString();
      
      // 从HTML中提取字幕数据
      final regex = RegExp(r'"captionTracks":(\[.*?\])');
      final match = regex.firstMatch(html);
      if (match == null || match.groupCount < 1) {
        return [];
      }
      
      final captionsJson = match.group(1)!;
      final captions = jsonDecode(captionsJson) as List;
      
      if (captions.isEmpty) {
        return [];
      }
      
      final result = <Map<String, dynamic>>[];
      
      // 为每个轨道添加一个条目
      for (final track in captions) {
        final lang = track['languageCode'] as String;
        final name = track['name']?['simpleText'] ?? track['name']?['runs']?[0]?['text'] ?? lang;
        final isAuto = track['kind'] == 'asr';
        final baseUrl = track['baseUrl'] as String;
        
        result.add({
          'source': 'web',
          'languageCode': lang,
          'languageName': name,
          'isAutoGenerated': isAuto,
          'name': '$name${isAuto ? " (自动生成)" : ""}',
          'baseUrl': baseUrl,
        });
      }
      
      return result;
    } catch (e) {
      _debug('从网页获取字幕轨道失败: $e');
      return [];
    }
  }
  
  // 将YouTube的JSON3格式转换为SRT
  String _convertJson3ToSrt(dynamic jsonData) {
    try {
      final data = jsonData is String ? jsonDecode(jsonData) : jsonData;
      final events = data['events'] as List<dynamic>? ?? [];
      final buffer = StringBuffer();
      
      int index = 1;
      for (final event in events) {
        if (event == null) continue;
        
        // 跳过没有文本的事件
        if (!event.containsKey('segs')) continue;
        
        final start = (event['tStartMs'] as num?) ?? 0;
        final duration = (event['dDurationMs'] as num?) ?? 0;
        final end = start + duration;
        
        final segs = event['segs'] as List<dynamic>? ?? [];
        final text = segs
            .map((seg) => seg['utf8'] as String?)
            .where((s) => s != null && s.isNotEmpty)
            .join('')
            .replaceAll('\n', ' ')
            .trim();
        
        if (text.isEmpty) continue;
        
        buffer.writeln('$index');
        buffer.writeln('${_formatTime(start / 1000)} --> ${_formatTime(end / 1000)}');
        buffer.writeln(text);
        buffer.writeln();
        
        index++;
      }
      
      return buffer.toString();
    } catch (e) {
      _debug('JSON3转SRT失败: $e');
      return '';
    }
  }
  
  // 将XML格式转换为SRT
  String _convertXmlToSrt(String xml) {
    try {
      final buffer = StringBuffer();
      final regex = RegExp(r'<text start="([\d.]+)" dur="([\d.]+)".*?>(.*?)</text>', dotAll: true);
      final matches = regex.allMatches(xml);
      
      int index = 1;
      for (final match in matches) {
        if (match.groupCount < 3) continue;
        
        final start = double.parse(match.group(1)!);
        final duration = double.parse(match.group(2)!);
        final end = start + duration;
        final text = _decodeHtmlEntities(match.group(3)!);
        
        if (text.isEmpty) continue;
        
        buffer.writeln('$index');
        buffer.writeln('${_formatTime(start)} --> ${_formatTime(end)}');
        buffer.writeln(text);
        buffer.writeln();
        
        index++;
      }
      
      return buffer.toString();
    } catch (e) {
      _debug('XML转SRT失败: $e');
      return '';
    }
  }
  
  // 将Transcript格式转换为SRT
  String _convertTranscriptToSrt(List transcript) {
    try {
      final buffer = StringBuffer();
      
      int index = 1;
      for (final item in transcript) {
        if (item == null) continue;
        
        final start = (item['start'] as num?)?.toDouble() ?? 0;
        final duration = (item['duration'] as num?)?.toDouble() ?? 0;
        final end = start + duration;
        final text = item['text'] as String? ?? '';
        
        if (text.isEmpty) continue;
        
        buffer.writeln('$index');
        buffer.writeln('${_formatTime(start)} --> ${_formatTime(end)}');
        buffer.writeln(text);
        buffer.writeln();
        
        index++;
      }
      
      return buffer.toString();
    } catch (e) {
      _debug('Transcript转SRT失败: $e');
      return '';
    }
  }
  
  // 通用转换方法
  String _convertToSrt(dynamic data) {
    if (data is String) {
      // 检查是否已经是SRT格式
      if (data.contains('-->')) return data;
      
      // 检查是否是XML格式
      if (data.contains('<transcript>') || data.contains('<text')) {
        return _convertXmlToSrt(data);
      }
      
      // 尝试解析为JSON
      try {
        return _convertJson3ToSrt(data);
      } catch (e) {
        // 不是JSON，可能是其他格式
        return data;
      }
    } else if (data is List) {
      // 可能是transcript格式
      return _convertTranscriptToSrt(data);
    } else {
      // 尝试转换为SRT
      try {
        return _convertJson3ToSrt(data);
      } catch (e) {
        return data.toString();
      }
    }
  }
  
  // 格式化时间为SRT格式
  String _formatTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    final millis = ((seconds % 1) * 1000).floor();
    
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')},'
        '${millis.toString().padLeft(3, '0')}';
  }
  
  // 解码HTML实体
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('<br />', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ''); // 移除其他HTML标签
  }
  
  // 更新状态
  void _updateStatus(String message) {
    if (onStatusUpdate != null) {
      onStatusUpdate!(message);
    }
  }
  
  // 调试输出
  void _debug(String message) {
    debugPrint('YouTubeSubtitleDownloader: $message');
  }
}