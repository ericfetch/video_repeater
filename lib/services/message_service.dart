import 'dart:async';
import 'package:flutter/material.dart';

/// 应用中央消息服务，用于在应用顶部显示消息
class MessageService extends ChangeNotifier {
  // 当前消息
  String? _message;
  Timer? _messageTimer;
  
  // 获取当前消息
  String? get message => _message;
  
  // 显示消息
  void showMessage(String message, {int durationMs = 1000}) {
    _message = message;
    
    // 取消可能存在的定时器
    _messageTimer?.cancel();
    
    // 设置一个定时器，在短暂显示后清除消息
    _messageTimer = Timer(Duration(milliseconds: durationMs), () {
      _message = null;
      notifyListeners();
    });
    
    notifyListeners();
  }
  
  // 清除消息
  void clearMessage() {
    _message = null;
    _messageTimer?.cancel();
    notifyListeners();
  }
  
  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }
} 