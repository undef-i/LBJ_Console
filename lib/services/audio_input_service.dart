import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;

class AudioInputService {
  static final AudioInputService _instance = AudioInputService._internal();
  factory AudioInputService() => _instance;
  AudioInputService._internal();

  static const _methodChannel = MethodChannel('org.noxylva.lbjconsole/audio_input');
  
  bool _isListening = false;
  bool get isListening => _isListening;

  Future<bool> startListening() async {
    if (_isListening) return true;

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        developer.log('Microphone permission denied', name: 'AudioInput');
        return false;
      }
    }

    try {
      await _methodChannel.invokeMethod('start');
      _isListening = true;
      developer.log('Audio input started', name: 'AudioInput');
      return true;
    } on PlatformException catch (e) {
      developer.log('Failed to start audio input: ${e.message}', name: 'AudioInput');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    
    try {
      await _methodChannel.invokeMethod('stop');
      _isListening = false;
      developer.log('Audio input stopped', name: 'AudioInput');
    } catch (e) {
      developer.log('Error stopping audio input: $e', name: 'AudioInput');
    }
  }
}