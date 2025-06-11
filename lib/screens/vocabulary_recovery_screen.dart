import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vocabulary_service.dart';

class VocabularyRecoveryScreen extends StatefulWidget {
  const VocabularyRecoveryScreen({Key? key}) : super(key: key);

  @override
  _VocabularyRecoveryScreenState createState() => _VocabularyRecoveryScreenState();
}

class _VocabularyRecoveryScreenState extends State<VocabularyRecoveryScreen> {
  List<String> _allKeys = [];
  bool _isLoading = false;
  String _statusMessage = '';
  int _recoveredCount = 0;
  int _totalVocabularyCount = 0;
  List<String> _videoNames = [];

  @override
  void initState() {
    super.initState();
    _loadAllKeys();
    _loadVocabularyStats();
  }

  Future<void> _loadAllKeys() async {
    setState(() {
      _isLoading = true;
    });

    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    try {
      final keys = await vocabularyService.diagnosticListAllKeys();
      setState(() {
        _allKeys = keys;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '加载键失败: $e';
        _isLoading = false;
      });
    }
  }
  
  void _loadVocabularyStats() {
    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    setState(() {
      _totalVocabularyCount = vocabularyService.getTotalVocabularyCount();
      _videoNames = vocabularyService.getAllVideoNames();
    });
  }

  Future<void> _emergencyRecover() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在尝试恢复所有可能的生词本数据...';
    });

    final vocabularyService = Provider.of<VocabularyService>(context, listen: false);
    try {
      final count = await vocabularyService.emergencyRecoverAllVocabularyData();
      setState(() {
        _recoveredCount = count;
        _statusMessage = '恢复完成！成功恢复 $count 个生词本。';
        _isLoading = false;
      });
      
      // 重新加载键列表和统计信息
      _loadAllKeys();
      _loadVocabularyStats();
    } catch (e) {
      setState(() {
        _statusMessage = '恢复失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本数据恢复'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '生词本恢复工具',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '如果您的生词本数据丢失，此工具可以帮助您尝试恢复。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // 生词本统计信息
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '生词本统计',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('当前加载的生词本数量: ${_videoNames.length}'),
                          Text('总单词数: $_totalVocabularyCount'),
                          if (_videoNames.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('已加载的视频:'),
                            const SizedBox(height: 4),
                            Container(
                              height: 100,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ListView.builder(
                                itemCount: _videoNames.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 2.0,
                                    ),
                                    child: Text(_videoNames[index]),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _emergencyRecover,
                    child: const Text('尝试恢复所有生词本数据'),
                  ),
                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _recoveredCount > 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_statusMessage),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    '当前存储的所有键:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _allKeys.length,
                      itemBuilder: (context, index) {
                        final key = _allKeys[index];
                        final isVocabularyKey = key.contains('vocabulary');
                        
                        return ListTile(
                          title: Text(key),
                          tileColor: isVocabularyKey
                              ? Colors.green.withOpacity(0.1)
                              : null,
                          subtitle: isVocabularyKey
                              ? const Text('生词本数据')
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 