import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../models/daily_video_model.dart';
import '../services/daily_video_service.dart';
import '../services/message_service.dart';
import 'real_time_study_duration.dart';
import 'dart:async';

/// 今日视频列表组件
class DailyVideoListWidget extends StatelessWidget {
  final VoidCallback? onHide;
  
  const DailyVideoListWidget({super.key, this.onHide});

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyVideoService>(
      builder: (context, dailyVideoService, child) {
        final todayVideos = dailyVideoService.todayVideos;
        final stats = dailyVideoService.todayStats;
        
        return Container(
          width: 300,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
          ),
          child: Column(
            children: [
              // 标题栏
              _buildHeader(context, stats),
              
              // 顶部操作栏
              _buildTopActions(context, dailyVideoService),
              
              // 视频列表
              Expanded(
                child: todayVideos.isEmpty
                    ? _buildEmptyState(context)
                    : _buildVideoList(context, todayVideos, dailyVideoService),
              ),
              
              // 底部操作栏
              _buildBottomActions(context, dailyVideoService),
            ],
          ),
        );
      },
    );
  }

  /// 构建标题栏
  Widget _buildHeader(BuildContext context, DailyVideoStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.video_library, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Text(
                '今日视频列表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (onHide != null)
                IconButton(
                  onPressed: onHide,
                  icon: const Icon(Icons.visibility_off, size: 20),
                  tooltip: '隐藏列表',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatsRow(context, stats),
        ],
      ),
    );
  }

  /// 构建统计信息行
  Widget _buildStatsRow(BuildContext context, DailyVideoStats stats) {
    return Row(
      children: [
        _buildStatChip(
          context,
          '总计: ${stats.totalVideos}',
          Colors.blue,
        ),
        const SizedBox(width: 4),
        _buildStatChip(
          context,
          '已完成: ${stats.completedVideos}',
          Colors.green,
        ),
        const SizedBox(width: 4),
        if (stats.totalStudyDuration > 0)
          _buildStatChip(
            context,
                                      '${(stats.totalStudyDuration / 60.0).toStringAsFixed(0)}分钟',
            Colors.orange,
          ),
      ],
    );
  }

  /// 构建统计标签
  Widget _buildStatChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有添加今日学习视频',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方"添加视频"按钮开始',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建视频列表
  Widget _buildVideoList(
    BuildContext context,
    List<DailyVideoItem> videos,
    DailyVideoService dailyVideoService,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _buildVideoItem(context, video, dailyVideoService);
      },
    );
  }

  /// 构建视频条目
  Widget _buildVideoItem(
    BuildContext context,
    DailyVideoItem video,
    DailyVideoService dailyVideoService,
  ) {
    final isCurrentVideo = dailyVideoService.currentVideo?.videoPath == video.videoPath;
    final isLoading = dailyVideoService.isVideoLoading(video.videoPath);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isCurrentVideo 
            ? Theme.of(context).primaryColor.withOpacity(0.1)
            : null,
        border: isCurrentVideo
            ? Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3))
            : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildVideoIcon(video, isLoading),
        title: Text(
          video.displayName,
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildVideoSubtitle(video, dailyVideoService),
        trailing: _buildVideoActions(context, video, dailyVideoService),
        onTap: () => _onVideoTap(context, video, dailyVideoService),
      ),
    );
  }

  /// 构建视频图标
  Widget _buildVideoIcon(DailyVideoItem video, bool isLoading) {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    
    IconData icon;
    Color color;
    
    switch (video.loadStatus) {
      case VideoLoadStatus.loaded:
        icon = Icons.play_circle_fill;
        color = Colors.green;
        break;
      case VideoLoadStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.play_circle_outline;
        color = Colors.grey;
    }
    
    return Icon(icon, size: 20, color: color);
  }

  /// 构建视频副标题
  Widget _buildVideoSubtitle(DailyVideoItem video, DailyVideoService dailyVideoService) {
    final List<Widget> children = [];
    
    // 添加学习状态
    switch (video.studyStatus) {
      case VideoStudyStatus.completed:
        children.add(const Text('✓ 已完成', style: TextStyle(fontSize: 11)));
        break;
      case VideoStudyStatus.studying:
        children.add(const Text('📖 学习中', style: TextStyle(fontSize: 11)));
        break;
      default:
        children.add(const Text('⚪ 未开始', style: TextStyle(fontSize: 11)));
    }
    
    // 添加学习时长
    if (video.studyDuration > 0) {
      final realDuration = dailyVideoService.getCurrentVideoStudyDuration(video.videoPath);
      final minutes = (realDuration / 60).round();
      children.add(const Text(' • ', style: TextStyle(fontSize: 11)));
      children.add(
        Text(
          '${minutes}分钟',
          style: TextStyle(
            fontSize: 11,
            color: Colors.blue.shade600,
          ),
        ),
      );
    }
    
    // 添加分析状态
    children.add(const Text(' • ', style: TextStyle(fontSize: 11)));
    switch (video.analysisStatus) {
      case SubtitleAnalysisStatus.pending:
        children.add(const Text('⏳ 待分析', style: TextStyle(fontSize: 11, color: Colors.orange)));
        break;
      case SubtitleAnalysisStatus.analyzing:
        children.add(const Text('🔄 分析中', style: TextStyle(fontSize: 11, color: Colors.blue)));
        break;
      case SubtitleAnalysisStatus.completed:
        children.add(const Text('📊 已分析', style: TextStyle(fontSize: 11, color: Colors.green)));
        break;
      case SubtitleAnalysisStatus.error:
        children.add(const Text('❌ 分析失败', style: TextStyle(fontSize: 11, color: Colors.red)));
        break;
    }
    
    return Wrap(
      children: children,
    );
  }

  /// 构建视频操作按钮
  Widget _buildVideoActions(
    BuildContext context,
    DailyVideoItem video,
    DailyVideoService dailyVideoService,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
      itemBuilder: (context) => [
        if (video.loadStatus == VideoLoadStatus.pending)
          const PopupMenuItem(
            value: 'load',
            child: Text('加载视频'),
          ),
        if (video.analysisStatus == SubtitleAnalysisStatus.pending ||
            video.analysisStatus == SubtitleAnalysisStatus.error)
          const PopupMenuItem(
            value: 'analyze',
            child: Text('重新分析'),
          ),
        if (video.subtitlePath == null)
          const PopupMenuItem(
            value: 'fix_subtitle',
            child: Text('修复字幕路径'),
          ),
        if (video.studyStatus != VideoStudyStatus.completed)
          const PopupMenuItem(
            value: 'complete',
            child: Text('标记完成'),
          ),
        if (video.studyStatus == VideoStudyStatus.completed)
          const PopupMenuItem(
            value: 'reset',
            child: Text('重置状态'),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: Text('从列表移除'),
        ),
        const PopupMenuItem(
          value: 'debug',
          child: Text('查看详情'),
        ),
      ],
      onSelected: (value) => _handleVideoAction(
        context,
        video,
        value,
        dailyVideoService,
      ),
    );
  }

  /// 构建顶部操作栏
  Widget _buildTopActions(BuildContext context, DailyVideoService dailyVideoService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionButton(
            context,
            Icons.download,
            '加载所有',
            () => _handleListAction(context, 'load_all', dailyVideoService),
          ),
          _buildActionButton(
            context,
            Icons.clear_all,
            '清空列表',
            () => _handleListAction(context, 'clear_all', dailyVideoService),
          ),
        ],
      ),
    );
  }

  /// 构建底部操作栏
  Widget _buildBottomActions(BuildContext context, DailyVideoService dailyVideoService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ElevatedButton.icon(
        onPressed: () => _addVideo(context, dailyVideoService),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('添加视频', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          minimumSize: const Size(double.infinity, 40),
        ),
      ),
    );
  }

  /// 处理视频点击
  void _onVideoTap(
    BuildContext context,
    DailyVideoItem video,
    DailyVideoService dailyVideoService,
  ) {
    // 直接播放视频，无需复杂的加载状态处理
    dailyVideoService.loadVideo(video.videoPath);
  }

  /// 处理视频操作
  void _handleVideoAction(
    BuildContext context,
    DailyVideoItem video,
    String action,
    DailyVideoService dailyVideoService,
  ) {
    final messageService = Provider.of<MessageService>(context, listen: false);
    
    switch (action) {
      case 'load':
        dailyVideoService.loadVideo(video.videoPath);
        break;
      case 'analyze':
        dailyVideoService.analyzeSubtitles(video.videoPath);
        messageService.showSuccess('开始重新分析视频字幕');
        break;
      case 'fix_subtitle':
        dailyVideoService.fixVideoSubtitlePath(video.videoPath);
        messageService.showInfo('开始修复字幕路径');
        break;
      case 'complete':
        dailyVideoService.markVideoCompleted(video.videoPath);
        messageService.showSuccess('视频已标记为完成');
        break;
      case 'reset':
        dailyVideoService.resetVideoStudyStatus(video.videoPath);
        messageService.showSuccess('视频状态已重置');
        break;
      case 'remove':
        _confirmRemoveVideo(context, video, dailyVideoService);
        break;
      case 'debug':
        _showVideoDetails(context, video);
        break;
    }
  }

  /// 处理列表操作
  void _handleListAction(
    BuildContext context,
    String action,
    DailyVideoService dailyVideoService,
  ) {
    final messageService = Provider.of<MessageService>(context, listen: false);
    
    switch (action) {
      case 'load_all':
        dailyVideoService.loadAllVideos();
        messageService.showSuccess('开始批量加载视频');
        break;
      case 'clear_all':
        _confirmClearList(context, dailyVideoService);
        break;
    }
  }

  /// 添加视频
  void _addVideo(BuildContext context, DailyVideoService dailyVideoService) async {
    final success = await dailyVideoService.addVideo(autoLoad: true);
    
    if (success) {
      final messageService = Provider.of<MessageService>(context, listen: false);
      messageService.showSuccess('视频已添加到今日列表');
    }
  }

  /// 确认删除视频
  void _confirmRemoveVideo(
    BuildContext context,
    DailyVideoItem video,
    DailyVideoService dailyVideoService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从今日列表中移除"${video.displayName}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              dailyVideoService.removeVideo(video.videoPath);
              final messageService = Provider.of<MessageService>(context, listen: false);
              messageService.showSuccess('视频已从列表中移除');
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 确认清空列表
  void _confirmClearList(
    BuildContext context,
    DailyVideoService dailyVideoService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空今日视频列表吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              dailyVideoService.clearTodayList();
              final messageService = Provider.of<MessageService>(context, listen: false);
              messageService.showSuccess('今日列表已清空');
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 显示视频详情
  void _showVideoDetails(BuildContext context, DailyVideoItem video) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('视频详情: ${video.displayName}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('视频路径: ${video.videoPath}'),
              const SizedBox(height: 8),
              Text('加载状态: ${video.loadStatus}'),
              const SizedBox(height: 8),
              Text('学习状态: ${video.studyStatus}'),
              const SizedBox(height: 8),
              Text('分析状态: ${video.analysisStatus}'),
              const SizedBox(height: 8),
              Text('学习时长: ${video.studyDuration}秒'),
              const SizedBox(height: 8),
              Text('字幕路径: ${video.subtitlePath ?? "未设置"}'),
              const SizedBox(height: 8),
              Text('添加时间: ${video.addedTime}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建通用操作按钮
  Widget _buildActionButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                foregroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(40, 40),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
} 