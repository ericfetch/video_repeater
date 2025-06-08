import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
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
      audioStreamsList.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      var selectedAudioStream = audioStreamsList.first;
      
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
      onStatusUpdate('错误: ${e.toString()}');
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
      
      // 尝试使用FFmpeg合并
      bool usedFFmpeg = false;
      
      try {
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
          
          onStatusUpdate?.call('正在处理...');
          debugPrint('运行FFmpeg命令: ffmpeg ${ffmpegArgs.join(' ')}');
          
          final ffmpegProcess = await Process.start('ffmpeg', ffmpegArgs);
          
          // 显示进度（虽然FFmpeg不一定输出具体百分比）
          ffmpegProcess.stderr.transform(utf8.decoder).listen((data) {
            debugPrint('FFmpeg: $data');
            // 可以从输出中尝试解析进度，但这里简化处理
            if (data.contains('time=')) {
              onStatusUpdate?.call('处理中...');
            }
          });
          
          final exitCode = await ffmpegProcess.exitCode;
          if (exitCode == 0) {
            onStatusUpdate?.call('FFmpeg合并成功');
            usedFFmpeg = true;
          } else {
            debugPrint('FFmpeg退出代码: $exitCode，尝试使用备用方法');
            onStatusUpdate?.call('FFmpeg处理失败，尝试备用方法');
          }
        } else {
          debugPrint('FFmpeg不可用，使用备用方法');
        }
      } catch (e) {
        debugPrint('FFmpeg执行出错: $e');
        onStatusUpdate?.call('FFmpeg执行出错，尝试备用方法');
      }
      
      // 如果FFmpeg不可用或失败，使用备用方法
      if (!usedFFmpeg) {
        onStatusUpdate?.call('使用备用方法合并');
        debugPrint('使用简单方法合并视频和音频');
        
        // 这里我们简化处理，直接使用视频文件
        // 实际应用中，如果没有FFmpeg，可能需要在应用中内置一个简单的合并库
        // 或者提供只有视频没有音频的体验
        await File(videoFile).copy(outputFile);
        
        onStatusUpdate?.call('使用视频文件作为最终输出');
      }
      
      onStatusUpdate?.call('合并完成');
      return true;
    } catch (e) {
      debugPrint('合并视频和音频失败: $e');
      onStatusUpdate?.call('合并失败: $e');
      return false;
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
  
  // 从分辨率字符串中提取高度值
  int _parseHeight(String resolution) {
    // 尝试从分辨率字符串中提取数字部分 (例如 "720p" -> 720)
    final match = RegExp(r'(\d+)').firstMatch(resolution);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }
  
  // 直接下载字幕到指定文件
  Future<bool> _downloadSubtitlesDirectly(String videoId, String outputPath, Function(String)? onStatusUpdate) async {
    try {
      // 获取视频字幕轨道信息
      onStatusUpdate?.call('正在获取视频字幕信息...');
      var trackManifest = await _yt.videos.closedCaptions.getManifest(videoId);
      
      // 检查是否有字幕
      if (trackManifest.tracks.isEmpty) {
        debugPrint('视频没有字幕轨道');
        return false;
      }
      
      // 优先选择英文字幕，如果没有则选择第一个可用的
      var track = trackManifest.tracks.firstWhere(
        (t) => t.language.code.toLowerCase() == 'en', 
        orElse: () => trackManifest.tracks.first
      );
      
      debugPrint('选择字幕: ${track.language.name} (${track.language.code})');
      onStatusUpdate?.call('找到字幕: ${track.language.name} (${track.language.code})');
      
      // 获取字幕内容
      var captionTrack = await _yt.videos.closedCaptions.get(track);
      
      if (captionTrack.captions.isEmpty) {
        debugPrint('字幕轨道没有字幕内容');
        return false;
      }
      
      // 转换为SRT格式并保存
      final srtContent = StringBuffer();
      int index = 1;
      
      for (var caption in captionTrack.captions) {
        // 索引编号
        srtContent.writeln(index++);
        
        // 时间格式: 00:00:00,000 --> 00:00:00,000
        final start = _formatTimestamp(caption.offset);
        final end = _formatTimestamp(caption.offset + caption.duration);
        srtContent.writeln('$start --> $end');
        
        // 字幕文本
        srtContent.writeln(caption.text);
        
        // 空行分隔
        srtContent.writeln();
      }
      
      // 保存字幕文件
      await File(outputPath).writeAsString(srtContent.toString());
      debugPrint('字幕已保存: $outputPath');
      
      return true;
    } catch (e) {
      debugPrint('下载字幕错误: $e');
      return false;
    }
  }
  
  // 格式化时间戳为SRT格式
  String _formatTimestamp(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final milliseconds = threeDigits(duration.inMilliseconds.remainder(1000));
    
    return '$hours:$minutes:$seconds,$milliseconds';
  }
  
  // 下载YouTube视频和字幕（如果有）
  Future<(String, String?)?> downloadVideoAndSubtitles(String videoId, 
      {Function(double)? onProgress, Function(String)? onStatusUpdate}) async {
    
    try {
      // 首先检查缓存
      final cachedFilePath = _getFromDownloadCache(videoId);
      if (cachedFilePath != null) {
        debugPrint('从缓存中找到视频文件: $cachedFilePath');
        onStatusUpdate?.call('使用已缓存的视频文件');
        
              // 获取字幕（如果有）
      try {
        // 尝试直接下载字幕文件
        final tempDir = await getTemporaryDirectory();
        final subtitleFileName = '${videoId}_subtitle.srt';
        final subtitleFile = path.join(tempDir.path, subtitleFileName);
        
        onStatusUpdate?.call('尝试下载字幕...');
        bool subtitleSuccess = await _downloadSubtitlesDirectly(videoId, subtitleFile, 
            (status) => onStatusUpdate?.call('字幕: $status'));
            
        String? subtitlePath = subtitleSuccess ? subtitleFile : null;
        
        return (cachedFilePath, subtitlePath);
      } catch (e) {
        debugPrint('字幕下载失败，但将继续使用无字幕视频: $e');
        onStatusUpdate?.call('字幕下载失败，将使用无字幕视频');
        return (cachedFilePath, null);
      }
      }
      
      // 获取视频信息
      onStatusUpdate?.call('正在获取视频详细信息...');
      final video = await _yt.videos.get(videoId).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('获取视频详细信息超时');
        }
      );
      
      // 获取下载质量设置
      String targetQuality = '720p'; // 默认使用720p
      if (_configService != null) {
        targetQuality = _configService!.youtubeVideoQuality;
      }
      
      // 更新进度回调，确保非空
      final progressCallback = onProgress ?? (_) {};
      final statusCallback = onStatusUpdate ?? (_) {};
      
      // 下载视频和音频流
      onStatusUpdate?.call('准备下载视频: ${video.title}');
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
        // 格式化文件名
        String fileName = '${video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_')}_${videoId}.mp4';
        outputFilePath = path.join(_configService!.youtubeDownloadPath, fileName);
        
        // 确保目录存在
        final directory = path.dirname(outputFilePath);
        if (!Directory(directory).existsSync()) {
          await Directory(directory).create(recursive: true);
        }
      } else {
        // 使用临时目录
        final tempDir = await getTemporaryDirectory();
        outputFilePath = path.join(tempDir.path, '${video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_')}_${videoId}.mp4');
      }
      
      // 合并视频和音频文件
      onStatusUpdate?.call('正在合并视频和音频...');
      final mergeSuccess = await _mergeVideoAudio(videoPath, audioPath, outputFilePath,
        (status) => onStatusUpdate?.call('合并: $status')
      );
      
      // 下载字幕
      String? subtitlePath = null;
      try {
        // 尝试直接下载字幕文件
        final subtitleFileName = '${path.basenameWithoutExtension(outputFilePath)}.srt';
        final subtitleFile = path.join(path.dirname(outputFilePath), subtitleFileName);
        
        onStatusUpdate?.call('尝试下载字幕...');
        bool subtitleSuccess = await _downloadSubtitlesDirectly(videoId, subtitleFile, 
            (status) => onStatusUpdate?.call('字幕: $status'));
            
        if (subtitleSuccess) {
          subtitlePath = subtitleFile;
          onStatusUpdate?.call('字幕下载完成');
        } else {
          onStatusUpdate?.call('未找到可用字幕');
        }
      } catch (e) {
        debugPrint('下载字幕失败: $e');
        onStatusUpdate?.call('字幕下载失败，将继续使用无字幕视频');
      }
      
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
        // 添加到下载缓存
        await _addToDownloadCache(videoId, outputFilePath);
        
        final fileSize = await File(outputFilePath).length();
        debugPrint('视频下载完成: $outputFilePath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
        onStatusUpdate?.call('下载完成: ${video.title}');
        
        return (outputFilePath, subtitlePath);
      } else {
        onStatusUpdate?.call('视频合并失败，尝试使用单流视频');
        
        // 如果合并失败，尝试直接使用视频流（如果是webm或mp4格式）
        if (path.extension(videoPath) == '.mp4' || path.extension(videoPath) == '.webm') {
          final tempOutputPath = path.join(path.dirname(outputFilePath), 
              '${path.basenameWithoutExtension(outputFilePath)}_单流${path.extension(videoPath)}');
          
          // 复制视频文件
          await File(videoPath).copy(tempOutputPath);
          
          // 添加到下载缓存
          await _addToDownloadCache(videoId, tempOutputPath);
          
          final fileSize = await File(tempOutputPath).length();
          debugPrint('使用单流视频: $tempOutputPath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
          onStatusUpdate?.call('使用单流视频完成下载 (无音频)');
          
          return (tempOutputPath, subtitlePath);
        }
        
        return null;
      }
      
    } catch (e) {
      debugPrint('下载视频错误: $e');
      onStatusUpdate?.call('下载失败: $e');
      return null;
    }
  }
  
  void dispose() {
    _yt.close();
  }
} 