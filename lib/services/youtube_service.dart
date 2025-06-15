import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import '../models/subtitle_model.dart';
import '../utils/yt_subtitle_down.dart';  // 添加对字幕下载工具的导入
import 'config_service.dart';
import 'download_info_service.dart';
import 'package:flutter/services.dart';

import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  ConfigService? _configService;
  
  // 下载缓存 - 存储结构改为Map<String, Map<String, dynamic>>，包含文件名和字幕文件名
  final Map<String, Map<String, dynamic>> _downloadCache = {};
  
  // 日志
  final _logger = Logger('YouTubeService');
  
  // 缓存文件名
  static const String _cacheFileName = 'youtube_download_cache.json';
  
  // 构造函数，加载缓存
  YouTubeService() {
    _loadCache();
    _setupLogging();
  }
  
  // 设置日志记录
  void _setupLogging() {
    Logger.root.level = Level.FINER;
    Logger.root.onRecord.listen((e) {
      debugPrint('YouTube-API: ${e.message}');
      if (e.error != null) {
        debugPrint('Error: ${e.error}');
        debugPrint('Stack: ${e.stackTrace}');
      }
    });
  }
  
  // 加载下载缓存
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheFileName);
      
      if (cacheJson != null) {
        final Map<String, dynamic> data = jsonDecode(cacheJson);
        
        // 清空当前缓存并重新加载
        _downloadCache.clear();
        
        // 加载所有缓存记录
        data.forEach((videoId, info) {
          if (info is Map<String, dynamic>) {
            _downloadCache[videoId] = info;
          }
        });
        
        debugPrint('已加载YouTube下载缓存，共${_downloadCache.length}条记录');
      } else {
        debugPrint('未找到YouTube下载缓存');
      }
    } catch (e) {
      debugPrint('加载YouTube下载缓存失败: $e');
    }
  }
  
  // 保存下载缓存
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_downloadCache);
      await prefs.setString(_cacheFileName, cacheJson);
      debugPrint('已保存YouTube下载缓存，共${_downloadCache.length}条记录');
    } catch (e) {
      debugPrint('保存YouTube下载缓存失败: $e');
    }
  }
  
  // 添加下载记录到缓存
  Future<void> _addToDownloadCache(String videoId, String videoFilename, String? subtitleFilename) async {
    final cacheEntry = {
      'filename': videoFilename,
    };
    
    if (subtitleFilename != null) {
      cacheEntry['subtitleFilename'] = subtitleFilename;
    }
    
    _downloadCache[videoId] = cacheEntry;
    await _saveCache();
    debugPrint('已添加下载记录到缓存: videoId=$videoId, filename=$videoFilename, subtitleFilename=$subtitleFilename');
  }
  
  // 从下载缓存中获取视频
  Future<(String?, String?)> _getFromDownloadCache(String videoId) async {
    try {
      // 尝试从缓存中加载
      _loadCache();
      
      // 检查配置服务和下载路径
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        debugPrint('===== 用户指定了下载目录，将在该目录中查找视频 =====');
        debugPrint('用户指定的下载目录: ${_configService!.youtubeDownloadPath}');
        
        final directory = Directory(_configService!.youtubeDownloadPath);
        if (await directory.exists()) {
          // 首先查找缓存记录
          final cachedInfo = _downloadCache[videoId];
          if (cachedInfo != null) {
            debugPrint('找到缓存记录: $cachedInfo');
            
            // 构建文件路径
            final videoPath = path.join(_configService!.youtubeDownloadPath, cachedInfo['filename'] as String);
            final subtitlePath = cachedInfo['subtitleFilename'] != null ? 
                path.join(_configService!.youtubeDownloadPath, cachedInfo['subtitleFilename'] as String) : null;
            
            debugPrint('在用户目录中查找视频: $videoPath');
            final videoExists = await File(videoPath).exists();
            final subtitleExists = subtitlePath != null ? await File(subtitlePath).exists() : false;
            
            debugPrint('视频文件存在: $videoExists');
            debugPrint('字幕文件存在: $subtitleExists');
            
            if (videoExists) {
              return (videoPath, subtitleExists ? subtitlePath : null);
      } else {
              // 如果文件不存在，从缓存记录中删除
              debugPrint('视频文件不存在，从缓存记录中删除');
        _downloadCache.remove(videoId);
              _saveCache();
            }
          } else {
            debugPrint('缓存记录中没有此视频: $videoId');
            
            // 缓存中没有记录，但尝试直接在目录中查找以videoId开头的文件
            try {
              List<FileSystemEntity> files = await directory.list().toList();
              
              // 查找视频文件
              String? foundVideoPath;
              String? foundSubtitlePath;
              
              for (var file in files) {
                if (file is File) {
                  String fileName = path.basename(file.path);
                  
                  // 查找以videoId_开头的视频文件
                  if (fileName.startsWith('${videoId}_') && 
                      (fileName.endsWith('.mp4') || fileName.endsWith('.webm') || fileName.endsWith('.mkv'))) {
                    foundVideoPath = file.path;
                    debugPrint('直接在目录中找到视频文件: $foundVideoPath');
                    
                    // 查找同名但扩展名为.srt的字幕文件
                    String expectedSubtitleName = '${fileName.substring(0, fileName.lastIndexOf('.'))}.srt';
                    String expectedSubtitlePath = path.join(directory.path, expectedSubtitleName);
                    if (await File(expectedSubtitlePath).exists()) {
                      foundSubtitlePath = expectedSubtitlePath;
                      debugPrint('找到同名字幕文件: $foundSubtitlePath');
                    }
                  }
                  
                  // 如果还没找到字幕，查找以videoId_开头的字幕文件
                  if (foundSubtitlePath == null && fileName.startsWith('${videoId}_') && fileName.endsWith('.srt')) {
                    foundSubtitlePath = file.path;
                    debugPrint('直接在目录中找到字幕文件: $foundSubtitlePath');
                  }
                }
              }
              
              // 如果找到视频文件，添加到缓存并返回
              if (foundVideoPath != null) {
                final videoFileName = path.basename(foundVideoPath);
                final subtitleFileName = foundSubtitlePath != null ? path.basename(foundSubtitlePath) : null;
                
                // 添加到缓存
                final cacheEntry = {
                  'filename': videoFileName,
                };
                
                if (subtitleFileName != null) {
                  cacheEntry['subtitleFilename'] = subtitleFileName;
                }
                
                _downloadCache[videoId] = cacheEntry;
                await _saveCache();
                debugPrint('将找到的文件添加到缓存: $cacheEntry');
                
                return (foundVideoPath, foundSubtitlePath);
              }
            } catch (e) {
              debugPrint('在目录中查找文件出错: $e');
            }
          }
        } else {
          debugPrint('用户指定的下载目录不存在');
        }
        
        return (null, null);
      }
      
      // 以下是原来的缓存目录逻辑，现在只在用户未指定下载目录时使用
      // 这部分将逐渐弃用，因为我们优先使用用户指定的目录
      if (_downloadCache.containsKey(videoId)) {
        final cachedInfo = _downloadCache[videoId]!;
        final tempDir = await getTemporaryDirectory();
        
        final videoPath = path.join(tempDir.path, cachedInfo['filename'] as String);
        final subtitlePath = cachedInfo['subtitleFilename'] != null ? 
            path.join(tempDir.path, cachedInfo['subtitleFilename'] as String) : null;
        
        final videoExists = await File(videoPath).exists();
        final subtitleExists = subtitlePath != null ? await File(subtitlePath).exists() : false;
        
        if (videoExists) {
          return (videoPath, subtitleExists ? subtitlePath : null);
        } else {
          // 文件不存在，从缓存中删除
          _downloadCache.remove(videoId);
          _saveCache();
        }
      }
    } catch (e) {
      debugPrint('获取缓存出错: $e');
    }
    
    return (null, null);
  }
  
  // 清理缓存中无效的条目
  Future<void> cleanupDownloadCache() async {
    final invalidKeys = <String>[];
    
    _downloadCache.forEach((videoId, info) {
      final file = File(info['filename'] as String);
      if (!file.existsSync() || file.lengthSync() == 0) {
        invalidKeys.add(videoId);
      }
    });
    
    for (final key in invalidKeys) {
      _downloadCache.remove(key);
    }
    
    if (invalidKeys.isNotEmpty) {
      await _saveCache();
      debugPrint('已清理${invalidKeys.length}条无效的下载缓存记录');
    }
  }
  
  // 设置配置服务
  void setConfigService(ConfigService configService) {
    _configService = configService;
    debugPrint('YouTube服务已设置配置服务引用');
  }
  
  // 从URL中提取视频ID
  String? _extractVideoId(String url) {
    // 已经是视频ID格式
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) {
        return url;
      }
      
    // YouTube URL格式
    final patterns = [
      // youtu.be格式
      r'youtu\.be/([a-zA-Z0-9_-]{11})',
      // 标准watch?v=格式
      r'watch\?v=([a-zA-Z0-9_-]{11})',
      // 嵌入格式
      r'embed/([a-zA-Z0-9_-]{11})',
      // 任何包含v=后跟11个字符的格式
      r'v=([a-zA-Z0-9_-]{11})',
    ];
    
    for (final pattern in patterns) {
      final match = RegExp(pattern).firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }
    
        return null;
      }
  
  // 从URL中提取视频ID (公开方法)
  String? extractVideoId(String url) {
    return _extractVideoId(url);
  }
  
  // 获取视频信息
  Future<Video?> getVideoInfo(String videoId) async {
    try {
      return await _yt.videos.get(videoId);
    } catch (e) {
      debugPrint('获取视频信息错误: $e');
      return null;
    }
  }
  
  // 获取视频的直接流URL
  Future<String?> getVideoStreamUrl(String videoId) async {
    try {
      // 尝试使用多种客户端获取视频的最高质量音视频流，添加更多客户端类型以获取更多选项
      final manifest = await _yt.videos.streams.getManifest(videoId, ytClients: [
        YoutubeApiClient.tv,        // 添加TV客户端，通常可以获得更高质量
        YoutubeApiClient.safari,
        YoutubeApiClient.android,
        YoutubeApiClient.androidVr
      ]);
      
      // 打印可用的视频流信息，帮助调试
      debugPrint('==== 可用混合视频流 ====');
      for (var stream in manifest.muxed) {
        debugPrint('${stream.qualityLabel} - 比特率: ${stream.bitrate} - 容器: ${stream.container.name}');
      }
      
      debugPrint('==== 可用仅视频流 ====');
      for (var stream in manifest.videoOnly) {
        debugPrint('${stream.qualityLabel} - 比特率: ${stream.bitrate} - 容器: ${stream.container.name}');
      }
      
      // 首先尝试获取HLS流，这在某些情况下可以提供更高质量
      if (manifest.hls.isNotEmpty) {
        final hlsStream = manifest.hls.first;
        debugPrint('获取到HLS视频流URL: ${hlsStream.url}');
        return hlsStream.url.toString();
      }
      
      // 获取所需视频质量
      String targetQuality = '720p'; // 目标质量
      if (_configService != null) {
        targetQuality = _configService!.youtubeVideoQuality;
      }
      debugPrint('目标视频质量: $targetQuality');
      
      // 解析目标高度
      int targetHeight = 720; // 默认720p
      if (targetQuality == '1080p') targetHeight = 1080;
      else if (targetQuality == '720p') targetHeight = 720;
      else if (targetQuality == '480p') targetHeight = 480;
      else if (targetQuality == '360p') targetHeight = 360;
      else if (targetQuality == '240p') targetHeight = 240;
      
      // 优先选择混合流，简化代码
      StreamInfo? streamInfo;
      
      // 查找接近目标质量的混合流
      var qualityStreams = manifest.muxed.toList()
        ..sort((a, b) => _parseHeight(b.qualityLabel).compareTo(_parseHeight(a.qualityLabel)));
      
      // 过滤出不超过目标质量的流
      qualityStreams = qualityStreams.where((s) => _parseHeight(s.qualityLabel) <= targetHeight).toList();
      
      if (qualityStreams.isNotEmpty) {
        // 选择最接近目标质量的流
        streamInfo = qualityStreams.first;
        debugPrint('选择混合流: ${streamInfo.qualityLabel} - 比特率: ${streamInfo.bitrate}');
      } else {
        // 如果没有找到合适的混合流，尝试仅视频流（不能直接播放，但会在下载方法中处理）
        var videoStreams = manifest.videoOnly.toList()
          ..sort((a, b) => _parseHeight(b.qualityLabel).compareTo(_parseHeight(a.qualityLabel)));
        
        videoStreams = videoStreams.where((s) => _parseHeight(s.qualityLabel) <= targetHeight).toList();
        
        if (videoStreams.isNotEmpty) {
          streamInfo = videoStreams.first;
          debugPrint('未找到合适的混合流，选择仅视频流: ${streamInfo.qualityLabel} - 比特率: ${streamInfo.bitrate}');
          debugPrint('注意：仅视频流无法直接播放，需要下载后合并音频');
        }
      }
      
      if (streamInfo != null) {
        debugPrint('最终选择的视频流: $streamInfo');
        return streamInfo.url.toString();
      }
      
      debugPrint('未找到合适的视频流');
      return null;
    } catch (e) {
      debugPrint('获取视频流URL错误: $e');
      return null;
    }
  }
  
  // 下载视频到临时文件
  Future<(String, String)?> downloadVideoToTemp(String videoId, String targetQuality, 
      Function(double) onProgress, Function(String) onStatusUpdate) async {
    try {
      // 尝试获取视频信息
      onStatusUpdate('正在解析视频信息...');
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      var info = await _yt.videos.get(videoId);
      
      // 分析可用的视频流
      var videoStreams = manifest.videoOnly;
      var audioStreams = manifest.audioOnly;
      
      // 如果没有分离的视频/音频流，则使用混合流
      if (videoStreams.isEmpty || audioStreams.isEmpty) {
        onStatusUpdate('无法获取分离的视频和音频流，尝试使用混合流');
        var muxedStreams = manifest.muxed.sortByVideoQuality();
        if (muxedStreams.isEmpty) {
          throw Exception('无可用的视频流');
        }
        
        // 选择最佳质量的混合流
        var stream = muxedStreams.first;
        debugPrint('使用混合流: ${stream.qualityLabel}');
        onStatusUpdate('使用混合流下载视频 (${stream.qualityLabel})');
        
        // 创建临时文件
        var tempDir = await getTemporaryDirectory();
        var fileName = '${info.title.replaceAll(RegExp(r'[^\w\s]+'), '_')}_${videoId}_muxed.${stream.container.name}';
        fileName = fileName.replaceAll(RegExp(r'\s+'), '_');
        var filePath = path.join(tempDir.path, fileName);
        
        // 下载视频
        var file = File(filePath);
        var fileStream = file.openWrite();
        
        try {
          onStatusUpdate('开始下载混合流...');
          await _downloadStreamByChunks(stream.url.toString(), filePath, videoId, onProgress, onStatusUpdate);
          await fileStream.flush();
          await fileStream.close();
          
          // 返回文件路径（视频和音频路径相同，因为是混合流）
          return (filePath, filePath);
        } catch (e) {
          await fileStream.close();
          debugPrint('下载混合流失败: $e');
          onStatusUpdate('下载失败: ${e.toString()}');
          return null;
        }
      }
      
      // 解析目标高度
      int targetHeight = _parseHeight(targetQuality);
      
      // 强制使用分离流模式下载视频和音频
      debugPrint('使用分离流模式，目标质量: ${targetHeight}p');
      onStatusUpdate('使用分离流模式下载视频和音频 (${targetQuality})');
      
      // 按清晰度排序视频流并选择最佳的视频流
      var videoStreamsList = videoStreams.toList();
      videoStreamsList.sort((a, b) => _parseHeight(b.qualityLabel).compareTo(_parseHeight(a.qualityLabel)));
      
      // 过滤出不超过目标质量的流
      var filteredStreams = videoStreamsList.where((s) => _parseHeight(s.qualityLabel) <= targetHeight).toList();
      
      // 如果没有找到合适的流，则使用所有流中最低的
      if (filteredStreams.isEmpty) {
        videoStreamsList.sort((a, b) => _parseHeight(a.qualityLabel).compareTo(_parseHeight(b.qualityLabel)));
        filteredStreams = videoStreamsList;
      }
      
      if (filteredStreams.isEmpty) {
        throw Exception('无法找到合适的视频流');
      }
      
      // 选择最佳视频流
      var selectedVideoStream = filteredStreams.first;
      
      // 选择最佳音质的音频流
      var audioStreamsList = audioStreams.toList();
      
      // 首先检查是否有原始音频流（通常是英语）
      // 对音频流进行分类，优先选择原始音频而非配音版本
      var originalAudioStreams = audioStreamsList.where((stream) {
        // YouTube原始音频通常没有特殊标记，但配音版本通常会在标签中包含语言信息
        // 检查是否为配音版本的特征
        final tag = stream.tag.toString().toLowerCase();
        final description = stream.toString().toLowerCase();
        
        // 检查是否包含非原始音频的关键词
        final containsDubKeywords = tag.contains('dubbed') || tag.contains('dub') || 
                                   tag.contains('voice') || tag.contains('translation');
        
        // 检查是否包含特定语言代码（非英语）
        final containsNonEnglishCode = tag.contains('pt-') || tag.contains('es-') || 
                                      tag.contains('fr-') || tag.contains('de-') || 
                                      tag.contains('it-') || tag.contains('ru-');
        
        // 检查是否包含语言名称
        final containsLanguageName = description.contains('portuguese') || 
                                    description.contains('spanish') || 
                                    description.contains('french') || 
                                    description.contains('german') || 
                                    description.contains('italian') || 
                                    description.contains('russian');
        
        // 判断是否为原始音频
        final isOriginal = !containsDubKeywords && !containsNonEnglishCode && !containsLanguageName;
        
        // 输出每个音频流的信息用于调试
        debugPrint('音频流: 比特率=${stream.bitrate.bitsPerSecond/1000}kbps, 编码=${stream.audioCodec}, ' +
                  '标签=${stream.tag}, 判断为${isOriginal ? "原始音频" : "可能是配音"}');
        
        return isOriginal;
      }).toList();
      
      // 声明变量
      var selectedAudioStream;
      
      // 如果找到原始音频流，则从中选择最高质量的
      if (originalAudioStreams.isNotEmpty) {
        originalAudioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        selectedAudioStream = originalAudioStreams.first;
        debugPrint('选择原始音频流: ${selectedAudioStream.bitrate}bps, ${selectedAudioStream.audioCodec}');
      } else {
        // 如果没有找到原始音频流，则使用默认排序方法
        audioStreamsList.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        selectedAudioStream = audioStreamsList.first;
        debugPrint('未找到原始音频流，使用最高比特率的音频: ${selectedAudioStream.bitrate}bps, ${selectedAudioStream.audioCodec}');
      }
      
      debugPrint('已选择视频流: ${selectedVideoStream.qualityLabel}, ${selectedVideoStream.videoResolution}, ${selectedVideoStream.bitrate}bps');
      debugPrint('已选择音频流: ${selectedAudioStream.bitrate}bps, ${selectedAudioStream.audioCodec}');
      
      onStatusUpdate('已选择视频质量: ${selectedVideoStream.qualityLabel}，音频质量: ${(selectedAudioStream.bitrate.bitsPerSecond / 1000).round()}kbps');
      
      // 创建临时文件
      var tempDir = await getTemporaryDirectory();
      var videoFileName = '${info.title.replaceAll(RegExp(r'[^\w\s]+'), '_')}_${videoId}_video.${selectedVideoStream.container.name}';
      var audioFileName = '${info.title.replaceAll(RegExp(r'[^\w\s]+'), '_')}_${videoId}_audio.${selectedAudioStream.container.name}';
      
      // 替换文件名中的空格
      videoFileName = videoFileName.replaceAll(RegExp(r'\s+'), '_');
      audioFileName = audioFileName.replaceAll(RegExp(r'\s+'), '_');
      
      var videoPath = path.join(tempDir.path, videoFileName);
      var audioPath = path.join(tempDir.path, audioFileName);
      
      // 下载视频和音频
      bool videoSuccess = false;
      bool audioSuccess = false;
      
      // 视频下载进度
      double videoProgress = 0.0;
      double audioProgress = 0.0;
      
      void updateTotalProgress() {
        // 视频占70%权重，音频占30%权重
        onProgress(videoProgress * 0.7 + audioProgress * 0.3);
      }
      
      // 下载视频
      try {
        onStatusUpdate('开始下载视频流 (${selectedVideoStream.qualityLabel})...');
        await _downloadStreamByChunks(
          selectedVideoStream.url.toString(), 
          videoPath,
          videoId,
          (progress) {
            videoProgress = progress;
            updateTotalProgress();
          }, 
          (status) => onStatusUpdate('视频: $status')
        );
        videoSuccess = true;
        debugPrint('视频下载完成: $videoPath');
      } catch (e) {
        debugPrint('视频下载失败: $e');
        onStatusUpdate('视频下载失败: ${e.toString()}');
      }
      
      // 下载音频
      try {
        onStatusUpdate('开始下载音频流 (${(selectedAudioStream.bitrate.bitsPerSecond / 1000).round()}kbps)...');
        await _downloadStreamByChunks(
          selectedAudioStream.url.toString(), 
          audioPath,
          videoId,
          (progress) {
            audioProgress = progress;
            updateTotalProgress();
          }, 
          (status) => onStatusUpdate('音频: $status')
        );
        audioSuccess = true;
        debugPrint('音频下载完成: $audioPath');
      } catch (e) {
        debugPrint('音频下载失败: $e');
        onStatusUpdate('音频下载失败: ${e.toString()}');
      }
      
      // 检查下载结果
      if (videoSuccess && audioSuccess) {
        return (videoPath, audioPath);
      } else {
        throw Exception('下载失败: 视频=${videoSuccess}, 音频=${audioSuccess}');
      }
      
    } catch (e) {
      debugPrint('下载视频时发生错误: $e');
      onStatusUpdate?.call('错误: ${e.toString()}');
        return null;
    }
  }
  
  // 下载完整视频，使用分块下载方式
  Future<bool> _downloadStreamByChunks(String streamUrl, String outputPath, String videoId,
      Function(double)? onProgress, Function(String)? onStatusUpdate) async {
    // 检查媒体流信息以获取大小
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 20);
    
    try {
      // 先发送HEAD请求获取总大小
      final request = await httpClient.headUrl(Uri.parse(streamUrl));
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36');
      request.headers.set('Accept', '*/*');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
      request.headers.set('Origin', 'https://www.youtube.com');
      request.headers.set('Referer', 'https://www.youtube.com/watch?v=$videoId');
      
      final response = await request.close();
      await response.drain(); // 丢弃响应体
      
      if (response.statusCode != 200) {
        debugPrint('无法获取视频大小: ${response.statusCode}');
        // 如果失败，回退到常规下载方式
        final file = File(outputPath);
        final fileStream = file.openWrite();
        final result = await _downloadStream(streamUrl, fileStream, videoId, onProgress, onStatusUpdate);
        await fileStream.flush();
        await fileStream.close();
        return result;
      }
      
      // 从头部获取内容长度
      final contentLength = response.contentLength;
      if (contentLength <= 0) {
        debugPrint('无法确定视频大小，使用常规下载');
        // 如果无法获取大小，回退到常规下载方式
        final file = File(outputPath);
        final fileStream = file.openWrite();
        final result = await _downloadStream(streamUrl, fileStream, videoId, onProgress, onStatusUpdate);
        await fileStream.flush();
        await fileStream.close();
        return result;
      }
      
      // 使用分块下载
      const chunkSize = 4 * 1024 * 1024; // 4MB每块
      final totalChunks = (contentLength / chunkSize).ceil();
      debugPrint('视频总大小: ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB, 分为 $totalChunks 块下载');
      onStatusUpdate?.call('准备下载: ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB, 分为 $totalChunks 块');
      
      // 创建文件
      final file = File(outputPath);
      final raf = await file.open(mode: FileMode.write);
      
      // 下载计数器
      int downloadedBytes = 0;
      final startTime = DateTime.now();
      
      // 下载每个块
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = min(start + chunkSize - 1, contentLength - 1);
        
        // 设置重试次数
        int retries = 0;
        const maxRetries = 5;
        bool chunkSuccess = false;
        
        while (!chunkSuccess && retries < maxRetries) {
          try {
            // 创建新的客户端用于每个块
            final chunkClient = HttpClient();
            chunkClient.connectionTimeout = const Duration(seconds: 15);
            chunkClient.idleTimeout = const Duration(seconds: 30);
            
            // 创建请求
            final chunkRequest = await chunkClient.getUrl(Uri.parse(streamUrl));
            chunkRequest.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36');
            chunkRequest.headers.set('Accept', '*/*');
            chunkRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
            chunkRequest.headers.set('Origin', 'https://www.youtube.com');
            chunkRequest.headers.set('Referer', 'https://www.youtube.com/watch?v=$videoId');
            chunkRequest.headers.set('Range', 'bytes=$start-$end');
            
            // 获取响应
            final chunkResponse = await chunkRequest.close();
            
            if (chunkResponse.statusCode != 206 && chunkResponse.statusCode != 200) {
              throw Exception('下载块 ${i+1}/$totalChunks 失败: ${chunkResponse.statusCode}');
            }
            
            // 读取响应数据
            final chunkData = await chunkResponse.fold<List<int>>(
              <int>[],
              (previous, element) => previous..addAll(element),
            );
            
            // 写入文件的特定位置
            await raf.setPosition(start);
            await raf.writeFrom(chunkData);
            
            // 更新进度
            downloadedBytes += chunkData.length;
            final progress = downloadedBytes / contentLength;
            onProgress?.call(progress);
            
            // 计算下载速度和剩余时间
            final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
            if (elapsedSeconds > 0) {
              final speed = downloadedBytes / elapsedSeconds;
              final remainingBytes = contentLength - downloadedBytes;
              String remainingTime = '计算中...';
              
              if (speed > 0) {
                final remainingSeconds = remainingBytes / speed;
                if (remainingSeconds < 60) {
                  remainingTime = '${remainingSeconds.toInt()}秒';
                } else if (remainingSeconds < 3600) {
                  remainingTime = '${(remainingSeconds / 60).toInt()}分${(remainingSeconds % 60).toInt()}秒';
        } else {
                  remainingTime = '${(remainingSeconds / 3600).toInt()}小时${((remainingSeconds % 3600) / 60).toInt()}分';
                }
              }
              
              final percent = (progress * 100).toStringAsFixed(1);
              final downloadedMB = (downloadedBytes / 1024 / 1024).toStringAsFixed(2);
              final totalMB = (contentLength / 1024 / 1024).toStringAsFixed(2);
              final speedMB = (speed / 1024 / 1024).toStringAsFixed(2);
              
              onStatusUpdate?.call('下载中: $percent% ($downloadedMB MB / $totalMB MB) - 块 ${i+1}/$totalChunks - $speedMB MB/s - 剩余: $remainingTime');
            }
            
            // 块下载成功
            chunkSuccess = true;
            chunkClient.close();
            
          } catch (e) {
            retries++;
            debugPrint('下载块 ${i+1}/$totalChunks 失败 (重试 $retries/$maxRetries): $e');
            onStatusUpdate?.call('块 ${i+1}/$totalChunks 下载失败，重试 $retries/$maxRetries...');
            
            if (retries >= maxRetries) {
              // 最后一次尝试失败，回退到常规下载
              debugPrint('块下载失败次数过多，回退到常规下载');
              await raf.close();
              
              // 删除不完整的文件
              await file.delete();
              
              // 使用常规方式下载
      final fileStream = file.openWrite();
              final result = await _downloadStream(streamUrl, fileStream, videoId, onProgress, onStatusUpdate);
              await fileStream.flush();
              await fileStream.close();
              return result;
            }
            
            // 等待一段时间后重试
            await Future.delayed(Duration(seconds: retries * 2));
          }
        }
      }
      
      // 关闭文件
      await raf.close();
      httpClient.close();
      
      return true;
    } catch (e) {
      debugPrint('分块下载初始化失败: $e');
      httpClient.close();
      
      // 回退到常规下载
      final file = File(outputPath);
      if (await file.exists()) {
        await file.delete();
      }
      
      final fileStream = file.openWrite();
      final result = await _downloadStream(streamUrl, fileStream, videoId, onProgress, onStatusUpdate);
      await fileStream.flush();
      await fileStream.close();
      return result;
    }
  }
  
  // 基本的流下载方法（作为备用）
  Future<bool> _downloadStream(String streamUrl, IOSink fileStream, String videoId, 
      Function(double)? onProgress, Function(String)? onStatusUpdate) async {
      // 最大重试次数
      const int maxRetries = 3;
      int retryCount = 0;
      bool downloadSuccess = false;
      Exception? lastException;
    DateTime startTime = DateTime.now();
      
      while (!downloadSuccess && retryCount < maxRetries) {
        try {
          if (retryCount > 0) {
            // 重试间隔增加，避免触发YouTube的限制
            final waitTime = Duration(seconds: 3 + retryCount * 2);
            onStatusUpdate?.call('下载失败，${waitTime.inSeconds}秒后重试 (${retryCount}/$maxRetries)...');
            await Future.delayed(waitTime);
          }
          
          // 创建HTTP客户端
          final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 30);
        httpClient.idleTimeout = const Duration(minutes: 5);
          
          // 显示连接状态
          int waitSeconds = 0;
          Timer? waitTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
            waitSeconds++;
            onStatusUpdate?.call('正在连接视频服务器${'.'.padRight((waitSeconds % 6) + 1, '.')}');
          });
          
          // 创建请求
          final request = await httpClient.getUrl(Uri.parse(streamUrl));
          
          // 添加请求头，模拟浏览器行为，减少被YouTube识别为爬虫的可能
          request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36');
          request.headers.set('Accept', '*/*');
          request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
          request.headers.set('Origin', 'https://www.youtube.com');
          request.headers.set('Referer', 'https://www.youtube.com/watch?v=$videoId');
          request.headers.set('Sec-Fetch-Dest', 'video');
          request.headers.set('Sec-Fetch-Mode', 'cors');
          request.headers.set('Sec-Fetch-Site', 'cross-site');
          request.headers.set('Connection', 'keep-alive');
          
          final response = await request.close();
          
          // 连接成功，停止等待提示
          waitTimer.cancel();
          
        if (response.statusCode != 200 && response.statusCode != 206) {
            throw Exception('服务器返回错误: ${response.statusCode}');
          }
          
          // 获取内容长度（如果有）
          final totalBytes = response.contentLength;
          var receivedBytes = 0;
          
          onStatusUpdate?.call('开始接收数据...');
          
        // 设置状态更新定时器 - 更频繁地更新
        Timer progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
            if (totalBytes > 0) {
              final percent = (receivedBytes / totalBytes * 100).toStringAsFixed(1);
              final downloaded = (receivedBytes / 1024 / 1024).toStringAsFixed(2);
              final total = (totalBytes / 1024 / 1024).toStringAsFixed(2);
            final elapsedTime = DateTime.now().difference(startTime);
            final bytesPerSecond = elapsedTime.inSeconds > 0 ? receivedBytes / elapsedTime.inSeconds : 0;
            final speed = bytesPerSecond > 0 ? '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s' : '计算中...';
            
            // 计算剩余时间
            String remainingTime = '计算中...';
            if (bytesPerSecond > 0 && totalBytes > 0) {
              final remainingBytes = totalBytes - receivedBytes;
              final remainingSeconds = remainingBytes / bytesPerSecond;
              if (remainingSeconds < 60) {
                remainingTime = '${remainingSeconds.toInt()}秒';
              } else if (remainingSeconds < 3600) {
                remainingTime = '${(remainingSeconds / 60).toInt()}分${(remainingSeconds % 60).toInt()}秒';
              } else {
                remainingTime = '${(remainingSeconds / 3600).toInt()}小时${((remainingSeconds % 3600) / 60).toInt()}分';
              }
            }
            
            onStatusUpdate?.call('下载中: $percent% ($downloaded MB / $total MB) - $speed - 剩余: $remainingTime');
            } else if (receivedBytes > 0) {
              // 如果没有总大小信息，只显示已下载的大小
              final downloaded = (receivedBytes / 1024 / 1024).toStringAsFixed(2);
            final elapsedTime = DateTime.now().difference(startTime);
            final bytesPerSecond = elapsedTime.inSeconds > 0 ? receivedBytes / elapsedTime.inSeconds : 0;
            final speed = '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
              onStatusUpdate?.call('下载中: $downloaded MB - $speed');
            }
          
          // 更新进度
          if (totalBytes > 0) {
            onProgress?.call(receivedBytes / totalBytes);
            }
          });
        
        // 使用缓冲区减少IO操作
        const bufferSize = 1024 * 1024; // 1MB缓冲区
        List<int> buffer = [];
          
          // 下载数据
        await for (final data in response) {
          buffer.addAll(data);
            receivedBytes += data.length;
          
          // 当缓冲区达到一定大小时才写入文件
          if (buffer.length >= bufferSize) {
            fileStream.add(buffer);
            buffer = [];
          }
        }
        
        // 写入剩余的缓冲区数据
        if (buffer.isNotEmpty) {
          fileStream.add(buffer);
        }
          
          // 取消状态更新定时器
        progressUpdateTimer.cancel();
          
          // 关闭HTTP客户端
          httpClient.close();
          
          // 下载成功
          downloadSuccess = true;
          break;
          
        } catch (e) {
          debugPrint('下载尝试 ${retryCount + 1} 失败: $e');
          lastException = e is Exception ? e : Exception(e.toString());
          retryCount++;
          
          // 如果是最后一次重试，则不需要清理，因为后面会处理
          if (retryCount < maxRetries) {
            onStatusUpdate?.call('下载中断，准备重试...');
          }
        }
      }
      
      // 如果所有重试都失败
      if (!downloadSuccess) {
        debugPrint('所有下载尝试都失败');
        onStatusUpdate?.call('下载失败，所有重试均未成功');
        
      throw lastException ?? Exception('下载失败，原因未知');
    }
    
    return true;
  }
  
  // 合并视频和音频文件
  Future<bool> _mergeVideoAudio(String videoFile, String audioFile, String outputFile, Function(String)? onStatusUpdate) async {
    try {
      onStatusUpdate?.call('开始合并视频和音频');
      
      // 详细日志
      debugPrint('\n===== 视频合并开始 =====');
      debugPrint('视频文件: $videoFile');
      debugPrint('音频文件: $audioFile');
      debugPrint('输出文件: $outputFile');
      
      // 检查源文件
      final videoExists = await File(videoFile).exists();
      final audioExists = await File(audioFile).exists();
      debugPrint('视频文件存在: $videoExists (${videoExists ? (await File(videoFile).length() / 1024 / 1024).toStringAsFixed(2) + "MB" : "N/A"})');
      debugPrint('音频文件存在: $audioExists (${audioExists ? (await File(audioFile).length() / 1024 / 1024).toStringAsFixed(2) + "MB" : "N/A"})');
      
      if (!videoExists) {
        debugPrint('错误: 视频文件不存在!');
        return false;
      }
      
      // 确保输出目录存在
      final outputDir = path.dirname(outputFile);
      if (!Directory(outputDir).existsSync()) {
        debugPrint('创建输出目录: $outputDir');
        await Directory(outputDir).create(recursive: true);
      }
      
      debugPrint('输出目录: $outputDir');
      debugPrint('输出目录存在: ${Directory(outputDir).existsSync()}');
      
      // 尝试使用系统FFmpeg
      try {
        // 如果仅有视频没有音频，直接复制
        if (!audioExists) {
          debugPrint('无音频文件，直接复制视频文件');
          await File(videoFile).copy(outputFile);
          
          // 检查输出文件
          final outputExists = await File(outputFile).exists();
          final outputSize = outputExists ? await File(outputFile).length() : 0;
          debugPrint('复制后文件存在: $outputExists (大小: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB)');
          
          onStatusUpdate?.call('使用视频文件作为最终输出');
          return outputExists;
        }
        
        // 检查是否能运行FFmpeg命令
        final ffmpegCheckResult = await Process.run('ffmpeg', ['-version']);
        if (ffmpegCheckResult.exitCode == 0) {
          onStatusUpdate?.call('使用FFmpeg合并视频和音频');
          debugPrint('FFmpeg可用，使用FFmpeg合并');
          
          // 构建FFmpeg命令
          final ffmpegArgs = [
            '-i', videoFile,  // 视频输入
            '-i', audioFile,  // 音频输入
            '-c:v', 'copy',   // 直接复制视频流，不重新编码
            '-c:a', 'aac',    // 将音频编码为AAC
            '-strict', 'experimental',
            '-map', '0:v:0',  // 使用第一个输入的视频流
            '-map', '1:a:0',  // 使用第二个输入的音频流
            '-shortest',      // 取最短的输入长度
            '-y',             // 覆盖输出文件
            outputFile        // 输出文件
          ];
          
          debugPrint('FFmpeg命令: ffmpeg ${ffmpegArgs.join(' ')}');
          onStatusUpdate?.call('正在处理视频和音频...');
          
          // 执行FFmpeg命令
          final ffmpegProcess = await Process.start('ffmpeg', ffmpegArgs);
          
          // 显示进度
          ffmpegProcess.stderr.transform(utf8.decoder).listen((data) {
            debugPrint('FFmpeg: $data');
            // 可以从输出中尝试解析进度
            if (data.contains('time=')) {
              onStatusUpdate?.call('处理中...');
            }
          });
          
          final exitCode = await ffmpegProcess.exitCode;
          
          // 检查处理结果
          if (exitCode == 0) {
            onStatusUpdate?.call('视频和音频合并成功');
            
            // 检查输出文件
            final outputExists = await File(outputFile).exists();
            final outputSize = outputExists ? await File(outputFile).length() : 0;
            debugPrint('输出文件存在: $outputExists (大小: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB)');
            
            // 确保文件在正确的位置
            if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
              // 检查文件是否在用户指定的目录
              final userDir = _configService!.youtubeDownloadPath.toLowerCase();
              final outFile = outputFile.toLowerCase();
              if (!outFile.contains(userDir)) {
                debugPrint('===== 文件不在用户指定目录，需要复制 =====');
                final fileName = path.basename(outputFile);
                final targetPath = path.join(_configService!.youtubeDownloadPath, fileName);
                
                // 确保目标目录存在
                final targetDir = path.dirname(targetPath);
                if (!Directory(targetDir).existsSync()) {
                  await Directory(targetDir).create(recursive: true);
                }
                
                // 复制文件到目标位置
                debugPrint('复制文件从: $outputFile');
                debugPrint('复制文件到: $targetPath');
                
                final targetFile = File(targetPath);
                if (await targetFile.exists()) {
                  await targetFile.delete();
                }
                
                await File(outputFile).copy(targetPath);
                
                // 验证目标文件
                final targetExists = await File(targetPath).exists();
                final targetSize = targetExists ? await File(targetPath).length() : 0;
                debugPrint('目标文件存在: $targetExists (大小: ${(targetSize / 1024 / 1024).toStringAsFixed(2)} MB)');
                
                // 如果成功复制，使用新路径
                if (targetExists && targetSize > 1024) {
                  debugPrint('===== 成功将文件移到用户指定目录 =====');
                  return true;
                }
              }
            }
            
            if (outputExists && outputSize > 1024) {
              debugPrint('===== 视频合并成功 =====\n');
              return true;
            } else {
              debugPrint('警告: 输出文件过小或不存在');
            }
          } else {
            debugPrint('FFmpeg处理失败，退出代码: $exitCode，尝试备用方法');
            onStatusUpdate?.call('视频处理失败，尝试备用方法');
          }
        } else {
          debugPrint('FFmpeg不可用，使用备用方法');
        }
        
        // 如果FFmpeg不可用或失败，尝试直接复制视频文件
        debugPrint('FFmpeg处理失败，尝试直接复制视频文件');
        await File(videoFile).copy(outputFile);
        
        // 再次检查输出文件
        final outputExists = await File(outputFile).exists();
        final outputSize = outputExists ? await File(outputFile).length() : 0;
        debugPrint('备用方法后文件存在: $outputExists (大小: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB)');
        
        onStatusUpdate?.call('使用备用方法完成');
        debugPrint('===== 视频处理完成(备用方法) =====\n');
        return outputExists;
        
      } catch (e) {
        debugPrint('FFmpeg执行出错，尝试直接复制: $e');
        
        // 尝试直接复制
        try {
          await File(videoFile).copy(outputFile);
          final exists = await File(outputFile).exists();
          debugPrint('复制后文件存在: $exists');
          return exists;
        } catch (copyError) {
          debugPrint('复制也失败了: $copyError');
          return false;
        }
      }
    } catch (e) {
      debugPrint('合并视频和音频失败: $e');
      onStatusUpdate?.call('合并失败: $e');
      
      try {
        // 出现异常时的备用方法：直接复制视频文件
        await File(videoFile).copy(outputFile);
        final exists = await File(outputFile).exists();
        debugPrint('异常后复制，文件存在: $exists');
        onStatusUpdate?.call('出错后使用备用方法完成');
        return exists;
      } catch (copyError) {
        debugPrint('备用方法也失败: $copyError');
        return false;
      }
    }
  }
  
  // 格式化时间戳为SRT格式
  String _formatTimestamp(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds = (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    
    return '$hours:$minutes:$seconds,$milliseconds';
  }
  
  // 下载字幕
  Future<String?> downloadSubtitles(String videoId, {String? languageCode, Function(String)? onStatusUpdate}) async {
    try {
      // 获取视频信息以获取标题
      final video = await _yt.videos.get(videoId);
      final videoTitle = video.title;
      
      // 准备字幕文件路径
      String subtitleFilename = '';
      String subtitleFilePath = '';
      
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        // 首先尝试查找与视频文件同名的字幕文件
        final directory = Directory(_configService!.youtubeDownloadPath);
        if (await directory.exists()) {
          List<FileSystemEntity> files = await directory.list().toList();
          
          // 查找与视频同名的字幕文件
          for (var file in files) {
            if (file is File) {
              String fileName = path.basename(file.path);
              
              // 查找以videoId_开头且以.mp4/.webm/.mkv结尾的视频文件
              if (fileName.startsWith('${videoId}_') && 
                  (fileName.endsWith('.mp4') || fileName.endsWith('.webm') || fileName.endsWith('.mkv'))) {
                // 构建对应的字幕文件名
                String expectedSubtitleName = '${fileName.substring(0, fileName.lastIndexOf('.'))}.srt';
                String expectedSubtitlePath = path.join(directory.path, expectedSubtitleName);
                
                // 检查字幕文件是否存在
                if (await File(expectedSubtitlePath).exists()) {
                  debugPrint('找到与视频对应的字幕文件: $expectedSubtitlePath');
                  onStatusUpdate?.call('使用已下载的字幕');
                  return expectedSubtitlePath;
                }
              }
            }
          }
        }
        
        // 如果没有找到同名字幕，创建与视频相同命名格式的字幕文件名
        String safeTitle = videoTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_');
        subtitleFilename = '${videoId}_${safeTitle}.srt';
        subtitleFilePath = path.join(_configService!.youtubeDownloadPath, subtitleFilename);
        
        // 检查是否已经存在同名字幕文件
        if (await File(subtitleFilePath).exists()) {
          debugPrint('字幕文件已存在，直接使用: $subtitleFilePath');
          onStatusUpdate?.call('使用已下载的字幕');
          return subtitleFilePath;
        }
      } else {
        // 使用临时目录，仍然保持命名一致性
        final tempDir = await getTemporaryDirectory();
        subtitleFilename = '${videoId}_subtitle.srt';
        subtitleFilePath = path.join(tempDir.path, subtitleFilename);
      }
      
      onStatusUpdate?.call('尝试下载字幕...');
      debugPrint('===== 开始尝试下载字幕 =====');
      
      // 使用重构后的 YouTubeSubtitleDownloader 下载字幕
      final downloader = YouTubeSubtitleDownloader(
        videoId: videoId,
        languageCode: languageCode ?? 'zh-CN', // 使用传入的语言代码，如果没有则默认使用中文
        maxRetries: 3,
        retryDelay: const Duration(seconds: 1),
      );
      
      try {
        final subtitles = await downloader.downloadSubtitles();
        if (subtitles.isNotEmpty) {
          debugPrint('成功下载字幕，内容长度: ${subtitles.length}');
          
          // 保存字幕到文件
          final file = await downloader.saveSubtitlesToFile(subtitles, subtitleFilePath);
          debugPrint('字幕已保存到: ${file.path}');
          onStatusUpdate?.call('字幕下载成功');
          return file.path;
        } else {
          debugPrint('下载的字幕内容为空');
          onStatusUpdate?.call('字幕内容为空');
          return null;
        }
      } catch (e) {
        debugPrint('使用 YouTubeSubtitleDownloader 下载字幕失败: $e');
        onStatusUpdate?.call('字幕下载失败');
        return null;
      }
    } catch (e, stack) {
      debugPrint('下载字幕主方法异常: $e');
      debugPrint('堆栈: $stack');
      onStatusUpdate?.call('下载字幕错误');
      return null;
    }
  }
  
  // 清理YouTube字幕内容中的特殊标签和格式问题
  String _cleanYouTubeSpecificContent(String content) {
    try {
      debugPrint('清理YouTube字幕内容中的特殊标签');
      
      // 检查内容是否为空
      if (content.isEmpty) {
        return content;
      }
      
      // 清理常见的HTML/XML标签
      var cleaned = content
          .replaceAll(RegExp(r'</?[^>]+(>|$)'), '') // 移除所有HTML/XML标签
          .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ') // 替换HTML实体如&nbsp;
          .replaceAll(RegExp(r'&#\d+;'), ' '); // 替换数字HTML实体如&#39;
      
      // 移除多余的空白字符
      cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      
      // 检查是否有非法的XML字符
      cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
      
      // 修复SRT格式中可能的问题
      final lines = cleaned.split('\n');
      final result = StringBuffer();
      
      int index = 1;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // 跳过空行
        if (line.isEmpty) {
          continue;
        }
        
        // 如果是数字行，可能是索引
        if (RegExp(r'^\d+$').hasMatch(line)) {
          result.writeln(index);
          index++;
        }
        // 如果是时间行
        else if (line.contains('-->')) {
          result.writeln(line);
        }
        // 否则是文本行
        else {
          result.writeln(line);
        }
      }
      
      return result.toString().trim();
    } catch (e) {
      debugPrint('清理字幕内容出错: $e');
      return content; // 出错时返回原始内容
    }
  }
  
  // 清理字幕文本
  String _cleanSubtitleText(String text) {
    return text.replaceAll('&amp;', '&')
               .replaceAll('&lt;', '<')
               .replaceAll('&gt;', '>')
               .replaceAll('&quot;', '"')
               .replaceAll('&#39;', "'")
               .replaceAll('&nbsp;', ' ')
               .replaceAll('<br />', '\n')
               .replaceAll('<br/>', '\n')
               .replaceAll('<br>', '\n')
               .replaceAll(RegExp(r'<\d+:\d+:\d+\.\d+>'), '') // 移除时间戳标签，如<00:00:31.359>
               .replaceAll(RegExp(r'</?c>'), '') // 移除<c>和</c>标签
               .replaceAll(RegExp(r'<[^>]*>'), ''); // 移除其他HTML标签
  }
  
  // 从分辨率字符串中提取高度值
  int _parseHeight(String resolution) {
    // 尝试从分辨率字符串中提取数字部分 (例如 "720p" -> 720)
    final match = RegExp(r'(\d+)').firstMatch(resolution);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }
  
  // 下载视频和字幕
  Future<(String, String?)?> downloadVideoAndSubtitles(
    String videoUrl, {
    Function(double)? onProgress,
    Function(String)? onStatusUpdate,
    String? preferredQuality,
    DownloadInfoService? downloadInfoService,
  }) async {
    try {
      // 提供更详细的初始状态
      onStatusUpdate?.call('正在初始化YouTube下载...');
      // 支持多种URL格式
      final videoId = _extractVideoId(videoUrl);
      if (videoId == null) {
        onStatusUpdate?.call('无效的YouTube URL');
        return null;
      }
      
      // 首先检查用户指定目录中是否已有该视频
      final (existingVideo, existingSubtitle) = await _getFromDownloadCache(videoId);
      if (existingVideo != null) {
        onStatusUpdate?.call('使用已下载的视频文件');
        debugPrint('使用已下载的视频: $existingVideo');
        debugPrint('字幕路径: $existingSubtitle');
        
        // 获取可用字幕轨道并显示在面板中
        if (downloadInfoService != null) {
          onStatusUpdate?.call('获取可用字幕轨道...');
          final subtitleTracks = await getAllSubtitleTracks(videoId);
          if (subtitleTracks.isNotEmpty) {
            downloadInfoService.setAvailableSubtitleTracks(subtitleTracks, videoId);
            onStatusUpdate?.call('找到${subtitleTracks.length}个可用字幕轨道');
          }
        }
        
        return (existingVideo, existingSubtitle);
      }
      
      // 获取视频信息
      onStatusUpdate?.call('获取视频信息...');
      
      // 检查配置服务和下载路径
      debugPrint('\n===== 检查配置服务和下载路径 =====');
      debugPrint('配置服务为空: ${_configService == null}');
      debugPrint('下载路径为空: ${_configService?.youtubeDownloadPath.isEmpty}');
      debugPrint('下载路径值: "${_configService?.youtubeDownloadPath}"');
      
      // 获取视频信息
      final video = await _yt.videos.get(videoId);
      final title = video.title;
      final author = video.author;
      
      // 获取视频和字幕
      final videoFile = await _downloadVideo(
        videoId,
        title,
        onStatusUpdate: onStatusUpdate,
        onProgress: onProgress,
        preferredQuality: preferredQuality,
      );
      
      if (videoFile == null) {
        onStatusUpdate?.call('下载视频失败');
        return null;
      }
      
      // 获取可用字幕轨道并显示在面板中
      String? subtitleFile;
      if (downloadInfoService != null) {
        onStatusUpdate?.call('获取可用字幕轨道...');
        final subtitleTracks = await getAllSubtitleTracks(videoId);
        if (subtitleTracks.isNotEmpty) {
          downloadInfoService.setAvailableSubtitleTracks(subtitleTracks, videoId);
          onStatusUpdate?.call('找到${subtitleTracks.length}个可用字幕轨道');
        } else {
          // 如果没有找到字幕轨道，尝试下载默认字幕
          try {
            // 使用默认语言 'zh-CN'（中文）或系统语言
            subtitleFile = await downloadSubtitles(
              videoId, 
              languageCode: 'zh-CN',  // 默认使用中文
              onStatusUpdate: onStatusUpdate
            );
          } catch (e) {
            debugPrint('下载字幕错误: $e');
            subtitleFile = null;
          }
        }
      } else {
        // 下载字幕
        try {
          // 使用默认语言 'zh-CN'（中文）或系统语言
          subtitleFile = await downloadSubtitles(
            videoId, 
            languageCode: 'zh-CN',  // 默认使用中文
            onStatusUpdate: onStatusUpdate
          );
        } catch (e) {
          debugPrint('下载字幕错误: $e');
          subtitleFile = null;
        }
      }
      
      // 添加到缓存
      final fileName = path.basename(videoFile);
      final subtitleFileName = subtitleFile != null ? path.basename(subtitleFile) : null;
      await _addToDownloadCache(videoId, fileName, subtitleFileName);
      
      // 通知下载完成
      if (downloadInfoService != null) {
        downloadInfoService.endDownload();
      }
      
      return (videoFile, subtitleFile);
    } catch (e) {
      debugPrint('下载YouTube视频时发生错误: $e');
      onStatusUpdate?.call('下载失败: $e');
      return null;
    }
  }
  
  // 保存内存中的字幕数据到文件
  Future<bool> saveSubtitleToFile(SubtitleData subtitleData, String outputPath) async {
    try {
      // 转换为SRT格式
      final srtContent = StringBuffer();
      
      for (var i = 0; i < subtitleData.entries.length; i++) {
        final entry = subtitleData.entries[i];
        
        // 索引编号
        srtContent.writeln(i + 1);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final start = _formatTimestamp(entry.start);
        final end = _formatTimestamp(entry.end);
        srtContent.writeln('$start --> $end');
        
        // 字幕文本 - 确保清理所有特殊标签
        String cleanedText = _cleanSubtitleText(entry.text);
        // 额外清理YouTube特殊格式
        cleanedText = _cleanYouTubeSpecificTags(cleanedText);
        srtContent.writeln(cleanedText);
        
        // 空行分隔
        srtContent.writeln();
      }
      
      // 确保目录存在
      final directory = path.dirname(outputPath);
      if (!Directory(directory).existsSync()) {
        await Directory(directory).create(recursive: true);
      }
      
      // 保存字幕文件
      await File(outputPath).writeAsString(srtContent.toString());
      debugPrint('字幕已保存: $outputPath');
      
      return true;
    } catch (e) {
      debugPrint('保存字幕错误: $e');
      return false;
    }
  }
  
  // 清理YouTube特有的字幕标签格式
  String _cleanYouTubeSpecificTags(String text) {
    // 移除时间戳标签，如<00:00:31.359>
    text = text.replaceAll(RegExp(r'<\d+:\d+:\d+\.\d+>'), '');
    // 移除<c>和</c>标签
    text = text.replaceAll(RegExp(r'</?c>'), '');
    // 移除其他可能的格式标签
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    return text;
  }
  
  // 清除下载缓存（仅用于测试）
  void clearDownloadCache() {
    _downloadCache.clear();
    debugPrint('===== 已清除下载缓存 =====');
    _saveCache(); // 保存空缓存
  }
  
  void dispose() {
    _yt.close();
  }
  
  // 下载视频
  Future<String?> _downloadVideo(
    String videoId, 
    String title, {
    Function(String)? onStatusUpdate,
    Function(double)? onProgress,
    String? preferredQuality,
  }) async {
    try {
      // 获取下载质量设置
      String targetQuality = preferredQuality ?? '720p'; // 默认使用720p
      if (_configService != null && preferredQuality == null) {
        targetQuality = _configService!.youtubeVideoQuality;
      }
      
      // 更新进度回调，确保非空
      final progressCallback = onProgress ?? (_) {};
      final statusCallback = onStatusUpdate ?? (_) {};
      
      // 下载视频和音频流
      statusCallback('准备下载视频: $title');
      statusCallback('目标质量: $targetQuality');
      final streamResult = await downloadVideoToTemp(videoId, targetQuality, 
          progressCallback, statusCallback);
      
      if (streamResult == null) {
        debugPrint('下载视频流失败');
        return null;
      }
      
      // 解包视频和音频路径
      final (videoPath, audioPath) = streamResult;
      
      // 确定最终输出路径
      String outputFilePath;
      
      // 检查是否有自定义下载路径
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        // 使用视频ID作为文件名前缀，添加标题以便识别
        String safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_');
        // 格式: videoId_标题.mp4
        String fileName = '${videoId}_${safeTitle}.mp4';
        outputFilePath = path.join(_configService!.youtubeDownloadPath, fileName);
        
        // 确保目录存在
        final directory = path.dirname(outputFilePath);
        if (!Directory(directory).existsSync()) {
          await Directory(directory).create(recursive: true);
        }
        
        // 打印详细日志
        debugPrint('===== 视频将保存到用户指定目录 =====');
        debugPrint('配置的下载路径: ${_configService!.youtubeDownloadPath}');
        debugPrint('文件名: $fileName');
        debugPrint('完整输出路径: $outputFilePath');
        debugPrint('目录是否存在: ${Directory(directory).existsSync()}');
        try {
          // 测试目录写入权限
          final testFile = File(path.join(directory, 'test_write.tmp'));
          await testFile.writeAsString('test');
          debugPrint('目录可写: ${testFile.path}');
          await testFile.delete();
        } catch (e) {
          debugPrint('目录写入测试失败: $e');
        }
      } else {
        // 使用临时目录
        final tempDir = await getTemporaryDirectory();
        // 使用视频ID作为文件名前缀
        String safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_');
        outputFilePath = path.join(tempDir.path, '${videoId}_${safeTitle}.mp4');
        debugPrint('===== 将保存到临时目录 =====');
        debugPrint('临时目录: ${tempDir.path}');
        debugPrint('完整输出路径: $outputFilePath');
      }
      
      // 合并视频和音频文件
      statusCallback('正在合并视频和音频...');
      final mergeSuccess = await _mergeVideoAudio(videoPath, audioPath, outputFilePath,
        (status) => statusCallback('合并: $status')
      );
      
      // 清理临时文件
      try {
        if (videoPath != outputFilePath) {
          File(videoPath).deleteSync();
        }
        if (audioPath != outputFilePath && audioPath != videoPath) {
          File(audioPath).deleteSync();
        }
      } catch (e) {
        debugPrint('清理临时文件失败: $e');
      }
      
      if (mergeSuccess) {
        // 检查文件是否实际存在于用户指定的目录
        String finalOutputPath = outputFilePath;
        
        if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
          // 构造用户指定目录中的预期路径
          final fileName = path.basename(outputFilePath);
          final expectedPath = path.join(_configService!.youtubeDownloadPath, fileName);
          
          // 检查此路径是否存在
          final expectedFile = File(expectedPath);
          if (await expectedFile.exists() && await expectedFile.length() > 0) {
            debugPrint('===== 检测到文件已在用户指定目录中 =====');
            finalOutputPath = expectedPath;
          }
        }
        
        // 检查文件是否确实保存在指定位置
        final outputFile = File(finalOutputPath);
        final exists = await outputFile.exists();
        final fileSize = exists ? await outputFile.length() : 0;
        
        debugPrint('===== 视频处理完成状态 =====');
        debugPrint('合并成功: $mergeSuccess');
        debugPrint('最终输出文件路径: $finalOutputPath');
        debugPrint('文件存在: $exists');
        debugPrint('文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        
        if (exists && fileSize > 0) {
          debugPrint('视频成功保存到: $finalOutputPath');
          statusCallback('下载完成: $title');
          return finalOutputPath;
        } else {
          debugPrint('警告: 视频文件可能未正确保存!');
        }
      } else {
        statusCallback('视频合并失败，尝试使用单流视频');
        
        // 如果合并失败，尝试直接使用视频流（如果是webm或mp4格式）
        if (path.extension(videoPath) == '.mp4' || path.extension(videoPath) == '.webm') {
          final tempOutputPath = path.join(path.dirname(outputFilePath), 
              '${path.basenameWithoutExtension(outputFilePath)}_单流${path.extension(videoPath)}');
          
          // 复制视频文件
          await File(videoPath).copy(tempOutputPath);
          
          final fileSize = await File(tempOutputPath).length();
          debugPrint('使用单流视频: $tempOutputPath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
          statusCallback('使用单流视频完成下载 (无音频)');
          
          return tempOutputPath;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('下载视频错误: $e');
      onStatusUpdate?.call('下载失败: $e');
      return null;
    }
  }
  
  // 将秒数转换为SRT时间戳格式 (HH:MM:SS,mmm)
  String _secondsToTimestamp(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    final millis = ((seconds - seconds.floor()) * 1000).floor();
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')},${millis.toString().padLeft(3, '0')}';
  }
  
  // 将毫秒转换为SRT格式时间戳
  String _millisecondsToTimestamp(int milliseconds) {
    final seconds = milliseconds / 1000;
    return _secondsToTimestamp(seconds);
  }
  
  // 尝试解析WebVTT格式，即使格式不完全标准
  String? _parseWebVTTContent(String content) {
    try {
      debugPrint('尝试作为WebVTT格式直接解析');
      
      // 检查内容是否看起来像WebVTT
      if (!content.contains('-->')) {
        debugPrint('内容不包含时间标记，不像是WebVTT格式');
        return null;
      }
      
      final lines = content.split('\n');
      final srtContent = StringBuffer();
      int subtitleIndex = 1;
      
      // WebVTT可能没有标准的WEBVTT头部，直接尝试解析时间行
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // 寻找时间行 (包含 --> 的行)
        if (line.contains('-->')) {
          // 输出当前行用于调试
          debugPrint('找到时间行: $line');
          
          final timeParts = line.split('-->');
          if (timeParts.length == 2) {
            // 处理开始时间
            String startTime = timeParts[0].trim();
            // 如果时间格式包含小时，但没有小时部分，添加小时
            if (!startTime.contains(':')) {
              startTime = '00:$startTime';
            } else if (startTime.split(':').length == 2) {
              startTime = '00:$startTime';
            }
            // 处理毫秒分隔符
            if (startTime.contains('.')) {
              startTime = startTime.replaceAll('.', ',');
            }
            
            // 处理结束时间
            String endTime = timeParts[1].trim();
            // 处理同样的格式问题
            if (!endTime.contains(':')) {
              endTime = '00:$endTime';
            } else if (endTime.split(':').length == 2) {
              endTime = '00:$endTime';
            }
            if (endTime.contains('.')) {
              endTime = endTime.replaceAll('.', ',');
            }
            
            // 移除VTT特有的样式信息
            if (endTime.contains(' ')) {
              endTime = endTime.substring(0, endTime.indexOf(' '));
            }
            
            // 写入SRT序号
            srtContent.writeln(subtitleIndex++);
            
            // 写入SRT格式的时间行
            srtContent.writeln('$startTime --> $endTime');
            
            // 收集后续的文本行，直到遇到空行
            final textBuffer = StringBuffer();
            i++;
            while (i < lines.length && lines[i].trim().isNotEmpty) {
              if (textBuffer.isNotEmpty) {
                textBuffer.write('\n');
              }
              textBuffer.write(lines[i].trim());
              i++;
            }
            
            // 写入文本内容
            final text = textBuffer.toString().trim();
            if (text.isNotEmpty) {
              srtContent.writeln(text);
              srtContent.writeln(); // 空行分隔
            } else {
              // 回退计数器，因为没有有效文本
              subtitleIndex--;
            }
          }
        }
      }
      
      final result = srtContent.toString().trim();
      if (result.isEmpty || subtitleIndex <= 1) {
        debugPrint('未能提取出任何字幕内容');
        return null;
      }
      
      debugPrint('成功从类WebVTT格式提取${subtitleIndex - 1}条字幕');
      return result;
    } catch (e) {
      debugPrint('解析WebVTT内容出错: $e');
      return null;
    }
  }
  
  // 直接通过HTTP请求获取WebVTT格式字幕
  Future<String?> _getSubtitlesDirectly(String videoId, {String? preferredLanguage}) async {
    try {
      debugPrint('尝试直接通过HTTP请求获取WebVTT字幕，首选语言: ${preferredLanguage ?? "默认"}');
      
      // 获取视频页面
      final response = await http.get(
        Uri.parse('https://www.youtube.com/watch?v=$videoId'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-us,en;q=0.5',
          'Sec-Fetch-Mode': 'navigate',
          'Cookie': 'CONSENT=YES+cb', // 添加基本的Cookie以避免某些限制
        }
      );
      
      if (response.statusCode != 200) {
        debugPrint('获取视频页面失败: ${response.statusCode}');
        return null;
      }
      
      // 从HTML中提取player_response
      final playerResponseRegex = RegExp(r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\});\s*var');
      final match = playerResponseRegex.firstMatch(response.body);
      
      if (match == null || match.groupCount < 1) {
        debugPrint('未找到player_response数据');
        
        // 尝试使用备用正则表达式
        final altRegex = RegExp(r'"captions":\s*(\{.+?\}\})');
        final altMatch = altRegex.firstMatch(response.body);
        if (altMatch == null || altMatch.groupCount < 1) {
          debugPrint('备用正则表达式也未找到字幕数据');
          return null;
        }
        
        String? captionsJson = '{${altMatch.group(1)}}';
        try {
          Map<String, dynamic> captionsData = jsonDecode(captionsJson);
          return _processCaptionsData(captionsData, preferredLanguage);
        } catch (e) {
          debugPrint('解析备用字幕数据失败: $e');
          return null;
        }
      }
      
      String? playerResponseJson = match.group(1);
      if (playerResponseJson == null) {
        debugPrint('player_response数据为空');
        return null;
      }
      
      // 解析JSON
      Map<String, dynamic> playerResponse;
      try {
        playerResponse = jsonDecode(playerResponseJson);
      } catch (e) {
        debugPrint('解析player_response失败: $e');
        
        // 尝试修复JSON
        playerResponseJson = playerResponseJson
            .replaceAll("'", '"')
            .replaceAll(RegExp(r',\s*\}'), '}')
            .replaceAll(RegExp(r',\s*\]'), ']');
        
        try {
          playerResponse = jsonDecode(playerResponseJson);
        } catch (e) {
          debugPrint('修复后仍然无法解析JSON: $e');
          return null;
        }
      }
      
      return _processCaptionsData(playerResponse, preferredLanguage);
    } catch (e) {
      debugPrint('直接获取字幕失败: $e');
      return null;
    }
  }
  
  // 处理从页面提取的字幕数据
  Future<String?> _processCaptionsData(Map<String, dynamic> data, String? preferredLanguage) async {
    try {
      // 提取字幕URL
      final captions = data['captions'];
      if (captions == null) {
        debugPrint('未找到字幕数据');
        return null;
      }
      
      final captionTracks = captions['playerCaptionsTracklistRenderer']?['captionTracks'];
      if (captionTracks == null || captionTracks is! List || captionTracks.isEmpty) {
        debugPrint('未找到字幕轨道');
        return null;
      }
      
      // 打印所有可用字幕轨道
      debugPrint('找到${captionTracks.length}条字幕轨道:');
      for (final track in captionTracks) {
        final lang = track['languageCode'];
        final name = track['name']?['simpleText'] ?? track['name']?['runs']?[0]?['text'];
        final isAuto = track['kind'] == 'asr';
        debugPrint('- $name ($lang): ${isAuto ? "自动生成" : "人工添加"}');
      }
      
      // 选择字幕轨道
      Map<String, dynamic>? selectedTrack;
      
      // 如果指定了首选语言，优先选择该语言的字幕
      if (preferredLanguage != null) {
        for (final track in captionTracks) {
          final lang = (track['languageCode'] as String).toLowerCase();
          if (lang == preferredLanguage.toLowerCase()) {
            selectedTrack = track;
            debugPrint('找到首选语言字幕: $preferredLanguage');
            break;
          }
        }
      }
      
      // 如果没有找到首选语言字幕，按优先级选择
      if (selectedTrack == null) {
        // 首先寻找非自动生成的英文字幕
        for (final track in captionTracks) {
          final lang = (track['languageCode'] as String).toLowerCase();
          final isAuto = track['kind'] == 'asr';
          
          if (!isAuto && lang == 'en') {
            selectedTrack = track;
            debugPrint('找到非自动生成的英文字幕');
            break;
          }
        }
        
        // 如果没有找到非自动生成的英文字幕，找自动生成的英文字幕
        if (selectedTrack == null) {
          for (final track in captionTracks) {
            final lang = (track['languageCode'] as String).toLowerCase();
            
            if (lang == 'en') {
              selectedTrack = track;
              debugPrint('找到自动生成的英文字幕');
              break;
            }
          }
        }
        
        // 如果没有找到英文字幕，找中文字幕
        if (selectedTrack == null) {
          for (final track in captionTracks) {
            final lang = (track['languageCode'] as String).toLowerCase();
            
            if (lang == 'zh' || lang == 'zh-cn' || lang == 'zh-tw') {
              selectedTrack = track;
              debugPrint('找到中文字幕');
              break;
            }
          }
        }
        
        // 如果还是没找到，用第一个可用的
        if (selectedTrack == null && captionTracks.isNotEmpty) {
          selectedTrack = captionTracks[0];
          final lang = selectedTrack?['languageCode'] ?? 'unknown';
          debugPrint('使用第一个可用字幕: $lang');
        }
      }
      
      if (selectedTrack == null) {
        debugPrint('无法选择任何字幕轨道');
        return null;
      }
      
      // 获取字幕URL
      String baseUrl = selectedTrack!['baseUrl'];
      debugPrint('字幕基础URL: $baseUrl');
      
      // 添加格式参数，获取WebVTT格式
      final vttUrl = '$baseUrl&fmt=vtt';
      debugPrint('WebVTT字幕URL: $vttUrl');
      
      // 下载字幕内容，添加重试机制
      String? vttContent;
      int maxRetries = 3;
      for (int i = 0; i < maxRetries; i++) {
        try {
          final subtitleResponse = await http.get(
            Uri.parse(vttUrl),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
              'Cookie': 'CONSENT=YES+cb',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
              'Accept-Language': 'en-US,en;q=0.5',
            }
          );
          
          if (subtitleResponse.statusCode != 200) {
            debugPrint('获取字幕内容失败 (尝试 ${i+1}/${maxRetries}): ${subtitleResponse.statusCode}');
            await Future.delayed(Duration(seconds: 1)); // 延迟1秒后重试
            continue;
          }
          
          vttContent = subtitleResponse.body;
          if (vttContent.isEmpty) {
            debugPrint('字幕内容为空 (尝试 ${i+1}/${maxRetries})');
            await Future.delayed(Duration(seconds: 1));
            continue;
          }
          
          // 检查是否为XML格式，如果是，检查是否有错误
          if (vttContent.trim().startsWith('<?xml') || vttContent.trim().startsWith('<transcript>')) {
            debugPrint('检测到XML格式的字幕，检查是否有错误');
            
            // 检查是否包含错误信息
            final hasError = vttContent.contains('<error>') || vttContent.contains('<e>');
            if (hasError) {
              final errorRegex = RegExp(r'<(?:error|e)>([^<]+)</(?:error|e)>');
              final match = errorRegex.firstMatch(vttContent);
              if (match != null && match.groupCount >= 1) {
                final errorMsg = match.group(1);
                debugPrint('XML字幕包含错误: $errorMsg');
                
                // 如果是最后一次尝试，则继续尝试解析，否则尝试其他方式
                if (i == maxRetries - 1) {
                  debugPrint('这是最后一次尝试，继续处理XML');
                } else {
                  debugPrint('尝试其他方式获取字幕');
                  await Future.delayed(Duration(seconds: 1));
                  continue;
                }
              }
            }
            
            // 尝试解析XML格式的字幕
            try {
              final xmlContent = vttContent;
              
              // 简单的XML解析，提取文本和时间信息
              final textRegex = RegExp(r'<text[^>]*start="([^"]+)"[^>]*dur="([^"]+)"[^>]*>([^<]*)</text>');
              final matches = textRegex.allMatches(xmlContent);
              
              if (matches.isEmpty) {
                debugPrint('未找到XML格式的字幕内容');
                if (i < maxRetries - 1) {
                  await Future.delayed(Duration(seconds: 1));
                  continue;
                }
              } else {
                // 构建SRT格式的字幕
                final srtBuffer = StringBuffer();
                int index = 1;
                
                for (final match in matches) {
                  if (match.groupCount >= 3) {
                    final startSeconds = double.tryParse(match.group(1) ?? '0') ?? 0;
                    final durationSeconds = double.tryParse(match.group(2) ?? '0') ?? 0;
                    final endSeconds = startSeconds + durationSeconds;
                    final text = match.group(3) ?? '';
                    
                    if (text.trim().isNotEmpty) {
                      // 索引编号
                      srtBuffer.writeln(index);
                      index++;
                      
                      // 时间格式
                      final start = _formatTimestamp(Duration(milliseconds: (startSeconds * 1000).round()));
                      final end = _formatTimestamp(Duration(milliseconds: (endSeconds * 1000).round()));
                      srtBuffer.writeln('$start --> $end');
                      
                      // 字幕文本
                      srtBuffer.writeln(text);
                      srtBuffer.writeln();
                    }
                  }
                }
                
                final result = srtBuffer.toString().trim();
                if (result.isNotEmpty) {
                  debugPrint('成功从XML格式提取${index - 1}条字幕');
                  return result;
                }
              }
            } catch (e) {
              debugPrint('解析XML字幕失败: $e');
              if (i < maxRetries - 1) {
                await Future.delayed(Duration(seconds: 1));
                continue;
              }
            }
          }
          
          debugPrint('成功获取WebVTT字幕，长度: ${vttContent.length}字节');
          break;
        } catch (e) {
          debugPrint('获取字幕内容出错 (尝试 ${i+1}/${maxRetries}): $e');
          if (i < maxRetries - 1) {
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
      
      if (vttContent == null || vttContent.isEmpty) {
        debugPrint('多次尝试后仍无法获取字幕内容');
        return null;
      }
      
      // 检查内容是否为有效的WebVTT格式
      if (!vttContent.trim().startsWith('WEBVTT') && !vttContent.contains('-->')) {
        debugPrint('获取到的内容不是有效的WebVTT格式');
        debugPrint('内容片段: ${vttContent.substring(0, vttContent.length > 100 ? 100 : vttContent.length)}');
        return null;
      }
      
      // 转换为SRT格式
      return _convertVttToSrt(vttContent);
    } catch (e) {
      debugPrint('处理字幕数据失败: $e');
      return null;
    }
  }
  
  // 从官方API获取字幕
  Future<String?> _getSubtitlesFromOfficialApi(String videoId, Function(String)? onStatusUpdate) async {
    try {
      debugPrint('尝试从官方API获取字幕');
      onStatusUpdate?.call('从官方API获取字幕...');
      
      // 获取视频的字幕轨道
      final manifest = await _yt.videos.closedCaptions.getManifest(videoId);
      if (manifest.tracks.isEmpty) {
        debugPrint('无可用字幕轨道');
        return null;
      }
      
      // 优先选择英文字幕
      var track = manifest.tracks.firstWhere(
        (track) => track.language.code.toLowerCase() == 'en',
        orElse: () => manifest.tracks.first
      );
      
      debugPrint('选择字幕轨道: ${track.language.code}');
      
      // 获取字幕内容
      final captionTrack = await _yt.videos.closedCaptions.get(track);
      if (captionTrack.captions.isEmpty) {
        debugPrint('字幕内容为空');
        return null;
      }
      
      // 转换为SRT格式
      final srtContent = StringBuffer();
      for (var i = 0; i < captionTrack.captions.length; i++) {
        final caption = captionTrack.captions[i];
        
        // 索引编号
        srtContent.writeln(i + 1);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final start = _formatTimestamp(Duration(milliseconds: caption.offset.inMilliseconds));
        final end = _formatTimestamp(Duration(milliseconds: caption.offset.inMilliseconds + caption.duration.inMilliseconds));
        srtContent.writeln('$start --> $end');
        
        // 字幕文本
        srtContent.writeln(caption.text);
        srtContent.writeln();
      }
      
      debugPrint('成功从官方API获取${captionTrack.captions.length}条字幕');
      return srtContent.toString();
    } catch (e) {
      debugPrint('从官方API获取字幕失败: $e');
      return null;
    }
  }

  // 从HTTP API获取字幕
  Future<String?> _getSubtitlesFromHttpApi(String videoId, {String? langCode}) async {
    try {
      debugPrint('尝试从HTTP API获取字幕，语言: ${langCode ?? "默认"}');
      
      // 构建API请求URL
      String apiUrl = 'https://youtubetranscript.com/?server_vid=$videoId';
      if (langCode != null) {
        apiUrl += '&lang=$langCode';
      }
      debugPrint('请求URL: $apiUrl');
      
      // 发送请求
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        debugPrint('HTTP API请求失败: ${response.statusCode}');
        return null;
      }
      
      // 解析响应
      final responseData = jsonDecode(response.body);
      if (responseData == null || responseData['success'] != true) {
        debugPrint('API返回错误: ${responseData['message'] ?? '未知错误'}');
        return null;
      }
      
      // 提取字幕数据
      final transcriptData = responseData['transcript'];
      if (transcriptData == null || transcriptData is! List || transcriptData.isEmpty) {
        debugPrint('字幕数据为空或格式错误');
        return null;
      }
      
      // 转换为SRT格式
      final srtContent = StringBuffer();
      for (var i = 0; i < transcriptData.length; i++) {
        final item = transcriptData[i];
        
        // 索引编号
        srtContent.writeln(i + 1);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final startSeconds = (item['start'] as num).toDouble();
        final durationSeconds = (item['duration'] as num).toDouble();
        final endSeconds = startSeconds + durationSeconds;
        
        final start = _formatTimestamp(Duration(milliseconds: (startSeconds * 1000).round()));
        final end = _formatTimestamp(Duration(milliseconds: (endSeconds * 1000).round()));
        srtContent.writeln('$start --> $end');
        
        // 字幕文本
        srtContent.writeln(item['text']);
        srtContent.writeln();
      }
      
      debugPrint('成功从HTTP API获取${transcriptData.length}条字幕');
      return srtContent.toString();
    } catch (e) {
      debugPrint('从HTTP API获取字幕失败: $e');
      return null;
    }
  }

  // 将WebVTT格式转换为SRT格式
  String? _convertVttToSrt(String vttContent) {
    try {
      debugPrint('开始转换WebVTT到SRT格式');
      
      // 检查内容是否为WebVTT格式
      if (!vttContent.contains('WEBVTT') && !vttContent.contains('Kind:')) {
        debugPrint('内容不是标准的WebVTT格式，尝试直接解析');
        debugPrint('内容前100个字符: ${vttContent.substring(0, min(100, vttContent.length))}');
      }
      
      // 分割行
      final lines = vttContent.split('\n');
      debugPrint('WebVTT共有${lines.length}行');
      
      // 移除WebVTT头部
      int startIndex = 0;
      for (int i = 0; i < min(10, lines.length); i++) {
        if (lines[i].contains('-->')) {
          startIndex = i;
          break;
        }
      }
      
      debugPrint('找到第一个时间标记行，索引: $startIndex');
      
      // 解析字幕
      final srtLines = <String>[];
      int subtitleIndex = 1;
      int i = startIndex;
      
      while (i < lines.length) {
        // 查找时间行
        if (lines[i].contains('-->')) {
          // 添加字幕索引
          srtLines.add(subtitleIndex.toString());
          
          // 处理时间格式
          final timeLine = lines[i].trim();
          final convertedTimeLine = _convertVttTimeToSrtTime(timeLine);
          srtLines.add(convertedTimeLine);
          
          // 收集字幕文本
          final textLines = <String>[];
          i++;
          while (i < lines.length && lines[i].trim().isNotEmpty) {
            textLines.add(lines[i].trim());
            i++;
          }
          
          // 添加字幕文本
          if (textLines.isNotEmpty) {
            srtLines.add(textLines.join('\n'));
            srtLines.add(''); // 空行分隔
            subtitleIndex++;
          }
        } else {
          i++;
        }
      }
      
      debugPrint('转换完成，SRT格式共有${srtLines.length}行，${subtitleIndex-1}个字幕');
      
      // 如果没有找到任何字幕，返回null
      if (subtitleIndex <= 1) {
        debugPrint('未找到有效字幕');
        return null;
      }
      
      return srtLines.join('\n');
    } catch (e, stackTrace) {
      debugPrint('转换WebVTT到SRT格式失败: $e');
      debugPrint('错误堆栈: $stackTrace');
      return null;
    }
  }
  
  // 转换WebVTT时间格式为SRT时间格式
  String _convertVttTimeToSrtTime(String vttTime) {
    try {
      // 处理WebVTT时间格式
      final parts = vttTime.split('-->');
      if (parts.length != 2) {
        debugPrint('无效的时间格式: $vttTime');
        return vttTime; // 返回原始格式
      }
      
      String startTime = parts[0].trim();
      String endTime = parts[1].trim();
      
      // 移除时间之后的设置（如position:50%）
      if (endTime.contains(' ')) {
        endTime = endTime.split(' ')[0];
      }
      
      // 确保毫秒部分有3位数字
      startTime = _ensureMillisecondsFormat(startTime);
      endTime = _ensureMillisecondsFormat(endTime);
      
      return '$startTime --> $endTime';
    } catch (e) {
      debugPrint('转换时间格式失败: $e');
      return vttTime; // 出错时返回原始格式
    }
  }
  
  // 确保时间格式的毫秒部分有3位数字
  String _ensureMillisecondsFormat(String time) {
    try {
      // 处理00:00:00.000格式
      if (time.contains('.')) {
        final parts = time.split('.');
        String milliseconds = parts[1];
        
        // 如果毫秒部分不是3位数字，进行调整
        if (milliseconds.length < 3) {
          milliseconds = milliseconds.padRight(3, '0');
        } else if (milliseconds.length > 3) {
          milliseconds = milliseconds.substring(0, 3);
        }
        
        return '${parts[0]}.$milliseconds';
      }
      // 处理00:00:00,000格式
      else if (time.contains(',')) {
        final parts = time.split(',');
        String milliseconds = parts[1];
        
        // 如果毫秒部分不是3位数字，进行调整
        if (milliseconds.length < 3) {
          milliseconds = milliseconds.padRight(3, '0');
        } else if (milliseconds.length > 3) {
          milliseconds = milliseconds.substring(0, 3);
        }
        
        return '${parts[0]},$milliseconds';
      }
      // 如果没有毫秒部分，添加.000
      else {
        return '$time.000';
      }
    } catch (e) {
      debugPrint('调整毫秒格式失败: $e');
      return time; // 出错时返回原始格式
    }
  }
  
  // 获取视频的所有字幕轨道
  Future<List<Map<String, dynamic>>> getAllSubtitleTracks(String videoId) async {
    try {
      debugPrint('获取视频的所有字幕轨道: $videoId');
      final List<Map<String, dynamic>> result = [];
      // 不再使用语言代码集合来过滤字幕
      // final Set<String> addedLanguageCodes = {}; 
      
      // 尝试从官方API获取字幕轨道
      try {
        final manifest = await _yt.videos.closedCaptions.getManifest(videoId);
        if (manifest.tracks.isNotEmpty) {
          debugPrint('从官方API获取到${manifest.tracks.length}个字幕轨道');
          
          // 为相同语言代码的轨道计数
          final Map<String, int> languageCount = {};
          
          for (var track in manifest.tracks) {
            final languageCode = track.language.code;
            
            // 更新语言计数
            languageCount[languageCode] = (languageCount[languageCode] ?? 0) + 1;
            final count = languageCount[languageCode]!;
            
            // 添加所有轨道，不再过滤相同语言代码
            result.add({
              'source': 'official',
              'languageCode': languageCode,
              'languageName': track.language.name,
              'isAutoGenerated': track.isAutoGenerated,
              // 在名称中添加更多信息来区分相同语言的不同轨道
              'name': '${track.language.name}${track.isAutoGenerated ? " (自动生成)" : ""} ${count > 1 ? "#$count" : ""}',
              'track': track,
            });
          }
          
          // 如果从官方API获取到了字幕轨道，就不再尝试从网页获取
          if (result.isNotEmpty) {
            return result;
          }
        }
      } catch (e) {
        debugPrint('从官方API获取字幕轨道失败: $e');
      }
      
      // 如果官方API失败，尝试从网页获取字幕轨道
      try {
        // 获取视频页面
        final response = await http.get(
          Uri.parse('https://www.youtube.com/watch?v=$videoId'),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-us,en;q=0.5',
            'Sec-Fetch-Mode': 'navigate',
          }
        );
        
        if (response.statusCode != 200) {
          debugPrint('获取视频页面失败: ${response.statusCode}');
          return result;
        }
        
        // 从HTML中提取player_response
        final playerResponseRegex = RegExp(r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\});\s*var');
        final match = playerResponseRegex.firstMatch(response.body);
        
        if (match == null || match.groupCount < 1) {
          debugPrint('未找到player_response数据');
          return result;
        }
        
        String? playerResponseJson = match.group(1);
        if (playerResponseJson == null) {
          debugPrint('player_response数据为空');
          return result;
        }
        
        // 解析JSON
        Map<String, dynamic> playerResponse;
        try {
          playerResponse = jsonDecode(playerResponseJson);
        } catch (e) {
          debugPrint('解析player_response失败: $e');
          
          // 尝试修复JSON
          playerResponseJson = playerResponseJson
              .replaceAll("'", '"')
              .replaceAll(RegExp(r',\s*\}'), '}')
              .replaceAll(RegExp(r',\s*\]'), ']');
          
          try {
            playerResponse = jsonDecode(playerResponseJson);
          } catch (e) {
            debugPrint('修复后仍然无法解析JSON: $e');
            return result;
          }
        }
        
        // 提取字幕轨道
        final captions = playerResponse['captions'];
        if (captions == null) {
          debugPrint('未找到字幕数据');
          return result;
        }
        
        final captionTracks = captions['playerCaptionsTracklistRenderer']?['captionTracks'];
        if (captionTracks == null || captionTracks is! List || captionTracks.isEmpty) {
          debugPrint('未找到字幕轨道');
          return result;
        }
        
        // 为相同语言代码的轨道计数
        final Map<String, int> languageCount = {};
        
        // 添加字幕轨道
        debugPrint('从网页获取到${captionTracks.length}个字幕轨道');
        for (final track in captionTracks) {
          final lang = track['languageCode'] as String;
          
          // 更新语言计数
          languageCount[lang] = (languageCount[lang] ?? 0) + 1;
          final count = languageCount[lang]!;
          
          // 添加所有轨道，不再过滤相同语言代码
          final name = track['name']?['simpleText'] ?? track['name']?['runs']?[0]?['text'] ?? lang;
          final isAuto = track['kind'] == 'asr';
          final baseUrl = track['baseUrl'] as String;
          
          result.add({
            'source': 'web',
            'languageCode': lang,
            'languageName': name,
            'isAutoGenerated': isAuto,
            'name': '$name${isAuto ? " (自动生成)" : ""} ${count > 1 ? "#$count" : ""}',
            'baseUrl': baseUrl,
          });
        }
      } catch (e) {
        debugPrint('从网页获取字幕轨道失败: $e');
      }
      
      return result;
    } catch (e) {
      debugPrint('获取字幕轨道失败: $e');
      return [];
    }
  }
  
  // 下载指定的字幕轨道
  Future<String?> downloadSpecificSubtitle(String videoId, Map<String, dynamic> subtitleTrack, {Function(String)? onStatusUpdate}) async {
    try {
      // 获取视频信息以获取标题
      final video = await _yt.videos.get(videoId);
      final videoTitle = video.title;
      
      // 准备字幕文件路径
      String subtitleFilename = '';
      String subtitleFilePath = '';
      
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        // 创建与视频相同命名格式的字幕文件名
        String safeTitle = videoTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_');
        String langCode = subtitleTrack['languageCode'] as String;
        subtitleFilename = '${videoId}_${safeTitle}_${langCode}.srt';
        subtitleFilePath = path.join(_configService!.youtubeDownloadPath, subtitleFilename);
        
        // 检查是否已经存在同名字幕文件
        if (await File(subtitleFilePath).exists()) {
          debugPrint('字幕文件已存在，直接使用: $subtitleFilePath');
          onStatusUpdate?.call('使用已下载的字幕');
          return subtitleFilePath;
        }
      } else {
        // 使用临时目录，仍然保持命名一致性
        final tempDir = await getTemporaryDirectory();
        String langCode = subtitleTrack['languageCode'] as String;
        subtitleFilename = '${videoId}_subtitle_${langCode}.srt';
        subtitleFilePath = path.join(tempDir.path, subtitleFilename);
      }
      
      onStatusUpdate?.call('下载字幕中...');
      
      // 获取语言代码
      final languageCode = subtitleTrack['languageCode'] as String? ?? 'en';
      
      // 使用重构后的 YouTubeSubtitleDownloader 下载字幕
      final downloader = YouTubeSubtitleDownloader(
        videoId: videoId,
        languageCode: languageCode,
        maxRetries: 3,
        retryDelay: const Duration(seconds: 1),
      );
      
      try {
        final subtitles = await downloader.downloadSubtitles();
        if (subtitles.isNotEmpty) {
          debugPrint('成功下载字幕，内容长度: ${subtitles.length}');
          
          // 保存字幕到文件
          final file = await downloader.saveSubtitlesToFile(subtitles, subtitleFilePath);
          debugPrint('字幕已保存到: ${file.path}');
          onStatusUpdate?.call('字幕下载成功');
          
          // 将字幕文件添加到缓存
          if (_downloadCache.containsKey(videoId)) {
            _downloadCache[videoId]!['subtitleFilename'] = path.basename(subtitleFilePath);
            await _saveCache();
          }
          
          return file.path;
        } else {
          debugPrint('下载的字幕内容为空');
          onStatusUpdate?.call('字幕内容为空');
          return null;
        }
      } catch (e) {
        debugPrint('使用 YouTubeSubtitleDownloader 下载字幕失败: $e');
        onStatusUpdate?.call('字幕下载失败');
        return null;
      }
    } catch (e, stack) {
      debugPrint('下载字幕异常: $e');
      debugPrint('堆栈: $stack');
      onStatusUpdate?.call('下载字幕错误');
      return null;
    }
  }
  
  // 处理XML解析错误
  Future<String?> _handleXmlParseError(String videoId, String? languageCode, Function(String)? onStatusUpdate) async {
    debugPrint('处理XML解析错误，尝试使用备用方法获取字幕');
    onStatusUpdate?.call('XML解析错误，尝试备用方法...');
    
    try {
      // 首先尝试使用HTTP API
      String? srtContent = await _getSubtitlesFromHttpApi(videoId, langCode: languageCode);
      
      // 如果失败，尝试直接方法
      if (srtContent == null || srtContent.isEmpty) {
        debugPrint('HTTP API获取字幕失败，尝试直接方法');
        onStatusUpdate?.call('尝试直接获取字幕...');
        
        // 使用不同的User-Agent尝试
        final userAgents = [
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15',
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36'
        ];
        
        // 尝试不同的User-Agent
        for (final userAgent in userAgents) {
          try {
            debugPrint('尝试使用User-Agent: $userAgent');
            
            // 获取视频页面
            final response = await http.get(
              Uri.parse('https://www.youtube.com/watch?v=$videoId'),
              headers: {
                'User-Agent': userAgent,
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-us,en;q=0.5',
                'Cookie': 'CONSENT=YES+cb',
              }
            );
            
            if (response.statusCode != 200) {
              debugPrint('获取视频页面失败: ${response.statusCode}');
              continue;
            }
            
            // 从HTML中提取字幕URL
            final captionUrlRegex = RegExp(r'"captionTracks":\s*\[\s*\{\s*"baseUrl":\s*"([^"]+)"');
            final match = captionUrlRegex.firstMatch(response.body);
            
            if (match == null || match.groupCount < 1) {
              debugPrint('未找到字幕URL');
              continue;
            }
            
            String? captionUrl = match.group(1);
            if (captionUrl == null) {
              debugPrint('字幕URL为空');
              continue;
            }
            
            // 解码URL
            captionUrl = captionUrl.replaceAll(r'\u0026', '&');
            debugPrint('找到字幕URL: $captionUrl');
            
            // 添加格式参数，获取WebVTT格式
            if (!captionUrl.contains('fmt=')) {
              captionUrl += '&fmt=vtt';
            }
            
            // 下载字幕内容
            final subtitleResponse = await http.get(Uri.parse(captionUrl));
            if (subtitleResponse.statusCode != 200) {
              debugPrint('获取字幕内容失败: ${subtitleResponse.statusCode}');
              continue;
            }
            
            final vttContent = subtitleResponse.body;
            if (vttContent.isEmpty) {
              debugPrint('字幕内容为空');
              continue;
            }
            
            // 转换为SRT格式
            srtContent = _convertVttToSrt(vttContent);
            if (srtContent != null && srtContent.isNotEmpty) {
              debugPrint('成功获取字幕内容');
              break;
            }
          } catch (e) {
            debugPrint('使用User-Agent $userAgent 获取字幕失败: $e');
          }
        }
      }
      
      return srtContent;
    } catch (e) {
      debugPrint('处理XML解析错误失败: $e');
      return null;
    }
  }
  
  // 使用YouTube timedtext API获取字幕
  Future<String?> _getSubtitlesUsingTimedTextAPI(String videoId, String? languageCode) async {
    try {
      debugPrint('尝试使用timedtext API获取字幕，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 构建请求URL - 首先尝试指定语言
      String timedTextUrl = 'https://www.youtube.com/api/timedtext?v=$videoId&lang=${languageCode ?? "en"}';
      debugPrint('请求URL: $timedTextUrl');
      
      // 发送请求
      var response = await http.get(
        Uri.parse(timedTextUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }
      );
      
      debugPrint('timedtext API响应状态码: ${response.statusCode}');
      
      // 如果第一次请求失败，尝试不指定语言
      if (response.statusCode != 200 || response.body.isEmpty || !response.body.contains('<text')) {
        debugPrint('第一次请求失败或返回内容为空，尝试不指定语言');
        
        timedTextUrl = 'https://www.youtube.com/api/timedtext?v=$videoId';
        debugPrint('新请求URL: $timedTextUrl');
        
        response = await http.get(
          Uri.parse(timedTextUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          }
        );
        
        debugPrint('第二次请求状态码: ${response.statusCode}');
      }
      
      // 如果第二次请求也失败，尝试添加更多参数
      if (response.statusCode != 200 || response.body.isEmpty || !response.body.contains('<text')) {
        debugPrint('第二次请求失败或返回内容为空，尝试添加更多参数');
        
        timedTextUrl = 'https://www.youtube.com/api/timedtext?v=$videoId&lang=${languageCode ?? "en"}&fmt=srv1&xorb=2&xobt=3&xovt=3';
        debugPrint('第三次请求URL: $timedTextUrl');
        
        response = await http.get(
          Uri.parse(timedTextUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          }
        );
        
        debugPrint('第三次请求状态码: ${response.statusCode}');
      }
      
      if (response.statusCode != 200) {
        debugPrint('所有timedtext API请求都失败: ${response.statusCode}');
        return null;
      }
      
      final xmlContent = response.body;
      if (xmlContent.isEmpty) {
        debugPrint('timedtext API返回内容为空');
        return null;
      }
      
      debugPrint('timedtext API返回内容长度: ${xmlContent.length}字节');
      debugPrint('timedtext API返回内容预览: ${xmlContent.substring(0, min(200, xmlContent.length))}');
      
      // 如果返回的是XML格式的字幕，需要解析并转换为SRT格式
      if (xmlContent.contains('<transcript>') || xmlContent.contains('<text ')) {
        debugPrint('检测到XML格式字幕，开始解析...');
        return _parseXmlSubtitles(xmlContent);
      } else {
        debugPrint('API返回内容不是XML格式，无法解析');
        return null;
      }
    } catch (e, stack) {
      debugPrint('使用timedtext API获取字幕失败: $e');
      debugPrint('错误堆栈: $stack');
      return null;
    }
  }
  
  // 解析XML格式的字幕
  String? _parseXmlSubtitles(String xmlContent) {
    try {
      debugPrint('开始解析XML格式字幕');
      
      // 使用正则表达式提取字幕文本和时间信息
      final textRegex = RegExp(r'<text start="([^"]+)" dur="([^"]+)"[^>]*>(.*?)</text>', dotAll: true);
      final matches = textRegex.allMatches(xmlContent);
      
      if (matches.isEmpty) {
        debugPrint('未找到字幕文本');
        return null;
      }
      
      debugPrint('找到${matches.length}条字幕');
      
      // 构建SRT格式字幕
      final srtBuffer = StringBuffer();
      int index = 1;
      
      for (final match in matches) {
        if (match.groupCount >= 3) {
          // 获取开始时间和持续时间
          final startSeconds = double.tryParse(match.group(1) ?? '0') ?? 0;
          final durationSeconds = double.tryParse(match.group(2) ?? '0') ?? 0;
          final endSeconds = startSeconds + durationSeconds;
          
          // 转换为SRT时间格式
          final startTime = _secondsToSrtTime(startSeconds);
          final endTime = _secondsToSrtTime(endSeconds);
          
          // 获取字幕文本并解码HTML实体
          String text = match.group(3) ?? '';
          text = _decodeHtmlEntities(text);
          
          // 写入SRT格式
          srtBuffer.writeln(index);
          srtBuffer.writeln('$startTime --> $endTime');
          srtBuffer.writeln(text);
          srtBuffer.writeln();
          
          index++;
        }
      }
      
      final srtContent = srtBuffer.toString();
      debugPrint('XML解析完成，生成了${index-1}条SRT格式字幕');
      
      return srtContent.isNotEmpty ? srtContent : null;
    } catch (e, stack) {
      debugPrint('解析XML字幕失败: $e');
      debugPrint('错误堆栈: $stack');
      return null;
    }
  }
  
  // 将秒数转换为SRT时间格式
  String _secondsToSrtTime(double seconds) {
    final int hours = (seconds / 3600).floor();
    final int minutes = ((seconds % 3600) / 60).floor();
    final int secs = (seconds % 60).floor();
    final int milliseconds = ((seconds - seconds.floor()) * 1000).round();
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')},${milliseconds.toString().padLeft(3, '0')}';
  }
  
  // 解码HTML实体
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('<br />', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br>', '\n');
  }
  
  // 使用新的API方法获取字幕
  Future<String?> _getSubtitlesUsingNewAPI(String videoId, String? languageCode) async {
    try {
      debugPrint('尝试使用新的API方法获取字幕，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 构建请求URL - 使用新的API格式
      final apiUrl = 'https://www.youtube.com/youtubei/v1/get_transcript?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
      debugPrint('请求URL: $apiUrl');
      
      // 构建请求体
      final requestBody = {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20220805.00.00',
          }
        },
        'params': base64Encode(utf8.encode('${{"videoId":"$videoId"}}')),
      };
      
      // 发送POST请求
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
          'Content-Type': 'application/json',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        body: jsonEncode(requestBody),
      );
      
      debugPrint('新API响应状态码: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        debugPrint('新API请求失败: ${response.statusCode}');
        return null;
      }
      
      final responseData = jsonDecode(response.body);
      debugPrint('新API响应数据: ${jsonEncode(responseData).substring(0, min(500, jsonEncode(responseData).length))}');
      
      // 解析字幕数据
      final actions = responseData['actions'];
      if (actions == null || actions is! List || actions.isEmpty) {
        debugPrint('未找到actions数据');
        return null;
      }
      
      // 尝试从不同的数据结构中提取字幕
      List<dynamic>? cues;
      
      // 遍历actions寻找字幕数据
      for (final action in actions) {
        if (action['updateEngagementPanelAction'] != null) {
          final content = action['updateEngagementPanelAction']['content'];
          if (content != null && content['transcriptRenderer'] != null) {
            final transcriptRenderer = content['transcriptRenderer'];
            if (transcriptRenderer['body'] != null) {
              final body = transcriptRenderer['body'];
              if (body['transcriptBodyRenderer'] != null) {
                final transcriptBodyRenderer = body['transcriptBodyRenderer'];
                if (transcriptBodyRenderer['cueGroups'] != null) {
                  final cueGroups = transcriptBodyRenderer['cueGroups'];
                  if (cueGroups is List && cueGroups.isNotEmpty) {
                    // 提取所有cues
                    final allCues = <dynamic>[];
                    for (final group in cueGroups) {
                      if (group['transcriptCueGroupRenderer'] != null) {
                        final renderer = group['transcriptCueGroupRenderer'];
                        if (renderer['cues'] != null && renderer['cues'] is List) {
                          allCues.addAll(renderer['cues']);
                        }
                      }
                    }
                    if (allCues.isNotEmpty) {
                      cues = allCues;
                      break;
                    }
                  }
                }
              }
            }
          }
        }
      }
      
      if (cues == null || cues.isEmpty) {
        debugPrint('未找到字幕cues数据');
        return null;
      }
      
      debugPrint('找到${cues.length}条字幕');
      
      // 构建SRT格式字幕
      final srtBuffer = StringBuffer();
      int index = 1;
      
      for (final cue in cues) {
        if (cue['transcriptCueRenderer'] != null) {
          final renderer = cue['transcriptCueRenderer'];
          
          // 获取开始时间（毫秒）
          final startMs = int.tryParse(renderer['startMs'] ?? '0') ?? 0;
          final durationMs = int.tryParse(renderer['durationMs'] ?? '0') ?? 0;
          final endMs = startMs + durationMs;
          
          // 获取文本
          String text = '';
          if (renderer['cue'] != null && renderer['cue']['simpleText'] != null) {
            text = renderer['cue']['simpleText'];
          } else if (renderer['cue'] != null && renderer['cue']['runs'] != null) {
            final runs = renderer['cue']['runs'];
            if (runs is List) {
              final textParts = <String>[];
              for (final run in runs) {
                if (run['text'] != null) {
                  textParts.add(run['text']);
                }
              }
              text = textParts.join('');
            }
          }
          
          if (text.isNotEmpty) {
            // 写入SRT格式
            srtBuffer.writeln(index);
            
            // 转换时间格式
            final startTime = _millisecondsToTimestamp(startMs);
            final endTime = _millisecondsToTimestamp(endMs);
            srtBuffer.writeln('$startTime --> $endTime');
            
            // 写入文本
            srtBuffer.writeln(text);
            srtBuffer.writeln();
            
            index++;
          }
        }
      }
      
      final srtContent = srtBuffer.toString();
      debugPrint('新API解析完成，生成了${index-1}条SRT格式字幕');
      
      return srtContent.isNotEmpty ? srtContent : null;
    } catch (e, stack) {
      debugPrint('使用新的API方法获取字幕失败: $e');
      debugPrint('错误堆栈: $stack');
      return null;
    }
  }

  // 使用YouTube Transcript API获取字幕
  Future<String?> _getSubtitlesUsingYoutubeTranscriptAPI(String videoId, String? languageCode) async {
    try {
      debugPrint('尝试使用YouTube Transcript API获取字幕，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 构建API请求URL - 使用公共的YouTube Transcript API服务
      final apiUrl = 'https://youtubetranscript.com/?server_vid=$videoId';
      final Map<String, String> queryParams = {};
      
      // 如果指定了语言，添加语言参数
      if (languageCode != null && languageCode.isNotEmpty) {
        queryParams['lang'] = languageCode;
      }
      
      // 构建最终URL
      final Uri uri = Uri.parse(apiUrl).replace(queryParameters: queryParams);
      debugPrint('请求URL: $uri');
      
      // 发送请求
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
          'Accept': 'application/json',
          'Accept-Language': 'en-US,en;q=0.9',
        }
      );
      
      debugPrint('YouTube Transcript API响应状态码: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        debugPrint('YouTube Transcript API请求失败: ${response.statusCode}');
        debugPrint('响应内容: ${response.body.substring(0, min(500, response.body.length))}');
        return null;
      }
      
      // 解析JSON响应
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      
      // 检查是否成功
      if (responseData['success'] != true) {
        debugPrint('API返回错误: ${responseData['message'] ?? '未知错误'}');
        return null;
      }
      
      // 提取字幕数据
      final transcriptData = responseData['transcript'];
      if (transcriptData == null || transcriptData is! List || transcriptData.isEmpty) {
        debugPrint('字幕数据为空或格式错误');
        return null;
      }
      
      debugPrint('成功获取${transcriptData.length}条字幕');
      
      // 转换为SRT格式
      final srtBuffer = StringBuffer();
      for (var i = 0; i < transcriptData.length; i++) {
        final item = transcriptData[i];
        
        // 索引编号
        srtBuffer.writeln(i + 1);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final startSeconds = (item['start'] as num).toDouble();
        final durationSeconds = (item['duration'] as num).toDouble();
        final endSeconds = startSeconds + durationSeconds;
        
        final start = _formatTimestamp(Duration(milliseconds: (startSeconds * 1000).round()));
        final end = _formatTimestamp(Duration(milliseconds: (endSeconds * 1000).round()));
        srtBuffer.writeln('$start --> $end');
        
        // 字幕文本
        srtBuffer.writeln(item['text']);
        srtBuffer.writeln();
      }
      
      return srtBuffer.toString();
    } catch (e, stack) {
      debugPrint('使用YouTube Transcript API获取字幕失败: $e');
      debugPrint('错误堆栈: $stack');
      return null;
    }
  }

  // 使用youtube_explode_dart库直接获取字幕
  Future<String?> _getSubtitlesFromYouTubeExplodeApi(String videoId, {String? languageCode}) async {
    try {
      debugPrint('尝试使用youtube_explode_dart库直接获取字幕，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 获取视频的字幕轨道
      final manifest = await _yt.videos.closedCaptions.getManifest(videoId);
      if (manifest.tracks.isEmpty) {
        debugPrint('无可用字幕轨道');
        return null;
      }
      
      // 选择字幕轨道
      ClosedCaptionTrackInfo? selectedTrack;
      if (languageCode != null && languageCode.isNotEmpty) {
        // 尝试找到指定语言的字幕
        try {
          selectedTrack = manifest.tracks.firstWhere(
            (t) => t.language.code.toLowerCase() == languageCode.toLowerCase()
          );
        } catch (e) {
          selectedTrack = null;
        }
      }
      
      // 如果没有找到指定语言的字幕，使用默认优先级
      if (selectedTrack == null) {
        // 优先选择英文字幕
        try {
          selectedTrack = manifest.tracks.firstWhere(
            (t) => t.language.code.toLowerCase() == 'en'
          );
        } catch (e) {
          // 如果没有英文字幕，使用第一个可用的字幕
          if (manifest.tracks.isNotEmpty) {
            selectedTrack = manifest.tracks.first;
          } else {
            debugPrint('没有找到可用的字幕轨道');
            return null;
          }
        }
      }
      
      debugPrint('选择字幕轨道: ${selectedTrack.language.code}');
      
      // 获取字幕内容
      final captionTrack = await _yt.videos.closedCaptions.get(selectedTrack);
      if (captionTrack.captions.isEmpty) {
        debugPrint('字幕内容为空');
        return null;
      }
      
      // 转换为SRT格式
      final srtContent = StringBuffer();
      for (var i = 0; i < captionTrack.captions.length; i++) {
        final caption = captionTrack.captions[i];
        
        // 索引编号
        srtContent.writeln(i + 1);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final start = _formatTimestamp(Duration(milliseconds: caption.offset.inMilliseconds));
        final end = _formatTimestamp(Duration(milliseconds: caption.offset.inMilliseconds + caption.duration.inMilliseconds));
        srtContent.writeln('$start --> $end');
        
        // 字幕文本
        srtContent.writeln(caption.text);
        srtContent.writeln();
      }
      
      debugPrint('成功从youtube_explode_dart库获取${captionTrack.captions.length}条字幕');
      return srtContent.toString();
    } catch (e, stack) {
      debugPrint('使用youtube_explode_dart库获取字幕失败: $e');
      debugPrint('错误堆栈: $stack');
      return null;
    }
  }

  // 使用YouTube内部API(Innertube)获取字幕
  Future<String?> _getSubtitlesUsingInnertubeAPI(String videoId, String? languageCode) async {
    try {
      debugPrint('尝试使用YouTube内部API(Innertube)获取字幕，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 构建请求URL
      final apiUrl = 'https://www.youtube.com/youtubei/v1/get_transcript';
      
      // 构建请求体
      final Map<String, dynamic> requestBody = {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20240617.01.00',
            'hl': languageCode ?? 'en',
          }
        },
        'params': base64.encode(utf8.encode('{"videoId":"$videoId"}')).replaceAll('=', '').replaceAll('/', '_').replaceAll('+', '-'),
      };
      
      debugPrint('请求URL: $apiUrl');
      debugPrint('请求体: ${jsonEncode(requestBody)}');
      
      // 发送请求
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
          'Accept-Language': languageCode ?? 'en-US,en;q=0.9',
        },
        body: jsonEncode(requestBody),
      );
      
      debugPrint('响应状态码: ${response.statusCode}');
      debugPrint('响应内容长度: ${response.body.length}');
      debugPrint('响应内容预览: ${response.body.substring(0, min(1000, response.body.length))}');
      
      if (response.statusCode == 200) {
        // 解析JSON响应
        final Map<String, dynamic> data = jsonDecode(response.body);
        
        // 打印完整的响应结构
        debugPrint('完整响应结构: ${jsonEncode(data)}');
        
        // 提取字幕数据
        if (data.containsKey('actions') && 
            data['actions'] is List && 
            data['actions'].isNotEmpty) {
          
          // 尝试提取字幕内容
          List<Map<String, dynamic>> subtitleCues = [];
          
          // 遍历actions寻找字幕数据
          for (var action in data['actions']) {
            if (action.containsKey('updateEngagementPanelAction')) {
              var content = action['updateEngagementPanelAction']['content'];
              if (content != null && content.containsKey('transcriptRenderer')) {
                var transcriptRenderer = content['transcriptRenderer'];
                if (transcriptRenderer.containsKey('body')) {
                  var body = transcriptRenderer['body'];
                  if (body.containsKey('transcriptBodyRenderer')) {
                    var bodyRenderer = body['transcriptBodyRenderer'];
                    if (bodyRenderer.containsKey('cueGroups')) {
                      var cueGroups = bodyRenderer['cueGroups'];
                      
                      // 处理每个字幕组
                      for (var cueGroup in cueGroups) {
                        if (cueGroup.containsKey('transcriptCueGroupRenderer')) {
                          var groupRenderer = cueGroup['transcriptCueGroupRenderer'];
                          if (groupRenderer.containsKey('cues')) {
                            for (var cue in groupRenderer['cues']) {
                              if (cue.containsKey('transcriptCueRenderer')) {
                                var cueRenderer = cue['transcriptCueRenderer'];
                                
                                // 提取时间和文本
                                if (cueRenderer.containsKey('startOffsetMs') && 
                                    cueRenderer.containsKey('durationMs') && 
                                    cueRenderer.containsKey('cue')) {
                                  
                                  int startTimeMs = int.parse(cueRenderer['startOffsetMs']);
                                  int durationMs = int.parse(cueRenderer['durationMs']);
                                  int endTimeMs = startTimeMs + durationMs;
                                  
                                  String text = '';
                                  if (cueRenderer['cue'].containsKey('simpleText')) {
                                    text = cueRenderer['cue']['simpleText'];
                                  } else if (cueRenderer['cue'].containsKey('runs')) {
                                    for (var run in cueRenderer['cue']['runs']) {
                                      if (run.containsKey('text')) {
                                        text += run['text'];
                                      }
                                    }
                                  }
                                  
                                  subtitleCues.add({
                                    'startTime': startTimeMs,
                                    'endTime': endTimeMs,
                                    'text': text
                                  });
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          
          // 如果找到字幕数据，转换为SRT格式
          if (subtitleCues.isNotEmpty) {
            debugPrint('找到 ${subtitleCues.length} 条字幕');
            
            // 按开始时间排序
            subtitleCues.sort((a, b) => a['startTime'].compareTo(b['startTime']));
            
            // 转换为SRT格式
            StringBuffer srtContent = StringBuffer();
            for (int i = 0; i < subtitleCues.length; i++) {
              var cue = subtitleCues[i];
              
              // 序号
              srtContent.writeln('${i + 1}');
              
              // 时间格式化
              String startTime = _formatTime(cue['startTime']);
              String endTime = _formatTime(cue['endTime']);
              srtContent.writeln('$startTime --> $endTime');
              
              // 字幕文本
              srtContent.writeln(cue['text']);
              
              // 空行
              srtContent.writeln('');
            }
            
            return srtContent.toString();
          } else {
            debugPrint('未找到字幕数据');
          }
        } else {
          debugPrint('响应中没有actions字段或为空');
        }
      } else {
        debugPrint('请求失败，状态码: ${response.statusCode}');
      }
      
      return null;
    } catch (e, stack) {
      debugPrint('使用YouTube内部API获取字幕出错: $e');
      debugPrint('堆栈: $stack');
      return null;
    }
  }
  
  // 将毫秒转换为SRT时间格式
  String _formatTime(int milliseconds) {
    int hours = milliseconds ~/ 3600000;
    int minutes = (milliseconds % 3600000) ~/ 60000;
    int seconds = (milliseconds % 60000) ~/ 1000;
    int millis = milliseconds % 1000;
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')},${millis.toString().padLeft(3, '0')}';
  }

  // 处理原始响应内容，不进行XML解析
  Future<String?> _handleRawResponse(String videoId, String? languageCode) async {
    try {
      debugPrint('尝试获取原始字幕响应，视频ID: $videoId，语言: ${languageCode ?? "默认"}');
      
      // 尝试多种URL格式
      final urlFormats = [
        // timedtext API
        'https://www.youtube.com/api/timedtext?v=$videoId&caps=asr&opi=112496729&xoaf=5&hl=${languageCode ?? "en"}&fmt=srv3',
        
        // 另一种timedtext格式
        'https://www.youtube.com/api/timedtext?v=$videoId&lang=${languageCode ?? "en"}',
        
        // 直接获取字幕
        'https://www.youtube.com/watch?v=$videoId&hl=${languageCode ?? "en"}'
      ];
      
      for (final url in urlFormats) {
        debugPrint('尝试URL: $url');
        
        try {
          // 发送请求
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
              'Accept-Language': '${languageCode ?? "en"}-US,${languageCode ?? "en"};q=0.9',
              'Cookie': 'CONSENT=YES+cb',
            },
          );
          
          debugPrint('响应状态码: ${response.statusCode}');
          debugPrint('响应内容长度: ${response.body.length}');
          
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            // 打印原始响应内容
            debugPrint('原始响应内容: ${response.body.substring(0, min(2000, response.body.length))}');
            
            // 如果是XML格式，尝试提取字幕
            if (response.body.trim().startsWith('<?xml') || response.body.contains('<transcript>')) {
              debugPrint('检测到XML格式响应');
              
              // 简单的XML解析，提取文本和时间信息
              final textRegex = RegExp(r'<text[^>]*start="([^"]+)"[^>]*dur="([^"]+)"[^>]*>([^<]*)</text>');
              final matches = textRegex.allMatches(response.body);
              
              if (matches.isNotEmpty) {
                // 构建SRT格式的字幕
                final srtBuffer = StringBuffer();
                int index = 1;
                
                for (final match in matches) {
                  if (match.groupCount >= 3) {
                    final startSeconds = double.tryParse(match.group(1) ?? '0') ?? 0;
                    final durationSeconds = double.tryParse(match.group(2) ?? '0') ?? 0;
                    final endSeconds = startSeconds + durationSeconds;
                    final text = match.group(3) ?? '';
                    
                    if (text.trim().isNotEmpty) {
                      // 索引编号
                      srtBuffer.writeln(index);
                      index++;
                      
                      // 时间格式
                      final start = _formatTimestamp(Duration(milliseconds: (startSeconds * 1000).round()));
                      final end = _formatTimestamp(Duration(milliseconds: (endSeconds * 1000).round()));
                      srtBuffer.writeln('$start --> $end');
                      
                      // 字幕文本
                      srtBuffer.writeln(text);
                      srtBuffer.writeln();
                    }
                  }
                }
                
                final result = srtBuffer.toString().trim();
                if (result.isNotEmpty) {
                  debugPrint('成功从XML格式提取${index - 1}条字幕');
                  return result;
                }
              }
            }
            
            // 如果是HTML格式，尝试提取player_response
            if (response.body.contains('ytInitialPlayerResponse')) {
              debugPrint('检测到HTML格式响应，尝试提取player_response');
              
              // 从HTML中提取player_response
              final playerResponseRegex = RegExp(r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\});\s*var');
              final match = playerResponseRegex.firstMatch(response.body);
              
              if (match != null && match.groupCount >= 1) {
                String? playerResponseJson = match.group(1);
                if (playerResponseJson != null) {
                  try {
                    final playerResponse = jsonDecode(playerResponseJson);
                    
                    // 提取字幕轨道
                    final captions = playerResponse['captions'];
                    if (captions != null) {
                      final captionTracks = captions['playerCaptionsTracklistRenderer']?['captionTracks'];
                      if (captionTracks != null && captionTracks is List && captionTracks.isNotEmpty) {
                        // 选择字幕轨道
                        Map<String, dynamic>? selectedTrack;
                        
                        // 如果指定了语言，优先选择该语言的字幕
                        if (languageCode != null) {
                          for (final track in captionTracks) {
                            final lang = (track['languageCode'] as String).toLowerCase();
                            if (lang == languageCode.toLowerCase()) {
                              selectedTrack = track;
                              break;
                            }
                          }
                        }
                        
                        // 如果没有找到指定语言的字幕，使用第一个
                        if (selectedTrack == null && captionTracks.isNotEmpty) {
                          selectedTrack = captionTracks[0];
                        }
                        
                        if (selectedTrack != null) {
                          // 获取字幕URL
                          String baseUrl = selectedTrack['baseUrl'];
                          
                          // 添加格式参数，获取WebVTT格式
                          final vttUrl = '$baseUrl&fmt=vtt';
                          
                          // 下载字幕内容
                          final subtitleResponse = await http.get(
                            Uri.parse(vttUrl),
                            headers: {
                              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
                            }
                          );
                          
                          if (subtitleResponse.statusCode == 200 && subtitleResponse.body.isNotEmpty) {
                            debugPrint('成功获取WebVTT字幕，长度: ${subtitleResponse.body.length}字节');
                            
                            // 打印原始VTT内容
                            debugPrint('原始VTT内容: ${subtitleResponse.body.substring(0, min(2000, subtitleResponse.body.length))}');
                            
                                                         // 直接返回原始内容，不进行转换
                             return subtitleResponse.body;
                          }
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('解析player_response失败: $e');
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('请求URL失败: $e');
        }
      }
      
      return null;
    } catch (e, stack) {
      debugPrint('处理原始响应出错: $e');
      debugPrint('堆栈: $stack');
      return null;
    }
  }
} 