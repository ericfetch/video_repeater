import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../services/message_service.dart';

class WindowsRequirementsScreen extends StatelessWidget {
  const WindowsRequirementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Windows系统要求'),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '需要安装额外组件',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '为了在Windows上正常播放视频，您需要安装以下组件:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              _RequirementItem(
                title: 'K-Lite Codec Pack',
                description: '包含常用的视频解码器，支持大多数视频格式',
                url: 'https://www.codecguide.com/download_kl.htm',
              ),
              const SizedBox(height: 16),
              _RequirementItem(
                title: 'VLC Media Player',
                description: '强大的开源媒体播放器，包含大量解码器',
                url: 'https://www.videolan.org/vlc/',
              ),
              const SizedBox(height: 32),
              const Text(
                '安装上述任一组件后，重启应用即可正常使用。',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/home');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('我已安装，继续使用'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequirementItem extends StatelessWidget {
  final String title;
  final String description;
  final String url;

  const _RequirementItem({
    required this.title,
    required this.description,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('下载'),
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (context.mounted) {
                    final messageService = Provider.of<MessageService>(context, listen: false);
                    messageService.showError('无法打开链接: $url');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
} 