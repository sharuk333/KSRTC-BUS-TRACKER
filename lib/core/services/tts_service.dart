import 'dart:async';
import 'dart:collection';

import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech wrapper used for passenger destination alerts.
///
/// Supports a speech queue so that messages are spoken sequentially —
/// each message waits for the previous one to finish before starting.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialised = false;
  bool _speaking = false;
  final Queue<String> _queue = Queue<String>();

  /// Initialise the TTS engine with sensible defaults.
  Future<void> init() async {
    if (_initialised) return;
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Listen for speech completion to process the queue.
    _tts.setCompletionHandler(() {
      _speaking = false;
      _processQueue();
    });

    _tts.setCancelHandler(() {
      _speaking = false;
      _queue.clear();
    });

    _tts.setErrorHandler((msg) {
      _speaking = false;
      _processQueue();
    });

    _initialised = true;
  }

  /// Enqueue [message] to be spoken. If nothing is currently playing,
  /// it starts immediately. Otherwise it waits for the current speech
  /// to finish.
  Future<void> speak(String message) async {
    await init();
    _queue.add(message);
    if (!_speaking) {
      _processQueue();
    }
  }

  /// Process the next item in the queue.
  void _processQueue() {
    if (_queue.isEmpty) return;
    _speaking = true;
    final next = _queue.removeFirst();
    _tts.speak(next);
  }

  /// Stop any ongoing speech and clear the queue.
  Future<void> stop() async {
    _queue.clear();
    _speaking = false;
    await _tts.stop();
  }

  /// Release engine resources.
  Future<void> dispose() async {
    _queue.clear();
    _speaking = false;
    await _tts.stop();
  }
}
