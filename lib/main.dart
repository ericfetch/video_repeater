import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'services/video_service.dart';
import 'services/history_service.dart';
import 'services/vocabulary_service.dart';
import 'services/message_service.dart';
import 'services/config_service.dart';
import 'screens/home_screen.dart';
import 'screens/windows_requirements_screen.dart';

// 自定义文本选择控制器，禁用系统默认菜单
class NoSelectionTextEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化MediaKit
  MediaKit.ensureInitialized();
  
  // 禁用长按文本选择弹出菜单
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 这将覆盖默认的文本选择控制器
      TextSelectionControls? currentTextSelectionControls;
      
      // 设置系统级别的覆盖
      SystemChannels.textInput.invokeMethod<void>(
        'TextInput.setSelectionMoveMethod',
        {'enabled': false},
      );
    });
  }
  
  // 初始化窗口管理器
  await windowManager.ensureInitialized();
  
  // 设置窗口属性
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 780),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoService()),
        ChangeNotifierProvider(create: (_) => HistoryService()),
        ChangeNotifierProvider(create: (_) => VocabularyService()),
        ChangeNotifierProvider(create: (_) => MessageService()),
        ChangeNotifierProvider(create: (_) => ConfigService()),
      ],
      child: Consumer<ConfigService>(
        builder: (context, configService, child) {
          // 初始化VideoService和ConfigService的关联
          final videoService = Provider.of<VideoService>(context, listen: false);
          videoService.setConfigService(configService);
          
          return MaterialApp(
            title: '视频学习助手',
            theme: ThemeData(
              primarySwatch: Colors.blue,
              brightness: configService.darkMode ? Brightness.dark : Brightness.light,
              useMaterial3: true,
              // 自定义文本选择控制器
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: Colors.blueAccent.withOpacity(0.4),
                cursorColor: Colors.blue,
                selectionHandleColor: Colors.blueAccent,
              ),
            ),
            // 禁用默认的文本选择菜单
            builder: (context, child) {
              // 使用自定义Builder显示全局消息
              return MessageOverlay(child: child!);
            },
            home: FutureBuilder<bool>(
              future: _checkWindowsRequirements(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                
                final requirementsOk = snapshot.data ?? false;
                if (!requirementsOk && Platform.isWindows) {
                  return const WindowsRequirementsScreen();
                }
                
                return MessageOverlay(child: HomeScreen());
              },
            ),
            debugShowCheckedModeBanner: false,
          );
        }
      ),
    );
  }
  
  Future<bool> _checkWindowsRequirements() async {
    if (!Platform.isWindows) return true;
    
    // 在这里可以添加检查Windows平台特定要求的代码
    // 例如检查是否安装了必要的解码器等
    
    return true; // 暂时默认返回true
  }
}

// Windows平台需求提示页面
class WindowsRequirementsScreen extends StatelessWidget {
  const WindowsRequirementsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统需求'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '需要安装以下组件才能正常播放视频：',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRequirementItem(
              '1. K-Lite Codec Pack',
              '包含常见视频格式的解码器，推荐安装Standard版本',
              'https://codecguide.com/download_kl.htm',
            ),
            const SizedBox(height: 8),
            _buildRequirementItem(
              '2. Visual C++ Redistributable',
              '运行视频解码器所需的Microsoft运行库',
              'https://aka.ms/vs/17/release/vc_redist.x64.exe',
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  );
                },
                child: const Text('我已安装，继续使用'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRequirementItem(String title, String description, String url) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 8),
            Text(
              '下载链接: $url',
              style: const TextStyle(color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息提示覆盖层
class MessageOverlay extends StatelessWidget {
  final Widget child;
  
  const MessageOverlay({Key? key, required this.child}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<MessageService>(
      builder: (context, messageService, _) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaleFactor: 1.0,
          ),
          child: Stack(
            children: [
              child,
              // 如果有消息，显示在顶部
              if (messageService.message != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        messageService.message!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
