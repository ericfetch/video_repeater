import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/subtitle_model.dart';
import '../services/vocabulary_service.dart';
import '../services/dictionary_service.dart';
import '../utils/word_lemmatizer.dart';

class SubtitleSelectionArea extends StatelessWidget {
  final SubtitleEntry subtitle;
  final Function(String) onSaveWord;
  final bool isBlurred;
  final double fontSize;
  final FontWeight fontWeight;
  final Color textColor;
  final Color backgroundColor;

  const SubtitleSelectionArea({
    super.key, 
    required this.subtitle, 
    required this.onSaveWord,
    this.isBlurred = false,
    this.fontSize = 14.0,
    this.fontWeight = FontWeight.normal,
    this.textColor = Colors.white,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    // 获取生词本服务
    final vocabularyService = Provider.of<VocabularyService>(context);
    // 获取词典服务
    final dictionaryService = Provider.of<DictionaryService>(context);
    
    // 如果字幕模糊，直接返回模糊的文本
    if (isBlurred) {
      return SelectableText(
        subtitle.text,
        textAlign: TextAlign.left,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.5,
          height: 1.2,
          overflow: TextOverflow.ellipsis,
          shadows: const [
            Shadow(
              color: Colors.white,
              blurRadius: 10,
            ),
          ],
          color: Colors.transparent,
        ),
        contextMenuBuilder: _buildContextMenu,
      );
    }
    
    // 如果不模糊，构建富文本，高亮显示生词本中的单词
    return _buildRichText(context, vocabularyService, dictionaryService);
  }
  
  // 构建富文本，高亮显示生词本中的单词
  Widget _buildRichText(BuildContext context, VocabularyService vocabularyService, DictionaryService dictionaryService) {
    // 获取生词本中的所有单词
    final vocabularyWords = vocabularyService.getAllWords().map((word) => word.word.toLowerCase()).toSet();
    
    // 如果生词本为空，直接返回普通文本
    if (vocabularyWords.isEmpty) {
      return SelectableText(
        subtitle.text,
        textAlign: TextAlign.left,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.5,
          height: 1.2,
          overflow: TextOverflow.ellipsis,
          color: textColor,
        ),
        contextMenuBuilder: _buildContextMenu,
      );
    }
    
    // 分割字幕文本为单词
    final text = subtitle.text;
    
    // 使用空格分割文本
    final List<String> parts = text.split(' ');
    
    // 构建富文本
    final List<TextSpan> spans = [];
    
    // 正则表达式匹配标点符号
    final RegExp punctuationRegex = RegExp(r'[^\w\s]');
    
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      
      // 跳过空字符串
      if (part.isEmpty) {
        spans.add(const TextSpan(text: ' '));
        continue;
      }
      
      // 检查单词是否包含标点符号
      if (punctuationRegex.hasMatch(part)) {
        // 提取单词部分（去除标点符号）
        final wordPart = part.replaceAll(punctuationRegex, '').toLowerCase();
        
        // 对单词进行词形还原
        final lemmatizedWord = WordLemmatizer.lemmatize(wordPart);
        
        // 检查原形或还原后的形式是否在生词本中
        final bool isInVocabulary = wordPart.isNotEmpty && 
            (vocabularyWords.contains(wordPart) || vocabularyWords.contains(lemmatizedWord));
        
        // 找到标点符号的位置
        int punctIndex = -1;
        for (int j = 0; j < part.length; j++) {
          if (punctuationRegex.hasMatch(part[j])) {
            punctIndex = j;
            break;
          }
        }
        
        if (punctIndex == -1) {
          // 如果没有找到标点符号（这种情况不应该发生），直接添加整个单词
          spans.add(TextSpan(
            text: part,
            style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
          ));
        } else if (punctIndex == 0) {
          // 标点符号在开头
          spans.add(TextSpan(text: part[0]));
          if (part.length > 1) {
            spans.add(TextSpan(
              text: part.substring(1),
              style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
            ));
          }
        } else if (punctIndex == part.length - 1) {
          // 标点符号在结尾
          spans.add(TextSpan(
            text: part.substring(0, punctIndex),
            style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
          ));
          spans.add(TextSpan(text: part[punctIndex]));
        } else {
          // 标点符号在中间
          spans.add(TextSpan(
            text: part.substring(0, punctIndex),
            style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
          ));
          spans.add(TextSpan(text: part[punctIndex]));
          spans.add(TextSpan(
            text: part.substring(punctIndex + 1),
            style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
          ));
        }
      } else {
        // 没有标点符号，检查是否在生词本中
        final String lowercaseWord = part.toLowerCase();
        
        // 对单词进行词形还原
        final lemmatizedWord = WordLemmatizer.lemmatize(lowercaseWord);
        
        // 检查原形或还原后的形式是否在生词本中
        final bool isInVocabulary = vocabularyWords.contains(lowercaseWord) || 
            vocabularyWords.contains(lemmatizedWord);
        
        spans.add(TextSpan(
          text: part,
          style: isInVocabulary ? _getVocabularyHighlightStyle() : null,
        ));
      }
      
      // 添加空格，除非是最后一个单词
      if (i < parts.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }
    
    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.5,
          height: 1.2,
          overflow: TextOverflow.ellipsis,
          color: textColor,
        ),
      ),
      textAlign: TextAlign.left,
      maxLines: 1,
      contextMenuBuilder: _buildContextMenu,
    );
  }
  
  // 获取生词本单词高亮样式
  TextStyle _getVocabularyHighlightStyle() {
    return TextStyle(
      color: Colors.yellow,
      backgroundColor: Colors.black,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: Colors.yellow,
      decorationThickness: 1.5,
    );
  }
  
  // 构建上下文菜单
  Widget _buildContextMenu(BuildContext context, EditableTextState editableTextState) {
    // 获取选中的文本
    final TextSelection selection = editableTextState.textEditingValue.selection;
    final String selectedText = selection.isValid && !selection.isCollapsed
        ? subtitle.text.substring(selection.start, selection.end)
        : '';

    return AdaptiveTextSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      children: [
        InkWell(
          onTap: () {
            if (selectedText.isNotEmpty) {
              // 添加到生词本
              onSaveWord(selectedText);
              
              // 同时复制到剪贴板
              Clipboard.setData(ClipboardData(text: selectedText));
              
              // 清除选择
              editableTextState.hideToolbar();
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: const Text('添加到生词本', style: TextStyle(fontSize: 14)),
          ),
        ),
        InkWell(
          onTap: () {
            if (selectedText.isNotEmpty) {
              // 仅复制到剪贴板
              Clipboard.setData(ClipboardData(text: selectedText));
              
              // 清除选择
              editableTextState.hideToolbar();
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: const Text('复制', style: TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }
}
