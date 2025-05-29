import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subtitle_model.dart';

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
    return SelectableText(
      subtitle.text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: 0.5,
        height: 1.5,
        // 如果模糊，应用模糊效果
        shadows: isBlurred ? [
          const Shadow(
            color: Colors.white,
            blurRadius: 10,
          ),
        ] : null,
        // 如果模糊，使用透明色
        color: isBlurred ? Colors.transparent : textColor,
      ),
      contextMenuBuilder: (context, editableTextState) {
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
      },
    );
  }
}
