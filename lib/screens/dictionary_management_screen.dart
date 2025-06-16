import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../models/dictionary_word.dart';
import '../services/dictionary_service.dart';

class DictionaryManagementScreen extends StatefulWidget {
  const DictionaryManagementScreen({super.key});

  @override
  State<DictionaryManagementScreen> createState() => _DictionaryManagementScreenState();
}

class _DictionaryManagementScreenState extends State<DictionaryManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<DictionaryWord> _selectedWords = [];
  List<DictionaryWord> _filteredWords = [];
  bool _isLoading = false;
  String _statusMessage = '';
  
  // 进度指示器相关变量
  bool _showProgressIndicator = false;
  double _progressValue = 0.0;
  
  // 过滤选项
  bool? _showFamiliarFilter = null; // null表示显示全部，true只显示熟知，false只显示未熟知
  
  @override
  void initState() {
    super.initState();
    _loadDictionary();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadDictionary() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '加载词典数据...';
    });
    
    // 确保词典服务已初始化
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    if (!dictionaryService.isInitialized) {
      await dictionaryService.initialize();
    }
    
    _filterWords();
    
    setState(() {
      _isLoading = false;
      _statusMessage = '词典加载完成，共 ${dictionaryService.allWords.length} 个单词';
    });
  }
  
  void _filterWords() {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final query = _searchController.text.trim();
    
    setState(() {
      if (_showFamiliarFilter != null) {
        _filteredWords = dictionaryService.searchDictionaryWithFamiliar(query, _showFamiliarFilter);
      } else {
        _filteredWords = dictionaryService.searchDictionary(query);
      }
    });
  }
  
  Future<void> _importDictionary(String fileType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [fileType],
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          _isLoading = true;
          _statusMessage = '导入词典中...';
        });
        
        final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
        int count = 0;
        
        if (fileType == 'json') {
          count = await dictionaryService.importDictionaryFromJson(result.files.single.path!);
        } else if (fileType == 'csv') {
          count = await dictionaryService.importDictionaryFromCsv(result.files.single.path!);
        }
        
        _filterWords();
        
        setState(() {
          _isLoading = false;
          _statusMessage = '导入完成，共导入 $count 个单词';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '导入失败: $e';
      });
    }
  }
  
  Future<void> _exportDictionary(String fileType) async {
    try {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存词典文件',
        fileName: 'dictionary.$fileType',
      );
      
      if (outputPath != null) {
        setState(() {
          _isLoading = true;
          _statusMessage = '导出词典中...';
        });
        
        final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
        bool success = false;
        
        if (fileType == 'json') {
          success = await dictionaryService.exportDictionaryToJson(outputPath);
        } else if (fileType == 'csv') {
          success = await dictionaryService.exportDictionaryToCsv(outputPath);
        }
        
        setState(() {
          _isLoading = false;
          _statusMessage = success ? '导出成功' : '导出失败';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '导出失败: $e';
      });
    }
  }
  
  void _toggleWordSelection(DictionaryWord word) {
    setState(() {
      if (_selectedWords.contains(word)) {
        _selectedWords.remove(word);
      } else {
        _selectedWords.add(word);
      }
    });
  }
  
  void _selectAllWords() {
    setState(() {
      if (_selectedWords.length == _filteredWords.length) {
        // 如果已经全选，则取消全选
        _selectedWords.clear();
      } else {
        // 否则全选
        _selectedWords.clear();
        _selectedWords.addAll(_filteredWords);
      }
    });
  }
  
  void _deleteSelectedWords() {
    if (_selectedWords.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedWords.length} 个单词吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              setState(() {
                _isLoading = true;
                _statusMessage = '删除单词中...';
              });
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.removeWords(_selectedWords.map((w) => w.word).toList());
              
              _selectedWords.clear();
              _filterWords();
              
              setState(() {
                _isLoading = false;
                _statusMessage = '删除完成';
              });
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
  
  void _clearDictionary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空整个词典吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              setState(() {
                _isLoading = true;
                _statusMessage = '清空词典中...';
              });
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.clearDictionary();
              
              _selectedWords.clear();
              _filterWords();
              
              setState(() {
                _isLoading = false;
                _statusMessage = '词典已清空';
              });
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
  
  void _addNewWord() {
    final wordController = TextEditingController();
    final partOfSpeechController = TextEditingController();
    final definitionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加新单词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                decoration: const InputDecoration(
                  labelText: '单词',
                  hintText: '输入单词',
                ),
              ),
              TextField(
                controller: partOfSpeechController,
                decoration: const InputDecoration(
                  labelText: '词性',
                  hintText: '例如: n., v., adj.',
                ),
              ),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(
                  labelText: '释义',
                  hintText: '输入单词释义',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final word = wordController.text.trim();
              if (word.isEmpty) {
                return;
              }
              
              Navigator.of(context).pop();
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              await dictionaryService.addWord(DictionaryWord(
                word: word,
                partOfSpeech: partOfSpeechController.text.trim(),
                definition: definitionController.text.trim(),
                rank: 0,
              ));
              
              _filterWords();
              setState(() {
                _statusMessage = '添加单词成功';
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
  
  void _editWord(DictionaryWord word) {
    final wordController = TextEditingController(text: word.word);
    final partOfSpeechController = TextEditingController(text: word.partOfSpeech);
    final definitionController = TextEditingController(text: word.definition);
    final phoneticController = TextEditingController(text: word.phonetic);
    final cefrController = TextEditingController(text: word.cefr);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑单词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordController,
                decoration: const InputDecoration(
                  labelText: '单词',
                  hintText: '输入单词',
                ),
                readOnly: true, // 不允许修改单词本身
              ),
              TextField(
                controller: partOfSpeechController,
                decoration: const InputDecoration(
                  labelText: '词性',
                  hintText: '例如: n., v., adj.',
                ),
              ),
              TextField(
                controller: phoneticController,
                decoration: const InputDecoration(
                  labelText: '音标',
                  hintText: '例如: əˈbaʊt',
                ),
              ),
              TextField(
                controller: cefrController,
                decoration: const InputDecoration(
                  labelText: 'CEFR等级',
                  hintText: '例如: A1, B2, C1',
                ),
              ),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(
                  labelText: '释义',
                  hintText: '输入单词释义',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
              word.partOfSpeech = partOfSpeechController.text.trim();
              word.definition = definitionController.text.trim();
              word.phonetic = phoneticController.text.trim();
              word.cefr = cefrController.text.trim();
              
              // 根据CEFR等级更新rank
              if (word.cefr != null && word.cefr!.isNotEmpty) {
                switch (word.cefr!.toUpperCase()) {
                  case 'A1': word.rank = 1; break;
                  case 'A2': word.rank = 2; break;
                  case 'B1': word.rank = 3; break;
                  case 'B2': word.rank = 4; break;
                  case 'C1': word.rank = 5; break;
                  case 'C2': word.rank = 6; break;
                }
              }
              
              await dictionaryService.updateWord(word);
              
              _filterWords();
              setState(() {
                _statusMessage = '更新单词成功';
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  // 批量查询单词信息
  Future<void> _enrichSelectedWords() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要查询的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认查询'),
        content: Text('确定要查询选中的 ${_selectedWords.length} 个单词的详细信息吗？这将通过网络API查询单词的释义和词性。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在查询单词信息...';
    });
    
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final wordList = _selectedWords.map((w) => w.word).toList();
    
    try {
      final results = await dictionaryService.enrichWordsWithAPI(
        wordList,
        batchSize: 5,
        onProgress: (current, total) {
          setState(() {
            _progressValue = current / total;
          });
        },
      );
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询完成: 成功 ${results['success']}，跳过 ${results['skipped']}，失败 ${results['failed']}';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询失败: $e';
      });
    }
  }
  
  // 批量查询所有无释义单词
  Future<void> _enrichAllIncompleteWords() async {
    final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
    final incompleteWords = dictionaryService.allWords
        .where((word) => word.definition == null || word.partOfSpeech == null)
        .map((word) => word.word)
        .toList();
    
    if (incompleteWords.isEmpty) {
      setState(() {
        _statusMessage = '没有找到需要补充信息的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认查询'),
        content: Text('找到 ${incompleteWords.length} 个缺少释义或词性的单词，确定要查询它们的详细信息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在查询单词信息...';
    });
    
    try {
      final results = await dictionaryService.enrichWordsWithAPI(
        incompleteWords,
        batchSize: 5,
        onProgress: (current, total) {
          setState(() {
            _progressValue = current / total;
          });
        },
      );
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询完成: 成功 ${results['success']}，跳过 ${results['skipped']}，失败 ${results['failed']}';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '查询失败: $e';
      });
    }
  }
  
  // 将数字排名转换为CEFR等级
  String _getCefrFromRank(int rank) {
    switch (rank) {
      case 1: return 'A1';
      case 2: return 'A2';
      case 3: return 'B1';
      case 4: return 'B2';
      case 5: return 'C1';
      case 6: return 'C2';
      default: return rank.toString();
    }
  }
  
  void _showWordDetails(DictionaryWord word) {
    // Implementation of _showWordDetails method
  }
  
  // 批量标记选中的单词为熟知
  Future<void> _markSelectedWordsAsFamiliar() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要标记的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认标记'),
        content: Text('确定要将选中的 ${_selectedWords.length} 个单词标记为熟知吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在标记单词...';
    });
    
    try {
      final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
      int count = 0;
      
      for (int i = 0; i < _selectedWords.length; i++) {
        await dictionaryService.markAsFamiliar(_selectedWords[i].word);
        count++;
        
        setState(() {
          _progressValue = i / _selectedWords.length;
        });
      }
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '成功标记 $count 个单词为熟知';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '标记失败: $e';
      });
    }
  }
  
  // 批量取消标记选中的单词为熟知
  Future<void> _unmarkSelectedWordsAsFamiliar() async {
    if (_selectedWords.isEmpty) {
      setState(() {
        _statusMessage = '请先选择要取消标记的单词';
      });
      return;
    }
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认取消标记'),
        content: Text('确定要取消选中的 ${_selectedWords.length} 个单词的熟知标记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _showProgressIndicator = true;
      _progressValue = 0.0;
      _statusMessage = '正在取消标记单词...';
    });
    
    try {
      final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
      int count = 0;
      
      for (int i = 0; i < _selectedWords.length; i++) {
        await dictionaryService.unmarkAsFamiliar(_selectedWords[i].word);
        count++;
        
        setState(() {
          _progressValue = i / _selectedWords.length;
        });
      }
      
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '成功取消 $count 个单词的熟知标记';
      });
      
      // 刷新显示
      _filterWords();
    } catch (e) {
      setState(() {
        _showProgressIndicator = false;
        _statusMessage = '取消标记失败: $e';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词典管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewWord,
            tooltip: '添加新单词',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _selectedWords.isNotEmpty ? _deleteSelectedWords : null,
            tooltip: '删除选中的单词',
          ),
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _filteredWords.isNotEmpty ? _selectAllWords : null,
            tooltip: '全选/取消全选',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _selectedWords.isNotEmpty ? _enrichSelectedWords : null,
            tooltip: '查询选中单词的详细信息',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'import_json':
                  _importDictionary('json');
                  break;
                case 'import_csv':
                  _importDictionary('csv');
                  break;
                case 'export_json':
                  _exportDictionary('json');
                  break;
                case 'export_csv':
                  _exportDictionary('csv');
                  break;
                case 'enrich_all':
                  _enrichAllIncompleteWords();
                  break;
                case 'mark_familiar':
                  _markSelectedWordsAsFamiliar();
                  break;
                case 'unmark_familiar':
                  _unmarkSelectedWordsAsFamiliar();
                  break;
                case 'clear':
                  _clearDictionary();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import_json',
                child: Text('导入JSON词典'),
              ),
              const PopupMenuItem(
                value: 'import_csv',
                child: Text('导入CSV词典'),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: Text('导出为JSON'),
              ),
              const PopupMenuItem(
                value: 'export_csv',
                child: Text('导出为CSV'),
              ),
              const PopupMenuItem(
                value: 'enrich_all',
                child: Text('查询所有缺失信息的单词'),
              ),
              const PopupMenuItem(
                value: 'mark_familiar',
                child: Text('标记选中单词为熟知'),
              ),
              const PopupMenuItem(
                value: 'unmark_familiar',
                child: Text('取消选中单词的熟知标记'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空词典'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '搜索单词',
                hintText: '输入关键词搜索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterWords();
                      },
                    )
                  : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _filterWords(),
            ),
          ),
          
          // 状态信息和进度条
          if (_isLoading || _statusMessage.isNotEmpty || _showProgressIndicator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_statusMessage.isNotEmpty)
                    Text(_statusMessage),
                  if (_isLoading)
                    const LinearProgressIndicator(),
                  if (_showProgressIndicator)
                    LinearProgressIndicator(value: _progressValue),
                ],
              ),
            ),
          
          // 单词统计信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Consumer<DictionaryService>(
                  builder: (context, dictionaryService, child) {
                    final totalWords = dictionaryService.allWords.length;
                    final familiarWords = dictionaryService.familiarWords.length;
                    final percentage = totalWords > 0 
                        ? (familiarWords / totalWords * 100).toStringAsFixed(1) 
                        : '0';
                        
                    return Text(
                      '总单词: $totalWords  |  熟知单词: $familiarWords ($percentage%)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
                ),
                const Spacer(),
                // 熟知过滤选项
                DropdownButton<bool?>(
                  value: _showFamiliarFilter,
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('全部单词'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('熟知单词'),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text('未熟知单词'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _showFamiliarFilter = value;
                      _filterWords();
                    });
                  },
                  hint: const Text('过滤'),
                ),
                ],
              ),
            ),
          
          // 选中单词信息
          if (_selectedWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Text('已选择 ${_selectedWords.length} 个单词'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedWords.clear();
                      });
                    },
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
          
          // 单词列表
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _filteredWords.length,
                  itemBuilder: (context, index) {
                    final word = _filteredWords[index];
                    final isSelected = _selectedWords.contains(word);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 选择框
                            Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                _toggleWordSelection(word);
                              },
                            ),
                            
                            // 单词内容
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 单词、词性和CEFR等级
                                  Row(
                                    children: [
                                      // 单词
                                      Text(
                                        word.word,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      
                                      // 词性
                                      if (word.partOfSpeech != null && word.partOfSpeech!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            word.partOfSpeech!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.secondary,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      
                                      // 音标
                                      if (word.phonetic != null && word.phonetic!.isNotEmpty)
                                        Text(
                                          '[${word.phonetic!}]',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      
                                      // CEFR等级
                                      if (word.cefr != null || word.rank != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            word.getCefrString() ?? _getCefrFromRank(word.rank ?? 0),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      
                                      // 熟知标签
                                      if (word.isFamiliar)
                                        Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            '熟知',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  // 定义
                                  if (word.definition != null && word.definition!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        word.definition!,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            // 编辑按钮
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _editWord(word),
                              tooltip: '编辑单词',
                            ),
                            
                            // 熟知切换按钮
                            IconButton(
                              icon: Icon(
                                word.isFamiliar 
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                                size: 20,
                                color: word.isFamiliar ? Colors.blue : null,
                              ),
                              onPressed: () async {
                                final dictionaryService = Provider.of<DictionaryService>(context, listen: false);
                                if (word.isFamiliar) {
                                  await dictionaryService.unmarkAsFamiliar(word.word);
                                } else {
                                  await dictionaryService.markAsFamiliar(word.word);
                                }
                                _filterWords();
                              },
                              tooltip: word.isFamiliar ? '取消标记为熟知' : '标记为熟知',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
} 