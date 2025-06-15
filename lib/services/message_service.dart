import 'dart:async';
import 'package:flutter/material.dart';

/// 消息类型枚举
enum MessageType {
  info,     // 信息
  success,  // 成功
  warning,  // 警告
  error,    // 错误
}

/// 应用中央消息服务，用于在应用顶部显示消息
class MessageService extends ChangeNotifier {
  // 当前消息
  String? _message;
  // 当前消息类型
  MessageType _messageType = MessageType.info;
  Timer? _messageTimer;
  
  // 获取当前消息
  String? get message => _message;
  
  // 获取当前消息类型
  MessageType get messageType => _messageType;
  
  // 显示消息
  void showMessage(String message, {int durationMs = 2000, MessageType type = MessageType.info}) {
    _message = message;
    _messageType = type;
    
    // 取消可能存在的定时器
    _messageTimer?.cancel();
    
    // 设置一个定时器，在短暂显示后清除消息
    _messageTimer = Timer(Duration(milliseconds: durationMs), () {
      _message = null;
      notifyListeners();
    });
    
    notifyListeners();
  }
  
  // 显示成功消息
  void showSuccess(String message, {int durationMs = 2000}) {
    showMessage(message, durationMs: durationMs, type: MessageType.success);
  }
  
  // 显示错误消息
  void showError(String message, {int durationMs = 2500}) {
    showMessage(message, durationMs: durationMs, type: MessageType.error);
  }
  
  // 显示警告消息
  void showWarning(String message, {int durationMs = 2000}) {
    showMessage(message, durationMs: durationMs, type: MessageType.warning);
  }
  
  // 显示信息消息
  void showInfo(String message, {int durationMs = 2000}) {
    showMessage(message, durationMs: durationMs, type: MessageType.info);
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