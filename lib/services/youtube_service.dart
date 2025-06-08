import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'dart:convert';
import '../models/subtitle_model.dart';
import '../services/config_service.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  ConfigService? _configService;
  
  // 下载缓存
  final Map<String, String> _downloadCache = {};
  
  // 构造函数，加载缓存
  YouTubeService() {
    _loadDownloadCache();
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
  Future<void> _loadDownloadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString('youtube_download_cache');
      
      if (cacheJson != null) {
        final Map<String, dynamic> cacheMap = json.decode(cacheJson);
        cacheMap.forEach((key, value) {
          if (value is String) {
            _downloadCache[key] = value;
          }
        });
        
        debugPrint('已加载YouTube下载缓存，共${_downloadCache.length}条记录');
      }
    } catch (e) {
      debugPrint('加载YouTube下载缓存失败: $e');
    }
  }
  
  // 保存下载缓存
  Future<void> _saveDownloadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_downloadCache);
      await prefs.setString('youtube_download_cache', cacheJson);
      debugPrint('已保存YouTube下载缓存，共${_downloadCache.length}条记录');
    } catch (e) {
      debugPrint('保存YouTube下载缓存失败: $e');
    }
  }
  
  // 添加下载记录到缓存
  Future<void> _addToDownloadCache(String videoId, String filePath) async {
    _downloadCache[videoId] = filePath;
    await _saveDownloadCache();
  }
  
  // 从缓存中获取下载记录
  String? _getFromDownloadCache(String videoId) {
    final filePath = _downloadCache[videoId];
    
    // 验证文件是否存在
    if (filePath != null) {
      final file = File(filePath);
      if (file.existsSync() && file.lengthSync() > 0) {
        return filePath;
      } else {
        // 文件不存在或大小为0，从缓存中移除
        _downloadCache.remove(videoId);
        _saveDownloadCache();
        return null;
      }
    }
    
    return null;
  }
  
  // 清理缓存中无效的条目
  Future<void> cleanupDownloadCache() async {
    final invalidKeys = <String>[];
    
    _downloadCache.forEach((videoId, filePath) {
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        invalidKeys.add(videoId);
      }
    });
    
    for (final key in invalidKeys) {
      _downloadCache.remove(key);
    }
    
    if (invalidKeys.isNotEmpty) {
      await _saveDownloadCache();
      debugPrint('已清理${invalidKeys.length}条无效的下载缓存记录');
    }
  }
  
  // 设置配置服务
  void setConfigService(ConfigService configService) {
    _configService = configService;
  }
  
  // 从URL中提取视频ID
  Future<String?> extractVideoId(String url) async {
    try {
      // 如果输入的是视频ID（11个字符且不包含特殊符号）
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        return url;
      }
      
      // 从URL中提取视频ID
      var uri = Uri.parse(url);
      
      // 处理youtube.com/watch?v=ID 格式
      if (uri.host.contains('youtube.com') && uri.path.contains('watch')) {
        return uri.queryParameters['v'];
      }
      
      // 处理youtu.be/ID 格式
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      
      // 尝试使用YouTube Explode解析
      try {
        final videoId = await _yt.videos.streamsClient.getManifest(url).then((_) => url);
        return videoId;
      } catch (_) {
        // 如果无法解析，返回null
        return null;
      }
    } catch (e) {
      debugPrint('提取视频ID错误: $e');
      return null;
    }
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
      // 尝试使用多种客户端获取视频的最高质量音视频流
      final manifest = await _yt.videos.streams.getManifest(videoId, ytClients: [
        YoutubeApiClient.safari,
        YoutubeApiClient.android
      ]);
      
      // 首先尝试获取HLS流，这在某些情况下更稳定
      if (manifest.hls.isNotEmpty) {
        final hlsStream = manifest.hls.first;
        debugPrint('获取到HLS视频流URL: ${hlsStream.url}');
        return hlsStream.url.toString();
      }
      
      // 然后尝试获取混合流
      final streamInfo = manifest.muxed.withHighestBitrate();
      if (streamInfo != null) {
        debugPrint('获取到混合视频流URL: ${streamInfo.url}');
        return streamInfo.url.toString();
      }
      
      debugPrint('未找到合适的视频流');
      return null;
    } catch (e) {
      debugPrint('获取视频流URL错误: $e');
      return null;
    }
  }
  
  // 下载视频到本地或临时文件
  Future<String?> downloadVideoToTemp(String videoId, {Function(double)? onProgress, Function(String)? onStatusUpdate}) async {
    try {
      // 首先检查缓存
      final cachedFilePath = _getFromDownloadCache(videoId);
      if (cachedFilePath != null) {
        debugPrint('从缓存中找到视频文件: $cachedFilePath');
        onStatusUpdate?.call('使用已缓存的视频文件');
        return cachedFilePath;
      }
      
      onStatusUpdate?.call('正在获取视频信息...');
      
      // 获取视频信息
      onStatusUpdate?.call('正在获取视频详细信息...');
      final video = await _yt.videos.get(videoId).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('获取视频详细信息超时');
        }
      );
      
      // 尝试使用多种客户端获取视频的最高质量音视频流
      onStatusUpdate?.call('正在获取视频流信息...');
      final manifest = await _yt.videos.streams.getManifest(videoId, ytClients: [
        YoutubeApiClient.safari,
        YoutubeApiClient.android
      ]).timeout(
        const Duration(seconds: 30), 
        onTimeout: () {
          throw TimeoutException('获取视频信息超时，请检查网络连接');
        }
      );
      
      // 尝试不同的流类型
      StreamInfo? streamInfo;
      String streamType = "混合流";
      
      // 首先尝试HLS流
      if (manifest.hls.isNotEmpty) {
        // HLS流不能直接赋值给StreamInfo，因为它们是不同的类型
        // 我们只获取HLS流的URL，然后使用HTTP客户端下载
        streamType = "HLS流";
        debugPrint('使用HLS流');
      } else {
        // 然后尝试混合流
        streamInfo = manifest.muxed.withHighestBitrate();
        if (streamInfo == null) {
          // 如果没有混合流，尝试获取最高质量的视频流
          final videoOnlyStream = manifest.videoOnly.withHighestBitrate();
          if (videoOnlyStream != null) {
            streamInfo = videoOnlyStream;
            streamType = "仅视频流";
            debugPrint('使用仅视频流');
          }
        } else {
          debugPrint('使用混合流');
        }
      }
      
      // 如果没有找到任何流，返回null
      if (streamInfo == null && manifest.hls.isEmpty) {
        debugPrint('未找到合适的视频流');
        onStatusUpdate?.call('未找到合适的视频流');
        return null;
      }
      
      onStatusUpdate?.call('准备下载: ${video.title} (使用${streamType})');
      
      // 获取文件名和保存路径
      onStatusUpdate?.call('正在准备下载路径...');
      String fileName = '${videoId}.mp4';
      // 尝试使用视频标题作为文件名（移除非法字符）
      if (video.title.isNotEmpty) {
        final safeTitle = video.title
            .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') // 替换Windows不允许的文件名字符
            .replaceAll(RegExp(r'\s+'), '_'); // 替换空白字符为下划线
        fileName = '${safeTitle}_${videoId}.mp4';
      }
      
      String filePath;
      // 检查是否有自定义下载路径
      if (_configService != null && _configService!.youtubeDownloadPath.isNotEmpty) {
        // 使用自定义路径
        filePath = path.join(_configService!.youtubeDownloadPath, fileName);
        debugPrint('使用自定义下载路径: $filePath');
      } else {
        // 使用临时目录
        final tempDir = await getTemporaryDirectory();
        filePath = path.join(tempDir.path, fileName);
        debugPrint('使用临时目录: $filePath');
      }
      
      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        // 检查文件大小，确保文件完整
        final fileSize = await file.length();
        if (fileSize > 0) {
          debugPrint('视频文件已存在: $filePath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
          onStatusUpdate?.call('视频文件已存在，无需重新下载');
          
          // 添加到缓存
          await _addToDownloadCache(videoId, filePath);
          
          return filePath;
        } else {
          // 文件存在但大小为0，可能是上次下载失败的残留文件
          debugPrint('删除无效的视频文件: $filePath');
          await file.delete();
        }
      }
      
      // 确保目录存在
      final directory = path.dirname(filePath);
      if (!Directory(directory).existsSync()) {
        await Directory(directory).create(recursive: true);
      }
      
      debugPrint('开始下载视频: ${video.title}');
      onStatusUpdate?.call('正在连接到YouTube服务器...');
      
      // 创建文件
      final fileStream = file.openWrite();
      
      // 获取视频流URL
      String streamUrl;
      if (manifest.hls.isNotEmpty) {
        streamUrl = manifest.hls.first.url.toString();
      } else {
        streamUrl = streamInfo!.url.toString();
      }
      debugPrint('获取到视频URL: $streamUrl');
      
      // 最大重试次数
      const int maxRetries = 3;
      int retryCount = 0;
      bool downloadSuccess = false;
      Exception? lastException;
      
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
          
          if (response.statusCode != 200) {
            throw Exception('服务器返回错误: ${response.statusCode}');
          }
          
          // 获取内容长度（如果有）
          final totalBytes = response.contentLength;
          var receivedBytes = 0;
          
          onStatusUpdate?.call('开始接收数据...');
          
          // 设置状态更新定时器
          Timer? statusTimer;
          statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (totalBytes > 0) {
              final percent = (receivedBytes / totalBytes * 100).toStringAsFixed(1);
              final downloaded = (receivedBytes / 1024 / 1024).toStringAsFixed(2);
              final total = (totalBytes / 1024 / 1024).toStringAsFixed(2);
              final speed = receivedBytes > 0 ? '${(receivedBytes / timer.tick / 1024 / 1024).toStringAsFixed(2)} MB/s' : '计算中...';
              onStatusUpdate?.call('下载中: $percent% ($downloaded MB / $total MB) - $speed');
            } else if (receivedBytes > 0) {
              // 如果没有总大小信息，只显示已下载的大小
              final downloaded = (receivedBytes / 1024 / 1024).toStringAsFixed(2);
              final speed = '${(receivedBytes / timer.tick / 1024 / 1024).toStringAsFixed(2)} MB/s';
              onStatusUpdate?.call('下载中: $downloaded MB - $speed');
            }
          });
          
          // 下载数据
          await response.listen((data) {
            fileStream.add(data);
            receivedBytes += data.length;
            if (totalBytes > 0) {
              final progress = receivedBytes / totalBytes;
              onProgress?.call(progress);
            }
          }).asFuture();
          
          // 取消状态更新定时器
          statusTimer?.cancel();
          
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
      
      // 关闭文件流
      await fileStream.flush();
      await fileStream.close();
      
      // 如果所有重试都失败
      if (!downloadSuccess) {
        debugPrint('所有下载尝试都失败');
        onStatusUpdate?.call('下载失败，所有重试均未成功');
        
        // 删除不完整的文件
        if (await file.exists()) {
          try {
            await file.delete();
            debugPrint('已删除不完整的下载文件');
          } catch (_) {}
        }
        
        throw lastException ?? Exception('下载失败，原因未知');
      }
      
      // 验证下载文件
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      
      if (!fileExists || fileSize == 0) {
        debugPrint('下载失败: 文件不存在或大小为0');
        onStatusUpdate?.call('下载失败: 文件不完整');
        return null;
      }
      
      // 添加到下载缓存
      await _addToDownloadCache(videoId, filePath);
      
      debugPrint('视频下载完成: $filePath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      onStatusUpdate?.call('下载完成: ${video.title}');
      return filePath;
    } catch (e) {
      debugPrint('下载视频错误: $e');
      onStatusUpdate?.call('下载失败: $e');
      return null;
    }
  }
  
  // 下载字幕
  Future<SubtitleData?> downloadSubtitles(String videoId, {String languageCode = 'en'}) async {
    try {
      // 获取字幕轨道清单
      final trackManifest = await _yt.videos.closedCaptions.getManifest(videoId);
      
      // 查找指定语言的字幕
      ClosedCaptionTrackInfo? trackInfo;
      for (final track in trackManifest.tracks) {
        if (track.language.code == languageCode) {
          trackInfo = track;
          break;
        }
      }
      
      if (trackInfo == null) {
        debugPrint('未找到$languageCode语言的字幕');
        return null;
      }
      
      // 下载字幕
      final track = await _yt.videos.closedCaptions.get(trackInfo);
      
      // 解析成应用需要的字幕格式
      List<SubtitleEntry> entries = [];
      for (int i = 0; i < track.captions.length; i++) {
        final caption = track.captions[i];
        
        final entry = SubtitleEntry(
          index: i,
          start: caption.offset,
          end: caption.offset + caption.duration,
          text: caption.text,
        );
        
        entries.add(entry);
      }
      
      return SubtitleData(entries: entries);
    } catch (e) {
      debugPrint('下载字幕错误: $e');
      return null;
    }
  }
  
  // 下载字幕直接到文件
  Future<String?> _downloadSubtitlesDirectly(String videoId, {String languageCode = 'en', Function(String)? onStatusUpdate}) async {
    try {
      onStatusUpdate?.call('正在获取字幕信息...');
      
      // 获取字幕轨道清单
      final trackManifest = await _yt.videos.closedCaptions.getManifest(videoId);
      
      // 查找指定语言的字幕
      ClosedCaptionTrackInfo? trackInfo;
      for (final track in trackManifest.tracks) {
        if (track.language.code == languageCode) {
          trackInfo = track;
          break;
        }
      }
      
      if (trackInfo == null) {
        debugPrint('未找到$languageCode语言的字幕');
        onStatusUpdate?.call('未找到可用字幕');
        return null;
      }
      
      onStatusUpdate?.call('正在下载字幕...');
      
      // 下载字幕
      final track = await _yt.videos.closedCaptions.get(trackInfo);
      
      // 将字幕转换为SRT格式
      final srtContent = _convertToSrt(track.captions);
      
      // 保存到文件
      final tempDir = await getTemporaryDirectory();
      final subtitleFile = File(path.join(tempDir.path, '$videoId.srt'));
      await subtitleFile.writeAsString(srtContent);
      
      debugPrint('字幕保存到: ${subtitleFile.path}');
      onStatusUpdate?.call('成功下载${track.captions.length}条字幕');
      
      return subtitleFile.path;
    } catch (e) {
      debugPrint('下载字幕错误: $e');
      onStatusUpdate?.call('下载字幕失败: $e');
      return null;
    }
  }
  
  // 将字幕转换为SRT格式
  String _convertToSrt(List<ClosedCaption> captions) {
    final buffer = StringBuffer();
    
    for (int i = 0; i < captions.length; i++) {
      final caption = captions[i];
      
      // 字幕序号
      buffer.writeln('${i + 1}');
      
      // 时间码格式: 00:00:00,000 --> 00:00:00,000
      final startTime = _formatDuration(caption.offset);
      final endTime = _formatDuration(caption.offset + caption.duration);
      buffer.writeln('$startTime --> $endTime');
      
      // 字幕文本
      buffer.writeln(caption.text);
      
      // 空行分隔
      buffer.writeln();
    }
    
    return buffer.toString();
  }
  
  // 格式化时间为SRT格式
  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds = (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    
    return '$hours:$minutes:$seconds,$milliseconds';
  }
  
  // 合并视频和音频文件
  Future<String?> _mergeVideoAudio(String videoPath, String audioPath, {Function(String)? onStatusUpdate}) async {
    try {
      onStatusUpdate?.call('正在合并视频和音频...');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final outputPath = path.join(tempDir.path, '${path.basenameWithoutExtension(videoPath)}_merged.mp4');
      
      // 读取视频文件
      final videoFile = File(videoPath);
      final videoBytes = await videoFile.readAsBytes();
      
      // 读取音频文件
      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();
      
      // 创建输出文件
      final outputFile = File(outputPath);
      
      // 简单合并（注意：这种方式不是真正的音视频合并，只是为了示例）
      // 实际应用中应该使用FFmpeg等工具进行专业合并
      final outputBytes = [...videoBytes, ...audioBytes];
      await outputFile.writeAsBytes(outputBytes);
      
      onStatusUpdate?.call('视频和音频合并完成');
      return outputPath;
    } catch (e) {
      debugPrint('合并视频和音频错误: $e');
      onStatusUpdate?.call('合并失败: $e');
      return null;
    }
  }
  
  // 下载视频和字幕（主要方法）
  Future<(String, String?)> downloadVideoAndSubtitles(
    String videoId, {
    Function(double)? onProgress,
    Function(String)? onStatusUpdate
  }) async {
    try {
      // 开始下载视频
      onStatusUpdate?.call('正在下载视频...');
      final videoPath = await downloadVideoToTemp(
        videoId,
        onProgress: onProgress,
        onStatusUpdate: onStatusUpdate
      );
      
      if (videoPath == null) {
        throw Exception('视频下载失败');
      }
      
      // 尝试下载字幕
      onStatusUpdate?.call('正在下载字幕...');
      String? subtitlePath;
      try {
        subtitlePath = await _downloadSubtitlesDirectly(
          videoId,
          onStatusUpdate: onStatusUpdate
        );
      } catch (e) {
        debugPrint('下载字幕错误: $e');
        onStatusUpdate?.call('下载字幕失败: $e');
        // 继续处理，即使字幕下载失败
      }
      
      // 返回视频路径和字幕路径
      return (videoPath, subtitlePath);
    } catch (e) {
      debugPrint('下载视频和字幕错误: $e');
      onStatusUpdate?.call('下载失败: $e');
      rethrow;
    }
  }
  
  void dispose() {
    _yt.close();
  }
} 